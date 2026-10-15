import 'dart:typed_data';

import 'package:antd_client/src/errors.dart';
import 'package:antd_client/src/generated/antd/v1/manifests.pbgrpc.dart'
    as manifests_pb;
import 'package:antd_client/src/grpc_client.dart';
import 'package:antd_client/src/manifests.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// ManifestService wire mapping for [GrpcAntdClient]: a real grpc-dart server
/// on `127.0.0.1:0` with a mock ManifestService, dialled by a real client.
/// Covers raw `.ant` bytes (no base64 over gRPC), proto3 `optional`
/// presence (an absent size is null, a present 0 is 0), the `embed_roots`
/// default, the pre-send entry check, INVALID_ARGUMENT mapping, and
/// manifests past the 4 MiB message size other gRPC stacks default to.

/// The five-byte `.ant` header.
final manifestHeader = Uint8List.fromList([0xC1, 0x41, 0x4E, 0x54, 0x01]);

final addrA = 'aa' * 32;
final addrB = 'bb' * 32;

/// 8 MiB: twice the 4 MiB default receive limit of other gRPC stacks.
const bigManifestBytes = 8 * 1024 * 1024;

void main() {
  late Server server;
  late GrpcAntdClient client;
  late _MockManifestService service;

  setUp(() async {
    service = _MockManifestService();
    server = Server.create(services: [service]);
    await server.serve(address: '127.0.0.1', port: 0);
    client = GrpcAntdClient(host: '127.0.0.1', port: server.port!);
  });

  tearDown(() async {
    await client.close();
    await server.shutdown();
  });

  group('Build', () {
    test('maps entries and options onto the request', () async {
      await client.buildManifest(
          [
            const ManifestEntryInput(path: 'a.txt', size: 10, dataMap: 'abcd'),
            ManifestEntryInput(address: addrB),
            ManifestEntryInput(path: 'empty', size: 0, address: addrA),
          ],
          name: 'album',
          torrentInfoHashes: ['11' * 20]);
      final req = service.lastBuild!;
      expect(req.hasName(), isTrue);
      expect(req.name, equals('album'));
      expect(req.torrentInfoHashes, equals(['11' * 20]));
      expect(req.entries, hasLength(3));

      final a = req.entries[0];
      expect(a.whichSource(),
          equals(manifests_pb.ManifestEntryInput_Source.dataMap));
      expect(a.dataMap, equals('abcd'));
      expect(a.hasPath(), isTrue);
      expect(a.path, equals('a.txt'));
      expect(a.hasSize(), isTrue);
      expect(a.size, equals(Int64(10)));

      final b = req.entries[1];
      expect(b.whichSource(),
          equals(manifests_pb.ManifestEntryInput_Source.address));
      expect(b.address, equals(addrB));
      expect(b.hasPath(), isFalse);
      expect(b.hasSize(), isFalse, reason: 'an unset size is absent, not 0');

      final c = req.entries[2];
      expect(c.hasSize(), isTrue, reason: 'a size of 0 is sent as present');
      expect(c.size, equals(Int64.ZERO));
    });

    test('embed_roots is sent as true by default, false when asked', () async {
      await client.buildManifest([ManifestEntryInput(address: addrA)]);
      expect(service.lastBuild!.hasEmbedRoots(), isTrue);
      expect(service.lastBuild!.embedRoots, isTrue);
      expect(service.lastBuild!.hasName(), isFalse);
      expect(service.lastBuild!.torrentInfoHashes, isEmpty);

      await client.buildManifest([ManifestEntryInput(address: addrA)],
          embedRoots: false, name: '');
      expect(service.lastBuild!.hasEmbedRoots(), isTrue);
      expect(service.lastBuild!.embedRoots, isFalse);
      expect(service.lastBuild!.hasName(), isFalse);
    });

    test('reads raw bytes, the link, and presence-based sizes', () async {
      final res =
          await client.buildManifest([ManifestEntryInput(address: addrA)]);
      expect(res.manifest, equals(manifestHeader));
      expect(res.link, equals('ant://manifest/wUFOVAE'));
      final a = res.entries[0];
      expect([a.effectiveName, a.path, a.kind, a.contentAddress],
          equals(['a.txt', 'a.txt', 'embedded', 'cc']));
      expect(a.size, equals(10));
      expect(a.exactSize, equals(10));
      expect(a.dataMap, isNull);
      expect(a.error, isNull);
      final p = res.entries[1];
      expect(p.path, isNull);
      expect(p.size, isNull, reason: 'an absent size is null, not 0');
      expect(p.exactSize, isNull,
          reason: 'an absent exact_size is null, not 0');
      final z = res.entries[2];
      expect(z.size, equals(0), reason: 'a present 0 reads as 0');
      expect(z.exactSize, equals(0));
    });

    test('an empty link reads as null', () async {
      service.buildLink = '';
      final res =
          await client.buildManifest([ManifestEntryInput(address: addrA)]);
      expect(res.link, isNull);
    });

    test('rejects both or neither of dataMap and address before sending',
        () async {
      for (final bad in [
        const ManifestEntryInput(path: 'x'),
        ManifestEntryInput(dataMap: 'abcd', address: addrA),
      ]) {
        await expectLater(
          client.buildManifest([bad]),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'entries[0]')),
        );
      }
      expect(service.buildCalls, equals(0));
    });

    test('INVALID_ARGUMENT is a BadRequestError that keeps the message',
        () async {
      await expectLater(
        client
            .buildManifest([ManifestEntryInput(path: '../x', address: addrA)]),
        throwsA(isA<BadRequestError>().having((e) => e.message, 'message',
            'Bad request: 1 invalid entries: entries[0]: invalid path "../x"')),
      );
    });
  });

  group('Decode', () {
    test('sends raw bytes and resolve; unset fields read as null', () async {
      final res = await client.decodeManifest(manifestHeader, resolve: true);
      final req = service.lastDecode!;
      expect(req.whichInput(),
          equals(manifests_pb.DecodeManifestRequest_Input.manifest));
      expect(req.manifest, equals(manifestHeader),
          reason: 'no base64 over gRPC');
      expect(req.resolve, isTrue);
      expect(res.source, equals('manifest'));
      expect(res.name, equals('album'));
      expect(res.torrentInfoHashV1, isNull);
      expect(res.torrentInfoHashV2, equals('22' * 32));
      final a = res.entries[0];
      expect(a.dataMap, equals('abcd'));
      expect(a.exactSize, equals(3));
      final b = res.entries[1];
      expect(b.dataMap, isNull);
      expect(b.exactSize, isNull);
      expect(b.error, equals('Record not found: gone'));
    });

    test('a link is sent as the link arm; resolve defaults to false', () async {
      final res = await client.decodeManifestLink(addrA);
      final req = service.lastDecode!;
      expect(req.whichInput(),
          equals(manifests_pb.DecodeManifestRequest_Input.link));
      expect(req.link, equals(addrA));
      expect(req.resolve, isFalse);
      expect(res.source, equals('file_link'));
      expect(res.name, isNull, reason: 'an absent name is null');
      expect(res.entries.single.contentAddress, equals(addrA));
    });

    test('rejects empty input before sending', () async {
      await expectLater(
          client.decodeManifest(Uint8List(0)), throwsA(isA<ArgumentError>()));
      await expectLater(
          client.decodeManifestLink(''), throwsA(isA<ArgumentError>()));
      expect(service.decodeCalls, equals(0));
    });

    test('INVALID_ARGUMENT is a BadRequestError', () async {
      await expectLater(
        client.decodeManifest(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<BadRequestError>()
            .having((e) => e.message, 'message', contains('not a manifest'))),
      );
    });
  });

  group('message size', () {
    test('Build receives and Decode sends an 8 MiB manifest', () async {
      final big = Uint8List(bigManifestBytes);
      for (var i = 0; i < big.length; i += 4096) {
        big[i] = i ~/ 4096 % 256;
      }
      big.setRange(0, manifestHeader.length, manifestHeader);
      service.buildManifest = big;

      final built =
          await client.buildManifest([ManifestEntryInput(address: addrA)]);
      expect(built.manifest.length, equals(bigManifestBytes));
      expect(built.manifest, equals(big));

      final res = await client.decodeManifest(built.manifest);
      expect(service.lastDecode!.manifest.length, equals(bigManifestBytes));
      expect(res.name, equals('album'));
    });
  });
}

