import 'dart:convert';

import 'package:antd_client/src/errors.dart';
import 'package:antd_client/src/generated/antd/v1/common.pb.dart' as common_msg;
import 'package:antd_client/src/generated/antd/v1/pointers.pbgrpc.dart'
    as pointers_pb;
import 'package:antd_client/src/grpc_client.dart';
import 'package:antd_client/src/models.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// PointerService wire mapping for [GrpcAntdClient]: a real grpc-dart server
/// on `127.0.0.1:0` with a mock PointerService, dialled by a real client.
/// Covers every method, the gRPC "unset" values ("" and absent messages)
/// reading as null, and the `x-antd-error-code` trailer mapping.

final owner = 'a1' * 32;
final other = 'b2' * 32;
final target1 = 'c3' * 32;
final stateId = 'e5' * 32;
const u64Max = '18446744073709551615';

const errorCodeTrailer = 'x-antd-error-code';

/// A status the daemon tags with its REST code, as antd's `with_code` does.
GrpcError tagged(int code, String message, String tag) =>
    GrpcError.custom(code, message, null, null, {errorCodeTrailer: tag});

void main() {
  late Server server;
  late GrpcAntdClient client;
  late _MockPointerService service;

  setUp(() async {
    service = _MockPointerService();
    server = Server.create(services: [service]);
    await server.serve(address: '127.0.0.1', port: 0);
    client = GrpcAntdClient(host: '127.0.0.1', port: server.port!);
  });

  tearDown(() async {
    await client.close();
    await server.shutdown();
  });

  group('PointerService requests and responses', () {
    test('pointerKeys', () async {
      expect(await client.pointerKeys(), equals([owner, other]));
    });

    test('pointerCreate sends the default kind', () async {
      final w = await client.pointerCreate(owner, target1);
      final req = service.lastWrite!;
      expect(
          [req.owner, req.target, req.kind], equals([owner, target1, 'chunk']));
      expect(w.address, equals(owner));
      expect(w.stateId, equals(stateId));
      expect(w.counter, equals(BigInt.zero));
    });

    test('pointerUpdate sends kind pointer', () async {
      final w =
          await client.pointerUpdate(owner, other, kind: PointerKind.pointer);
      expect(service.lastWrite!.kind, equals('pointer'));
      expect(w.counter, equals(BigInt.one));
    });

    test('pointerTransfer reads finality, "" reads as null', () async {
      final t = await client.pointerTransfer(owner, other);
      expect(service.lastTransfer!.recipient, equals(other));
      expect(t.finalityError, isNull);
      final f = t.finality!;
      expect(f.isFinal, isTrue);
      expect(f.status, equals(const PointerFinal()));
      expect(f.transferredTo, equals(other));
      expect(f.counter, isNull);
      expect(f.state!.transferredTo, equals(other));
      expect(f.majority, isNull);
      expect(f.states, isEmpty);
    });

    test('pointerTransfer without finality keeps the error', () async {
      final t = await client.pointerTransfer(owner, 'no-finality');
      expect(t.finality, isNull);
      expect(t.finalityError, equals('only 3 of 7 answered'));
    });

    test('pointerGet reads a final record at 2^64 - 1', () async {
      final r = await client.pointerGet(owner);
      expect(r.counter, equals(pointerFinalCounter));
      expect(r.isFinal, isTrue);
      expect(r.transferredTo, equals(other));
      expect(r.kindTag, equals(1));
      expect(r.targetKind, equals(PointerKind.pointer));
    });

    test('pointerGet reads an empty transferred_to as null', () async {
      final r = await client.pointerGet(other);
      expect(r.counter, equals(BigInt.from(2)));
      expect(r.isFinal, isFalse);
      expect(r.transferredTo, isNull);
    });

    test('pointerResolve', () async {
      final r = await client.pointerResolve(owner);
      expect([r.kind, r.kindTag, r.target], equals(['chunk', 0, target1]));
    });

    test('pointerFinality open: counter set, absent messages null', () async {
      final f = await client.pointerFinality(other);
      expect(f.status, isA<PointerOpen>());
      expect(f.counter, equals(BigInt.from(4)));
      expect(f.state, isNull);
      expect(f.majority, isNull);
      expect(f.transferredTo, isNull);
      expect([f.group, f.answered], equals([7, 6]));
    });

    test('pointerFinality open with an empty counter reads null', () async {
      final f = await client.pointerFinality('open-empty');
      expect(f.counter, isNull);
    });

    test('pointerFinality forked carries every state and the majority',
        () async {
      final f = await client.pointerFinality('forked');
      expect(f.status, isA<PointerForked>());
      expect(f.states.map((s) => s.holders), equals([5, 2]));
      expect(f.majority!.holders, equals(5));
      expect(f.state, isNull);
    });

    test('pointerFinality keeps an unknown status', () async {
      final f = await client.pointerFinality('contested');
      expect(f.status, equals(const PointerFinalityUnknown('contested')));
    });

    test('pointerController', () async {
      final c = await client.pointerController(owner);
      expect(c.pointer, equals(other));
      expect(c.transfers, equals([other]));
      expect(c.frozen, isFalse);
    });

    test('pointerPrepare update maps the payment and signed quotes', () async {
      final p = await client.pointerPrepare(PointerPrepareRequest.update(
          owner: owner, target: target1, includeSignedQuotes: true));
      final req = service.lastPrepare!;
      expect([req.owner, req.op, req.target, req.kind, req.recipient],
          equals([owner, 'update', target1, 'chunk', '']));
      expect(req.includeSignedQuotes, isTrue);
      expect(p.uploadId, equals('up1'));
      expect(p.op, equals('update'));
      expect(p.counter, equals(BigInt.one));
      expect(p.paymentType, equals('wave_batch'));
      expect(p.payments.single.quoteHash, equals('0xq'));
      expect(p.payments.single.rewardsAddress, equals('0xr'));
      expect(p.totalAmount, equals('9'));
      expect(p.rpcUrl, equals('http://rpc'));
      // Bytes over gRPC, base64 to match REST.
      expect(p.signedQuotes.first.quote, equals(base64.encode([1, 2, 3])));
      expect(p.signedQuotes.first.commitmentSidecar,
          equals(base64.encode([4, 5])));
      expect(p.signedQuotes.last.commitmentSidecar, isNull);
    });

    test('pointerPrepare transfer sends the recipient only', () async {
      await client.pointerPrepare(
          PointerPrepareRequest.transfer(owner: owner, recipient: other));
      final req = service.lastPrepare!;
      expect([req.op, req.target, req.kind, req.recipient],
          equals(['transfer', '', '', other]));
      expect(req.includeSignedQuotes, isFalse);
    });

    test('pointerFinalize sends the tx hashes', () async {
      final r = await client.pointerFinalize('up1', {'0xq': '0xtx'});
      expect(service.lastFinalize!.uploadId, equals('up1'));
      expect(service.lastFinalize!.txHashes, equals({'0xq': '0xtx'}));
      expect(r.counter, equals(BigInt.one));
      expect(r.finality, isNull);
    });

    test('pointerFinalize of a transfer carries finality', () async {
      final r = await client.pointerFinalize('transfer', {});
      expect(r.counter, equals(pointerFinalCounter));
      expect(r.finality!.status, isA<PointerSettling>());
    });

    test('a malformed counter is an error, not zero', () async {
      await expectLater(
          client.pointerGet('bad-counter'), throwsA(isA<InternalError>()));
      await expectLater(client.pointerCreate('bad-counter', target1),
          throwsA(isA<InternalError>()));
    });
  });

  group('PointerService errors', () {
    Future<void> expectError(GrpcError error, Matcher matcher) async {
      service.error = error;
      await expectLater(client.pointerUpdate(owner, target1), throwsA(matcher));
    }

    test('FAILED_PRECONDITION + POINTER_FINAL is PointerFinalError', () async {
      await expectError(
          tagged(StatusCode.failedPrecondition, 'Pointer is final: x',
              'POINTER_FINAL'),
          allOf(
            isA<PointerFinalError>()
                .having((e) => e.message, 'message', 'Pointer is final: x'),
            isNot(isA<PaymentError>()),
          ));
    });

    test('FAILED_PRECONDITION + POINTER_FORKED is ForkError', () async {
      await expectError(
          tagged(StatusCode.failedPrecondition, 'Pointer is forked: x',
              'POINTER_FORKED'),
          isA<ForkError>());
    });

    test('FAILED_PRECONDITION without a tag is still PaymentError', () async {
      await expectError(
          const GrpcError.failedPrecondition('wallet not configured'),
          isA<PaymentError>());
    });

    test('ABORTED + CONFLICT is ConflictError', () async {
      await expectError(
          tagged(StatusCode.aborted, 'Conflict: pending', 'CONFLICT'),
          isA<ConflictError>());
    });

    test('UNAVAILABLE + CLOSE_GROUP_SHORTFALL with the retained hint',
        () async {
      await expectError(
          tagged(
              StatusCode.unavailable,
              'Close group shortfall: stored on 4 of 7 (paid attempt '
                  'retained: call finalize again with the same upload_id to '
                  'store it against the same payment)',
              'CLOSE_GROUP_SHORTFALL'),
          isA<CloseGroupShortfallError>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.statusCode, 'statusCode', 503));
    });

    test('UNAVAILABLE + CLOSE_GROUP_SHORTFALL without the hint', () async {
      await expectError(
          tagged(
              StatusCode.unavailable,
              'Close group shortfall: only 3 answered',
              'CLOSE_GROUP_SHORTFALL'),
          isA<CloseGroupShortfallError>()
              .having((e) => e.retryable, 'retryable', isFalse));
    });

    test('a retained hint that does not close the message is not retryable',
        () async {
      await expectError(
          tagged(
              StatusCode.unavailable,
              'Close group shortfall: peer said (paid attempt retained) but '
                  'then failed',
              'CLOSE_GROUP_SHORTFALL'),
          isA<CloseGroupShortfallError>()
              .having((e) => e.retryable, 'retryable', isFalse));
    });

    test('UNAVAILABLE without a tag is still NetworkError', () async {
      await expectError(const GrpcError.unavailable('no route'),
          allOf(isA<NetworkError>(), isNot(isA<CloseGroupShortfallError>())));
    });

    test('a tag on a status code it does not belong to is ignored', () async {
      await expectError(
          tagged(StatusCode.aborted, 'Pointer is final: x', 'POINTER_FINAL'),
          allOf(isA<AntdError>(), isNot(isA<PointerFinalError>())));
      await expectError(tagged(StatusCode.failedPrecondition, 'x', 'CONFLICT'),
          isA<PaymentError>());
    });

    test('an unknown tag keeps the code mapping', () async {
      await expectError(
          tagged(StatusCode.failedPrecondition, 'x', 'SOMETHING_NEW'),
          isA<PaymentError>());
    });

    test('ALREADY_EXISTS is AlreadyExistsError', () async {
      await expectError(
          const GrpcError.alreadyExists('exists'), isA<AlreadyExistsError>());
    });

    test('the tag maps on reads too', () async {
      service.error = tagged(StatusCode.unavailable,
          'Close group shortfall: only 3 answered', 'CLOSE_GROUP_SHORTFALL');
      await expectLater(client.pointerFinality(owner),
          throwsA(isA<CloseGroupShortfallError>()));
      service.error = tagged(StatusCode.failedPrecondition,
          'Pointer is forked: x', 'POINTER_FORKED');
      await expectLater(client.pointerGet(owner), throwsA(isA<ForkError>()));
    });
  });
}

