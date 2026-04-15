// This is a generated file - do not edit.
//
// Generated from antd/v1/files.proto.

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
import 'files.pb.dart' as $0;

export 'files.pb.dart';

@$pb.GrpcServiceName('antd.v1.FileService')
class FileServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  FileServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.UploadPublicResponse> uploadPublic(
    $0.UploadFileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$uploadPublic, request, options: options);
  }

  $grpc.ResponseFuture<$0.DownloadResponse> downloadPublic(
    $0.DownloadPublicRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$downloadPublic, request, options: options);
  }

  $grpc.ResponseFuture<$0.UploadPublicResponse> dirUploadPublic(
    $0.UploadFileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$dirUploadPublic, request, options: options);
  }

  $grpc.ResponseFuture<$0.DownloadResponse> dirDownloadPublic(
    $0.DownloadPublicRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$dirDownloadPublic, request, options: options);
  }

  $grpc.ResponseFuture<$1.Cost> getFileCost(
    $0.FileCostRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getFileCost, request, options: options);
  }

  // method descriptors

  static final _$uploadPublic =
      $grpc.ClientMethod<$0.UploadFileRequest, $0.UploadPublicResponse>(
          '/antd.v1.FileService/UploadPublic',
          ($0.UploadFileRequest value) => value.writeToBuffer(),
          $0.UploadPublicResponse.fromBuffer);
  static final _$downloadPublic =
      $grpc.ClientMethod<$0.DownloadPublicRequest, $0.DownloadResponse>(
          '/antd.v1.FileService/DownloadPublic',
          ($0.DownloadPublicRequest value) => value.writeToBuffer(),
          $0.DownloadResponse.fromBuffer);
  static final _$dirUploadPublic =
      $grpc.ClientMethod<$0.UploadFileRequest, $0.UploadPublicResponse>(
          '/antd.v1.FileService/DirUploadPublic',
          ($0.UploadFileRequest value) => value.writeToBuffer(),
          $0.UploadPublicResponse.fromBuffer);
  static final _$dirDownloadPublic =
      $grpc.ClientMethod<$0.DownloadPublicRequest, $0.DownloadResponse>(
          '/antd.v1.FileService/DirDownloadPublic',
          ($0.DownloadPublicRequest value) => value.writeToBuffer(),
          $0.DownloadResponse.fromBuffer);
  static final _$getFileCost = $grpc.ClientMethod<$0.FileCostRequest, $1.Cost>(
      '/antd.v1.FileService/GetFileCost',
      ($0.FileCostRequest value) => value.writeToBuffer(),
      $1.Cost.fromBuffer);
}

@$pb.GrpcServiceName('antd.v1.FileService')
abstract class FileServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.FileService';

  FileServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.UploadFileRequest, $0.UploadPublicResponse>(
            'UploadPublic',
            uploadPublic_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UploadFileRequest.fromBuffer(value),
            ($0.UploadPublicResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.DownloadPublicRequest, $0.DownloadResponse>(
            'DownloadPublic',
            downloadPublic_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.DownloadPublicRequest.fromBuffer(value),
            ($0.DownloadResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UploadFileRequest, $0.UploadPublicResponse>(
            'DirUploadPublic',
            dirUploadPublic_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UploadFileRequest.fromBuffer(value),
            ($0.UploadPublicResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.DownloadPublicRequest, $0.DownloadResponse>(
            'DirDownloadPublic',
            dirDownloadPublic_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.DownloadPublicRequest.fromBuffer(value),
            ($0.DownloadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FileCostRequest, $1.Cost>(
        'GetFileCost',
        getFileCost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.FileCostRequest.fromBuffer(value),
        ($1.Cost value) => value.writeToBuffer()));
  }

  $async.Future<$0.UploadPublicResponse> uploadPublic_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UploadFileRequest> $request) async {
    return uploadPublic($call, await $request);
  }

  $async.Future<$0.UploadPublicResponse> uploadPublic(
      $grpc.ServiceCall call, $0.UploadFileRequest request);

  $async.Future<$0.DownloadResponse> downloadPublic_Pre($grpc.ServiceCall $call,
      $async.Future<$0.DownloadPublicRequest> $request) async {
    return downloadPublic($call, await $request);
  }

  $async.Future<$0.DownloadResponse> downloadPublic(
      $grpc.ServiceCall call, $0.DownloadPublicRequest request);

  $async.Future<$0.UploadPublicResponse> dirUploadPublic_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UploadFileRequest> $request) async {
    return dirUploadPublic($call, await $request);
  }

  $async.Future<$0.UploadPublicResponse> dirUploadPublic(
      $grpc.ServiceCall call, $0.UploadFileRequest request);

  $async.Future<$0.DownloadResponse> dirDownloadPublic_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DownloadPublicRequest> $request) async {
    return dirDownloadPublic($call, await $request);
  }

  $async.Future<$0.DownloadResponse> dirDownloadPublic(
      $grpc.ServiceCall call, $0.DownloadPublicRequest request);

  $async.Future<$1.Cost> getFileCost_Pre($grpc.ServiceCall $call,
      $async.Future<$0.FileCostRequest> $request) async {
    return getFileCost($call, await $request);
  }

  $async.Future<$1.Cost> getFileCost(
      $grpc.ServiceCall call, $0.FileCostRequest request);
}
