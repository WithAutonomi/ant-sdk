import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// The `sha256` fields (antd 0.17.0) over REST against a mock daemon: each
/// upload result reads it when present and as null when the key is absent or
/// empty, a manifest entry input sends it only when set and non-empty, a
/// manifest entry info reads it, and the daemon's 400 for a bad one is a
/// BadRequestError.

final sha = 'ab' * 32;
final addr = 'aa' * 32;

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
          return http.Response(jsonEncode(body), status,
              headers: {'content-type': 'application/json'});
        }),
      );

  Map<String, dynamic> body(int index) =>
      jsonDecode(requests[index].body) as Map<String, dynamic>;
}

typedef _Call = Future<String?> Function(AntdClient);

void main() {
  final calls = <String, (String, Map<String, dynamic>, _Call)>{
    'dataPut': (
      'POST /v1/data',
      {'data_map': 'dd', 'chunks_stored': 3},
      (c) async => (await c.dataPut(Uint8List(1))).sha256
    ),
    'dataPutPublic': (
      'POST /v1/data/public',
      {'address': addr, 'chunks_stored': 3},
      (c) async => (await c.dataPutPublic(Uint8List(1))).sha256
    ),
    'filePut': (
      'POST /v1/files',
      {
        'data_map': 'dd',
        'storage_cost_atto': '1',
        'gas_cost_wei': '2',
        'chunks_stored': 3,
        'payment_mode_used': 'single',
      },
      (c) async => (await c.filePut('/tmp/f')).sha256
    ),
    'filePutPublic': (
      'POST /v1/files/public',
      {
        'address': addr,
        'storage_cost_atto': '1',
        'gas_cost_wei': '2',
        'chunks_stored': 3,
        'payment_mode_used': 'single',
      },
      (c) async => (await c.filePutPublic('/tmp/f')).sha256
    ),
    'finalizeUpload': (
      'POST /v1/upload/finalize',
      {'address': '', 'chunks_stored': 3, 'data_map': 'dd'},
      (c) async => (await c.finalizeUpload('u', {})).sha256
    ),
    'finalizeMerkleUpload': (
      'POST /v1/upload/finalize',
      {'address': '', 'chunks_stored': 3, 'data_map': 'dd'},
      (c) async => (await c.finalizeMerkleUpload('u', '0xp')).sha256
    ),
  };

  group('upload results', () {
    for (final entry in calls.entries) {
      final (route, base, call) = entry.value;
      test('${entry.key} reads sha256, none when absent or empty', () async {
        final present = _Daemon({
          route: (200, {...base, 'sha256': sha})
        });
        expect(await call(present.client), equals(sha));
        final absent = _Daemon({route: (200, base)});
        expect(await call(absent.client), isNull);
        final empty = _Daemon({
          route: (200, {...base, 'sha256': ''})
        });
        expect(await call(empty.client), isNull);
      });
    }

    test('existing construction still compiles; sha256 defaults to null', () {
      expect(const DataPutResult(dataMap: 'x').sha256, isNull);
      expect(const DataPutPublicResult(address: 'x').sha256, isNull);
      expect(
          const FilePutResult(
                  dataMap: 'x',
                  storageCostAtto: '0',
                  gasCostWei: '0',
                  chunksStored: 0,
                  paymentModeUsed: 'auto')
              .sha256,
          isNull);
      expect(const FinalizeUploadResult(address: '', chunksStored: 0).sha256,
          isNull);
    });
  });

  const build = 'POST /v1/manifests/build';
  const decode = 'POST /v1/manifests/decode';

  Map<String, dynamic> info(String name,
          {Object? sha256, bool present = false}) =>
      {
        'effective_name': name,
        'path': name,
        'kind': 'public',
        'content_address': addr,
        if (present) 'sha256': sha256,
      };

  group('manifest entries', () {
    test('build sends sha256 only when set and non-empty', () async {
      final daemon = _Daemon({
        build: (
          200,
          {
            'manifest': 'wUFOVAE=',
            'entries': [
              info('a.txt', sha256: sha, present: true),
              info('b.txt'),
              info('c.txt', sha256: '', present: true),
            ],
          }
        ),
      });
      final res = await daemon.client.buildManifest([
        ManifestEntryInput(path: 'a.txt', address: addr, sha256: sha),
        ManifestEntryInput(path: 'b.txt', address: addr),
        ManifestEntryInput(path: 'c.txt', address: addr, sha256: ''),
      ]);
      final entries = daemon.body(0)['entries'] as List;
      expect(entries[0],
          equals({'path': 'a.txt', 'address': addr, 'sha256': sha}));
      expect(entries[1], equals({'path': 'b.txt', 'address': addr}));
      expect(entries[2], equals({'path': 'c.txt', 'address': addr}));
      expect(res.entries[0].sha256, equals(sha));
      expect(res.entries[1].sha256, isNull);
      expect(res.entries[2].sha256, isNull, reason: 'an empty string is none');
    });

    test('sha256 is passed through as given', () async {
      final daemon = _Daemon({
        build: (200, {'manifest': 'wUFOVAE=', 'entries': []})
      });
      await daemon.client
          .buildManifest([ManifestEntryInput(address: addr, sha256: 'ZZ ')]);
      expect((daemon.body(0)['entries'] as List)[0]['sha256'], equals('ZZ '));
    });

    test('decode reads sha256, none when absent or empty', () async {
      final daemon = _Daemon({
        decode: (
          200,
          {
            'source': 'manifest',
            'entries': [
              info('a.txt', sha256: sha, present: true),
              info('b.txt'),
              info('c.txt', sha256: '', present: true),
            ],
          }
        ),
      });
      final res = await daemon.client.decodeManifestLink('ant://manifest/x');
      expect(res.entries.map((e) => e.sha256), equals([sha, null, null]));
    });

    test('a bad sha256 is the daemon BadRequestError, message kept', () async {
      final daemon = _Daemon({
        build: (
          400,
          {
            'error': 'entries[0]: sha256 must be 32 bytes, got 1',
            'code': 'BAD_REQUEST',
          }
        ),
      });
      await expectLater(
        daemon.client
            .buildManifest([ManifestEntryInput(address: addr, sha256: 'zz')]),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message',
                contains('entries[0]: sha256 must be 32 bytes, got 1'))),
      );
    });
  });
}