pointers_pb.PointerFinalState _finalState(int holders,
        {String transferredTo = ''}) =>
    pointers_pb.PointerFinalState()
      ..stateId = stateId
      ..kind = 'pointer'
      ..kindTag = 1
      ..target = other
      ..holders = holders
      ..transferredTo = transferredTo;

/// Mock PointerService. Throws [error] from every method when set; otherwise
/// answers by the request's address or owner, and records the last request.
class _MockPointerService extends pointers_pb.PointerServiceBase {
  GrpcError? error;
  pointers_pb.PointerWriteRequest? lastWrite;
  pointers_pb.PointerTransferRequest? lastTransfer;
  pointers_pb.PreparePointerRequest? lastPrepare;
  pointers_pb.FinalizePointerRequest? lastFinalize;

  void _maybeThrow() {
    if (error != null) throw error!;
  }

  pointers_pb.PointerWriteResponse _write(
          pointers_pb.PointerWriteRequest request, String counter) =>
      pointers_pb.PointerWriteResponse()
        ..address = request.owner
        ..stateId = stateId
        ..counter = request.owner == 'bad-counter' ? '-1' : counter;

  @override
  Future<pointers_pb.ListPointerKeysResponse> listKeys(
      ServiceCall call, pointers_pb.ListPointerKeysRequest request) async {
    _maybeThrow();
    return pointers_pb.ListPointerKeysResponse()
      ..keys.addAll([
        pointers_pb.PointerKey()..address = owner,
        pointers_pb.PointerKey()..address = other,
      ]);
  }

