//
//  Generated code. Do not modify.
//  source: antd/v1/files.proto
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

class PutFileRequest extends $pb.GeneratedMessage {
  factory PutFileRequest({
    $core.String? path,
    $core.String? paymentMode,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (paymentMode != null) result.paymentMode = paymentMode;
    return result;
  }

  PutFileRequest._();

  factory PutFileRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutFileRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutFileRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'paymentMode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFileRequest clone() => PutFileRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFileRequest copyWith(void Function(PutFileRequest) updates) => super.copyWith((message) => updates(message as PutFileRequest)) as PutFileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutFileRequest create() => PutFileRequest._();
  @$core.override
  PutFileRequest createEmptyInstance() => create();
  static $pb.PbList<PutFileRequest> createRepeated() => $pb.PbList<PutFileRequest>();
  @$core.pragma('dart2js:noInline')
  static PutFileRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutFileRequest>(create);
  static PutFileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  /// Optional payment mode: "auto" (default), "merkle", or "single". Empty
  /// string is treated as "auto" so old clients omitting the field stay
  /// wire-compatible.
  @$pb.TagNumber(2)
  $core.String get paymentMode => $_getSZ(1);
  @$pb.TagNumber(2)
  set paymentMode($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPaymentMode() => $_has(1);
  @$pb.TagNumber(2)
  void clearPaymentMode() => $_clearField(2);
}

class PutFilePublicResponse extends $pb.GeneratedMessage {
  factory PutFilePublicResponse({
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

  PutFilePublicResponse._();

  factory PutFilePublicResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutFilePublicResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutFilePublicResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..aOS(3, _omitFieldNames ? '' : 'storageCostAtto')
    ..aOS(4, _omitFieldNames ? '' : 'gasCostWei')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'chunksStored', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(6, _omitFieldNames ? '' : 'paymentModeUsed')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFilePublicResponse clone() => PutFilePublicResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFilePublicResponse copyWith(void Function(PutFilePublicResponse) updates) => super.copyWith((message) => updates(message as PutFilePublicResponse)) as PutFilePublicResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutFilePublicResponse create() => PutFilePublicResponse._();
  @$core.override
  PutFilePublicResponse createEmptyInstance() => create();
  static $pb.PbList<PutFilePublicResponse> createRepeated() => $pb.PbList<PutFilePublicResponse>();
  @$core.pragma('dart2js:noInline')
  static PutFilePublicResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutFilePublicResponse>(create);
  static PutFilePublicResponse? _defaultInstance;

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

class PutFileResponse extends $pb.GeneratedMessage {
  factory PutFileResponse({
    $core.String? dataMap,
    $core.String? storageCostAtto,
    $core.String? gasCostWei,
    $fixnum.Int64? chunksStored,
    $core.String? paymentModeUsed,
  }) {
    final result = create();
    if (dataMap != null) result.dataMap = dataMap;
    if (storageCostAtto != null) result.storageCostAtto = storageCostAtto;
    if (gasCostWei != null) result.gasCostWei = gasCostWei;
    if (chunksStored != null) result.chunksStored = chunksStored;
    if (paymentModeUsed != null) result.paymentModeUsed = paymentModeUsed;
    return result;
  }

  PutFileResponse._();

  factory PutFileResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutFileResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutFileResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dataMap')
    ..aOS(2, _omitFieldNames ? '' : 'storageCostAtto')
    ..aOS(3, _omitFieldNames ? '' : 'gasCostWei')
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'chunksStored', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(5, _omitFieldNames ? '' : 'paymentModeUsed')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFileResponse clone() => PutFileResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFileResponse copyWith(void Function(PutFileResponse) updates) => super.copyWith((message) => updates(message as PutFileResponse)) as PutFileResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutFileResponse create() => PutFileResponse._();
  @$core.override
  PutFileResponse createEmptyInstance() => create();
  static $pb.PbList<PutFileResponse> createRepeated() => $pb.PbList<PutFileResponse>();
  @$core.pragma('dart2js:noInline')
  static PutFileResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutFileResponse>(create);
  static PutFileResponse? _defaultInstance;

  /// Hex-encoded rmp_serde-serialized DataMap. The caller keeps this; it is
  /// NOT stored on the network. Same shape as `PutDataResponse.data_map`.
  @$pb.TagNumber(1)
  $core.String get dataMap => $_getSZ(0);
  @$pb.TagNumber(1)
  set dataMap($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDataMap() => $_has(0);
  @$pb.TagNumber(1)
  void clearDataMap() => $_clearField(1);

  /// Total storage cost paid in token units (atto). "0" if all chunks already existed.
  @$pb.TagNumber(2)
  $core.String get storageCostAtto => $_getSZ(1);
  @$pb.TagNumber(2)
  set storageCostAtto($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStorageCostAtto() => $_has(1);
  @$pb.TagNumber(2)
  void clearStorageCostAtto() => $_clearField(2);

  /// Total gas cost paid in wei, as a decimal string (u128 exceeds JSON safe-integer range).
  @$pb.TagNumber(3)
  $core.String get gasCostWei => $_getSZ(2);
  @$pb.TagNumber(3)
  set gasCostWei($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGasCostWei() => $_has(2);
  @$pb.TagNumber(3)
  void clearGasCostWei() => $_clearField(3);

  /// Number of chunks stored on the network.
  @$pb.TagNumber(4)
  $fixnum.Int64 get chunksStored => $_getI64(3);
  @$pb.TagNumber(4)
  set chunksStored($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasChunksStored() => $_has(3);
  @$pb.TagNumber(4)
  void clearChunksStored() => $_clearField(4);

  /// Which payment mode was actually used ("auto", "merkle", or "single").
  @$pb.TagNumber(5)
  $core.String get paymentModeUsed => $_getSZ(4);
  @$pb.TagNumber(5)
  set paymentModeUsed($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPaymentModeUsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearPaymentModeUsed() => $_clearField(5);
}

class GetFilePublicRequest extends $pb.GeneratedMessage {
  factory GetFilePublicRequest({
    $core.String? address,
    $core.String? destPath,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (destPath != null) result.destPath = destPath;
    return result;
  }

  GetFilePublicRequest._();

  factory GetFilePublicRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetFilePublicRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetFilePublicRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'destPath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFilePublicRequest clone() => GetFilePublicRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFilePublicRequest copyWith(void Function(GetFilePublicRequest) updates) => super.copyWith((message) => updates(message as GetFilePublicRequest)) as GetFilePublicRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetFilePublicRequest create() => GetFilePublicRequest._();
  @$core.override
  GetFilePublicRequest createEmptyInstance() => create();
  static $pb.PbList<GetFilePublicRequest> createRepeated() => $pb.PbList<GetFilePublicRequest>();
  @$core.pragma('dart2js:noInline')
  static GetFilePublicRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetFilePublicRequest>(create);
  static GetFilePublicRequest? _defaultInstance;

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

class GetFileRequest extends $pb.GeneratedMessage {
  factory GetFileRequest({
    $core.String? dataMap,
    $core.String? destPath,
  }) {
    final result = create();
    if (dataMap != null) result.dataMap = dataMap;
    if (destPath != null) result.destPath = destPath;
    return result;
  }

  GetFileRequest._();

  factory GetFileRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetFileRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetFileRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dataMap')
    ..aOS(2, _omitFieldNames ? '' : 'destPath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFileRequest clone() => GetFileRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFileRequest copyWith(void Function(GetFileRequest) updates) => super.copyWith((message) => updates(message as GetFileRequest)) as GetFileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetFileRequest create() => GetFileRequest._();
  @$core.override
  GetFileRequest createEmptyInstance() => create();
  static $pb.PbList<GetFileRequest> createRepeated() => $pb.PbList<GetFileRequest>();
  @$core.pragma('dart2js:noInline')
  static GetFileRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetFileRequest>(create);
  static GetFileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get dataMap => $_getSZ(0);
  @$pb.TagNumber(1)
  set dataMap($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDataMap() => $_has(0);
  @$pb.TagNumber(1)
  void clearDataMap() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get destPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set destPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDestPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearDestPath() => $_clearField(2);
}

/// Shared by GetPublic and Get — the file is written to dest_path, the response
/// itself is empty (success = file written, failure = RPC error).
class GetFileResponse extends $pb.GeneratedMessage {
  factory GetFileResponse() => create();

  GetFileResponse._();

  factory GetFileResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetFileResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetFileResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFileResponse clone() => GetFileResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFileResponse copyWith(void Function(GetFileResponse) updates) => super.copyWith((message) => updates(message as GetFileResponse)) as GetFileResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetFileResponse create() => GetFileResponse._();
  @$core.override
  GetFileResponse createEmptyInstance() => create();
  static $pb.PbList<GetFileResponse> createRepeated() => $pb.PbList<GetFileResponse>();
  @$core.pragma('dart2js:noInline')
  static GetFileResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetFileResponse>(create);
  static GetFileResponse? _defaultInstance;
}

class FileCostRequest extends $pb.GeneratedMessage {
  factory FileCostRequest({
    $core.String? path,
    $core.bool? isPublic,
    $core.String? paymentMode,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (isPublic != null) result.isPublic = isPublic;
    if (paymentMode != null) result.paymentMode = paymentMode;
    return result;
  }

  FileCostRequest._();

  factory FileCostRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FileCostRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FileCostRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOB(2, _omitFieldNames ? '' : 'isPublic')
    ..aOS(3, _omitFieldNames ? '' : 'paymentMode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileCostRequest clone() => FileCostRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileCostRequest copyWith(void Function(FileCostRequest) updates) => super.copyWith((message) => updates(message as FileCostRequest)) as FileCostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileCostRequest create() => FileCostRequest._();
  @$core.override
  FileCostRequest createEmptyInstance() => create();
  static $pb.PbList<FileCostRequest> createRepeated() => $pb.PbList<FileCostRequest>();
  @$core.pragma('dart2js:noInline')
  static FileCostRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileCostRequest>(create);
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

  /// Optional payment mode the estimate should reflect: "auto" (default),
  /// "merkle", or "single". Empty string is treated as "auto".
  @$pb.TagNumber(3)
  $core.String get paymentMode => $_getSZ(2);
  @$pb.TagNumber(3)
  set paymentMode($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPaymentMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearPaymentMode() => $_clearField(3);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
