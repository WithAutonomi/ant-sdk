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

import 'pointers.pb.dart' as $6;

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

  static final _$listKeys = $grpc.ClientMethod<$6.ListPointerKeysRequest, $6.ListPointerKeysResponse>(
      '/antd.v1.PointerService/ListKeys',
      ($6.ListPointerKeysRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.ListPointerKeysResponse.fromBuffer(value));
  static final _$create = $grpc.ClientMethod<$6.PointerWriteRequest, $6.PointerWriteResponse>(
      '/antd.v1.PointerService/Create',
      ($6.PointerWriteRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerWriteResponse.fromBuffer(value));
  static final _$update = $grpc.ClientMethod<$6.PointerWriteRequest, $6.PointerWriteResponse>(
      '/antd.v1.PointerService/Update',
      ($6.PointerWriteRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerWriteResponse.fromBuffer(value));
  static final _$transfer = $grpc.ClientMethod<$6.PointerTransferRequest, $6.PointerTransferResponse>(
      '/antd.v1.PointerService/Transfer',
      ($6.PointerTransferRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerTransferResponse.fromBuffer(value));
  static final _$get = $grpc.ClientMethod<$6.GetPointerRequest, $6.PointerRecord>(
      '/antd.v1.PointerService/Get',
      ($6.GetPointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerRecord.fromBuffer(value));
  static final _$resolve = $grpc.ClientMethod<$6.ResolvePointerRequest, $6.PointerResolved>(
      '/antd.v1.PointerService/Resolve',
      ($6.ResolvePointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerResolved.fromBuffer(value));
  static final _$finality = $grpc.ClientMethod<$6.PointerFinalityRequest, $6.PointerFinality>(
      '/antd.v1.PointerService/Finality',
      ($6.PointerFinalityRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerFinality.fromBuffer(value));
  static final _$controller = $grpc.ClientMethod<$6.PointerControllerRequest, $6.PointerController>(
      '/antd.v1.PointerService/Controller',
      ($6.PointerControllerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PointerController.fromBuffer(value));
  static final _$prepare = $grpc.ClientMethod<$6.PreparePointerRequest, $6.PreparePointerResponse>(
      '/antd.v1.PointerService/Prepare',
      ($6.PreparePointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PreparePointerResponse.fromBuffer(value));
  static final _$finalize = $grpc.ClientMethod<$6.FinalizePointerRequest, $6.FinalizePointerResponse>(
      '/antd.v1.PointerService/Finalize',
      ($6.FinalizePointerRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.FinalizePointerResponse.fromBuffer(value));

  PointerServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$6.ListPointerKeysResponse> listKeys($6.ListPointerKeysRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$listKeys, request, options: options);
  }

  /// Create a pointer with the daemon wallet. ALREADY_EXISTS if it exists.
  $grpc.ResponseFuture<$6.PointerWriteResponse> create($6.PointerWriteRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$create, request, options: options);
  }

  /// Point a pointer at a new target with the daemon wallet, creating it if
  /// it does not exist. FAILED_PRECONDITION if the pointer is final.
  $grpc.ResponseFuture<$6.PointerWriteResponse> update($6.PointerWriteRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$update, request, options: options);
  }

  /// Hand a pointer over to the recipient's pointer for good, with the daemon
  /// wallet. Irreversible once stored.
  $grpc.ResponseFuture<$6.PointerTransferResponse> transfer($6.PointerTransferRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$transfer, request, options: options);
  }

  $grpc.ResponseFuture<$6.PointerRecord> get($6.GetPointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$get, request, options: options);
  }

  /// Follow a chain of pointers to the target at its end.
  $grpc.ResponseFuture<$6.PointerResolved> resolve($6.ResolvePointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$resolve, request, options: options);
  }

  /// Ask the whole close group whether a pointer is final, and on what.
  $grpc.ResponseFuture<$6.PointerFinality> finality($6.PointerFinalityRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$finality, request, options: options);
  }

  /// Follow a pointer's transfers to the pointer whose owner now decides.
  $grpc.ResponseFuture<$6.PointerController> controller($6.PointerControllerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$controller, request, options: options);
  }

  /// External signer: sign a write with a loaded key and quote it. Mirrors
  /// REST `/v1/pointers/prepare`; the payment shape is ChunkService's.
  $grpc.ResponseFuture<$6.PreparePointerResponse> prepare($6.PreparePointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$prepare, request, options: options);
  }

  /// External signer: store the prepared write once it is paid.
  $grpc.ResponseFuture<$6.FinalizePointerResponse> finalize($6.FinalizePointerRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$finalize, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.PointerService')
abstract class PointerServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.PointerService';

  PointerServiceBase() {
    $addMethod($grpc.ServiceMethod<$6.ListPointerKeysRequest, $6.ListPointerKeysResponse>(
        'ListKeys',
        listKeys_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.ListPointerKeysRequest.fromBuffer(value),
        ($6.ListPointerKeysResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PointerWriteRequest, $6.PointerWriteResponse>(
        'Create',
        create_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PointerWriteRequest.fromBuffer(value),
        ($6.PointerWriteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PointerWriteRequest, $6.PointerWriteResponse>(
        'Update',
        update_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PointerWriteRequest.fromBuffer(value),
        ($6.PointerWriteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PointerTransferRequest, $6.PointerTransferResponse>(
        'Transfer',
        transfer_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PointerTransferRequest.fromBuffer(value),
        ($6.PointerTransferResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.GetPointerRequest, $6.PointerRecord>(
        'Get',
        get_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.GetPointerRequest.fromBuffer(value),
        ($6.PointerRecord value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.ResolvePointerRequest, $6.PointerResolved>(
        'Resolve',
        resolve_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.ResolvePointerRequest.fromBuffer(value),
        ($6.PointerResolved value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PointerFinalityRequest, $6.PointerFinality>(
        'Finality',
        finality_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PointerFinalityRequest.fromBuffer(value),
        ($6.PointerFinality value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PointerControllerRequest, $6.PointerController>(
        'Controller',
        controller_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PointerControllerRequest.fromBuffer(value),
        ($6.PointerController value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.PreparePointerRequest, $6.PreparePointerResponse>(
        'Prepare',
        prepare_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.PreparePointerRequest.fromBuffer(value),
        ($6.PreparePointerResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.FinalizePointerRequest, $6.FinalizePointerResponse>(
        'Finalize',
        finalize_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.FinalizePointerRequest.fromBuffer(value),
        ($6.FinalizePointerResponse value) => value.writeToBuffer()));
  }

  $async.Future<$6.ListPointerKeysResponse> listKeys_Pre($grpc.ServiceCall $call, $async.Future<$6.ListPointerKeysRequest> $request) async {
    return listKeys($call, await $request);
  }

  $async.Future<$6.PointerWriteResponse> create_Pre($grpc.ServiceCall $call, $async.Future<$6.PointerWriteRequest> $request) async {
    return create($call, await $request);
  }

  $async.Future<$6.PointerWriteResponse> update_Pre($grpc.ServiceCall $call, $async.Future<$6.PointerWriteRequest> $request) async {
    return update($call, await $request);
  }

  $async.Future<$6.PointerTransferResponse> transfer_Pre($grpc.ServiceCall $call, $async.Future<$6.PointerTransferRequest> $request) async {
    return transfer($call, await $request);
  }

  $async.Future<$6.PointerRecord> get_Pre($grpc.ServiceCall $call, $async.Future<$6.GetPointerRequest> $request) async {
    return get($call, await $request);
  }

  $async.Future<$6.PointerResolved> resolve_Pre($grpc.ServiceCall $call, $async.Future<$6.ResolvePointerRequest> $request) async {
    return resolve($call, await $request);
  }

  $async.Future<$6.PointerFinality> finality_Pre($grpc.ServiceCall $call, $async.Future<$6.PointerFinalityRequest> $request) async {
    return finality($call, await $request);
  }

  $async.Future<$6.PointerController> controller_Pre($grpc.ServiceCall $call, $async.Future<$6.PointerControllerRequest> $request) async {
    return controller($call, await $request);
  }

  $async.Future<$6.PreparePointerResponse> prepare_Pre($grpc.ServiceCall $call, $async.Future<$6.PreparePointerRequest> $request) async {
    return prepare($call, await $request);
  }

  $async.Future<$6.FinalizePointerResponse> finalize_Pre($grpc.ServiceCall $call, $async.Future<$6.FinalizePointerRequest> $request) async {
    return finalize($call, await $request);
  }

  $async.Future<$6.ListPointerKeysResponse> listKeys($grpc.ServiceCall call, $6.ListPointerKeysRequest request);
  $async.Future<$6.PointerWriteResponse> create($grpc.ServiceCall call, $6.PointerWriteRequest request);
  $async.Future<$6.PointerWriteResponse> update($grpc.ServiceCall call, $6.PointerWriteRequest request);
  $async.Future<$6.PointerTransferResponse> transfer($grpc.ServiceCall call, $6.PointerTransferRequest request);
  $async.Future<$6.PointerRecord> get($grpc.ServiceCall call, $6.GetPointerRequest request);
  $async.Future<$6.PointerResolved> resolve($grpc.ServiceCall call, $6.ResolvePointerRequest request);
  $async.Future<$6.PointerFinality> finality($grpc.ServiceCall call, $6.PointerFinalityRequest request);
  $async.Future<$6.PointerController> controller($grpc.ServiceCall call, $6.PointerControllerRequest request);
  $async.Future<$6.PreparePointerResponse> prepare($grpc.ServiceCall call, $6.PreparePointerRequest request);
  $async.Future<$6.FinalizePointerResponse> finalize($grpc.ServiceCall call, $6.FinalizePointerRequest request);
}
