import 'dart:async';
import 'dart:typed_data';

import 'package:antd/src/grpc_client.dart';
import 'package:antd/src/generated/antd/v1/chunks.pb.dart' as chunks_msg;
import 'package:antd/src/generated/antd/v1/chunks.pbgrpc.dart' as chunks_pb;
import 'package:antd/src/generated/antd/v1/common.pb.dart' as common_msg;
import 'package:antd/src/generated/antd/v1/upload.pb.dart' as upload_msg;
import 'package:antd/src/generated/antd/v1/upload.pbgrpc.dart' as upload_pb;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// In-process mock-server tests for the V2-284 external-signer prepare/finalize
/// surface added to [GrpcAntdClient]. Mirrors the antd-rust / antd-go /
/// antd-py / antd-java / antd-kotlin / antd-csharp / antd-ruby suites.
///
/// Each test spins up a real `grpc-dart` server bound to `127.0.0.1:0`,
/// registers mock service implementations that exercise the real proto types,
/// then dials with a real [GrpcAntdClient]. This exercises the actual
/// wire-shape mapping in [GrpcAntdClient].
void main() {
  late Server server;
  late GrpcAntdClient client;

  setUp(() async {
    server = Server.create(services: [_MockChunkService(), _MockUploadService()]);
    await server.serve(address: '127.0.0.1', port: 0);
    client = GrpcAntdClient(host: '127.0.0.1', port: server.port!);
  });

  tearDown(() async {
    await server.shutdown();
  });

  group('External signer (V2-284) — prepare/finalize uploads', () {
    test('prepareUpload omits visibility when null', () async {
      final r = await client.prepareUpload('/tmp/x.bin');
      // Empty visibility = proto3 default; the mock echoes that into upload_id.
      expect(r.uploadId, equals('upid_file_'));
      expect(r.paymentType, equals('wave_batch'));
      expect(r.payments.length, equals(1));
      expect(r.payments.first.quoteHash, equals('0xqa'));
      expect(r.depth, isNull);
      expect(r.poolCommitments, isNull);
      expect(r.merklePaymentTimestamp, isNull);
    });

    test('prepareUpload forwards visibility public', () async {
      final r = await client.prepareUpload('/tmp/x.bin', visibility: 'public');
      expect(r.uploadId, equals('upid_file_public'));
    });

    test('prepareUploadPublic convenience wrapper', () async {
      final r = await client.prepareUploadPublic('/tmp/x.bin');
      expect(r.uploadId, equals('upid_file_public'));
    });

    test('prepareDataUpload wave-batch', () async {
      final r = await client.prepareDataUpload(Uint8List.fromList('small'.codeUnits));
      expect(r.uploadId, equals('upid_data_'));
      expect(r.paymentType, equals('wave_batch'));
      expect(r.depth, isNull);
    });

    test('prepareDataUpload merkle', () async {
      final r = await client.prepareDataUpload(
          Uint8List.fromList('MERKLE-large-payload'.codeUnits));
      expect(r.paymentType, equals('merkle'));
      expect(r.depth, equals(7));
      expect(r.merklePaymentTimestamp, equals(1700000000));
      expect(r.poolCommitments, isNotNull);
      expect(r.poolCommitments!.length, equals(1));
      expect(r.poolCommitments!.first.poolHash, equals('0xpool'));
      expect(r.poolCommitments!.first.candidates.first.rewardsAddress,
          equals('0xc1'));
    });

    test('finalizeUpload wave-batch private omits data_map_address', () async {
      final r = await client.finalizeUpload('upid_file_', {'0xq1': '0xtx1'});
      expect(r.dataMap, equals('dm_wave'));
      expect(r.dataMapAddress, equals(''));
      expect(r.chunksStored, equals(3));
    });

    test('finalizeUpload wave-batch public returns data_map_address', () async {
      final r = await client.finalizeUpload(
          'upid_file_public', {'0xq1': '0xtx1'});
      expect(r.dataMapAddress, equals('addr_public_dm'));
    });

    test('finalizeMerkleUpload store_data_map=true', () async {
      final r = await client.finalizeMerkleUpload(
          'upid_data_', '0xwinpool',
          storeDataMap: true);
      expect(r.dataMap, equals('dm_merkle'));
      expect(r.address, equals('stored_on_network'));
      expect(r.chunksStored, equals(64));
    });

    test('finalizeMerkleUpload store_data_map default false', () async {
      final r = await client.finalizeMerkleUpload('upid_data_', '0xwinpool');
      expect(r.dataMap, equals('dm_merkle'));
      expect(r.address, equals(''));
    });
  });

  group('External signer (V2-284) — prepare/finalize chunks', () {
    test('prepareChunkUpload new chunk', () async {
      final r = await client
          .prepareChunkUpload(Uint8List.fromList('newchunk'.codeUnits));
      expect(r.alreadyStored, isFalse);
      expect(r.address, equals('0xnewchunk'));
      expect(r.uploadId, equals('upid_chunk_42'));
      expect(r.paymentType, equals('wave_batch'));
      expect(r.payments.length, equals(1));
      expect(r.payments.first.quoteHash, equals('0xq1'));
      expect(r.totalAmount, equals('100'));
      expect(r.rpcUrl, equals('http://localhost:8545'));
    });

    test('prepareChunkUpload already-stored short-circuit', () async {
      final r = await client
          .prepareChunkUpload(Uint8List.fromList('EXISTS-data'.codeUnits));
      expect(r.alreadyStored, isTrue);
      expect(r.address, equals('0xabc'));
      expect(r.uploadId, equals(''));
      expect(r.payments, isEmpty);
    });

    test('finalizeChunkUpload returns address and forwards body', () async {
      final addr = await client
          .finalizeChunkUpload('upid_chunk_42', {'0xq1': '0xtxabc'});
      expect(addr, equals('addr_for_upid_chunk_42'));
    });
  });
}

