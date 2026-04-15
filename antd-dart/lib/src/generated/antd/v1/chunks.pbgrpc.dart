// This is a generated file - do not edit.
//
// Generated from antd/v1/chunks.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chunks.pb.dart' as $0;

export 'chunks.pb.dart';

@$pb.GrpcServiceName('antd.v1.ChunkService')
class ChunkServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ChunkServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.GetChunkResponse> get(
    $0.GetChunkRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$get, request, options: options);
  }

  $grpc.ResponseFuture<$0.PutChunkResponse> put(
    $0.PutChunkRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$put, request, options: options);
  }

  // method descriptors

  static final _$get =
      $grpc.ClientMethod<$0.GetChunkRequest, $0.GetChunkResponse>(
          '/antd.v1.ChunkService/Get',
          ($0.GetChunkRequest value) => value.writeToBuffer(),
          $0.GetChunkResponse.fromBuffer);
  static final _$put =
      $grpc.ClientMethod<$0.PutChunkRequest, $0.PutChunkResponse>(
          '/antd.v1.ChunkService/Put',
          ($0.PutChunkRequest value) => value.writeToBuffer(),
          $0.PutChunkResponse.fromBuffer);
}

@$pb.GrpcServiceName('antd.v1.ChunkService')
abstract class ChunkServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.ChunkService';

  ChunkServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.GetChunkRequest, $0.GetChunkResponse>(
        'Get',
        get_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetChunkRequest.fromBuffer(value),
        ($0.GetChunkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PutChunkRequest, $0.PutChunkResponse>(
        'Put',
        put_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PutChunkRequest.fromBuffer(value),
        ($0.PutChunkResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.GetChunkResponse> get_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetChunkRequest> $request) async {
    return get($call, await $request);
  }

  $async.Future<$0.GetChunkResponse> get(
      $grpc.ServiceCall call, $0.GetChunkRequest request);

  $async.Future<$0.PutChunkResponse> put_Pre($grpc.ServiceCall $call,
      $async.Future<$0.PutChunkRequest> $request) async {
    return put($call, await $request);
  }

  $async.Future<$0.PutChunkResponse> put(
      $grpc.ServiceCall call, $0.PutChunkRequest request);
}