  @override
  Future<pointers_pb.PointerWriteResponse> create(
      ServiceCall call, pointers_pb.PointerWriteRequest request) async {
    _maybeThrow();
    lastWrite = request;
    return _write(request, '0');
  }

  @override
  Future<pointers_pb.PointerWriteResponse> update(
      ServiceCall call, pointers_pb.PointerWriteRequest request) async {
    _maybeThrow();
    lastWrite = request;
    return _write(request, '1');
  }

  @override
  Future<pointers_pb.PointerTransferResponse> transfer(
      ServiceCall call, pointers_pb.PointerTransferRequest request) async {
    _maybeThrow();
    lastTransfer = request;
    final resp = pointers_pb.PointerTransferResponse()
      ..address = request.owner
      ..stateId = stateId;
    if (request.recipient == 'no-finality') {
      return resp..finalityError = 'only 3 of 7 answered';
    }
    return resp
      ..finality = (pointers_pb.PointerFinality()
        ..address = request.owner
        ..group = 7
        ..answered = 7
        ..status = 'final'
        ..state = _finalState(7, transferredTo: request.recipient)
        ..transferredTo = request.recipient);
  }

  @override
  Future<pointers_pb.PointerRecord> get(
      ServiceCall call, pointers_pb.GetPointerRequest request) async {
    _maybeThrow();
    final record = pointers_pb.PointerRecord()
      ..address = request.address
      ..owner = 'ab' * 1952
      ..kind = 'pointer'
      ..kindTag = 1
      ..target = other
      ..stateId = stateId;
    switch (request.address) {
      case 'bad-counter':
        return record..counter = '1.5';
      case final a when a == owner:
        return record
          ..counter = u64Max
          ..isFinal = true
          ..transferredTo = other;
      default:
        return record..counter = '2';
    }
  }