/// Mock ChunkService with PrepareChunk + FinalizeChunk overrides.
class _MockChunkService extends chunks_pb.ChunkServiceBase {
  @override
  Future<chunks_msg.PrepareChunkResponse> prepareChunk(
      ServiceCall call, chunks_msg.PrepareChunkRequest request) async {
    // Inputs starting with "EXISTS" → already-stored short-circuit.
    final n = request.data.length < 6 ? request.data.length : 6;
    final prefix = String.fromCharCodes(request.data.sublist(0, n));
    if (prefix == 'EXISTS') {
      return chunks_msg.PrepareChunkResponse()
        ..address = '0xabc'
        ..alreadyStored = true;
    }
    final resp = chunks_msg.PrepareChunkResponse()
      ..address = '0xnewchunk'
      ..alreadyStored = false
      ..uploadId = 'upid_chunk_42'
      ..paymentType = 'wave_batch'
      ..totalAmount = '100'
      ..paymentVaultAddress = '0xvault'
      ..paymentTokenAddress = '0xtoken'
      ..rpcUrl = 'http://localhost:8545';
    resp.payments.add(common_msg.PaymentEntry()
      ..quoteHash = '0xq1'
      ..rewardsAddress = '0xr1'
      ..amount = '100');
    return resp;
  }

  @override
  Future<chunks_msg.FinalizeChunkResponse> finalizeChunk(
      ServiceCall call, chunks_msg.FinalizeChunkRequest request) async {
    return chunks_msg.FinalizeChunkResponse()
      ..address = 'addr_for_${request.uploadId}';
  }

  // Other RPCs in the service definition must be implemented to satisfy the
  // abstract base class, but are not exercised here.
  @override
  Future<chunks_msg.GetChunkResponse> get(
      ServiceCall call, chunks_msg.GetChunkRequest request) async {
    throw GrpcError.unimplemented('not exercised by V2-284 tests');
  }

  @override
  Future<chunks_msg.PutChunkResponse> put(
      ServiceCall call, chunks_msg.PutChunkRequest request) async {
    throw GrpcError.unimplemented('not exercised by V2-284 tests');
  }
}

/// Mock UploadService with the V2-284 RPCs.
class _MockUploadService extends upload_pb.UploadServiceBase {
  @override
  Future<upload_msg.PrepareUploadResponse> prepareFileUpload(
      ServiceCall call, upload_msg.PrepareFileUploadRequest request) async {
    final resp = upload_msg.PrepareUploadResponse()
      ..uploadId = 'upid_file_${request.visibility}'
      ..paymentType = 'wave_batch'
      ..totalAmount = '1'
      ..paymentVaultAddress = '0xvault'
      ..paymentTokenAddress = '0xtoken'
      ..rpcUrl = 'http://localhost:8545';
    resp.payments.add(common_msg.PaymentEntry()
      ..quoteHash = '0xqa'
      ..rewardsAddress = '0xra'
      ..amount = '1');
    return resp;
  }

  @override
  Future<upload_msg.PrepareUploadResponse> prepareDataUpload(
      ServiceCall call, upload_msg.PrepareDataUploadRequest request) async {
    final uid = 'upid_data_${request.visibility}';
    final n = request.data.length < 6 ? request.data.length : 6;
    final prefix = String.fromCharCodes(request.data.sublist(0, n));
    if (prefix == 'MERKLE') {
      final merkle = upload_msg.PrepareUploadResponse()
        ..uploadId = uid
        ..paymentType = 'merkle'
        ..depth = 7
        ..merklePaymentTimestamp = Int64(1700000000)
        ..totalAmount = '0'
        ..paymentVaultAddress = '0xvault'
        ..paymentTokenAddress = '0xtoken'
        ..rpcUrl = 'http://localhost:8545';
      final pc = upload_msg.PoolCommitmentEntry()..poolHash = '0xpool';
      pc.candidates.add(upload_msg.CandidateNodeEntry()
        ..rewardsAddress = '0xc1'
        ..amount = '5');
      merkle.poolCommitments.add(pc);
      return merkle;
    }
    final wave = upload_msg.PrepareUploadResponse()
      ..uploadId = uid
      ..paymentType = 'wave_batch'
      ..totalAmount = '2'
      ..paymentVaultAddress = '0xvault'
      ..paymentTokenAddress = '0xtoken'
      ..rpcUrl = 'http://localhost:8545';
    wave.payments.add(common_msg.PaymentEntry()
      ..quoteHash = '0xqb'
      ..rewardsAddress = '0xrb'
      ..amount = '2');
    return wave;
  }

  @override
  Future<upload_msg.FinalizeUploadResponse> finalizeUpload(
      ServiceCall call, upload_msg.FinalizeUploadRequest request) async {
    if (request.winnerPoolHash.isNotEmpty) {
      return upload_msg.FinalizeUploadResponse()
        ..dataMap = 'dm_merkle'
        ..address = request.storeDataMap ? 'stored_on_network' : ''
        ..chunksStored = Int64(64);
    }
    final dmAddress =
        request.uploadId.endsWith('public') ? 'addr_public_dm' : '';
    return upload_msg.FinalizeUploadResponse()
      ..dataMap = 'dm_wave'
      ..dataMapAddress = dmAddress
      ..chunksStored = Int64(3);
  }
}
