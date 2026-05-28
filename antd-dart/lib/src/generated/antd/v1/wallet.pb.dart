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

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GetWalletAddressRequest extends $pb.GeneratedMessage {
  factory GetWalletAddressRequest() => create();

  GetWalletAddressRequest._();

  factory GetWalletAddressRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetWalletAddressRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetWalletAddressRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletAddressRequest clone() => GetWalletAddressRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletAddressRequest copyWith(void Function(GetWalletAddressRequest) updates) => super.copyWith((message) => updates(message as GetWalletAddressRequest)) as GetWalletAddressRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetWalletAddressRequest create() => GetWalletAddressRequest._();
  @$core.override
  GetWalletAddressRequest createEmptyInstance() => create();
  static $pb.PbList<GetWalletAddressRequest> createRepeated() => $pb.PbList<GetWalletAddressRequest>();
  @$core.pragma('dart2js:noInline')
  static GetWalletAddressRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetWalletAddressRequest>(create);
  static GetWalletAddressRequest? _defaultInstance;
}

class GetWalletAddressResponse extends $pb.GeneratedMessage {
  factory GetWalletAddressResponse({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  GetWalletAddressResponse._();

  factory GetWalletAddressResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetWalletAddressResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetWalletAddressResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletAddressResponse clone() => GetWalletAddressResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletAddressResponse copyWith(void Function(GetWalletAddressResponse) updates) => super.copyWith((message) => updates(message as GetWalletAddressResponse)) as GetWalletAddressResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetWalletAddressResponse create() => GetWalletAddressResponse._();
  @$core.override
  GetWalletAddressResponse createEmptyInstance() => create();
  static $pb.PbList<GetWalletAddressResponse> createRepeated() => $pb.PbList<GetWalletAddressResponse>();
  @$core.pragma('dart2js:noInline')
  static GetWalletAddressResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetWalletAddressResponse>(create);
  static GetWalletAddressResponse? _defaultInstance;

  /// Wallet address, hex with 0x prefix (20 bytes / 42 chars).
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class GetWalletBalanceRequest extends $pb.GeneratedMessage {
  factory GetWalletBalanceRequest() => create();

  GetWalletBalanceRequest._();

  factory GetWalletBalanceRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetWalletBalanceRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetWalletBalanceRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletBalanceRequest clone() => GetWalletBalanceRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletBalanceRequest copyWith(void Function(GetWalletBalanceRequest) updates) => super.copyWith((message) => updates(message as GetWalletBalanceRequest)) as GetWalletBalanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetWalletBalanceRequest create() => GetWalletBalanceRequest._();
  @$core.override
  GetWalletBalanceRequest createEmptyInstance() => create();
  static $pb.PbList<GetWalletBalanceRequest> createRepeated() => $pb.PbList<GetWalletBalanceRequest>();
  @$core.pragma('dart2js:noInline')
  static GetWalletBalanceRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetWalletBalanceRequest>(create);
  static GetWalletBalanceRequest? _defaultInstance;
}

class GetWalletBalanceResponse extends $pb.GeneratedMessage {
  factory GetWalletBalanceResponse({
    $core.String? balance,
    $core.String? gasBalance,
  }) {
    final result = create();
    if (balance != null) result.balance = balance;
    if (gasBalance != null) result.gasBalance = gasBalance;
    return result;
  }

  GetWalletBalanceResponse._();

  factory GetWalletBalanceResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetWalletBalanceResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetWalletBalanceResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'balance')
    ..aOS(2, _omitFieldNames ? '' : 'gasBalance')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletBalanceResponse clone() => GetWalletBalanceResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetWalletBalanceResponse copyWith(void Function(GetWalletBalanceResponse) updates) => super.copyWith((message) => updates(message as GetWalletBalanceResponse)) as GetWalletBalanceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetWalletBalanceResponse create() => GetWalletBalanceResponse._();
  @$core.override
  GetWalletBalanceResponse createEmptyInstance() => create();
  static $pb.PbList<GetWalletBalanceResponse> createRepeated() => $pb.PbList<GetWalletBalanceResponse>();
  @$core.pragma('dart2js:noInline')
  static GetWalletBalanceResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetWalletBalanceResponse>(create);
  static GetWalletBalanceResponse? _defaultInstance;

  /// Token balance, atto tokens as decimal string.
  @$pb.TagNumber(1)
  $core.String get balance => $_getSZ(0);
  @$pb.TagNumber(1)
  set balance($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBalance() => $_has(0);
  @$pb.TagNumber(1)
  void clearBalance() => $_clearField(1);

  /// Gas (native EVM token) balance, atto tokens as decimal string.
  @$pb.TagNumber(2)
  $core.String get gasBalance => $_getSZ(1);
  @$pb.TagNumber(2)
  set gasBalance($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGasBalance() => $_has(1);
  @$pb.TagNumber(2)
  void clearGasBalance() => $_clearField(2);
}

class WalletApproveRequest extends $pb.GeneratedMessage {
  factory WalletApproveRequest() => create();

  WalletApproveRequest._();

  factory WalletApproveRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory WalletApproveRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WalletApproveRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WalletApproveRequest clone() => WalletApproveRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WalletApproveRequest copyWith(void Function(WalletApproveRequest) updates) => super.copyWith((message) => updates(message as WalletApproveRequest)) as WalletApproveRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WalletApproveRequest create() => WalletApproveRequest._();
  @$core.override
  WalletApproveRequest createEmptyInstance() => create();
  static $pb.PbList<WalletApproveRequest> createRepeated() => $pb.PbList<WalletApproveRequest>();
  @$core.pragma('dart2js:noInline')
  static WalletApproveRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WalletApproveRequest>(create);
  static WalletApproveRequest? _defaultInstance;
}

class WalletApproveResponse extends $pb.GeneratedMessage {
  factory WalletApproveResponse({
    $core.bool? approved,
  }) {
    final result = create();
    if (approved != null) result.approved = approved;
    return result;
  }

  WalletApproveResponse._();

  factory WalletApproveResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory WalletApproveResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WalletApproveResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'approved')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WalletApproveResponse clone() => WalletApproveResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WalletApproveResponse copyWith(void Function(WalletApproveResponse) updates) => super.copyWith((message) => updates(message as WalletApproveResponse)) as WalletApproveResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WalletApproveResponse create() => WalletApproveResponse._();
  @$core.override
  WalletApproveResponse createEmptyInstance() => create();
  static $pb.PbList<WalletApproveResponse> createRepeated() => $pb.PbList<WalletApproveResponse>();
  @$core.pragma('dart2js:noInline')
  static WalletApproveResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WalletApproveResponse>(create);
  static WalletApproveResponse? _defaultInstance;

  /// True if the approve transaction succeeded.
  @$pb.TagNumber(1)
  $core.bool get approved => $_getBF(0);
  @$pb.TagNumber(1)
  set approved($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApproved() => $_has(0);
  @$pb.TagNumber(1)
  void clearApproved() => $_clearField(1);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
