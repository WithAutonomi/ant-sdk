// Live manifest round trip against a running antd with a devnet behind it.
//
// Skipped unless both are set:
//
// - ANTD_TEST_URL: the daemon's REST base URL, e.g. http://127.0.0.1:8082
// - ANTD_TEST_MANIFEST_ADDRESSES: two comma-separated addresses of public
//   data already on the network
//
// Optional:
//
// - ANTD_TEST_GRPC: the daemon's gRPC endpoint as host:port; without it the
//   gRPC test is skipped
// - ANTD_TEST_MANIFEST_SIZES: the two uploads' exact plaintext sizes,
//   comma-separated, checked against a resolving decode
// - ANTD_TEST_MANIFEST_DATA_MAP: a private upload's hex DataMap, added as an
//   embedded entry (ANTD_TEST_MANIFEST_DATA_MAP_SIZE: its plaintext size)
// - ANTD_TEST_MANIFEST_LINK: an `ant://manifest/` link to decode
//
// Nothing is uploaded or paid for: the test only builds and decodes
// manifests of data that is already there.
//
//   ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
//   ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> \
//   dart test test/live_manifests_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';
import 'package:antd_client/src/grpc_client.dart';
import 'package:test/test.dart';

final _env = Platform.environment;
final _url = _env['ANTD_TEST_URL'];
final _grpc = _env['ANTD_TEST_GRPC'];
final _addresses = _env['ANTD_TEST_MANIFEST_ADDRESSES']
    ?.split(',')
    .map((a) => a.trim())
    .where((a) => a.isNotEmpty)
    .toList();
final _sizes = _env['ANTD_TEST_MANIFEST_SIZES']
    ?.split(',')
    .map((s) => int.parse(s.trim()))
    .toList();
final _dataMap = _nonEmpty(_env['ANTD_TEST_MANIFEST_DATA_MAP']);
final _dataMapSize = _nonEmpty(_env['ANTD_TEST_MANIFEST_DATA_MAP_SIZE']);
final _link = _nonEmpty(_env['ANTD_TEST_MANIFEST_LINK']);

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;

Object _skip() {
  if (_url == null || _addresses == null) {
    return 'set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run';
  }
  if (_addresses!.length != 2) {
    return 'ANTD_TEST_MANIFEST_ADDRESSES must hold two addresses';
  }
  return false;
}

Object _skipGrpc() {
  final skip = _skip();
  if (skip != false) return skip;
  return _grpc == null ? 'set ANTD_TEST_GRPC to run' : false;
}

GrpcAntdClient _grpcClient(String target) {
  final hostPort = target.replaceFirst(RegExp(r'^https?://'), '');
  final colon = hostPort.lastIndexOf(':');
  return GrpcAntdClient(
    host: hostPort.substring(0, colon),
    port: int.parse(hostPort.substring(colon + 1)),
  );
}

const _one = 'live/one.txt';
const _two = 'live/two.txt';
const _three = 'live/private/three.txt';

/// The fixtures as build entries: the two public addresses and, when given,
/// the private DataMap, each with a path.
List<ManifestEntryInput> _inputs() => [
      ManifestEntryInput(path: _one, address: _addresses![0]),
      ManifestEntryInput(path: _two, address: _addresses![1]),
      if (_dataMap != null) ManifestEntryInput(path: _three, dataMap: _dataMap),
    ];

/// The same calls over either transport.
typedef _Build = Future<BuiltManifest> Function(List<ManifestEntryInput>,
    {String? name});
typedef _Decode = Future<DecodedManifest> Function(Uint8List, {bool resolve});
typedef _DecodeLink = Future<DecodedManifest> Function(String, {bool resolve});

ManifestEntryInfo _entry(List<ManifestEntryInfo> entries, String name) =>
    entries.singleWhere((e) => e.effectiveName == name,
        orElse: () => fail('no entry named $name in $entries'));

void _checkBuilt(BuiltManifest built) {
  expect(built.manifest, isNotEmpty);
  expect(built.link, isNotNull);
  expect(built.link, startsWith('ant://manifest/'));
  expect(built.entries.map((e) => e.effectiveName),
      equals([_one, _two, if (_dataMap != null) _three]..sort()),
      reason: 'entries come back in encoded (sorted) order');
  final one = _entry(built.entries, _one);
  expect(one.kind, equals('public'));
  expect(one.contentAddress, equals(_addresses![0]));
  expect(one.size, isNull, reason: 'no size was given');
  final two = _entry(built.entries, _two);
  expect(two.kind, equals('public'));
  expect(two.contentAddress, equals(_addresses![1]));
  if (_dataMap != null) {
    final three = _entry(built.entries, _three);
    expect(three.kind, equals('embedded'));
    expect(three.contentAddress, hasLength(64));
    expect(three.dataMap, isNull, reason: 'build reports no DataMap');
  }
}