  @override
  Future<pointers_pb.PointerResolved> resolve(
      ServiceCall call, pointers_pb.ResolvePointerRequest request) async {
    _maybeThrow();
    return pointers_pb.PointerResolved()
      ..kind = 'chunk'
      ..kindTag = 0
      ..target = target1;
  }

  @override
  Future<pointers_pb.PointerFinality> finality(
      ServiceCall call, pointers_pb.PointerFinalityRequest request) async {
    _maybeThrow();
    final f = pointers_pb.PointerFinality()
      ..address = request.address
      ..group = 7
      ..answered = 6;
    switch (request.address) {
      case 'open-empty':
        return f..status = 'open';
      case 'forked':
        return f
          ..status = 'forked'
          ..states.addAll([_finalState(5), _finalState(2)])
          ..majority = _finalState(5);
      case 'contested':
        return f..status = 'contested';
      default:
        return f
          ..status = 'open'
          ..counter = '4';
    }
  }

  @override
  Future<pointers_pb.PointerController> controller(
      ServiceCall call, pointers_pb.PointerControllerRequest request) async {
    _maybeThrow();
    return pointers_pb.PointerController()
      ..pointer = other
      ..transfers.add(other);
  }

  @override
  Future<pointers_pb.PreparePointerResponse> prepare(
      ServiceCall call, pointers_pb.PreparePointerRequest request) async {
    _maybeThrow();
    lastPrepare = request;
    final resp = pointers_pb.PreparePointerResponse()
      ..uploadId = 'up1'
      ..op = request.op
      ..address = request.owner
      ..stateId = stateId
      ..counter = request.op == 'transfer' ? u64Max : '1'
      ..paymentType = 'wave_batch'
      ..payments.add(common_msg.PaymentEntry()
        ..quoteHash = '0xq'
        ..rewardsAddress = '0xr'
        ..amount = '9')
      ..totalAmount = '9'
      ..paymentVaultAddress = '0xvault'
      ..paymentTokenAddress = '0xtoken'
      ..rpcUrl = 'http://rpc';
    if (request.includeSignedQuotes) {
      resp.signedQuotes.addAll([
        common_msg.SignedQuoteEntry()
          ..quoteHash = '0xq'
          ..quote = [1, 2, 3]
          ..commitmentSidecar = [4, 5],
        common_msg.SignedQuoteEntry()
          ..quoteHash = '0xb'
          ..quote = [6],
      ]);
    }
    return resp;
  }

  @override
  Future<pointers_pb.FinalizePointerResponse> finalize(
      ServiceCall call, pointers_pb.FinalizePointerRequest request) async {
    _maybeThrow();
    lastFinalize = request;
    final resp = pointers_pb.FinalizePointerResponse()
      ..address = owner
      ..stateId = stateId;
    if (request.uploadId == 'transfer') {
      return resp
        ..counter = u64Max
        ..finality = (pointers_pb.PointerFinality()
          ..address = owner
          ..group = 7
          ..answered = 7
          ..status = 'settling'
          ..state = _finalState(4, transferredTo: other));
    }
    return resp..counter = '1';
  }
}
