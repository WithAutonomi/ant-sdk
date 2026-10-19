// Live pointer round trip against a running antd with a devnet behind it.
//
// Skipped unless all three are set:
//
// - ANTD_TEST_URL: the daemon's REST base URL, e.g. http://127.0.0.1:8082
// - ANTD_TEST_GRPC: its gRPC endpoint as host:port, e.g. 127.0.0.1:50051
// - ANTD_TEST_POINTER_OWNERS: two comma-separated pointer addresses the
//   daemon holds keys for (antd --pointer-keys) and that have never been
//   written. The test creates both, transfers the first to the second, and
//   leaves the second with a prepared write awaiting payment, so each pair
//   can be used once.
//
// Every write is paid by the daemon's wallet, so run it against a devnet:
//
//   ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
//   ANTD_TEST_POINTER_OWNERS=<hex>,<hex> dart test test/live_pointers_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';
import 'package:antd_client/src/grpc_client.dart';
import 'package:test/test.dart';

final _env = Platform.environment;
final _url = _env['ANTD_TEST_URL'];
final _grpc = _env['ANTD_TEST_GRPC'];
final _owners = _env['ANTD_TEST_POINTER_OWNERS']?.split(',');

/// The daemon accepts a 0x prefix but returns bare hex.
String _norm(String address) {
  final a = address.trim().toLowerCase();
  return a.startsWith('0x') ? a.substring(2) : a;
}

Object _skip() {
  if (_url == null || _grpc == null || _owners == null) {
    return 'set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS '
        'to run';
  }
  if (_owners!.length != 2) {
    return 'ANTD_TEST_POINTER_OWNERS must hold two addresses';
  }
  return false;
}

GrpcAntdClient _grpcClient(String target) {
  final hostPort = target.replaceFirst(RegExp(r'^https?://'), '');
  final colon = hostPort.lastIndexOf(':');
  return GrpcAntdClient(
    host: hostPort.substring(0, colon),
    port: int.parse(hostPort.substring(colon + 1)),
  );
}

void main() {
  test(
    'live pointer round trip over REST and gRPC',
    () async {
      final a = _norm(_owners![0]);
      final b = _norm(_owners![1]);
      final rest = AntdClient(baseUrl: _url!);
      final grpc = _grpcClient(_grpc!);
      addTearDown(() async {
        rest.close();
        await grpc.close();
      });

      // Both owners must be writable through this daemon.
      final keys = (await rest.pointerKeys()).map(_norm).toList();
      expect(keys, containsAll([a, b]),
          reason: 'daemon holds no key for one of the owners');
      expect((await grpc.pointerKeys()).map(_norm), containsAll([a, b]));

      // Real targets, so the chain can be followed back to bytes.
      final oneBytes = utf8.encode('antd-dart pointer target one');
      final twoBytes = utf8.encode('antd-dart pointer target two');
      final one =
          (await rest.dataPutPublic(Uint8List.fromList(oneBytes))).address;
      final two =
          (await rest.dataPutPublic(Uint8List.fromList(twoBytes))).address;

      // REST: create, read, update.
      await expectLater(rest.pointerGet(a), throwsA(isA<NotFoundError>()),
          reason: 'owner $a has been written before; use a fresh pair');
      var w = await rest.pointerCreate(a, one);
      expect(w.counter, equals(BigInt.zero));
      expect(_norm(w.address), equals(a));
      await expectLater(
          rest.pointerCreate(a, two), throwsA(isA<AlreadyExistsError>()));
      var r = await rest.pointerGet(a);
      expect(r.counter, equals(BigInt.zero));
      expect(r.target, equals(one));
      expect(r.isFinal, isFalse);
      expect(r.transferredTo, isNull);
      expect(r.targetKind, equals(PointerKind.chunk));
      expect(r.owner.length, equals(2 * 1952));
      final resolved = await rest.pointerResolve(a);
      expect(resolved.target, equals(one));
      expect(await rest.dataGetPublic(resolved.target), equals(oneBytes));

      w = await rest.pointerUpdate(a, two);
      expect(w.counter, equals(BigInt.one));
      expect((await rest.pointerResolve(a)).target, equals(two));
      var f = await rest.pointerFinality(a);
      expect(f.status, isA<PointerOpen>());
      expect(f.counter, equals(BigInt.one));
      expect(f.answered, equals(f.group));

      // gRPC: a write, then a read.
      w = await grpc.pointerCreate(b, one);
      expect(w.counter, equals(BigInt.zero));
      r = await grpc.pointerGet(b);
      expect(r.counter, equals(BigInt.zero));
      expect(r.target, equals(one));
      expect(r.transferredTo, isNull);

      // Transfer a -> b.
      final t = await rest.pointerTransfer(a, b);
      expect(t.finality, isNotNull,
          reason: 'the close group should answer after the transfer '
              '(${t.finalityError})');
      expect(t.finality!.status, isA<PointerFinal>());
      expect(t.finality!.transferredTo, equals(b));
      r = await rest.pointerGet(a);
      expect(r.isFinal, isTrue);
      expect(r.counter, equals(pointerFinalCounter));
      expect(r.transferredTo, equals(b));
      final c = await rest.pointerController(a);
      expect(c.pointer, equals(b));
      expect(c.transfers, equals([b]));
      expect(c.frozen, isFalse);
      // a now resolves through b.
      expect((await grpc.pointerResolve(a)).target, equals(one));
      f = await grpc.pointerFinality(a);
      expect(f.isFinal, isTrue);
      expect(f.transferredTo, equals(b));
      r = await grpc.pointerGet(a);
      expect(r.counter, equals(pointerFinalCounter));
      expect(r.transferredTo, equals(b));

      // A final pointer refuses every write, before anything is paid.
      await expectLater(
          rest.pointerUpdate(a, one), throwsA(isA<PointerFinalError>()));
      await expectLater(
          grpc.pointerUpdate(a, one), throwsA(isA<PointerFinalError>()));
      await expectLater(
          rest.pointerTransfer(a, b), throwsA(isA<PointerFinalError>()));

      // External signer, up to the quote. Last: the prepared write blocks
      // b's other writes until it expires.
      final p = await rest
          .pointerPrepare(PointerPrepareRequest.update(owner: b, target: two));
      expect(p.op, equals('update'));
      expect(p.counter, equals(BigInt.one));
      expect(p.paymentType, equals('wave_batch'));
      expect(p.payments, isNotEmpty);
      expect(p.uploadId, isNotEmpty);
      await expectLater(
          rest.pointerUpdate(b, two), throwsA(isA<ConflictError>()));
      await expectLater(
          grpc.pointerPrepare(
              PointerPrepareRequest.update(owner: b, target: two)),
          throwsA(isA<ConflictError>()));
      // A finalize without the payment is refused and keeps the session.
      await expectLater(rest.pointerFinalize(p.uploadId, {}),
          throwsA(isA<BadRequestError>()));
      await expectLater(
          rest.pointerUpdate(b, two), throwsA(isA<ConflictError>()));
    },
    skip: _skip(),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