/// A ManifestService that records requests and answers with fixed responses.
class _MockManifestService extends manifests_pb.ManifestServiceBase {
  manifests_pb.BuildManifestRequest? lastBuild;
  manifests_pb.DecodeManifestRequest? lastDecode;
  int buildCalls = 0;
  int decodeCalls = 0;
  String buildLink = 'ant://manifest/wUFOVAE';
  Uint8List? buildManifest;

  @override
  Future<manifests_pb.BuildManifestResponse> build(
      ServiceCall call, manifests_pb.BuildManifestRequest request) async {
    buildCalls++;
    lastBuild = request;
    final path = request.entries.isEmpty ? null : request.entries.first.path;
    if (path == '../x') {
      throw const GrpcError.invalidArgument(
          'Bad request: 1 invalid entries: entries[0]: invalid path "../x"');
    }
    return manifests_pb.BuildManifestResponse()
      ..manifest = buildManifest ?? manifestHeader
      ..link = buildLink
      ..entries.addAll([
        manifests_pb.ManifestEntryInfo()
          ..effectiveName = 'a.txt'
          ..path = 'a.txt'
          ..size = Int64(10)
          ..kind = 'embedded'
          ..contentAddress = 'cc'
          ..exactSize = Int64(10),
        manifests_pb.ManifestEntryInfo()
          ..effectiveName = addrB
          ..kind = 'public'
          ..contentAddress = addrB,
        manifests_pb.ManifestEntryInfo()
          ..effectiveName = 'zero'
          ..path = 'zero'
          ..size = Int64.ZERO
          ..kind = 'embedded'
          ..contentAddress = 'ee'
          ..exactSize = Int64.ZERO,
      ]);
  }

