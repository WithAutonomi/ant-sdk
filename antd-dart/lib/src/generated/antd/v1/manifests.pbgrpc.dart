//
//  Generated code. Do not modify.
//  source: antd/v1/manifests.proto
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

import 'manifests.pb.dart' as $6;

export 'manifests.pb.dart';

/// ADR-0006 file manifests: `.ant` files and `ant://` links (V2-1570).
///
/// Stateless. The format, content addresses, link encoding and portable path
/// rules all come from ant-core, so callers never re-implement them. The
/// network is touched only to resolve DataMaps: the embedding policy on
/// Build, and `resolve` on Decode.
///
/// Both calls are unary. A manifest is one document of at most 64 MiB that is
/// produced and parsed whole, so the server accepts requests up to 100 MiB
/// (the REST body limit); clients receiving a large manifest must raise their
/// receive limit (antd-go does this per call).
@$pb.GrpcServiceName('antd.v1.ManifestService')
class ManifestServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$build = $grpc.ClientMethod<$6.BuildManifestRequest, $6.BuildManifestResponse>(
      '/antd.v1.ManifestService/Build',
      ($6.BuildManifestRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.BuildManifestResponse.fromBuffer(value));
  static final _$decode = $grpc.ClientMethod<$6.DecodeManifestRequest, $6.DecodeManifestResponse>(
      '/antd.v1.ManifestService/Decode',
      ($6.DecodeManifestRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.DecodeManifestResponse.fromBuffer(value));

  ManifestServiceClient(super.channel, {super.options, super.interceptors});

  /// Build a manifest from DataMaps and public addresses already in hand.
  /// Nothing is uploaded or paid for.
  $grpc.ResponseFuture<$6.BuildManifestResponse> build($6.BuildManifestRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$build, request, options: options);
  }

  /// Decode `.ant` bytes, a manifest link, a file link or a bare address.
  $grpc.ResponseFuture<$6.DecodeManifestResponse> decode($6.DecodeManifestRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$decode, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.ManifestService')
abstract class ManifestServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.ManifestService';

  ManifestServiceBase() {
    $addMethod($grpc.ServiceMethod<$6.BuildManifestRequest, $6.BuildManifestResponse>(
        'Build',
        build_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.BuildManifestRequest.fromBuffer(value),
        ($6.BuildManifestResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.DecodeManifestRequest, $6.DecodeManifestResponse>(
        'Decode',
        decode_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.DecodeManifestRequest.fromBuffer(value),
        ($6.DecodeManifestResponse value) => value.writeToBuffer()));
  }

  $async.Future<$6.BuildManifestResponse> build_Pre($grpc.ServiceCall $call, $async.Future<$6.BuildManifestRequest> $request) async {
    return build($call, await $request);
  }

  $async.Future<$6.DecodeManifestResponse> decode_Pre($grpc.ServiceCall $call, $async.Future<$6.DecodeManifestRequest> $request) async {
    return decode($call, await $request);
  }

  $async.Future<$6.BuildManifestResponse> build($grpc.ServiceCall call, $6.BuildManifestRequest request);
  $async.Future<$6.DecodeManifestResponse> decode($grpc.ServiceCall call, $6.DecodeManifestRequest request);
}
