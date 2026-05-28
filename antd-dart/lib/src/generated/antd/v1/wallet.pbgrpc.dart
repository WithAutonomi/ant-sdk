//
//  Generated code. Do not modify.
//  source: antd/v1/wallet.proto
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

import 'wallet.pb.dart' as $6;

export 'wallet.pb.dart';

/// Wallet operations. Mirrors the REST `/v1/wallet/*` surface 1:1.
///
/// All three RPCs require the daemon to have been started with a configured
/// wallet (the `AUTONOMI_WALLET_KEY` env var). When the wallet is absent the
/// daemon returns `Status::failed_precondition` with the same "wallet not
/// configured" message the REST handlers return as 503.
///
/// External-signer flows do NOT use this service — they pay via off-daemon
/// EVM transactions, see `UploadService` and `ChunkService.PrepareChunk` /
/// `FinalizeChunk` for the prepare/finalize surface. `WalletService` is only
/// for callers that have entrusted a key to the daemon.
@$pb.GrpcServiceName('antd.v1.WalletService')
class WalletServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  static final _$getAddress = $grpc.ClientMethod<$6.GetWalletAddressRequest, $6.GetWalletAddressResponse>(
      '/antd.v1.WalletService/GetAddress',
      ($6.GetWalletAddressRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.GetWalletAddressResponse.fromBuffer(value));
  static final _$getBalance = $grpc.ClientMethod<$6.GetWalletBalanceRequest, $6.GetWalletBalanceResponse>(
      '/antd.v1.WalletService/GetBalance',
      ($6.GetWalletBalanceRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.GetWalletBalanceResponse.fromBuffer(value));
  static final _$approve = $grpc.ClientMethod<$6.WalletApproveRequest, $6.WalletApproveResponse>(
      '/antd.v1.WalletService/Approve',
      ($6.WalletApproveRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.WalletApproveResponse.fromBuffer(value));

  WalletServiceClient(super.channel, {super.options, super.interceptors});

  /// Returns the wallet's on-chain address (hex with 0x prefix).
  $grpc.ResponseFuture<$6.GetWalletAddressResponse> getAddress($6.GetWalletAddressRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getAddress, request, options: options);
  }

  /// Returns the wallet's token + gas balances.
  $grpc.ResponseFuture<$6.GetWalletBalanceResponse> getBalance($6.GetWalletBalanceRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getBalance, request, options: options);
  }

  /// Approves the wallet to spend tokens on the payment vault contract.
  /// One-time operation; safe to call repeatedly (idempotent at the contract
  /// level — a no-op once approval is in place).
  $grpc.ResponseFuture<$6.WalletApproveResponse> approve($6.WalletApproveRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$approve, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.WalletService')
abstract class WalletServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.WalletService';

  WalletServiceBase() {
    $addMethod($grpc.ServiceMethod<$6.GetWalletAddressRequest, $6.GetWalletAddressResponse>(
        'GetAddress',
        getAddress_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.GetWalletAddressRequest.fromBuffer(value),
        ($6.GetWalletAddressResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.GetWalletBalanceRequest, $6.GetWalletBalanceResponse>(
        'GetBalance',
        getBalance_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.GetWalletBalanceRequest.fromBuffer(value),
        ($6.GetWalletBalanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.WalletApproveRequest, $6.WalletApproveResponse>(
        'Approve',
        approve_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.WalletApproveRequest.fromBuffer(value),
        ($6.WalletApproveResponse value) => value.writeToBuffer()));
  }

  $async.Future<$6.GetWalletAddressResponse> getAddress_Pre($grpc.ServiceCall $call, $async.Future<$6.GetWalletAddressRequest> $request) async {
    return getAddress($call, await $request);
  }

  $async.Future<$6.GetWalletBalanceResponse> getBalance_Pre($grpc.ServiceCall $call, $async.Future<$6.GetWalletBalanceRequest> $request) async {
    return getBalance($call, await $request);
  }

  $async.Future<$6.WalletApproveResponse> approve_Pre($grpc.ServiceCall $call, $async.Future<$6.WalletApproveRequest> $request) async {
    return approve($call, await $request);
  }

  $async.Future<$6.GetWalletAddressResponse> getAddress($grpc.ServiceCall call, $6.GetWalletAddressRequest request);
  $async.Future<$6.GetWalletBalanceResponse> getBalance($grpc.ServiceCall call, $6.GetWalletBalanceRequest request);
  $async.Future<$6.WalletApproveResponse> approve($grpc.ServiceCall call, $6.WalletApproveRequest request);
}
