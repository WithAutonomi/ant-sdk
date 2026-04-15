// This is a generated file - do not edit.
//
// Generated from antd/v1/files.proto.

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

class UploadFileRequest extends $pb.GeneratedMessage {
  factory UploadFileRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  UploadFileRequest._();

  factory UploadFileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UploadFileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UploadFileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadFileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadFileRequest copyWith(void Function(UploadFileRequest) updates) =>
      super.copyWith((message) => updates(message as UploadFileRequest))
          as UploadFileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadFileRequest create() => UploadFileRequest._();
  @$core.override
  UploadFileRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UploadFileRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UploadFileRequest>(create);
  static UploadFileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class UploadPublicResponse extends $pb.GeneratedMessage {
  factory UploadPublicResponse({
    $core.String? address,
    $core.String? storageCostAtto,
    $core.String? gasCostWei,
    $fixnum.Int64? chunksStored,
    $core.String? paymentModeUsed,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (storageCostAtto != null) result.storageCostAtto = storageCostAtto;
    if (gasCostWei != null) result.gasCostWei = gasCostWei;
    if (chunksStored != null) result.chunksStored = chunksStored;
    if (paymentModeUsed != null) result.paymentModeUsed = paymentModeUsed;
    return result;
  }

  UploadPublicResponse._();

  factory UploadPublicResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UploadPublicResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UploadPublicResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..aOS(3, _omitFieldNames ? '' : 'storageCostAtto')
    ..aOS(4, _omitFieldNames ? '' : 'gasCostWei')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'chunksStored', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(6, _omitFieldNames ? '' : 'paymentModeUsed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadPublicResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadPublicResponse copyWith(void Function(UploadPublicResponse) updates) =>
      super.copyWith((message) => updates(message as UploadPublicResponse))
          as UploadPublicResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadPublicResponse create() => UploadPublicResponse._();
  @$core.override
  UploadPublicResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UploadPublicResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UploadPublicResponse>(create);
  static UploadPublicResponse? _defaultInstance;

  @$pb.TagNumber(2)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(2)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(2)
  void clearAddress() => $_clearField(2);

  /// Total storage cost paid in token units (atto). "0" if all chunks already existed.
  @$pb.TagNumber(3)
  $core.String get storageCostAtto => $_getSZ(1);
  @$pb.TagNumber(3)
  set storageCostAtto($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasStorageCostAtto() => $_has(1);
  @$pb.TagNumber(3)
  void clearStorageCostAtto() => $_clearField(3);

  /// Total gas cost paid in wei, as a decimal string (u128 exceeds JSON safe-integer range).
  @$pb.TagNumber(4)
  $core.String get gasCostWei => $_getSZ(2);
  @$pb.TagNumber(4)
  set gasCostWei($core.String value) => $_setString(2, value);
  @$pb.TagNumber(4)
  $core.bool hasGasCostWei() => $_has(2);
  @$pb.TagNumber(4)
  void clearGasCostWei() => $_clearField(4);

  /// Number of chunks stored on the network.
  @$pb.TagNumber(5)
  $fixnum.Int64 get chunksStored => $_getI64(3);
  @$pb.TagNumber(5)
  set chunksStored($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(5)
  $core.bool hasChunksStored() => $_has(3);
  @$pb.TagNumber(5)
  void clearChunksStored() => $_clearField(5);

  /// Which payment mode was actually used ("auto", "merkle", or "single").
  @$pb.TagNumber(6)
  $core.String get paymentModeUsed => $_getSZ(4);
  @$pb.TagNumber(6)
  set paymentModeUsed($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasPaymentModeUsed() => $_has(4);
  @$pb.TagNumber(6)
  void clearPaymentModeUsed() => $_clearField(6);
}

class DownloadPublicRequest extends $pb.GeneratedMessage {
  factory DownloadPublicRequest({
    $core.String? address,
    $core.String? destPath,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (destPath != null) result.destPath = destPath;
    return result;
  }

  DownloadPublicRequest._();

  factory DownloadPublicRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadPublicRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadPublicRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'destPath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadPublicRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadPublicRequest copyWith(
          void Function(DownloadPublicRequest) updates) =>
      super.copyWith((message) => updates(message as DownloadPublicRequest))
          as DownloadPublicRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadPublicRequest create() => DownloadPublicRequest._();
  @$core.override
  DownloadPublicRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadPublicRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadPublicRequest>(create);
  static DownloadPublicRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get destPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set destPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDestPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearDestPath() => $_clearField(2);
}

class DownloadResponse extends $pb.GeneratedMessage {
  factory DownloadResponse() => create();

  DownloadResponse._();

  factory DownloadResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadResponse copyWith(void Function(DownloadResponse) updates) =>
      super.copyWith((message) => updates(message as DownloadResponse))
          as DownloadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadResponse create() => DownloadResponse._();
  @$core.override
  DownloadResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadResponse>(create);
  static DownloadResponse? _defaultInstance;
}

class FileCostRequest extends $pb.GeneratedMessage {
  factory FileCostRequest({
    $core.String? path,
    $core.bool? isPublic,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (isPublic != null) result.isPublic = isPublic;
    return result;
  }

  FileCostRequest._();

  factory FileCostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileCostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileCostRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOB(2, _omitFieldNames ? '' : 'isPublic')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileCostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileCostRequest copyWith(void Function(FileCostRequest) updates) =>
      super.copyWith((message) => updates(message as FileCostRequest))
          as FileCostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileCostRequest create() => FileCostRequest._();
  @$core.override
  FileCostRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileCostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileCostRequest>(create);
  static FileCostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isPublic => $_getBF(1);
  @$pb.TagNumber(2)
  set isPublic($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsPublic() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsPublic() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
