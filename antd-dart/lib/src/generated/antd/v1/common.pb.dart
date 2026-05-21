//
//  Generated code. Do not modify.
//  source: antd/v1/common.proto
//
// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Cost extends $pb.GeneratedMessage {
  factory Cost({
    $core.String? attoTokens,
    $fixnum.Int64? fileSize,
    $core.int? chunkCount,
    $core.String? estimatedGasCostWei,
    $core.String? paymentMode,
  }) {
    final result = create();
    if (attoTokens != null) result.attoTokens = attoTokens;
    if (fileSize != null) result.fileSize = fileSize;
    if (chunkCount != null) result.chunkCount = chunkCount;
    if (estimatedGasCostWei != null) result.estimatedGasCostWei = estimatedGasCostWei;
    if (paymentMode != null) result.paymentMode = paymentMode;
    return result;
  }

  Cost._();

  factory Cost.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory Cost.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Cost', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'attoTokens')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'fileSize', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'chunkCount', $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'estimatedGasCostWei')
    ..aOS(5, _omitFieldNames ? '' : 'paymentMode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Cost clone() => Cost()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Cost copyWith(void Function(Cost) updates) => super.copyWith((message) => updates(message as Cost)) as Cost;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Cost create() => Cost._();
  @$core.override
  Cost createEmptyInstance() => create();
  static $pb.PbList<Cost> createRepeated() => $pb.PbList<Cost>();
  @$core.pragma('dart2js:noInline')
  static Cost getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Cost>(create);
  static Cost? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get attoTokens => $_getSZ(0);
  @$pb.TagNumber(1)
  set attoTokens($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAttoTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearAttoTokens() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get fileSize => $_getI64(1);
  @$pb.TagNumber(2)
  set fileSize($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFileSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get chunkCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set chunkCount($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChunkCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearChunkCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get estimatedGasCostWei => $_getSZ(3);
  @$pb.TagNumber(4)
  set estimatedGasCostWei($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEstimatedGasCostWei() => $_has(3);
  @$pb.TagNumber(4)
  void clearEstimatedGasCostWei() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get paymentMode => $_getSZ(4);
  @$pb.TagNumber(5)
  set paymentMode($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPaymentMode() => $_has(4);
  @$pb.TagNumber(5)
  void clearPaymentMode() => $_clearField(5);
}

class Address extends $pb.GeneratedMessage {
  factory Address({
    $core.String? hex,
  }) {
    final result = create();
    if (hex != null) result.hex = hex;
    return result;
  }

  Address._();

  factory Address.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory Address.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Address', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hex')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Address clone() => Address()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Address copyWith(void Function(Address) updates) => super.copyWith((message) => updates(message as Address)) as Address;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Address create() => Address._();
  @$core.override
  Address createEmptyInstance() => create();
  static $pb.PbList<Address> createRepeated() => $pb.PbList<Address>();
  @$core.pragma('dart2js:noInline')
  static Address getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Address>(create);
  static Address? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get hex => $_getSZ(0);
  @$pb.TagNumber(1)
  set hex($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHex() => $_has(0);
  @$pb.TagNumber(1)
  void clearHex() => $_clearField(1);
}

class PublicKeyProto extends $pb.GeneratedMessage {
  factory PublicKeyProto({
    $core.String? hex,
  }) {
    final result = create();
    if (hex != null) result.hex = hex;
    return result;
  }

  PublicKeyProto._();

  factory PublicKeyProto.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PublicKeyProto.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PublicKeyProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hex')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyProto clone() => PublicKeyProto()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyProto copyWith(void Function(PublicKeyProto) updates) => super.copyWith((message) => updates(message as PublicKeyProto)) as PublicKeyProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PublicKeyProto create() => PublicKeyProto._();
  @$core.override
  PublicKeyProto createEmptyInstance() => create();
  static $pb.PbList<PublicKeyProto> createRepeated() => $pb.PbList<PublicKeyProto>();
  @$core.pragma('dart2js:noInline')
  static PublicKeyProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PublicKeyProto>(create);
  static PublicKeyProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get hex => $_getSZ(0);
  @$pb.TagNumber(1)
  set hex($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHex() => $_has(0);
  @$pb.TagNumber(1)
  void clearHex() => $_clearField(1);
}

class SecretKeyProto extends $pb.GeneratedMessage {
  factory SecretKeyProto({
    $core.String? hex,
  }) {
    final result = create();
    if (hex != null) result.hex = hex;
    return result;
  }

  SecretKeyProto._();

  factory SecretKeyProto.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory SecretKeyProto.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SecretKeyProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hex')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SecretKeyProto clone() => SecretKeyProto()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SecretKeyProto copyWith(void Function(SecretKeyProto) updates) => super.copyWith((message) => updates(message as SecretKeyProto)) as SecretKeyProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SecretKeyProto create() => SecretKeyProto._();
  @$core.override
  SecretKeyProto createEmptyInstance() => create();
  static $pb.PbList<SecretKeyProto> createRepeated() => $pb.PbList<SecretKeyProto>();
  @$core.pragma('dart2js:noInline')
  static SecretKeyProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SecretKeyProto>(create);
  static SecretKeyProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get hex => $_getSZ(0);
  @$pb.TagNumber(1)
  set hex($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHex() => $_has(0);
  @$pb.TagNumber(1)
  void clearHex() => $_clearField(1);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
