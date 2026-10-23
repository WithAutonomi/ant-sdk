import 'dart:typed_data';

import 'package:antd_client/src/errors.dart';
import 'package:antd_client/src/generated/antd/v1/data.pb.dart' as data_msg;
import 'package:antd_client/src/generated/antd/v1/data.pbgrpc.dart' as data_pb;
import 'package:antd_client/src/generated/antd/v1/files.pb.dart' as files_msg;
import 'package:antd_client/src/generated/antd/v1/files.pbgrpc.dart'
    as files_pb;
import 'package:antd_client/src/generated/antd/v1/manifests.pb.dart'
    as manifests_msg;
import 'package:antd_client/src/generated/antd/v1/manifests.pbgrpc.dart'
    as manifests_pb;
import 'package:antd_client/src/generated/antd/v1/upload.pb.dart' as upload_msg;
import 'package:antd_client/src/generated/antd/v1/upload.pbgrpc.dart'
    as upload_pb;
import 'package:antd_client/src/grpc_client.dart';
import 'package:antd_client/src/manifests.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// The `sha256` fields (antd 0.17.0) over gRPC: a real grpc-dart server on
/// `127.0.0.1:0` with mock services, dialled by a real client. An upload
/// result reads the hash when set and null when it is the proto3 zero value
/// (""); a manifest entry input sets the optional field only when given.

final sha = 'ab' * 32;
final addr = 'aa' * 32;

/// What the mocks put in every `sha256` field; "" is the zero value.
String mockSha = '';

void main() {
  late Server server;
  late GrpcAntdClient client;
  late _MockManifestService manifests;

  setUp(() async {
    mockSha = sha;
    manifests = _MockManifestService();
    server = Server.create(services: [
      _MockDataService(),
      _MockFileService(),
      _MockUploadService(),
      manifests,
    ]);
    await server.serve(address: '127.0.0.1', port: 0);
    client = GrpcAntdClient(host: '127.0.0.1', port: server.port!);
  });

  tearDown(() async {
    await client.close();
    await server.shutdown();
  });

  group('upload results', () {
    final calls = <String, Future<String?> Function()>{
      'dataPut': () async => (await client.dataPut(Uint8List(1))).sha256,
      'dataPutPublic': () async =>
          (await client.dataPutPublic(Uint8List(1))).sha256,
      'filePut': () async => (await client.filePut('/tmp/f')).sha256,
      'filePutPublic': () async =>
          (await client.filePutPublic('/tmp/f')).sha256,
      'finalizeUpload': () async =>
          (await client.finalizeUpload('u', {})).sha256,
      'finalizeMerkleUpload': () async =>
          (await client.finalizeMerkleUpload('u', '0xp')).sha256,
    };
    for (final entry in calls.entries) {
      test('${entry.key} reads sha256, none when empty', () async {
        expect(await entry.value(), equals(sha));
        mockSha = '';
        expect(await entry.value(), isNull);
      });
    }
  });

  group('manifest entries', () {
    test('build sets sha256 only when given', () async {
      final res = await client.buildManifest([
        ManifestEntryInput(path: 'a.txt', address: addr, sha256: sha),
        ManifestEntryInput(path: 'b.txt', address: addr),
        ManifestEntryInput(path: 'c.txt', address: addr, sha256: ''),
        ManifestEntryInput(path: 'd.txt', address: addr, sha256: 'ZZ '),
      ]);
      final req = manifests.lastBuild!;
      expect(req.entries[0].hasSha256(), isTrue);
      expect(req.entries[0].sha256, equals(sha));
      expect(req.entries[1].hasSha256(), isFalse);
      expect(req.entries[2].hasSha256(), isFalse,
          reason: 'an empty string is unset, not sent');
      expect(req.entries[3].sha256, equals('ZZ '),
          reason: 'passed through as given');
      expect(res.entries.map((e) => e.sha256), equals([sha, null]));
    });

    test('decode reads sha256, none when empty', () async {
      final res = await client.decodeManifestLink('ant://manifest/x');
      expect(res.entries.map((e) => e.sha256), equals([sha, null]));
    });

    test('INVALID_ARGUMENT for a bad sha256 is a BadRequestError', () async {
      await expectLater(
        client.buildManifest(
            [ManifestEntryInput(path: 'bad', address: addr, sha256: 'zz')]),
        throwsA(isA<BadRequestError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message',
                contains('entries[0]: sha256 must be 32 bytes, got 1'))),
      );
    });
  });
}

class _MockDataService extends data_pb.DataServiceBase {
  @override
  Future<data_msg.PutDataResponse> put(
          ServiceCall call, data_msg.PutDataRequest request) async =>
      data_msg.PutDataResponse()
        ..dataMap = 'dd'
        ..sha256 = mockSha;

  @override
  Future<data_msg.PutPublicDataResponse> putPublic(
          ServiceCall call, data_msg.PutPublicDataRequest request) async =>
      data_msg.PutPublicDataResponse()
        ..address = addr
        ..sha256 = mockSha;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw GrpcError.unimplemented();
}

class _MockFileService extends files_pb.FileServiceBase {
  @override
  Future<files_msg.PutFileResponse> put(
          ServiceCall call, files_msg.PutFileRequest request) async =>
      files_msg.PutFileResponse()
        ..dataMap = 'dd'
        ..sha256 = mockSha;

  @override
  Future<files_msg.PutFilePublicResponse> putPublic(
          ServiceCall call, files_msg.PutFileRequest request) async =>
      files_msg.PutFilePublicResponse()
        ..address = addr
        ..sha256 = mockSha;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw GrpcError.unimplemented();
}

class _MockUploadService extends upload_pb.UploadServiceBase {
  @override
  Future<upload_msg.FinalizeUploadResponse> finalizeUpload(
          ServiceCall call, upload_msg.FinalizeUploadRequest request) async =>
      upload_msg.FinalizeUploadResponse()
        ..dataMap = 'dd'
        ..sha256 = mockSha;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw GrpcError.unimplemented();
}

class _MockManifestService extends manifests_pb.ManifestServiceBase {
  manifests_msg.BuildManifestRequest? lastBuild;

  manifests_msg.ManifestEntryInfo _info(String name, String hash) =>
      manifests_msg.ManifestEntryInfo()
        ..effectiveName = name
        ..path = name
        ..kind = 'public'
        ..contentAddress = addr
        ..sha256 = hash;

  @override
  Future<manifests_msg.BuildManifestResponse> build(
      ServiceCall call, manifests_msg.BuildManifestRequest request) async {
    lastBuild = request;
    if (request.entries.first.path == 'bad') {
      throw const GrpcError.invalidArgument(
          'Bad request: entries[0]: sha256 must be 32 bytes, got 1');
    }
    return manifests_msg.BuildManifestResponse()
      ..manifest = [0xC1, 0x41, 0x4E, 0x54, 0x01]
      ..entries.addAll([_info('a.txt', sha), _info('b.txt', '')]);
  }

  @override
  Future<manifests_msg.DecodeManifestResponse> decode(ServiceCall call,
          manifests_msg.DecodeManifestRequest request) async =>
      manifests_msg.DecodeManifestResponse()
        ..source = 'manifest'
        ..entries.addAll([_info('a.txt', sha), _info('b.txt', '')]);
}
