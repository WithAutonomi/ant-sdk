//
//  Generated code. Do not modify.
//  source: antd/v1/data.proto
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
import 'data.pb.dart' as $1;

export 'data.pb.dart';

@$pb.GrpcServiceName('antd.v1.DataService')
class DataServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$put = $grpc.ClientMethod<$1.PutDataRequest, $1.PutDataResponse>(
      '/antd.v1.DataService/Put',
      ($1.PutDataRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.PutDataResponse.fromBuffer(value));
  static final _$putPublic = $grpc.ClientMethod<$1.PutPublicDataRequest, $1.PutPublicDataResponse>(
      '/antd.v1.DataService/PutPublic',
      ($1.PutPublicDataRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.PutPublicDataResponse.fromBuffer(value));
  static final _$get = $grpc.ClientMethod<$1.GetDataRequest, $1.GetDataResponse>(
      '/antd.v1.DataService/Get',
      ($1.GetDataRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.GetDataResponse.fromBuffer(value));
  static final _$getPublic = $grpc.ClientMethod<$1.GetPublicDataRequest, $1.GetPublicDataResponse>(
      '/antd.v1.DataService/GetPublic',
      ($1.GetPublicDataRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.GetPublicDataResponse.fromBuffer(value));
  static final _$streamPublic = $grpc.ClientMethod<$1.StreamPublicDataRequest, $1.DataChunk>(
      '/antd.v1.DataService/StreamPublic',
      ($1.StreamPublicDataRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.DataChunk.fromBuffer(value));
  static final _$cost = $grpc.ClientMethod<$1.DataCostRequest, $2.Cost>(
      '/antd.v1.DataService/Cost',
      ($1.DataCostRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $2.Cost.fromBuffer(value));

  DataServiceClient(super.channel, {super.options, super.interceptors});

  /// Private = unqualified verb (the DataMap is returned to the caller; it is
  /// NOT stored on the network). Public = `_public` suffix (the DataMap is
  /// additionally stored on-network and the call returns the resulting address).
  $grpc.ResponseFuture<$1.PutDataResponse> put($1.PutDataRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$put, request, options: options);
  }

  $grpc.ResponseFuture<$1.PutPublicDataResponse> putPublic($1.PutPublicDataRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$putPublic, request, options: options);
  }

  $grpc.ResponseFuture<$1.GetDataResponse> get($1.GetDataRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$get, request, options: options);
  }

  $grpc.ResponseFuture<$1.GetPublicDataResponse> getPublic($1.GetPublicDataRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getPublic, request, options: options);
  }

  $grpc.ResponseStream<$1.DataChunk> streamPublic($1.StreamPublicDataRequest request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$streamPublic, $async.Stream.fromIterable([request]), options: options);
  }

  $grpc.ResponseFuture<$2.Cost> cost($1.DataCostRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$cost, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.DataService')
abstract class DataServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.DataService';

  DataServiceBase() {
    $addMethod($grpc.ServiceMethod<$1.PutDataRequest, $1.PutDataResponse>(
        'Put',
        put_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.PutDataRequest.fromBuffer(value),
        ($1.PutDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.PutPublicDataRequest, $1.PutPublicDataResponse>(
        'PutPublic',
        putPublic_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.PutPublicDataRequest.fromBuffer(value),
        ($1.PutPublicDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetDataRequest, $1.GetDataResponse>(
        'Get',
        get_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.GetDataRequest.fromBuffer(value),
        ($1.GetDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetPublicDataRequest, $1.GetPublicDataResponse>(
        'GetPublic',
        getPublic_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.GetPublicDataRequest.fromBuffer(value),
        ($1.GetPublicDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.StreamPublicDataRequest, $1.DataChunk>(
        'StreamPublic',
        streamPublic_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $1.StreamPublicDataRequest.fromBuffer(value),
        ($1.DataChunk value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.DataCostRequest, $2.Cost>(
        'Cost',
        cost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.DataCostRequest.fromBuffer(value),
        ($2.Cost value) => value.writeToBuffer()));
  }

  $async.Future<$1.PutDataResponse> put_Pre($grpc.ServiceCall $call, $async.Future<$1.PutDataRequest> $request) async {
    return put($call, await $request);
  }

  $async.Future<$1.PutPublicDataResponse> putPublic_Pre($grpc.ServiceCall $call, $async.Future<$1.PutPublicDataRequest> $request) async {
    return putPublic($call, await $request);
  }

  $async.Future<$1.GetDataResponse> get_Pre($grpc.ServiceCall $call, $async.Future<$1.GetDataRequest> $request) async {
    return get($call, await $request);
  }

  $async.Future<$1.GetPublicDataResponse> getPublic_Pre($grpc.ServiceCall $call, $async.Future<$1.GetPublicDataRequest> $request) async {
    return getPublic($call, await $request);
  }

  $async.Stream<$1.DataChunk> streamPublic_Pre($grpc.ServiceCall $call, $async.Future<$1.StreamPublicDataRequest> $request) async* {
    yield* streamPublic($call, await $request);
  }

  $async.Future<$2.Cost> cost_Pre($grpc.ServiceCall $call, $async.Future<$1.DataCostRequest> $request) async {
    return cost($call, await $request);
  }

  $async.Future<$1.PutDataResponse> put($grpc.ServiceCall call, $1.PutDataRequest request);
  $async.Future<$1.PutPublicDataResponse> putPublic($grpc.ServiceCall call, $1.PutPublicDataRequest request);
  $async.Future<$1.GetDataResponse> get($grpc.ServiceCall call, $1.GetDataRequest request);
  $async.Future<$1.GetPublicDataResponse> getPublic($grpc.ServiceCall call, $1.GetPublicDataRequest request);
  $async.Stream<$1.DataChunk> streamPublic($grpc.ServiceCall call, $1.StreamPublicDataRequest request);
  $async.Future<$2.Cost> cost($grpc.ServiceCall call, $1.DataCostRequest request);
}
