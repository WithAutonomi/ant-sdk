// This is a generated file - do not edit.
//
// Generated from antd/v1/events.proto.

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

import 'events.pb.dart' as $0;

export 'events.pb.dart';

@$pb.GrpcServiceName('antd.v1.EventService')
class EventServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  EventServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseStream<$0.ClientEventProto> subscribe(
    $0.SubscribeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$subscribe, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$subscribe =
      $grpc.ClientMethod<$0.SubscribeRequest, $0.ClientEventProto>(
          '/antd.v1.EventService/Subscribe',
          ($0.SubscribeRequest value) => value.writeToBuffer(),
          $0.ClientEventProto.fromBuffer);
}

@$pb.GrpcServiceName('antd.v1.EventService')
abstract class EventServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.EventService';

  EventServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SubscribeRequest, $0.ClientEventProto>(
        'Subscribe',
        subscribe_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.SubscribeRequest.fromBuffer(value),
        ($0.ClientEventProto value) => value.writeToBuffer()));
  }

  $async.Stream<$0.ClientEventProto> subscribe_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SubscribeRequest> $request) async* {
    yield* subscribe($call, await $request);
  }

  $async.Stream<$0.ClientEventProto> subscribe(
      $grpc.ServiceCall call, $0.SubscribeRequest request);
}
