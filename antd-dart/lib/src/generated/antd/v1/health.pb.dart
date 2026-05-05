// This is a generated file - do not edit.
//
// Generated from antd/v1/health.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class HealthCheckRequest extends $pb.GeneratedMessage {
  factory HealthCheckRequest() => create();

  HealthCheckRequest._();

  factory HealthCheckRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HealthCheckRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HealthCheckRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckRequest copyWith(void Function(HealthCheckRequest) updates) =>
      super.copyWith((message) => updates(message as HealthCheckRequest))
          as HealthCheckRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HealthCheckRequest create() => HealthCheckRequest._();
  @$core.override
  HealthCheckRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HealthCheckRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HealthCheckRequest>(create);
  static HealthCheckRequest? _defaultInstance;
}

class HealthCheckResponse extends $pb.GeneratedMessage {
  factory HealthCheckResponse({
    $core.String? status,
    $core.String? network,
    $core.String? version,
    $core.String? evmNetwork,
    $fixnum.Int64? uptimeSeconds,
    $core.String? buildCommit,
    $core.String? paymentTokenAddress,
    $core.String? paymentVaultAddress,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (network != null) result.network = network;
    if (version != null) result.version = version;
    if (evmNetwork != null) result.evmNetwork = evmNetwork;
    if (uptimeSeconds != null) result.uptimeSeconds = uptimeSeconds;
    if (buildCommit != null) result.buildCommit = buildCommit;
    if (paymentTokenAddress != null)
      result.paymentTokenAddress = paymentTokenAddress;
    if (paymentVaultAddress != null)
      result.paymentVaultAddress = paymentVaultAddress;
    return result;
  }

  HealthCheckResponse._();

  factory HealthCheckResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HealthCheckResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HealthCheckResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'status')
    ..aOS(2, _omitFieldNames ? '' : 'network')
    ..aOS(3, _omitFieldNames ? '' : 'version')
    ..aOS(4, _omitFieldNames ? '' : 'evmNetwork')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'uptimeSeconds', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(6, _omitFieldNames ? '' : 'buildCommit')
    ..aOS(7, _omitFieldNames ? '' : 'paymentTokenAddress')
    ..aOS(8, _omitFieldNames ? '' : 'paymentVaultAddress')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckResponse copyWith(void Function(HealthCheckResponse) updates) =>
      super.copyWith((message) => updates(message as HealthCheckResponse))
          as HealthCheckResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HealthCheckResponse create() => HealthCheckResponse._();
  @$core.override
  HealthCheckResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HealthCheckResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HealthCheckResponse>(create);
  static HealthCheckResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get status => $_getSZ(0);
  @$pb.TagNumber(1)
  set status($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get network => $_getSZ(1);
  @$pb.TagNumber(2)
  set network($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNetwork() => $_has(1);
  @$pb.TagNumber(2)
  void clearNetwork() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get version => $_getSZ(2);
  @$pb.TagNumber(3)
  set version($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get evmNetwork => $_getSZ(3);
  @$pb.TagNumber(4)
  set evmNetwork($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEvmNetwork() => $_has(3);
  @$pb.TagNumber(4)
  void clearEvmNetwork() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get uptimeSeconds => $_getI64(4);
  @$pb.TagNumber(5)
  set uptimeSeconds($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUptimeSeconds() => $_has(4);
  @$pb.TagNumber(5)
  void clearUptimeSeconds() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get buildCommit => $_getSZ(5);
  @$pb.TagNumber(6)
  set buildCommit($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBuildCommit() => $_has(5);
  @$pb.TagNumber(6)
  void clearBuildCommit() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get paymentTokenAddress => $_getSZ(6);
  @$pb.TagNumber(7)
  set paymentTokenAddress($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPaymentTokenAddress() => $_has(6);
  @$pb.TagNumber(7)
  void clearPaymentTokenAddress() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get paymentVaultAddress => $_getSZ(7);
  @$pb.TagNumber(8)
  set paymentVaultAddress($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPaymentVaultAddress() => $_has(7);
  @$pb.TagNumber(8)
  void clearPaymentVaultAddress() => $_clearField(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
