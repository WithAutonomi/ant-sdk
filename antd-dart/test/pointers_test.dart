import 'dart:convert';

import 'package:antd_client/antd_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// REST pointer API against a mock daemon: request shapes, response
/// parsing (counters up to 2^64 - 1, REST nulls), and the error codes that
/// share an HTTP status with older errors.

final owner = 'a1' * 32;
final other = 'b2' * 32;
final target1 = 'c3' * 32;
final target2 = 'd4' * 32;
final stateId = 'e5' * 32;
const u64Max = '18446744073709551615';

/// A mock daemon answering `METHOD /path` routes with `(status, body)`, where
/// a String body is sent verbatim and anything else as JSON. Records every
/// request.
class _Daemon {
  final Map<String, (int, Object?)> routes;
  final requests = <http.Request>[];

  _Daemon(this.routes);

  AntdClient get client => AntdClient(
        baseUrl: 'http://daemon',
        httpClient: MockClient((request) async {
          requests.add(request);
          final route = routes['${request.method} ${request.url.path}'];
          if (route == null) {
            return http.Response(
                '{"error":"no route","code":"NOT_FOUND"}', 404);
          }
          final (status, body) = route;
          return http.Response(body is String ? body : jsonEncode(body), status,
              headers: {'content-type': 'application/json'});
        }),
      );

  Map<String, dynamic> body(int index) =>
      jsonDecode(requests[index].body) as Map<String, dynamic>;
}

AntdClient _answering(String route, int status, Object? body) =>
    _Daemon({route: (status, body)}).client;

Map<String, dynamic> _write(String counter) =>
    {'address': owner, 'state_id': stateId, 'counter': counter};

Map<String, dynamic> _finalState({String? transferredTo, int holders = 7}) => {
      'state_id': stateId,
      'kind': 'pointer',
      'kind_tag': 1,
      'target': other,
      'holders': holders,
      'transferred_to': transferredTo,
    };

Map<String, dynamic> _finality(String status,
        {Object? counter,
        Object? state,
        List<Object?> states = const [],
        Object? majority,
        String? transferredTo}) =>
    {
      'address': owner,
      'group': 7,
      'answered': 7,
      'status': status,
      'counter': counter,
      'state': state,
      'states': states,
      'majority': majority,
      'transferred_to': transferredTo,
    };

Map<String, dynamic> _errorBody(String code, [Map<String, dynamic>? extra]) =>
    {'error': 'refused: $code', 'code': code, ...?extra};

