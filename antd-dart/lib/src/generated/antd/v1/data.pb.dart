// This is a generated file - do not edit.
//
// Generated from antd/v1/data.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'common.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GetPublicDataRequest extends $pb.GeneratedMessage {
  factory GetPublicDataRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  GetPublicDataRequest._();

  factory GetPublicDataRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetPublicDataRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPublicDataRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataRequest copyWith(void Function(GetPublicDataRequest) updates) =>
      super.copyWith((message) => updates(message as GetPublicDataRequest))
          as GetPublicDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPublicDataRequest create() => GetPublicDataRequest._();
  @$core.override
  GetPublicDataRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetPublicDataRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPublicDataRequest>(create);
  static GetPublicDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class GetPublicDataResponse extends $pb.GeneratedMessage {
  factory GetPublicDataResponse({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  GetPublicDataResponse._();

  factory GetPublicDataResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetPublicDataResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPublicDataResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataResponse copyWith(
          void Function(GetPublicDataResponse) updates) =>
      super.copyWith((message) => updates(message as GetPublicDataResponse))
          as GetPublicDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPublicDataResponse create() => GetPublicDataResponse._();
  @$core.override
  GetPublicDataResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetPublicDataResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPublicDataResponse>(create);
  static GetPublicDataResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutPublicDataRequest extends $pb.GeneratedMessage {
  factory PutPublicDataRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  PutPublicDataRequest._();

  factory PutPublicDataRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PutPublicDataRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutPublicDataRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataRequest copyWith(void Function(PutPublicDataRequest) updates) =>
      super.copyWith((message) => updates(message as PutPublicDataRequest))
          as PutPublicDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutPublicDataRequest create() => PutPublicDataRequest._();
  @$core.override
  PutPublicDataRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PutPublicDataRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PutPublicDataRequest>(create);
  static PutPublicDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutPublicDataResponse extends $pb.GeneratedMessage {
  factory PutPublicDataResponse({
    $1.Cost? cost,
    $core.String? address,
  }) {
    final result = create();
    if (cost != null) result.cost = cost;
    if (address != null) result.address = address;
    return result;
  }

  PutPublicDataResponse._();

  factory PutPublicDataResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PutPublicDataResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutPublicDataResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOM<$1.Cost>(1, _omitFieldNames ? '' : 'cost', subBuilder: $1.Cost.create)
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataResponse copyWith(
          void Function(PutPublicDataResponse) updates) =>
      super.copyWith((message) => updates(message as PutPublicDataResponse))
          as PutPublicDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutPublicDataResponse create() => PutPublicDataResponse._();
  @$core.override
  PutPublicDataResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PutPublicDataResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PutPublicDataResponse>(create);
  static PutPublicDataResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Cost get cost => $_getN(0);
  @$pb.TagNumber(1)
  set cost($1.Cost value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCost() => $_has(0);
  @$pb.TagNumber(1)
  void clearCost() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Cost ensureCost() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get address => $_getSZ(1);
  @$pb.TagNumber(2)
  set address($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddress() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddress() => $_clearField(2);
}

class StreamPublicDataRequest extends $pb.GeneratedMessage {
  factory StreamPublicDataRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  StreamPublicDataRequest._();

  factory StreamPublicDataRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StreamPublicDataRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamPublicDataRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamPublicDataRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamPublicDataRequest copyWith(
          void Function(StreamPublicDataRequest) updates) =>
      super.copyWith((message) => updates(message as StreamPublicDataRequest))
          as StreamPublicDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamPublicDataRequest create() => StreamPublicDataRequest._();
  @$core.override
  StreamPublicDataRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StreamPublicDataRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamPublicDataRequest>(create);
  static StreamPublicDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class DataChunk extends $pb.GeneratedMessage {
  factory DataChunk({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  DataChunk._();

  factory DataChunk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DataChunk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataChunk',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataChunk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataChunk copyWith(void Function(DataChunk) updates) =>
      super.copyWith((message) => updates(message as DataChunk)) as DataChunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DataChunk create() => DataChunk._();
  @$core.override
  DataChunk createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DataChunk getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataChunk>(create);
  static DataChunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class GetPrivateDataRequest extends $pb.GeneratedMessage {
  factory GetPrivateDataRequest({
    $core.String? dataMap,
  }) {
    final result = create();
    if (dataMap != null) result.dataMap = dataMap;
    return result;
  }

  GetPrivateDataRequest._();

  factory GetPrivateDataRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetPrivateDataRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPrivateDataRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dataMap')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPrivateDataRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPrivateDataRequest copyWith(
          void Function(GetPrivateDataRequest) updates) =>
      super.copyWith((message) => updates(message as GetPrivateDataRequest))
          as GetPrivateDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPrivateDataRequest create() => GetPrivateDataRequest._();
  @$core.override
  GetPrivateDataRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetPrivateDataRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPrivateDataRequest>(create);
  static GetPrivateDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get dataMap => $_getSZ(0);
  @$pb.TagNumber(1)
  set dataMap($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDataMap() => $_has(0);
  @$pb.TagNumber(1)
  void clearDataMap() => $_clearField(1);
}

class GetPrivateDataResponse extends $pb.GeneratedMessage {
  factory GetPrivateDataResponse({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  GetPrivateDataResponse._();

  factory GetPrivateDataResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetPrivateDataResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPrivateDataResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPrivateDataResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPrivateDataResponse copyWith(
          void Function(GetPrivateDataResponse) updates) =>
      super.copyWith((message) => updates(message as GetPrivateDataResponse))
          as GetPrivateDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPrivateDataResponse create() => GetPrivateDataResponse._();
  @$core.override
  GetPrivateDataResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetPrivateDataResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPrivateDataResponse>(create);
  static GetPrivateDataResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutPrivateDataRequest extends $pb.GeneratedMessage {
  factory PutPrivateDataRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  PutPrivateDataRequest._();

  factory PutPrivateDataRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PutPrivateDataRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutPrivateDataRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPrivateDataRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPrivateDataRequest copyWith(
          void Function(PutPrivateDataRequest) updates) =>
      super.copyWith((message) => updates(message as PutPrivateDataRequest))
          as PutPrivateDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutPrivateDataRequest create() => PutPrivateDataRequest._();
  @$core.override
  PutPrivateDataRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PutPrivateDataRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PutPrivateDataRequest>(create);
  static PutPrivateDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutPrivateDataResponse extends $pb.GeneratedMessage {
  factory PutPrivateDataResponse({
    $1.Cost? cost,
    $core.String? dataMap,
  }) {
    final result = create();
    if (cost != null) result.cost = cost;
    if (dataMap != null) result.dataMap = dataMap;
    return result;
  }

  PutPrivateDataResponse._();

  factory PutPrivateDataResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PutPrivateDataResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutPrivateDataResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..aOM<$1.Cost>(1, _omitFieldNames ? '' : 'cost', subBuilder: $1.Cost.create)
    ..aOS(2, _omitFieldNames ? '' : 'dataMap')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPrivateDataResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPrivateDataResponse copyWith(
          void Function(PutPrivateDataResponse) updates) =>
      super.copyWith((message) => updates(message as PutPrivateDataResponse))
          as PutPrivateDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutPrivateDataResponse create() => PutPrivateDataResponse._();
  @$core.override
  PutPrivateDataResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PutPrivateDataResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PutPrivateDataResponse>(create);
  static PutPrivateDataResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Cost get cost => $_getN(0);
  @$pb.TagNumber(1)
  set cost($1.Cost value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCost() => $_has(0);
  @$pb.TagNumber(1)
  void clearCost() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Cost ensureCost() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get dataMap => $_getSZ(1);
  @$pb.TagNumber(2)
  set dataMap($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDataMap() => $_has(1);
  @$pb.TagNumber(2)
  void clearDataMap() => $_clearField(2);
}

class DataCostRequest extends $pb.GeneratedMessage {
  factory DataCostRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  DataCostRequest._();

  factory DataCostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DataCostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataCostRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataCostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataCostRequest copyWith(void Function(DataCostRequest) updates) =>
      super.copyWith((message) => updates(message as DataCostRequest))
          as DataCostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DataCostRequest create() => DataCostRequest._();
  @$core.override
  DataCostRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DataCostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataCostRequest>(create);
  static DataCostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
