//
//  Generated code. Do not modify.
//  source: antd/v1/upload.proto
//
// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'upload.pb.dart' as $6;

export 'upload.pb.dart';

/// External-signer flow for files + in-memory data. Mirrors the REST
/// `/v1/upload/prepare`, `/v1/data/prepare`, `/v1/upload/finalize` surface 1:1.
///
/// Two-phase: caller submits a prepare request, daemon collects quotes from the
/// network and stashes server-side state keyed by `upload_id`. Caller then
/// signs + submits the EVM payment off-daemon, then calls FinalizeUpload with
/// the resulting transaction artefacts.
///
/// Wave-batch (files with < 64 chunks): per-quote payments via `payForQuotes()`.
/// Merkle (files with >= 64 chunks): pool commitments via `payForMerkleTree2()`.
///
/// File and data prepares are intentionally separate RPCs (their request shapes
/// differ — filesystem path vs raw bytes), but they share one finalize RPC
/// because the server-side stored state is the same shape either way.
@$pb.GrpcServiceName('antd.v1.UploadService')
class UploadServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$prepareFileUpload = $grpc.ClientMethod<$6.PrepareFileUploadRequest, $6.PrepareUploadResponse>(
      '/antd.v1.UploadService/PrepareFileUpload',
      ($6.PrepareFileUploadRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PrepareUploadResponse.fromBuffer(value));
  static final _$prepareDataUpload = $grpc.ClientMethod<$6.PrepareDataUploadRequest, $6.PrepareUploadResponse>(
      '/antd.v1.UploadService/PrepareDataUpload',
      ($6.PrepareDataUploadRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PrepareUploadResponse.fromBuffer(value));
  static final _$finalizeUpload = $grpc.ClientMethod<$6.FinalizeUploadRequest, $6.FinalizeUploadResponse>(
      '/antd.v1.UploadService/FinalizeUpload',
      ($6.FinalizeUploadRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.FinalizeUploadResponse.fromBuffer(value));

  UploadServiceClient(super.channel, {super.options, super.interceptors});

  /// Phase 1: prepare a file upload for external signing. Returns payment
  /// details + an upload_id. For files with < 64 chunks returns
  /// `payment_type = "wave_batch"`; otherwise `payment_type = "merkle"`.
  $grpc.ResponseFuture<$6.PrepareUploadResponse> prepareFileUpload($6.PrepareFileUploadRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$prepareFileUpload, request, options: options);
  }

  /// Phase 1 (data): prepare an in-memory data upload for external signing.
  /// Same as PrepareFileUpload but takes raw bytes instead of a filesystem
  /// path. Honours visibility = "public" (requires ant-client #73, already
  /// merged on main since 2026-05-05).
  $grpc.ResponseFuture<$6.PrepareUploadResponse> prepareDataUpload($6.PrepareDataUploadRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$prepareDataUpload, request, options: options);
  }

  /// Phase 2: finalize an upload after the external EVM payment has landed.
  /// For wave-batch uploads pass `tx_hashes`; for merkle uploads pass
  /// `winner_pool_hash` from the `MerklePaymentMade` event. The server-side
  /// stored upload state is consumed (one-shot).
  $grpc.ResponseFuture<$6.FinalizeUploadResponse> finalizeUpload($6.FinalizeUploadRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$finalizeUpload, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.UploadService')
abstract class UploadServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.UploadService';

  UploadServiceBase() {
    $addMethod($grpc.ServiceMethod<$6.PrepareFileUploadRequest, $6.PrepareUploadResponse>(
        'PrepareFileUpload',
        prepareFileUpload_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PrepareFileUploadRequest.fromBuffer(value),
        ($6.PrepareUploadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PrepareDataUploadRequest, $6.PrepareUploadResponse>(
        'PrepareDataUpload',
        prepareDataUpload_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PrepareDataUploadRequest.fromBuffer(value),
        ($6.PrepareUploadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.FinalizeUploadRequest, $6.FinalizeUploadResponse>(
        'FinalizeUpload',
        finalizeUpload_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.FinalizeUploadRequest.fromBuffer(value),
        ($6.FinalizeUploadResponse value) => value.writeToBuffer()));
  }

  $async.Future<$6.PrepareUploadResponse> prepareFileUpload_Pre($grpc.ServiceCall $call, $async.Future<$6.PrepareFileUploadRequest> $request) async {
    return prepareFileUpload($call, await $request);
  }

  $async.Future<$6.PrepareUploadResponse> prepareDataUpload_Pre($grpc.ServiceCall $call, $async.Future<$6.PrepareDataUploadRequest> $request) async {
    return prepareDataUpload($call, await $request);
  }

  $async.Future<$6.FinalizeUploadResponse> finalizeUpload_Pre($grpc.ServiceCall $call, $async.Future<$6.FinalizeUploadRequest> $request) async {
    return finalizeUpload($call, await $request);
  }

  $async.Future<$6.PrepareUploadResponse> prepareFileUpload($grpc.ServiceCall call, $6.PrepareFileUploadRequest request);
  $async.Future<$6.PrepareUploadResponse> prepareDataUpload($grpc.ServiceCall call, $6.PrepareDataUploadRequest request);
  $async.Future<$6.FinalizeUploadResponse> finalizeUpload($grpc.ServiceCall call, $6.FinalizeUploadRequest request);
}