  @override
  Future<manifests_pb.DecodeManifestResponse> decode(
      ServiceCall call, manifests_pb.DecodeManifestRequest request) async {
    decodeCalls++;
    lastDecode = request;
    switch (request.whichInput()) {
      case manifests_pb.DecodeManifestRequest_Input.manifest:
        if (request.manifest.length < 5 || request.manifest[0] != 0xC1) {
          throw const GrpcError.invalidArgument(
              'Bad request: not a manifest: missing or invalid header');
        }
        return manifests_pb.DecodeManifestResponse()
          ..source = 'manifest'
          ..name = 'album'
          ..torrentInfoHashV2 = '22' * 32
          ..entries.addAll([
            manifests_pb.ManifestEntryInfo()
              ..effectiveName = 'a.txt'
              ..path = 'a.txt'
              ..kind = 'embedded'
              ..contentAddress = 'cc'
              ..dataMap = 'abcd'
              ..exactSize = Int64(3),
            manifests_pb.ManifestEntryInfo()
              ..effectiveName = 'b'
              ..path = 'b'
              ..kind = 'public'
              ..contentAddress = 'dd'
              ..error = 'Record not found: gone',
          ]);
      case manifests_pb.DecodeManifestRequest_Input.link:
        return manifests_pb.DecodeManifestResponse()
          ..source = 'file_link'
          ..entries.add(manifests_pb.ManifestEntryInfo()
            ..effectiveName = request.link
            ..kind = 'public'
            ..contentAddress = request.link);
      case manifests_pb.DecodeManifestRequest_Input.notSet:
        throw const GrpcError.invalidArgument('no input');
    }
  }
}
