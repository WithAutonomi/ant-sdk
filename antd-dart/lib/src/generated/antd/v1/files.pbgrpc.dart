//
//  Generated code. Do not modify.
//  source: antd/v1/files.proto
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

import 'common.pb.dart' as $2;
import 'files.pb.dart' as $4;

export 'files.pb.dart';

@$pb.GrpcServiceName('antd.v1.FileService')
class FileServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$put = $grpc.ClientMethod<$4.PutFileRequest, $4.PutFileResponse>(
      '/antd.v1.FileService/Put',
      ($4.PutFileRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.PutFileResponse.fromBuffer(value));
  static final _$putPublic = $grpc.ClientMethod<$4.PutFileRequest, $4.PutFilePublicResponse>(
      '/antd.v1.FileService/PutPublic',
      ($4.PutFileRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.PutFilePublicResponse.fromBuffer(value));
  static final _$get = $grpc.ClientMethod<$4.GetFileRequest, $4.GetFileResponse>(
      '/antd.v1.FileService/Get',
      ($4.GetFileRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.GetFileResponse.fromBuffer(value));
  static final _$getPublic = $grpc.ClientMethod<$4.GetFilePublicRequest, $4.GetFileResponse>(
      '/antd.v1.FileService/GetPublic',
      ($4.GetFilePublicRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.GetFileResponse.fromBuffer(value));
  static final _$cost = $grpc.ClientMethod<$4.FileCostRequest, $2.Cost>(
      '/antd.v1.FileService/Cost',
      ($4.FileCostRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $2.Cost.fromBuffer(value));

  FileServiceClient(super.channel, {super.options, super.interceptors});

  /// Private = unqualified verb (the DataMap is returned to the caller; it is
  /// NOT stored on the network). Public = `_public` suffix (the DataMap is
  /// additionally stored on-network and the call returns the resulting address).
  $grpc.ResponseFuture<$4.PutFileResponse> put($4.PutFileRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$put, request, options: options);
  }

  $grpc.ResponseFuture<$4.PutFilePublicResponse> putPublic($4.PutFileRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$putPublic, request, options: options);
  }

  $grpc.ResponseFuture<$4.GetFileResponse> get($4.GetFileRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$get, request, options: options);
  }

  $grpc.ResponseFuture<$4.GetFileResponse> getPublic($4.GetFilePublicRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getPublic, request, options: options);
  }

  $grpc.ResponseFuture<$2.Cost> cost($4.FileCostRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$cost, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.FileService')
abstract class FileServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.FileService';

  FileServiceBase() {
    $addMethod($grpc.ServiceMethod<$4.PutFileRequest, $4.PutFileResponse>(
        'Put',
        put_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.PutFileRequest.fromBuffer(value),
        ($4.PutFileResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.PutFileRequest, $4.PutFilePublicResponse>(
        'PutPublic',
        putPublic_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.PutFileRequest.fromBuffer(value),
        ($4.PutFilePublicResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.GetFileRequest, $4.GetFileResponse>(
        'Get',
        get_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.GetFileRequest.fromBuffer(value),
        ($4.GetFileResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.GetFilePublicRequest, $4.GetFileResponse>(
        'GetPublic',
        getPublic_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.GetFilePublicRequest.fromBuffer(value),
        ($4.GetFileResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.FileCostRequest, $2.Cost>(
        'Cost',
        cost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.FileCostRequest.fromBuffer(value),
        ($2.Cost value) => value.writeToBuffer()));
  }

  $async.Future<$4.PutFileResponse> put_Pre($grpc.ServiceCall $call, $async.Future<$4.PutFileRequest> $request) async {
    return put($call, await $request);
  }

  $async.Future<$4.PutFilePublicResponse> putPublic_Pre($grpc.ServiceCall $call, $async.Future<$4.PutFileRequest> $request) async {
    return putPublic($call, await $request);
  }

  $async.Future<$4.GetFileResponse> get_Pre($grpc.ServiceCall $call, $async.Future<$4.GetFileRequest> $request) async {
    return get($call, await $request);
  }

  $async.Future<$4.GetFileResponse> getPublic_Pre($grpc.ServiceCall $call, $async.Future<$4.GetFilePublicRequest> $request) async {
    return getPublic($call, await $request);
  }

  $async.Future<$2.Cost> cost_Pre($grpc.ServiceCall $call, $async.Future<$4.FileCostRequest> $request) async {
    return cost($call, await $request);
  }

  $async.Future<$4.PutFileResponse> put($grpc.ServiceCall call, $4.PutFileRequest request);
  $async.Future<$4.PutFilePublicResponse> putPublic($grpc.ServiceCall call, $4.PutFileRequest request);
  $async.Future<$4.GetFileResponse> get($grpc.ServiceCall call, $4.GetFileRequest request);
  $async.Future<$4.GetFileResponse> getPublic($grpc.ServiceCall call, $4.GetFilePublicRequest request);
  $async.Future<$2.Cost> cost($grpc.ServiceCall call, $4.FileCostRequest request);
}
