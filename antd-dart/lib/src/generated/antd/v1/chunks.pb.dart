//
//  Generated code. Do not modify.
//  source: antd/v1/chunks.proto
//
// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'common.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GetChunkRequest extends $pb.GeneratedMessage {
  factory GetChunkRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  GetChunkRequest._();

  factory GetChunkRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetChunkRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetChunkRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetChunkRequest clone() => GetChunkRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetChunkRequest copyWith(void Function(GetChunkRequest) updates) => super.copyWith((message) => updates(message as GetChunkRequest)) as GetChunkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetChunkRequest create() => GetChunkRequest._();
  @$core.override
  GetChunkRequest createEmptyInstance() => create();
  static $pb.PbList<GetChunkRequest> createRepeated() => $pb.PbList<GetChunkRequest>();
  @$core.pragma('dart2js:noInline')
  static GetChunkRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetChunkRequest>(create);
  static GetChunkRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class GetChunkResponse extends $pb.GeneratedMessage {
  factory GetChunkResponse({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  GetChunkResponse._();

  factory GetChunkResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetChunkResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetChunkResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetChunkResponse clone() => GetChunkResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetChunkResponse copyWith(void Function(GetChunkResponse) updates) => super.copyWith((message) => updates(message as GetChunkResponse)) as GetChunkResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetChunkResponse create() => GetChunkResponse._();
  @$core.override
  GetChunkResponse createEmptyInstance() => create();
  static $pb.PbList<GetChunkResponse> createRepeated() => $pb.PbList<GetChunkResponse>();
  @$core.pragma('dart2js:noInline')
  static GetChunkResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetChunkResponse>(create);
  static GetChunkResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutChunkRequest extends $pb.GeneratedMessage {
  factory PutChunkRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  PutChunkRequest._();

  factory PutChunkRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutChunkRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutChunkRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutChunkRequest clone() => PutChunkRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutChunkRequest copyWith(void Function(PutChunkRequest) updates) => super.copyWith((message) => updates(message as PutChunkRequest)) as PutChunkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutChunkRequest create() => PutChunkRequest._();
  @$core.override
  PutChunkRequest createEmptyInstance() => create();
  static $pb.PbList<PutChunkRequest> createRepeated() => $pb.PbList<PutChunkRequest>();
  @$core.pragma('dart2js:noInline')
  static PutChunkRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutChunkRequest>(create);
  static PutChunkRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutChunkResponse extends $pb.GeneratedMessage {
  factory PutChunkResponse({
    $2.Cost? cost,
    $core.String? address,
  }) {
    final result = create();
    if (cost != null) result.cost = cost;
    if (address != null) result.address = address;
    return result;
  }

  PutChunkResponse._();

  factory PutChunkResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutChunkResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutChunkResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOM<$2.Cost>(1, _omitFieldNames ? '' : 'cost', subBuilder: $2.Cost.create)
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutChunkResponse clone() => PutChunkResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutChunkResponse copyWith(void Function(PutChunkResponse) updates) => super.copyWith((message) => updates(message as PutChunkResponse)) as PutChunkResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutChunkResponse create() => PutChunkResponse._();
  @$core.override
  PutChunkResponse createEmptyInstance() => create();
  static $pb.PbList<PutChunkResponse> createRepeated() => $pb.PbList<PutChunkResponse>();
  @$core.pragma('dart2js:noInline')
  static PutChunkResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutChunkResponse>(create);
  static PutChunkResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $2.Cost get cost => $_getN(0);
  @$pb.TagNumber(1)
  set cost($2.Cost value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCost() => $_has(0);
  @$pb.TagNumber(1)
  void clearCost() => $_clearField(1);
  @$pb.TagNumber(1)
  $2.Cost ensureCost() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get address => $_getSZ(1);
  @$pb.TagNumber(2)
  set address($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddress() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddress() => $_clearField(2);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
