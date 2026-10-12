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

import 'wallet.pb.dart' as $7;

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

  static final _$getAddress = $grpc.ClientMethod<$7.GetWalletAddressRequest, $7.GetWalletAddressResponse>(
      '/antd.v1.WalletService/GetAddress',
      ($7.GetWalletAddressRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.GetWalletAddressResponse.fromBuffer(value));
  static final _$getBalance = $grpc.ClientMethod<$7.GetWalletBalanceRequest, $7.GetWalletBalanceResponse>(
      '/antd.v1.WalletService/GetBalance',
      ($7.GetWalletBalanceRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.GetWalletBalanceResponse.fromBuffer(value));
  static final _$approve = $grpc.ClientMethod<$7.WalletApproveRequest, $7.WalletApproveResponse>(
      '/antd.v1.WalletService/Approve',
      ($7.WalletApproveRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.WalletApproveResponse.fromBuffer(value));

  WalletServiceClient(super.channel, {super.options, super.interceptors});

  /// Returns the wallet's on-chain address (hex with 0x prefix).
  $grpc.ResponseFuture<$7.GetWalletAddressResponse> getAddress($7.GetWalletAddressRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getAddress, request, options: options);
  }

  /// Returns the wallet's token + gas balances.
  $grpc.ResponseFuture<$7.GetWalletBalanceResponse> getBalance($7.GetWalletBalanceRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getBalance, request, options: options);
  }

  /// Approves the wallet to spend tokens on the payment vault contract.
  /// One-time operation; safe to call repeatedly (idempotent at the contract
  /// level — a no-op once approval is in place).
  $grpc.ResponseFuture<$7.WalletApproveResponse> approve($7.WalletApproveRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$approve, request, options: options);
  }
}

@$pb.GrpcServiceName('antd.v1.WalletService')
abstract class WalletServiceBase extends $grpc.Service {
  $core.String get $name => 'antd.v1.WalletService';

  WalletServiceBase() {
    $addMethod($grpc.ServiceMethod<$7.GetWalletAddressRequest, $7.GetWalletAddressResponse>(
        'GetAddress',
        getAddress_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.GetWalletAddressRequest.fromBuffer(value),
        ($7.GetWalletAddressResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.GetWalletBalanceRequest, $7.GetWalletBalanceResponse>(
        'GetBalance',
        getBalance_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.GetWalletBalanceRequest.fromBuffer(value),
        ($7.GetWalletBalanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.WalletApproveRequest, $7.WalletApproveResponse>(
        'Approve',
        approve_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.WalletApproveRequest.fromBuffer(value),
        ($7.WalletApproveResponse value) => value.writeToBuffer()));
  }

  $async.Future<$7.GetWalletAddressResponse> getAddress_Pre($grpc.ServiceCall $call, $async.Future<$7.GetWalletAddressRequest> $request) async {
    return getAddress($call, await $request);
  }

  $async.Future<$7.GetWalletBalanceResponse> getBalance_Pre($grpc.ServiceCall $call, $async.Future<$7.GetWalletBalanceRequest> $request) async {
    return getBalance($call, await $request);
  }

  $async.Future<$7.WalletApproveResponse> approve_Pre($grpc.ServiceCall $call, $async.Future<$7.WalletApproveRequest> $request) async {
    return approve($call, await $request);
  }

  $async.Future<$7.GetWalletAddressResponse> getAddress($grpc.ServiceCall call, $7.GetWalletAddressRequest request);
  $async.Future<$7.GetWalletBalanceResponse> getBalance($grpc.ServiceCall call, $7.GetWalletBalanceRequest request);
  $async.Future<$7.WalletApproveResponse> approve($grpc.ServiceCall call, $7.WalletApproveRequest request);
}