void main() {
  group('pointer requests and responses', () {
    test('pointerKeys lists the addresses', () async {
      final client = _answering('GET /v1/pointers/keys', 200, {
        'keys': [
          {'address': owner},
          {'address': other},
        ],
      });
      expect(await client.pointerKeys(), equals([owner, other]));
    });

    test('pointerKeys with no keys is empty', () async {
      final client = _answering('GET /v1/pointers/keys', 200, {'keys': []});
      expect(await client.pointerKeys(), isEmpty);
    });

    test('pointerCreate sends owner, target and the default kind', () async {
      final daemon = _Daemon({'POST /v1/pointers': (200, _write('0'))});
      final w = await daemon.client.pointerCreate(owner, target1);
      expect(daemon.body(0),
          equals({'owner': owner, 'target': target1, 'kind': 'chunk'}));
      expect(w.address, equals(owner));
      expect(w.stateId, equals(stateId));
      expect(w.counter, equals(BigInt.zero));
    });

    test('pointerUpdate sends kind pointer and reads the counter', () async {
      final daemon = _Daemon({'POST /v1/pointers/update': (200, _write('7'))});
      final w = await daemon.client
          .pointerUpdate(owner, other, kind: PointerKind.pointer);
      expect(daemon.body(0),
          equals({'owner': owner, 'target': other, 'kind': 'pointer'}));
      expect(w.counter, equals(BigInt.from(7)));
    });

    test('pointerTransfer reads the close group finality', () async {
      final daemon = _Daemon({
        'POST /v1/pointers/transfer': (
          200,
          {
            'address': owner,
            'state_id': stateId,
            'finality': _finality('final',
                state: _finalState(transferredTo: other), transferredTo: other),
          }
        ),
      });
      final t = await daemon.client.pointerTransfer(owner, other);
      expect(daemon.body(0), equals({'owner': owner, 'recipient': other}));
      expect(t.address, equals(owner));
      expect(t.finalityError, isNull);
      final f = t.finality!;
      expect(f.status, equals(const PointerFinal()));
      expect(f.isFinal, isTrue);
      expect(f.transferredTo, equals(other));
      expect(f.counter, isNull);
      expect(f.state!.transferredTo, equals(other));
      expect(f.state!.holders, equals(7));
      expect(f.state!.kindTag, equals(1));
    });

    test('pointerTransfer without finality keeps the error', () async {
      final client = _answering('POST /v1/pointers/transfer', 200, {
        'address': owner,
        'state_id': stateId,
        'finality': null,
        'finality_error': 'only 3 of 7 answered',
      });
      final t = await client.pointerTransfer(owner, other);
      expect(t.finality, isNull);
      expect(t.finalityError, equals('only 3 of 7 answered'));
    });

    test('pointerGet reads a final record at 2^64 - 1', () async {
      final client = _answering('GET /v1/pointers/$owner', 200, {
        'address': owner,
        'owner': 'ab' * 1952,
        'counter': u64Max,
        'kind': 'pointer',
        'kind_tag': 1,
        'target': other,
        'state_id': stateId,
        'is_final': true,
        'transferred_to': other,
      });
      final r = await client.pointerGet(owner);
      expect(r.counter, equals(pointerFinalCounter));
      expect(r.counter.toString(), equals(u64Max));
      expect(r.isFinal, isTrue);
      expect(r.transferredTo, equals(other));
      expect(r.owner.length, equals(2 * 1952));
      expect(r.kind, equals('pointer'));
      expect(r.targetKind, equals(PointerKind.pointer));
    });

    test('pointerGet maps REST nulls to null and unknown kinds', () async {
      final client = _answering('GET /v1/pointers/$owner', 200, {
        'address': owner,
        'owner': 'ab',
        'counter': '3',
        'kind': 'unknown',
        'kind_tag': 9,
        'target': target1,
        'state_id': stateId,
        'is_final': false,
        'transferred_to': null,
      });
      final r = await client.pointerGet(owner);
      expect(r.counter, equals(BigInt.from(3)));
      expect(r.isFinal, isFalse);
      expect(r.transferredTo, isNull);
      expect(r.kindTag, equals(9));
      expect(r.targetKind, isNull);
    });

    test('pointerGet of nothing is NotFoundError', () async {
      final client = _answering('GET /v1/pointers/$owner', 404,
          _errorBody('NOT_FOUND', {'error': 'no pointer at $owner'}));
      await expectLater(
          client.pointerGet(owner), throwsA(isA<NotFoundError>()));
    });

    test('pointerResolve reads the end of the chain', () async {
      final client = _answering('GET /v1/pointers/$owner/resolve', 200,
          {'kind': 'chunk', 'kind_tag': 0, 'target': target2});
      final r = await client.pointerResolve(owner);
      expect(r.target, equals(target2));
      expect(r.kind, equals('chunk'));
      expect(r.targetKind, equals(PointerKind.chunk));
    });

    test('pointerFinality open carries the counter', () async {
      final client = _answering('GET /v1/pointers/$owner/finality', 200,
          _finality('open', counter: '12'));
      final f = await client.pointerFinality(owner);
      expect(f.status, isA<PointerOpen>());
      expect(f.isFinal, isFalse);
      expect(f.counter, equals(BigInt.from(12)));
      expect(f.state, isNull);
      expect(f.states, isEmpty);
      expect(f.majority, isNull);
      expect(f.transferredTo, isNull);
      expect(f.group, equals(7));
      expect(f.answered, equals(7));
    });

    test('pointerFinality open with no corroborated state', () async {
      final client = _answering(
          'GET /v1/pointers/$owner/finality', 200, _finality('open'));
      expect((await client.pointerFinality(owner)).counter, isNull);
    });

    test('pointerFinality settling and unconfirmed carry the state', () async {
      for (final status in ['settling', 'unconfirmed']) {
        final client = _answering('GET /v1/pointers/$owner/finality', 200,
            _finality(status, state: _finalState(holders: 3)));
        final f = await client.pointerFinality(owner);
        expect(f.status.wire, equals(status));
        expect(f.isFinal, isFalse);
        expect(f.state!.holders, equals(3));
        expect(f.state!.transferredTo, isNull);
      }
    });

    test('pointerFinality forked carries every state and the majority',
        () async {
      final client = _answering(
          'GET /v1/pointers/$owner/finality',
          200,
          _finality('forked',
              states: [_finalState(holders: 5), _finalState(holders: 2)],
              majority: _finalState(holders: 5)));
      final f = await client.pointerFinality(owner);
      expect(f.status, equals(const PointerForked()));
      expect(f.states.map((s) => s.holders), equals([5, 2]));
      expect(f.majority!.holders, equals(5));
    });

    test('pointerFinality keeps a status this SDK does not know', () async {
      final client = _answering(
          'GET /v1/pointers/$owner/finality', 200, _finality('contested'));
      final f = await client.pointerFinality(owner);
      expect(f.status, equals(const PointerFinalityUnknown('contested')));
      expect(f.status.wire, equals('contested'));
      expect(f.isFinal, isFalse);
    });

    test('pointerController reads the transfers', () async {
      final client = _answering('GET /v1/pointers/$owner/controller', 200, {
        'pointer': other,
        'transfers': [other],
        'frozen': false,
      });
      final c = await client.pointerController(owner);
      expect(c.pointer, equals(other));
      expect(c.transfers, equals([other]));
      expect(c.frozen, isFalse);
    });

    test('pointerPrepare update sends only the update fields', () async {
      final daemon = _Daemon({
        'POST /v1/pointers/prepare': (
          200,
          {
            'upload_id': 'up1',
            'op': 'update',
            'address': owner,
            'state_id': stateId,
            'counter': '1',
            'payment_type': 'wave_batch',
            'payments': [
              {'quote_hash': '0xq', 'rewards_address': '0xr', 'amount': '9'},
            ],
            'total_amount': '9',
            'payment_vault_address': '0xvault',
            'payment_token_address': '0xtoken',
            'rpc_url': 'http://rpc',
          }
        ),
      });
      final p = await daemon.client.pointerPrepare(
          PointerPrepareRequest.update(owner: owner, target: target2));
      expect(
          daemon.body(0),
          equals({
            'owner': owner,
            'op': 'update',
            'target': target2,
            'kind': 'chunk',
          }));
      expect(p.uploadId, equals('up1'));
      expect(p.op, equals('update'));
      expect(p.counter, equals(BigInt.one));
      expect(p.paymentType, equals('wave_batch'));
      expect(p.payments.single.quoteHash, equals('0xq'));
      expect(p.payments.single.amount, equals('9'));
      expect(p.totalAmount, equals('9'));
      expect(p.paymentVaultAddress, equals('0xvault'));
      expect(p.paymentTokenAddress, equals('0xtoken'));
      expect(p.rpcUrl, equals('http://rpc'));
      expect(p.signedQuotes, isEmpty);
    });

    test('pointerPrepare transfer asks for signed quotes', () async {
      final daemon = _Daemon({
        'POST /v1/pointers/prepare': (
          200,
          {
            'upload_id': 'up2',
            'op': 'transfer',
            'address': owner,
            'state_id': stateId,
            'counter': u64Max,
            'payment_type': 'wave_batch',
            'payments': [],
            'total_amount': '0',
            'payment_vault_address': '',
            'payment_token_address': '',
            'rpc_url': '',
            'signed_quotes': [
              {
                'quote_hash': '0xq',
                'quote': 'cXVvdGU=',
                'commitment_sidecar': 'c2lk'
              },
              {'quote_hash': '0xb', 'quote': 'YmFzZQ=='},
            ],
          }
        ),
      });
      final p = await daemon.client.pointerPrepare(
          PointerPrepareRequest.transfer(
              owner: owner, recipient: other, includeSignedQuotes: true));
      expect(
          daemon.body(0),
          equals({
            'owner': owner,
            'op': 'transfer',
            'recipient': other,
            'include_signed_quotes': true,
          }));
      expect(p.counter, equals(pointerFinalCounter));
      expect(p.signedQuotes.first.quote, equals('cXVvdGU='));
      expect(p.signedQuotes.first.commitmentSidecar, equals('c2lk'));
      expect(p.signedQuotes.last.commitmentSidecar, isNull);
    });

    test('pointerPrepare create sends the kind', () async {
      final daemon = _Daemon({
        'POST /v1/pointers/prepare': (
          200,
          {
            'upload_id': 'up3',
            'op': 'create',
            'address': owner,
            'state_id': stateId,
            'counter': '0',
          }
        ),
      });
      await daemon.client.pointerPrepare(PointerPrepareRequest.create(
          owner: owner, target: other, kind: PointerKind.pointer));
      expect(
          daemon.body(0),
          equals({
            'owner': owner,
            'op': 'create',
            'target': other,
            'kind': 'pointer',
          }));
    });

    test('pointerFinalize sends the tx hashes', () async {
      final daemon =
          _Daemon({'POST /v1/pointers/finalize': (200, _write('1'))});
      final r = await daemon.client.pointerFinalize('up1', {'0xq': '0xtx'});
      expect(
          daemon.body(0),
          equals({
            'upload_id': 'up1',
            'tx_hashes': {'0xq': '0xtx'},
          }));
      expect(r.counter, equals(BigInt.one));
      expect(r.finality, isNull);
    });

    test('pointerFinalize of a transfer carries finality', () async {
      final client = _answering('POST /v1/pointers/finalize', 200, {
        ..._write(u64Max),
        'finality': _finality('settling', state: _finalState(holders: 4)),
      });
      final r = await client.pointerFinalize('up2', {});
      expect(r.counter, equals(pointerFinalCounter));
      expect(r.finality!.status, isA<PointerSettling>());
    });
  });

  group('pointer counters', () {
    test('parse 0 and 2^64 - 1 exactly', () {
      expect(parsePointerCounter('counter', '0'), equals(BigInt.zero));
      expect(
          parsePointerCounter('counter', u64Max), equals(pointerFinalCounter));
      expect(pointerFinalCounter, equals((BigInt.one << 64) - BigInt.one));
    });

    for (final bad in <Object?>[
      '',
      '-1',
      '+1',
      ' 1',
      '1 ',
      '1.0',
      '0x10',
      '1e3',
      '18446744073709551616',
      '99999999999999999999999',
      7,
      null,
    ]) {
      test('reject ${jsonEncode(bad)}', () {
        expect(() => parsePointerCounter('counter', bad),
            throwsA(isA<InternalError>()));
      });
    }

    test('a malformed counter in a response is an error, not zero', () async {
      final client = _answering('POST /v1/pointers', 200, _write('nope'));
      await expectLater(
          client.pointerCreate(owner, target1), throwsA(isA<InternalError>()));
    });

    test('a numeric counter in a response is an error', () async {
      final client = _answering('GET /v1/pointers/$owner/finality', 200,
          _finality('open', counter: 5));
      await expectLater(
          client.pointerFinality(owner), throwsA(isA<InternalError>()));
    });
  });

  group('pointer errors over REST', () {
    test('409 POINTER_FINAL is PointerFinalError, not AlreadyExists', () async {
      final client = _answering(
          'POST /v1/pointers/update', 409, _errorBody('POINTER_FINAL'));
      await expectLater(
          client.pointerUpdate(owner, target1),
          throwsA(allOf(
            isA<PointerFinalError>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having((e) => e.message, 'message', 'refused: POINTER_FINAL'),
            isNot(isA<AlreadyExistsError>()),
          )));
    });

    test('409 POINTER_FORKED is ForkError', () async {
      final client = _answering(
          'GET /v1/pointers/$owner', 409, _errorBody('POINTER_FORKED'));
      await expectLater(client.pointerGet(owner), throwsA(isA<ForkError>()));
    });

    test('409 CONFLICT is ConflictError', () async {
      final client =
          _answering('POST /v1/pointers/update', 409, _errorBody('CONFLICT'));
      await expectLater(
          client.pointerUpdate(owner, target1), throwsA(isA<ConflictError>()));
    });

    test('409 ALREADY_EXISTS keeps AlreadyExistsError', () async {
      final client =
          _answering('POST /v1/pointers', 409, _errorBody('ALREADY_EXISTS'));
      await expectLater(client.pointerCreate(owner, target1),
          throwsA(isA<AlreadyExistsError>()));
    });

    test('a 409 without a code keeps AlreadyExistsError', () async {
      final client = _answering('POST /v1/pointers', 409, 'conflict');
      await expectLater(client.pointerCreate(owner, target1),
          throwsA(isA<AlreadyExistsError>()));
    });

    test('503 CLOSE_GROUP_SHORTFALL with retryable true', () async {
      final client = _answering('POST /v1/pointers/finalize', 503,
          _errorBody('CLOSE_GROUP_SHORTFALL', {'retryable': true}));
      await expectLater(
          client.pointerFinalize('up1', {}),
          throwsA(isA<CloseGroupShortfallError>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.statusCode, 'statusCode', 503)));
    });

    for (final retryable in <Object?>[null, false, 'true', 1]) {
      test(
          '503 CLOSE_GROUP_SHORTFALL with retryable ${jsonEncode(retryable)}'
          ' is not retryable', () async {
        final body = _errorBody('CLOSE_GROUP_SHORTFALL');
        if (retryable != null) body['retryable'] = retryable;
        final client =
            _answering('GET /v1/pointers/$owner/finality', 503, body);
        await expectLater(
            client.pointerFinality(owner),
            throwsA(isA<CloseGroupShortfallError>()
                .having((e) => e.retryable, 'retryable', isFalse)));
      });
    }

    test('CloseGroupShortfallError is still a ServiceUnavailableError',
        () async {
      final client = _answering('POST /v1/pointers/transfer', 503,
          _errorBody('CLOSE_GROUP_SHORTFALL'));
      await expectLater(client.pointerTransfer(owner, other),
          throwsA(isA<ServiceUnavailableError>()));
    });

    test('a 503 with another code stays ServiceUnavailableError', () async {
      final client = _answering(
          'POST /v1/pointers', 503, _errorBody('SERVICE_UNAVAILABLE'));
      await expectLater(
          client.pointerCreate(owner, target1),
          throwsA(allOf(isA<ServiceUnavailableError>(),
              isNot(isA<CloseGroupShortfallError>()))));
    });

    test('400 for an unknown owner is BadRequestError', () async {
      final client =
          _answering('POST /v1/pointers', 400, _errorBody('BAD_REQUEST'));
      await expectLater(client.pointerCreate(owner, target1),
          throwsA(isA<BadRequestError>()));
    });

    test('a failed paid write is sent once, never retried', () async {
      final daemon = _Daemon({
        'POST /v1/pointers': (503, _errorBody('CLOSE_GROUP_SHORTFALL')),
        'POST /v1/pointers/update': (502, _errorBody('NETWORK_ERROR')),
        'POST /v1/pointers/transfer': (500, _errorBody('INTERNAL_ERROR')),
        'POST /v1/pointers/finalize': (
          503,
          _errorBody('CLOSE_GROUP_SHORTFALL', {'retryable': true})
        ),
      });
      final client = daemon.client;
      await expectLater(
          client.pointerCreate(owner, target1), throwsA(isA<AntdError>()));
      await expectLater(
          client.pointerUpdate(owner, target1), throwsA(isA<AntdError>()));
      await expectLater(
          client.pointerTransfer(owner, other), throwsA(isA<AntdError>()));
      await expectLater(
          client.pointerFinalize('up1', {}), throwsA(isA<AntdError>()));
      expect(daemon.requests.length, equals(4));
    });
  });

  group('PointerFinalityStatus', () {
    test('parses every known status and compares by value', () {
      expect(PointerFinalityStatus.fromWire('open'), isA<PointerOpen>());
      expect(
          PointerFinalityStatus.fromWire('settling'), isA<PointerSettling>());
      expect(PointerFinalityStatus.fromWire('unconfirmed'),
          isA<PointerUnconfirmed>());
      expect(PointerFinalityStatus.fromWire('final'), isA<PointerFinal>());
      expect(PointerFinalityStatus.fromWire('forked'), isA<PointerForked>());
      expect(PointerFinalityStatus.fromWire('new'),
          equals(const PointerFinalityUnknown('new')));
      expect(PointerFinalityStatus.fromWire('final'),
          isNot(equals(const PointerFinalityUnknown('final'))));
    });

    test('switches exhaustively', () {
      String describe(PointerFinalityStatus status) => switch (status) {
            PointerOpen() => 'open',
            PointerSettling() => 'settling',
            PointerUnconfirmed() => 'unconfirmed',
            PointerFinal() => 'final',
            PointerForked() => 'forked',
            PointerFinalityUnknown(:final wire) => 'unknown $wire',
          };
      expect(describe(PointerFinalityStatus.fromWire('final')), 'final');
      expect(describe(PointerFinalityStatus.fromWire('x')), 'unknown x');
    });
  });
}
