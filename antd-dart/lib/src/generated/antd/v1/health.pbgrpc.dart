//
//  Generated code. Do not modify.
//  source: antd/v1/health.proto
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

import 'health.pb.dart' as $5;

export 'health.pb.dart';

@$pb.GrpcServiceName('antd.v1.HealthService')
class HealthServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$check = $grpc.ClientMethod<$5.HealthCheckRequest, $5.HealthCheckResponse>(
      '/antd.v1.HealthService/Check',
      ($5.HealthCheckRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $5.HealthCheckResponse.fromBuffer(value));

  HealthServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$5.HealthCheckResponse> check($5.HealthCheckRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$check, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.HealthService')
abstract class HealthServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.HealthService';

  HealthServiceBase() {
    $addMethod($grpc.ServiceMethod<$5.HealthCheckRequest, $5.HealthCheckResponse>(
        'Check',
        check_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $5.HealthCheckRequest.fromBuffer(value),
        ($5.HealthCheckResponse value) => value.writeToBuffer()));
  }

  $async.Future<$5.HealthCheckResponse> check_Pre($grpc.ServiceCall $call, $async.Future<$5.HealthCheckRequest> $request) async {
    return check($call, await $request);
  }

  $async.Future<$5.HealthCheckResponse> check($grpc.ServiceCall call, $5.HealthCheckRequest request);
}
