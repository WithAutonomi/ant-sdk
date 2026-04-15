// This is a generated file - do not edit.
//
// Generated from antd/v1/data.proto.

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

import 'common.pb.dart' as $1;
import 'data.pb.dart' as $0;

export 'data.pb.dart';

@$pb.GrpcServiceName('antd.v1.DataService')
class DataServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  DataServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.GetPublicDataResponse> getPublic(
    $0.GetPublicDataRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getPublic, request, options: options);
  }

  $grpc.ResponseFuture<$0.PutPublicDataResponse> putPublic(
    $0.PutPublicDataRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$putPublic, request, options: options);
  }

  $grpc.ResponseStream<$0.DataChunk> streamPublic(
    $0.StreamPublicDataRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$streamPublic, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.GetPrivateDataResponse> getPrivate(
    $0.GetPrivateDataRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getPrivate, request, options: options);
  }

  $grpc.ResponseFuture<$0.PutPrivateDataResponse> putPrivate(
    $0.PutPrivateDataRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$putPrivate, request, options: options);
  }

  $grpc.ResponseFuture<$1.Cost> getCost(
    $0.DataCostRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getCost, request, options: options);
  }

  // method descriptors

  static final _$getPublic =
      $grpc.ClientMethod<$0.GetPublicDataRequest, $0.GetPublicDataResponse>(
          '/antd.v1.DataService/GetPublic',
          ($0.GetPublicDataRequest value) => value.writeToBuffer(),
          $0.GetPublicDataResponse.fromBuffer);
  static final _$putPublic =
      $grpc.ClientMethod<$0.PutPublicDataRequest, $0.PutPublicDataResponse>(
          '/antd.v1.DataService/PutPublic',
          ($0.PutPublicDataRequest value) => value.writeToBuffer(),
          $0.PutPublicDataResponse.fromBuffer);
  static final _$streamPublic =
      $grpc.ClientMethod<$0.StreamPublicDataRequest, $0.DataChunk>(
          '/antd.v1.DataService/StreamPublic',
          ($0.StreamPublicDataRequest value) => value.writeToBuffer(),
          $0.DataChunk.fromBuffer);
  static final _$getPrivate =
      $grpc.ClientMethod<$0.GetPrivateDataRequest, $0.GetPrivateDataResponse>(
          '/antd.v1.DataService/GetPrivate',
          ($0.GetPrivateDataRequest value) => value.writeToBuffer(),
          $0.GetPrivateDataResponse.fromBuffer);
  static final _$putPrivate =
      $grpc.ClientMethod<$0.PutPrivateDataRequest, $0.PutPrivateDataResponse>(
          '/antd.v1.DataService/PutPrivate',
          ($0.PutPrivateDataRequest value) => value.writeToBuffer(),
          $0.PutPrivateDataResponse.fromBuffer);
  static final _$getCost = $grpc.ClientMethod<$0.DataCostRequest, $1.Cost>(
      '/antd.v1.DataService/GetCost',
      ($0.DataCostRequest value) => value.writeToBuffer(),
      $1.Cost.fromBuffer);
}

@$pb.GrpcServiceName('antd.v1.DataService')
abstract class DataServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.DataService';

  DataServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.GetPublicDataRequest, $0.GetPublicDataResponse>(
            'GetPublic',
            getPublic_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetPublicDataRequest.fromBuffer(value),
            ($0.GetPublicDataResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.PutPublicDataRequest, $0.PutPublicDataResponse>(
            'PutPublic',
            putPublic_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.PutPublicDataRequest.fromBuffer(value),
            ($0.PutPublicDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StreamPublicDataRequest, $0.DataChunk>(
        'StreamPublic',
        streamPublic_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.StreamPublicDataRequest.fromBuffer(value),
        ($0.DataChunk value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetPrivateDataRequest,
            $0.GetPrivateDataResponse>(
        'GetPrivate',
        getPrivate_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetPrivateDataRequest.fromBuffer(value),
        ($0.GetPrivateDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PutPrivateDataRequest,
            $0.PutPrivateDataResponse>(
        'PutPrivate',
        putPrivate_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.PutPrivateDataRequest.fromBuffer(value),
        ($0.PutPrivateDataResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DataCostRequest, $1.Cost>(
        'GetCost',
        getCost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.DataCostRequest.fromBuffer(value),
        ($1.Cost value) => value.writeToBuffer()));
  }

  $async.Future<$0.GetPublicDataResponse> getPublic_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetPublicDataRequest> $request) async {
    return getPublic($call, await $request);
  }

  $async.Future<$0.GetPublicDataResponse> getPublic(
      $grpc.ServiceCall call, $0.GetPublicDataRequest request);

  $async.Future<$0.PutPublicDataResponse> putPublic_Pre($grpc.ServiceCall $call,
      $async.Future<$0.PutPublicDataRequest> $request) async {
    return putPublic($call, await $request);
  }

  $async.Future<$0.PutPublicDataResponse> putPublic(
      $grpc.ServiceCall call, $0.PutPublicDataRequest request);

  $async.Stream<$0.DataChunk> streamPublic_Pre($grpc.ServiceCall $call,
      $async.Future<$0.StreamPublicDataRequest> $request) async* {
    yield* streamPublic($call, await $request);
  }

  $async.Stream<$0.DataChunk> streamPublic(
      $grpc.ServiceCall call, $0.StreamPublicDataRequest request);

  $async.Future<$0.GetPrivateDataResponse> getPrivate_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetPrivateDataRequest> $request) async {
    return getPrivate($call, await $request);
  }

  $async.Future<$0.GetPrivateDataResponse> getPrivate(
      $grpc.ServiceCall call, $0.GetPrivateDataRequest request);

  $async.Future<$0.PutPrivateDataResponse> putPrivate_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.PutPrivateDataRequest> $request) async {
    return putPrivate($call, await $request);
  }

  $async.Future<$0.PutPrivateDataResponse> putPrivate(
      $grpc.ServiceCall call, $0.PutPrivateDataRequest request);

  $async.Future<$1.Cost> getCost_Pre($grpc.ServiceCall $call,
      $async.Future<$0.DataCostRequest> $request) async {
    return getCost($call, await $request);
  }

  $async.Future<$1.Cost> getCost(
      $grpc.ServiceCall call, $0.DataCostRequest request);
}
