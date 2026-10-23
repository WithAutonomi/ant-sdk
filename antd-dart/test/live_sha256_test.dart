// Live sha256 checks against a running antd 0.17.0 or later with a devnet
// behind it.
//
// Skipped unless both are set:
//
// - ANTD_TEST_URL: the daemon's REST base URL, e.g. http://127.0.0.1:18084
// - ANTD_TEST_SHA_LINK: a manifest link with entries public.txt, private.txt
//   and nohash.txt (the first two carry a sha256, the third none)
//
// Also read (the checks that need them are skipped when unset):
//
// - ANTD_TEST_SHA_PUBLIC_SHA256, ANTD_TEST_SHA_DATA_MAP_SHA256: the hashes
//   public.txt and private.txt carry
// - ANTD_TEST_SHA_PUBLIC_ADDRESS: public data already on the network
// - ANTD_TEST_GRPC: the daemon's gRPC endpoint as host:port; without it the
//   gRPC test is skipped
//
// The one paid call per transport is a small public data upload.
//
//   source ~/sha-fanout-daemon/fixtures.env
//   dart test test/live_sha256_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';
import 'package:antd_client/src/grpc_client.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

final _env = Platform.environment;
final _url = _env['ANTD_TEST_URL'];
final _grpc = _env['ANTD_TEST_GRPC'];
final _link = _env['ANTD_TEST_SHA_LINK'];
final _publicAddress = _env['ANTD_TEST_SHA_PUBLIC_ADDRESS'];
final _publicSha = _env['ANTD_TEST_SHA_PUBLIC_SHA256'];
final _dataMapSha = _env['ANTD_TEST_SHA_DATA_MAP_SHA256'];

bool _unset(String? s) => s == null || s.isEmpty;

Object _skip() {
  if (_unset(_url) || _unset(_link)) {
    return 'set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run';
  }
  if (_unset(_publicAddress) || _unset(_publicSha) || _unset(_dataMapSha)) {
    return 'set the ANTD_TEST_SHA_* fixtures to run '
        '(source ~/sha-fanout-daemon/fixtures.env)';
  }
  return false;
}

Object _skipGrpc() {
  final skip = _skip();
  if (skip != false) return skip;
  return _unset(_grpc) ? 'set ANTD_TEST_GRPC to run' : false;
}

GrpcAntdClient _grpcClient(String target) {
  final hostPort = target.replaceFirst(RegExp(r'^https?://'), '');
  final colon = hostPort.lastIndexOf(':');
  return GrpcAntdClient(
    host: hostPort.substring(0, colon),
    port: int.parse(hostPort.substring(colon + 1)),
  );
}

typedef _Build = Future<BuiltManifest> Function(List<ManifestEntryInput>);
typedef _DecodeLink = Future<DecodedManifest> Function(String, {bool resolve});
typedef _PutPublic = Future<DataPutPublicResult> Function(Uint8List);

Future<void> _check(
    _Build build, _DecodeLink decodeLink, _PutPublic putPublic) async {
  // 1. Decode the fixture link without resolving.
  final decoded = await decodeLink(_link!, resolve: false);
  ManifestEntryInfo entry(String name) => decoded.entries
      .singleWhere((e) => e.effectiveName == name, orElse: () => fail(name));
  expect(entry('public.txt').sha256, equals(_publicSha));
  expect(entry('private.txt').sha256, equals(_dataMapSha));
  expect(entry('nohash.txt').sha256, isNull);

  // 2. Build with a sha256: the returned entry carries it.
  final built = await build([
    ManifestEntryInput(
        path: 'a.txt', address: _publicAddress, sha256: _publicSha),
  ]);
  expect(built.entries.single.sha256, equals(_publicSha));

  // 3. A malformed one is the daemon's bad-request error.
  await expectLater(
    build([
      ManifestEntryInput(path: 'a.txt', address: _publicAddress, sha256: 'zz'),
    ]),
    throwsA(isA<BadRequestError>()
        .having((e) => e.message, 'message', contains('sha256'))),
  );

  // 4. One paid call: a small public upload reports the plaintext's SHA-256.
  final payload = utf8.encode(
      'sha-fanout dart ${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
  final put = await putPublic(Uint8List.fromList(payload));
  expect(put.sha256, equals(crypto.sha256.convert(payload).toString()));
}

void main() {
  test(
    'live sha256 over REST',
    () async {
      final rest = AntdClient(baseUrl: _url!);
      addTearDown(rest.close);
      await _check(
        (entries) => rest.buildManifest(entries),
        (link, {resolve = false}) =>
            rest.decodeManifestLink(link, resolve: resolve),
        (data) => rest.dataPutPublic(data),
      );
    },
    skip: _skip(),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live sha256 over gRPC',
    () async {
      final grpc = _grpcClient(_grpc!);
      addTearDown(grpc.close);
      await _check(
        (entries) => grpc.buildManifest(entries),
        (link, {resolve = false}) =>
            grpc.decodeManifestLink(link, resolve: resolve),
        (data) => grpc.dataPutPublic(data),
      );
    },
    skip: _skipGrpc(),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
