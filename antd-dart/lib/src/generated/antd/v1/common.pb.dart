// This is a generated file - do not edit.
//
// Generated from antd/v1/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Cost extends $pb.GeneratedMessage {
  factory Cost({
    $core.String? attoTokens,
  }) {
    final result = create();
    if (attoTokens != null) result.attoTokens = attoTokens;
    return result;
  }

  Cost._();

  factory Cost.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Cost.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Cost',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'attoTokens')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Cost clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Cost copyWith(void Function(Cost) updates) =>
      super.copyWith((message) => updates(message as Cost)) as Cost;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Cost create() => Cost._();
  @$core.override
  Cost createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Cost getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Cost>(create);
  static Cost? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get attoTokens => $_getSZ(0);
  @$pb.TagNumber(1)
  set attoTokens($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAttoTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearAttoTokens() => $_clearField(1);
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

  factory Address.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Address.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Address',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hex')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Address clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Address copyWith(void Function(Address) updates) =>
      super.copyWith((message) => updates(message as Address)) as Address;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Address create() => Address._();
  @$core.override
  Address createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Address getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Address>(create);
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

  factory PublicKeyProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PublicKeyProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicKeyProto',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hex')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyProto copyWith(void Function(PublicKeyProto) updates) =>
      super.copyWith((message) => updates(message as PublicKeyProto))
          as PublicKeyProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PublicKeyProto create() => PublicKeyProto._();
  @$core.override
  PublicKeyProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PublicKeyProto getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PublicKeyProto>(create);
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

  factory SecretKeyProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SecretKeyProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SecretKeyProto',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hex')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SecretKeyProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SecretKeyProto copyWith(void Function(SecretKeyProto) updates) =>
      super.copyWith((message) => updates(message as SecretKeyProto))
          as SecretKeyProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SecretKeyProto create() => SecretKeyProto._();
  @$core.override
  SecretKeyProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SecretKeyProto getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SecretKeyProto>(create);
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

class GraphDescendant extends $pb.GeneratedMessage {
  factory GraphDescendant({
    $core.String? publicKey,
    $core.String? content,
  }) {
    final result = create();
    if (publicKey != null) result.publicKey = publicKey;
    if (content != null) result.content = content;
    return result;
  }

  GraphDescendant._();

  factory GraphDescendant.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GraphDescendant.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GraphDescendant',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'publicKey')
    ..aOS(2, _omitFieldNames ? '' : 'content')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphDescendant clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphDescendant copyWith(void Function(GraphDescendant) updates) =>
      super.copyWith((message) => updates(message as GraphDescendant))
          as GraphDescendant;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GraphDescendant create() => GraphDescendant._();
  @$core.override
  GraphDescendant createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GraphDescendant getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GraphDescendant>(create);
  static GraphDescendant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get publicKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set publicKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPublicKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPublicKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get content => $_getSZ(1);
  @$pb.TagNumber(2)
  set content($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearContent() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