/// A resolving decode of the fixtures: exact sizes for every entry, and the
/// DataMap entry embedded with its DataMap.
void _checkResolved(DecodedManifest decoded) {
  expect(decoded.source, equals('manifest'));
  expect(decoded.name, equals('antd-dart-live'));
  expect(decoded.torrentInfoHashV1, isNull);
  expect(decoded.torrentInfoHashV2, isNull);
  for (final (i, path) in [_one, _two].indexed) {
    final e = _entry(decoded.entries, path);
    expect(e.kind, equals('public'));
    expect(e.path, equals(path));
    expect(e.dataMap, isNull);
    expect(e.error, isNull, reason: 'resolve failed for $path');
    expect(e.exactSize, isNotNull);
    if (_sizes != null) expect(e.exactSize, equals(_sizes![i]));
  }
  if (_dataMap != null) {
    final e = _entry(decoded.entries, _three);
    expect(e.kind, equals('embedded'));
    expect(e.dataMap, isNotNull);
    expect(e.dataMap, isNotEmpty);
    expect(e.error, isNull);
    if (_dataMapSize != null) {
      expect(e.exactSize, equals(int.parse(_dataMapSize!)));
    }
  }
}

Future<BuiltManifest> _roundTrip(
    _Build build, _Decode decode, _DecodeLink decodeLink) async {
  // 1-2. Build, check kinds, names and the link.
  final built = await build(_inputs(), name: 'antd-dart-live');
  _checkBuilt(built);

  // 3. Decode the bytes and the link, resolving.
  _checkResolved(await decode(built.manifest, resolve: true));
  _checkResolved(await decodeLink(built.link!, resolve: true));

  // A bare address is a file link: one public entry with no path.
  final file = await decodeLink(_addresses![0], resolve: true);
  expect(file.source, equals('file_link'));
  expect(file.entries.single.path, isNull);
  expect(file.entries.single.contentAddress, equals(_addresses![0]));
  if (_sizes != null) expect(file.entries.single.exactSize, equals(_sizes![0]));

  // 4. The fixture link.
  if (_link != null) {
    final fixture = await decodeLink(_link!, resolve: true);
    expect(fixture.source, equals('manifest'));
    expect(
        fixture.entries.map((e) => e.contentAddress), containsAll(_addresses!));
    for (final e in fixture.entries) {
      expect(e.error, isNull, reason: '${e.effectiveName}: ${e.error}');
      expect(e.exactSize, isNotNull);
    }
    if (_dataMap != null) {
      expect(fixture.entries.where((e) => e.kind == 'embedded').single.dataMap,
          isNotEmpty);
    }
  }

  // 5. Bad entries: both sources is refused before sending; a bad path is
  // the daemon's 400 / INVALID_ARGUMENT, naming the entry.
  await expectLater(
    build([
      ManifestEntryInput(
          address: _addresses![0], dataMap: _dataMap ?? _addresses![1]),
    ]),
    throwsA(isA<ArgumentError>()),
  );
  await expectLater(
    build([ManifestEntryInput(path: '../x', address: _addresses![0])]),
    throwsA(isA<BadRequestError>()
        .having((e) => e.message, 'message', contains('entries[0]'))),
  );
  await expectLater(
    decode(Uint8List.fromList([1, 2, 3])),
    throwsA(isA<BadRequestError>()),
  );
  return built;
}

void main() {
  test(
    'live manifest round trip over REST',
    () async {
      final rest = AntdClient(baseUrl: _url!);
      addTearDown(rest.close);
      await _roundTrip(
        (entries, {name}) => rest.buildManifest(entries, name: name),
        (bytes, {resolve = false}) =>
            rest.decodeManifest(bytes, resolve: resolve),
        (link, {resolve = false}) =>
            rest.decodeManifestLink(link, resolve: resolve),
      );
    },
    skip: _skip(),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live manifest round trip over gRPC, matching REST',
    () async {
      final rest = AntdClient(baseUrl: _url!);
      final grpc = _grpcClient(_grpc!);
      addTearDown(() async {
        rest.close();
        await grpc.close();
      });
      final built = await _roundTrip(
        (entries, {name}) => grpc.buildManifest(entries, name: name),
        (bytes, {resolve = false}) =>
            grpc.decodeManifest(bytes, resolve: resolve),
        (link, {resolve = false}) =>
            grpc.decodeManifestLink(link, resolve: resolve),
      );

      // Both transports produce the same bytes and link.
      final viaRest =
          await rest.buildManifest(_inputs(), name: 'antd-dart-live');
      expect(built.manifest, equals(viaRest.manifest));
      expect(built.link, equals(viaRest.link));
    },
    skip: _skipGrpc(),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'a manifest past 4 MiB goes both ways over gRPC',
    () async {
      final grpc = _grpcClient(_grpc!);
      addTearDown(grpc.close);
      // Public entries need no network on build. ~800-byte paths make each
      // entry large, so 6,000 of them pass 4 MiB as a request, a manifest
      // and a decode request.
      final dirs = '${'a' * 250}/${'b' * 250}/${'c' * 250}';
      final entries = [
        for (var i = 0; i < 6000; i++)
          ManifestEntryInput(path: 'big/$dirs/$i.bin', address: _addresses![0]),
      ];
      final built = await grpc.buildManifest(entries);
      expect(built.manifest.length, greaterThan(4 * 1024 * 1024));
      expect(built.link, isNull, reason: 'far past 1,500 bytes');
      expect(built.entries, hasLength(6000));

      final decoded = await grpc.decodeManifest(built.manifest);
      expect(decoded.entries, hasLength(6000));
      expect(decoded.entries.first.contentAddress, equals(_addresses![0]));
    },
    skip: _skipGrpc(),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
