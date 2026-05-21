//
//  Generated code. Do not modify.
//  source: antd/v1/events.proto
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

import 'events.pb.dart' as $3;

export 'events.pb.dart';

@$pb.GrpcServiceName('antd.v1.EventService')
class EventServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$subscribe = $grpc.ClientMethod<$3.SubscribeRequest, $3.ClientEventProto>(
      '/antd.v1.EventService/Subscribe',
      ($3.SubscribeRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $3.ClientEventProto.fromBuffer(value));

  EventServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseStream<$3.ClientEventProto> subscribe($3.SubscribeRequest request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$subscribe, $async.Stream.fromIterable([request]), options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.EventService')
abstract class EventServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.EventService';

  EventServiceBase() {
    $addMethod($grpc.ServiceMethod<$3.SubscribeRequest, $3.ClientEventProto>(
        'Subscribe',
        subscribe_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $3.SubscribeRequest.fromBuffer(value),
        ($3.ClientEventProto value) => value.writeToBuffer()));
  }

  $async.Stream<$3.ClientEventProto> subscribe_Pre($grpc.ServiceCall $call, $async.Future<$3.SubscribeRequest> $request) async* {
    yield* subscribe($call, await $request);
  }

  $async.Stream<$3.ClientEventProto> subscribe($grpc.ServiceCall call, $3.SubscribeRequest request);
}
