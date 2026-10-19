//
//  Generated code. Do not modify.
//  source: antd/v1/pointers.proto
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

import 'pointers.pb.dart' as $7;

export 'pointers.pb.dart';

/// Pointers: owner-signed, paid, mutable references (ADR-0016 in ant-node),
/// with ownership transfer by final redirection (ADR-0018). Mirrors the REST
/// `/v1/pointers` surface 1:1.
///
/// antd signs with owner keys it loaded at startup (`--pointer-keys`). A write
/// names the pointer by its address (`owner`), never by a key; `ListKeys`
/// lists the pointers this daemon can write.
///
/// Addresses, state ids and targets are 64 hex characters. Counters are
/// decimal strings: a final state sits at u64::MAX.
///
/// Every write pays, and every attempt pays again. Do not retry Create,
/// Update or Transfer automatically; a Finalize that fails with
/// `CLOSE_GROUP_SHORTFALL` is retried by repeating it with the same
/// `upload_id`, which reuses the payment.
@$pb.GrpcServiceName('antd.v1.PointerService')
class PointerServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$listKeys = $grpc.ClientMethod<$7.ListPointerKeysRequest, $7.ListPointerKeysResponse>(
      '/antd.v1.PointerService/ListKeys',
      ($7.ListPointerKeysRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.ListPointerKeysResponse.fromBuffer(value));
  static final _$create = $grpc.ClientMethod<$7.PointerWriteRequest, $7.PointerWriteResponse>(
      '/antd.v1.PointerService/Create',
      ($7.PointerWriteRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerWriteResponse.fromBuffer(value));
  static final _$update = $grpc.ClientMethod<$7.PointerWriteRequest, $7.PointerWriteResponse>(
      '/antd.v1.PointerService/Update',
      ($7.PointerWriteRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerWriteResponse.fromBuffer(value));
  static final _$transfer = $grpc.ClientMethod<$7.PointerTransferRequest, $7.PointerTransferResponse>(
      '/antd.v1.PointerService/Transfer',
      ($7.PointerTransferRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerTransferResponse.fromBuffer(value));
  static final _$get = $grpc.ClientMethod<$7.GetPointerRequest, $7.PointerRecord>(
      '/antd.v1.PointerService/Get',
      ($7.GetPointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerRecord.fromBuffer(value));
  static final _$resolve = $grpc.ClientMethod<$7.ResolvePointerRequest, $7.PointerResolved>(
      '/antd.v1.PointerService/Resolve',
      ($7.ResolvePointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerResolved.fromBuffer(value));
  static final _$finality = $grpc.ClientMethod<$7.PointerFinalityRequest, $7.PointerFinality>(
      '/antd.v1.PointerService/Finality',
      ($7.PointerFinalityRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerFinality.fromBuffer(value));
  static final _$controller = $grpc.ClientMethod<$7.PointerControllerRequest, $7.PointerController>(
      '/antd.v1.PointerService/Controller',
      ($7.PointerControllerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PointerController.fromBuffer(value));
  static final _$prepare = $grpc.ClientMethod<$7.PreparePointerRequest, $7.PreparePointerResponse>(
      '/antd.v1.PointerService/Prepare',
      ($7.PreparePointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.PreparePointerResponse.fromBuffer(value));
  static final _$finalize = $grpc.ClientMethod<$7.FinalizePointerRequest, $7.FinalizePointerResponse>(
      '/antd.v1.PointerService/Finalize',
      ($7.FinalizePointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.FinalizePointerResponse.fromBuffer(value));

  PointerServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$7.ListPointerKeysResponse> listKeys($7.ListPointerKeysRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$listKeys, request, options: options);
  }

  /// Create a pointer with the daemon wallet. ALREADY_EXISTS if it exists.
  $grpc.ResponseFuture<$7.PointerWriteResponse> create($7.PointerWriteRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$create, request, options: options);
  }

  /// Point a pointer at a new target with the daemon wallet, creating it if
  /// it does not exist. FAILED_PRECONDITION if the pointer is final.
  $grpc.ResponseFuture<$7.PointerWriteResponse> update($7.PointerWriteRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$update, request, options: options);
  }

  /// Hand a pointer over to the recipient's pointer for good, with the daemon
  /// wallet. Irreversible once stored.
  $grpc.ResponseFuture<$7.PointerTransferResponse> transfer($7.PointerTransferRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$transfer, request, options: options);
  }

  $grpc.ResponseFuture<$7.PointerRecord> get($7.GetPointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$get, request, options: options);
  }

  /// Follow a chain of pointers to the target at its end.
  $grpc.ResponseFuture<$7.PointerResolved> resolve($7.ResolvePointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$resolve, request, options: options);
  }

  /// Ask the whole close group whether a pointer is final, and on what.
  $grpc.ResponseFuture<$7.PointerFinality> finality($7.PointerFinalityRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$finality, request, options: options);
  }

  /// Follow a pointer's transfers to the pointer whose owner now decides.
  $grpc.ResponseFuture<$7.PointerController> controller($7.PointerControllerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$controller, request, options: options);
  }

  /// External signer: sign a write with a loaded key and quote it. Mirrors
  /// REST `/v1/pointers/prepare`; the payment shape is ChunkService's.
  $grpc.ResponseFuture<$7.PreparePointerResponse> prepare($7.PreparePointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$prepare, request, options: options);
  }

  /// External signer: store the prepared write once it is paid.
  $grpc.ResponseFuture<$7.FinalizePointerResponse> finalize($7.FinalizePointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$finalize, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.PointerService')
abstract class PointerServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.PointerService';

  PointerServiceBase() {
    $addMethod($grpc.ServiceMethod<$7.ListPointerKeysRequest, $7.ListPointerKeysResponse>(
        'ListKeys',
        listKeys_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.ListPointerKeysRequest.fromBuffer(value),
        ($7.ListPointerKeysResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.PointerWriteRequest, $7.PointerWriteResponse>(
        'Create',
        create_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.PointerWriteRequest.fromBuffer(value),
        ($7.PointerWriteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.PointerWriteRequest, $7.PointerWriteResponse>(
        'Update',
        update_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.PointerWriteRequest.fromBuffer(value),
        ($7.PointerWriteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.PointerTransferRequest, $7.PointerTransferResponse>(
        'Transfer',
        transfer_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.PointerTransferRequest.fromBuffer(value),
        ($7.PointerTransferResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.GetPointerRequest, $7.PointerRecord>(
        'Get',
        get_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.GetPointerRequest.fromBuffer(value),
        ($7.PointerRecord value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.ResolvePointerRequest, $7.PointerResolved>(
        'Resolve',
        resolve_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.ResolvePointerRequest.fromBuffer(value),
        ($7.PointerResolved value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.PointerFinalityRequest, $7.PointerFinality>(
        'Finality',
        finality_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.PointerFinalityRequest.fromBuffer(value),
        ($7.PointerFinality value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.PointerControllerRequest, $7.PointerController>(
        'Controller',
        controller_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.PointerControllerRequest.fromBuffer(value),
        ($7.PointerController value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.PreparePointerRequest, $7.PreparePointerResponse>(
        'Prepare',
        prepare_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.PreparePointerRequest.fromBuffer(value),
        ($7.PreparePointerResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.FinalizePointerRequest, $7.FinalizePointerResponse>(
        'Finalize',
        finalize_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.FinalizePointerRequest.fromBuffer(value),
        ($7.FinalizePointerResponse value) => value.writeToBuffer()));
  }

  $async.Future<$7.ListPointerKeysResponse> listKeys_Pre($grpc.ServiceCall $call, $async.Future<$7.ListPointerKeysRequest> $request) async {
    return listKeys($call, await $request);
  }

  $async.Future<$7.PointerWriteResponse> create_Pre($grpc.ServiceCall $call, $async.Future<$7.PointerWriteRequest> $request) async {
    return create($call, await $request);
  }

  $async.Future<$7.PointerWriteResponse> update_Pre($grpc.ServiceCall $call, $async.Future<$7.PointerWriteRequest> $request) async {
    return update($call, await $request);
  }

  $async.Future<$7.PointerTransferResponse> transfer_Pre($grpc.ServiceCall $call, $async.Future<$7.PointerTransferRequest> $request) async {
    return transfer($call, await $request);
  }

  $async.Future<$7.PointerRecord> get_Pre($grpc.ServiceCall $call, $async.Future<$7.GetPointerRequest> $request) async {
    return get($call, await $request);
  }

  $async.Future<$7.PointerResolved> resolve_Pre($grpc.ServiceCall $call, $async.Future<$7.ResolvePointerRequest> $request) async {
    return resolve($call, await $request);
  }

  $async.Future<$7.PointerFinality> finality_Pre($grpc.ServiceCall $call, $async.Future<$7.PointerFinalityRequest> $request) async {
    return finality($call, await $request);
  }

  $async.Future<$7.PointerController> controller_Pre($grpc.ServiceCall $call, $async.Future<$7.PointerControllerRequest> $request) async {
    return controller($call, await $request);
  }

  $async.Future<$7.PreparePointerResponse> prepare_Pre($grpc.ServiceCall $call, $async.Future<$7.PreparePointerRequest> $request) async {
    return prepare($call, await $request);
  }

  $async.Future<$7.FinalizePointerResponse> finalize_Pre($grpc.ServiceCall $call, $async.Future<$7.FinalizePointerRequest> $request) async {
    return finalize($call, await $request);
  }

  $async.Future<$7.ListPointerKeysResponse> listKeys($grpc.ServiceCall call, $7.ListPointerKeysRequest request);
  $async.Future<$7.PointerWriteResponse> create($grpc.ServiceCall call, $7.PointerWriteRequest request);
  $async.Future<$7.PointerWriteResponse> update($grpc.ServiceCall call, $7.PointerWriteRequest request);
  $async.Future<$7.PointerTransferResponse> transfer($grpc.ServiceCall call, $7.PointerTransferRequest request);
  $async.Future<$7.PointerRecord> get($grpc.ServiceCall call, $7.GetPointerRequest request);
  $async.Future<$7.PointerResolved> resolve($grpc.ServiceCall call, $7.ResolvePointerRequest request);
  $async.Future<$7.PointerFinality> finality($grpc.ServiceCall call, $7.PointerFinalityRequest request);
  $async.Future<$7.PointerController> controller($grpc.ServiceCall call, $7.PointerControllerRequest request);
  $async.Future<$7.PreparePointerResponse> prepare($grpc.ServiceCall call, $7.PreparePointerRequest request);
  $async.Future<$7.FinalizePointerResponse> finalize($grpc.ServiceCall call, $7.FinalizePointerRequest request);
}
