import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// REST manifest API against a mock daemon: request shapes, the base64 wire
/// form of the `.ant` bytes, unset sizes reading as null (never 0), the
/// `embed_roots` default, the both-or-neither entry check, and the 400
/// mapping.

/// The five-byte `.ant` header; "wUFOVAE=" is its base64.
final manifestHeader = Uint8List.fromList([0xC1, 0x41, 0x4E, 0x54, 0x01]);
const manifestHeaderB64 = 'wUFOVAE=';

final addrA = 'aa' * 32;
final addrB = 'bb' * 32;

/// A mock daemon answering `POST /path` routes with `(status, body)`, where a
/// String body is sent verbatim and anything else as JSON. Records every
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

const build = 'POST /v1/manifests/build';
const decode = 'POST /v1/manifests/decode';
const emptyInput = 'needs a manifest (base64 .ant bytes) or a link';

Map<String, dynamic> _built({
  String manifest = manifestHeaderB64,
  String? link,
  List<Map<String, dynamic>> entries = const [],
}) =>
    {
      'manifest': manifest,
      if (link != null) 'link': link,
      'entries': entries,
    };

void main() {
  group('buildManifest', () {
    test('sends entries and options, reads the response', () async {
      final daemon = _Daemon({
        build: (
          200,
          _built(link: 'ant://manifest/wUFOVAE', entries: [
            {
              'effective_name': 'a.txt',
              'path': 'a.txt',
              'size': 10,
              'kind': 'embedded',
              'content_address': 'cc',
              'exact_size': 10,
            },
            {
              'effective_name': addrB,
              'kind': 'public',
              'content_address': addrB
            },
          ])
        ),
      });
      final res = await daemon.client.buildManifest(
          [
            const ManifestEntryInput(path: 'a.txt', size: 10, dataMap: 'abcd'),
            ManifestEntryInput(address: addrB),
          ],
          name: 'album',
          torrentInfoHashes: ['11' * 20, '22' * 32],
          embedRoots: false);

      final body = daemon.body(0);
      expect(body['name'], equals('album'));
      expect(body['embed_roots'], isFalse);
      expect(body['torrent_info_hashes'], equals(['11' * 20, '22' * 32]));
      final entries = body['entries'] as List;
      expect(entries[0],
          equals({'path': 'a.txt', 'size': 10, 'data_map': 'abcd'}));
      expect(entries[1], equals({'address': addrB}),
          reason: 'unset path and size are omitted, not sent as null or 0');

      expect(res.manifest, equals(manifestHeader));
      expect(res.link, equals('ant://manifest/wUFOVAE'));
      expect(res.entries, hasLength(2));
      final a = res.entries[0];
      expect([a.effectiveName, a.path, a.size, a.kind, a.contentAddress],
          equals(['a.txt', 'a.txt', 10, 'embedded', 'cc']));
      expect(a.exactSize, equals(10));
      expect(a.dataMap, isNull, reason: 'build reports no DataMap');
      expect(a.error, isNull);
      final p = res.entries[1];
      expect(p.kind, equals('public'));
      expect(p.effectiveName, equals(addrB));
      expect(p.path, isNull);
      expect(p.size, isNull, reason: 'an unset size is null, not 0');
      expect(p.exactSize, isNull, reason: 'an unset exact_size is null, not 0');
    });

    test('embed_roots defaults to true; unset options are omitted', () async {
      final daemon = _Daemon({build: (200, _built())});
      final res = await daemon.client
          .buildManifest([ManifestEntryInput(address: addrA)]);
      final body = daemon.body(0);
      expect(body['embed_roots'], isTrue);
      expect(body.containsKey('name'), isFalse);
      expect(body.containsKey('torrent_info_hashes'), isFalse);
      expect(res.link, isNull, reason: 'no link when it does not fit');
      expect(res.entries, isEmpty);
    });

    test('an empty name, path or hash list is omitted', () async {
      final daemon = _Daemon({build: (200, _built())});
      await daemon.client.buildManifest(
          [ManifestEntryInput(path: '', dataMap: '', address: addrA)],
          name: '',
          torrentInfoHashes: const []);
      final body = daemon.body(0);
      expect(body.containsKey('name'), isFalse);
      expect(body.containsKey('torrent_info_hashes'), isFalse);
      expect(
          body['entries'],
          equals([
            {'address': addrA}
          ]));
    });

    test('a size of 0 is sent, and read back, as 0', () async {
      final daemon = _Daemon({
        build: (
          200,
          _built(entries: [
            {
              'effective_name': 'empty',
              'path': 'empty',
              'size': 0,
              'kind': 'public',
              'content_address': addrA,
            },
          ])
        ),
      });
      final res = await daemon.client.buildManifest(
          [ManifestEntryInput(path: 'empty', size: 0, address: addrA)]);
      expect((daemon.body(0)['entries'] as List)[0]['size'], equals(0));
      expect(res.entries.single.size, equals(0));
      expect(res.entries.single.exactSize, isNull);
    });

    test('rejects both or neither of dataMap and address before sending',
        () async {
      final daemon = _Daemon({build: (200, _built())});
      final client = daemon.client;
      for (final (bad, message) in [
        (
          const ManifestEntryInput(),
          '1 invalid entries: entries[1]: needs a data_map or an address'
        ),
        (
          const ManifestEntryInput(path: 'x', dataMap: '', address: ''),
          '1 invalid entries: entries[1]: needs a data_map or an address'
        ),
        (
          ManifestEntryInput(dataMap: 'abcd', address: addrA),
          '1 invalid entries: entries[1]: give data_map or address, not both'
        ),
      ]) {
        await expectLater(
          client.buildManifest([ManifestEntryInput(address: addrA), bad]),
          throwsA(isA<BadRequestError>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', message)),
          reason: '$bad',
        );
      }
      expect(daemon.requests, isEmpty);
    });

    test('lists every bad entry, in the daemon wording', () async {
      final daemon = _Daemon({build: (200, _built())});
      await expectLater(
        daemon.client.buildManifest([
          ManifestEntryInput(dataMap: 'abcd', address: addrA),
          ManifestEntryInput(address: addrA),
          const ManifestEntryInput(path: 'y'),
        ]),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having(
                (e) => e.message,
                'message',
                '2 invalid entries: entries[0]: give data_map or address, '
                    'not both; entries[2]: needs a data_map or an address')),
      );
      expect(daemon.requests, isEmpty);
    });

    test('reports at most 20 bad entries, then "and N more"', () async {
      final daemon = _Daemon({build: (200, _built())});
      final shown = [
        for (var i = 0; i < 20; i++)
          'entries[$i]: needs a data_map or an address'
      ].join('; ');
      await expectLater(
        daemon.client.buildManifest(
            [for (var i = 0; i < 23; i++) const ManifestEntryInput()]),
        throwsA(isA<BadRequestError>().having((e) => e.message, 'message',
            '23 invalid entries: $shown; and 3 more')),
      );
      expect(daemon.requests, isEmpty);
    });

    test('rejects a negative size before sending', () async {
      final daemon = _Daemon({build: (200, _built())});
      await expectLater(
        daemon.client
            .buildManifest([ManifestEntryInput(size: -1, address: addrA)]),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message',
                '1 invalid entries: entries[0]: size must not be negative')),
      );
      expect(daemon.requests, isEmpty);
    });

    test('a 400 is a BadRequestError that keeps the message', () async {
      const message =
          'Bad request: 1 invalid entries: entries[0]: invalid path "../x": '
          'a path component is ".."';
      final client = _Daemon({
        build: (400, {'error': message, 'code': 'BAD_REQUEST'}),
      }).client;
      await expectLater(
        client
            .buildManifest([ManifestEntryInput(path: '../x', address: addrA)]),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', message)),
      );
    });

    test('malformed base64 in the response is an InternalError', () async {
      final client =
          _Daemon({build: (200, _built(manifest: 'not base64!'))}).client;
      await expectLater(
        client.buildManifest([ManifestEntryInput(address: addrA)]),
        throwsA(isA<InternalError>()),
      );
    });
  });

  group('decodeManifest', () {
    final decoded = {
      'source': 'manifest',
      'name': 'album',
      'torrent_info_hash_v2': '22' * 32,
      'entries': [
        {
          'effective_name': 'a.txt',
          'path': 'a.txt',
          'kind': 'embedded',
          'content_address': 'cc',
          'data_map': 'abcd',
          'exact_size': 3,
        },
        {
          'effective_name': 'b',
          'path': 'b',
          'kind': 'public',
          'content_address': 'dd',
          'error': 'Record not found: gone',
        },
      ],
    };

    test('sends base64 bytes and resolve, reads the response', () async {
      final daemon = _Daemon({decode: (200, decoded)});
      final res =
          await daemon.client.decodeManifest(manifestHeader, resolve: true);
      final body = daemon.body(0);
      expect(body, equals({'manifest': manifestHeaderB64, 'resolve': true}));

      expect(res.source, equals('manifest'));
      expect(res.name, equals('album'));
      expect(res.torrentInfoHashV1, isNull);
      expect(res.torrentInfoHashV2, equals('22' * 32));
      final a = res.entries[0];
      expect(a.dataMap, equals('abcd'));
      expect(a.exactSize, equals(3));
      expect(a.size, isNull);
      expect(a.error, isNull);
      final b = res.entries[1];
      expect(b.kind, equals('public'));
      expect(b.dataMap, isNull, reason: 'public entries carry no DataMap');
      expect(b.error, equals('Record not found: gone'),
          reason: "one entry's resolve failure is not a failed call");
      expect(b.exactSize, isNull);
    });

    test('resolve defaults to false', () async {
      final daemon = _Daemon({decode: (200, decoded)});
      await daemon.client.decodeManifest(manifestHeader);
      expect(daemon.body(0)['resolve'], isFalse);
    });

    test('every byte value survives the base64 round trip', () async {
      final bytes = Uint8List.fromList([for (var i = 0; i < 256; i++) i]);
      final echo = base64.encode(bytes);
      final daemon = _Daemon({
        decode: (200, decoded),
        build: (200, _built(manifest: echo)),
      });
      await daemon.client.decodeManifest(bytes);
      final sent = daemon.body(0)['manifest'] as String;
      expect(base64.decode(sent), equals(bytes));
      final built = await daemon.client
          .buildManifest([ManifestEntryInput(address: addrA)]);
      expect(built.manifest, equals(bytes));
    });

    test('rejects empty bytes before sending', () async {
      final daemon = _Daemon({decode: (200, decoded)});
      await expectLater(
        daemon.client.decodeManifest(Uint8List(0)),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', emptyInput)),
      );
      expect(daemon.requests, isEmpty);
    });

    test('a 400 is a BadRequestError that keeps the message', () async {
      const message = 'Bad request: not a manifest: missing or invalid header';
      final client = _Daemon({
        decode: (400, {'error': message, 'code': 'BAD_REQUEST'}),
      }).client;
      await expectLater(
        client.decodeManifest(Uint8List.fromList(utf8.encode('nope'))),
        throwsA(isA<BadRequestError>()
            .having((e) => e.message, 'message', message)),
      );
    });
  });

  group('decodeManifestLink', () {
    test('sends the link without bytes; a file link reads as one entry',
        () async {
      final daemon = _Daemon({
        decode: (
          200,
          {
            'source': 'file_link',
            'entries': [
              {
                'effective_name': addrA,
                'kind': 'public',
                'content_address': addrA,
                'exact_size': 46,
              },
            ],
          }
        ),
      });
      final res = await daemon.client.decodeManifestLink(addrA, resolve: true);
      expect(daemon.body(0), equals({'link': addrA, 'resolve': true}));
      expect(res.source, equals('file_link'));
      expect(res.name, isNull);
      expect(res.torrentInfoHashV1, isNull);
      expect(res.torrentInfoHashV2, isNull);
      final e = res.entries.single;
      expect(e.path, isNull);
      expect(e.size, isNull);
      expect(e.exactSize, equals(46));
    });

    test('rejects an empty link before sending', () async {
      final daemon = _Daemon({decode: (200, <String, dynamic>{})});
      await expectLater(
        daemon.client.decodeManifestLink(''),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', emptyInput)),
      );
      expect(daemon.requests, isEmpty);
    });

    test('a 400 is a BadRequestError', () async {
      final client = _Daemon({
        decode: (
          400,
          {'error': 'Bad request: invalid link', 'code': 'BAD_REQUEST'}
        ),
      }).client;
      await expectLater(
        client.decodeManifestLink('ant://nope'),
        throwsA(isA<BadRequestError>()),
      );
    });
  });
}
