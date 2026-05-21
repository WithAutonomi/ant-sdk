//
//  Generated code. Do not modify.
//  source: antd/v1/data.proto
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

class GetPublicDataRequest extends $pb.GeneratedMessage {
  factory GetPublicDataRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  GetPublicDataRequest._();

  factory GetPublicDataRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetPublicDataRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPublicDataRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataRequest clone() => GetPublicDataRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataRequest copyWith(void Function(GetPublicDataRequest) updates) => super.copyWith((message) => updates(message as GetPublicDataRequest)) as GetPublicDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPublicDataRequest create() => GetPublicDataRequest._();
  @$core.override
  GetPublicDataRequest createEmptyInstance() => create();
  static $pb.PbList<GetPublicDataRequest> createRepeated() => $pb.PbList<GetPublicDataRequest>();
  @$core.pragma('dart2js:noInline')
  static GetPublicDataRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPublicDataRequest>(create);
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

  factory GetPublicDataResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetPublicDataResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPublicDataResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataResponse clone() => GetPublicDataResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPublicDataResponse copyWith(void Function(GetPublicDataResponse) updates) => super.copyWith((message) => updates(message as GetPublicDataResponse)) as GetPublicDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPublicDataResponse create() => GetPublicDataResponse._();
  @$core.override
  GetPublicDataResponse createEmptyInstance() => create();
  static $pb.PbList<GetPublicDataResponse> createRepeated() => $pb.PbList<GetPublicDataResponse>();
  @$core.pragma('dart2js:noInline')
  static GetPublicDataResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPublicDataResponse>(create);
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
    $core.String? paymentMode,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (paymentMode != null) result.paymentMode = paymentMode;
    return result;
  }

  PutPublicDataRequest._();

  factory PutPublicDataRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutPublicDataRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutPublicDataRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'paymentMode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataRequest clone() => PutPublicDataRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataRequest copyWith(void Function(PutPublicDataRequest) updates) => super.copyWith((message) => updates(message as PutPublicDataRequest)) as PutPublicDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutPublicDataRequest create() => PutPublicDataRequest._();
  @$core.override
  PutPublicDataRequest createEmptyInstance() => create();
  static $pb.PbList<PutPublicDataRequest> createRepeated() => $pb.PbList<PutPublicDataRequest>();
  @$core.pragma('dart2js:noInline')
  static PutPublicDataRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutPublicDataRequest>(create);
  static PutPublicDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

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

class PutPublicDataResponse extends $pb.GeneratedMessage {
  factory PutPublicDataResponse({
    $2.Cost? cost,
    $core.String? address,
  }) {
    final result = create();
    if (cost != null) result.cost = cost;
    if (address != null) result.address = address;
    return result;
  }

  PutPublicDataResponse._();

  factory PutPublicDataResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutPublicDataResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutPublicDataResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOM<$2.Cost>(1, _omitFieldNames ? '' : 'cost', subBuilder: $2.Cost.create)
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataResponse clone() => PutPublicDataResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutPublicDataResponse copyWith(void Function(PutPublicDataResponse) updates) => super.copyWith((message) => updates(message as PutPublicDataResponse)) as PutPublicDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutPublicDataResponse create() => PutPublicDataResponse._();
  @$core.override
  PutPublicDataResponse createEmptyInstance() => create();
  static $pb.PbList<PutPublicDataResponse> createRepeated() => $pb.PbList<PutPublicDataResponse>();
  @$core.pragma('dart2js:noInline')
  static PutPublicDataResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutPublicDataResponse>(create);
  static PutPublicDataResponse? _defaultInstance;

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

class StreamPublicDataRequest extends $pb.GeneratedMessage {
  factory StreamPublicDataRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  StreamPublicDataRequest._();

  factory StreamPublicDataRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory StreamPublicDataRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StreamPublicDataRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamPublicDataRequest clone() => StreamPublicDataRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamPublicDataRequest copyWith(void Function(StreamPublicDataRequest) updates) => super.copyWith((message) => updates(message as StreamPublicDataRequest)) as StreamPublicDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamPublicDataRequest create() => StreamPublicDataRequest._();
  @$core.override
  StreamPublicDataRequest createEmptyInstance() => create();
  static $pb.PbList<StreamPublicDataRequest> createRepeated() => $pb.PbList<StreamPublicDataRequest>();
  @$core.pragma('dart2js:noInline')
  static StreamPublicDataRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StreamPublicDataRequest>(create);
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

  factory DataChunk.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory DataChunk.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DataChunk', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataChunk clone() => DataChunk()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataChunk copyWith(void Function(DataChunk) updates) => super.copyWith((message) => updates(message as DataChunk)) as DataChunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DataChunk create() => DataChunk._();
  @$core.override
  DataChunk createEmptyInstance() => create();
  static $pb.PbList<DataChunk> createRepeated() => $pb.PbList<DataChunk>();
  @$core.pragma('dart2js:noInline')
  static DataChunk getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataChunk>(create);
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

class GetDataRequest extends $pb.GeneratedMessage {
  factory GetDataRequest({
    $core.String? dataMap,
  }) {
    final result = create();
    if (dataMap != null) result.dataMap = dataMap;
    return result;
  }

  GetDataRequest._();

  factory GetDataRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetDataRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetDataRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dataMap')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDataRequest clone() => GetDataRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDataRequest copyWith(void Function(GetDataRequest) updates) => super.copyWith((message) => updates(message as GetDataRequest)) as GetDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetDataRequest create() => GetDataRequest._();
  @$core.override
  GetDataRequest createEmptyInstance() => create();
  static $pb.PbList<GetDataRequest> createRepeated() => $pb.PbList<GetDataRequest>();
  @$core.pragma('dart2js:noInline')
  static GetDataRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetDataRequest>(create);
  static GetDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get dataMap => $_getSZ(0);
  @$pb.TagNumber(1)
  set dataMap($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDataMap() => $_has(0);
  @$pb.TagNumber(1)
  void clearDataMap() => $_clearField(1);
}

class GetDataResponse extends $pb.GeneratedMessage {
  factory GetDataResponse({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  GetDataResponse._();

  factory GetDataResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetDataResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetDataResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDataResponse clone() => GetDataResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDataResponse copyWith(void Function(GetDataResponse) updates) => super.copyWith((message) => updates(message as GetDataResponse)) as GetDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetDataResponse create() => GetDataResponse._();
  @$core.override
  GetDataResponse createEmptyInstance() => create();
  static $pb.PbList<GetDataResponse> createRepeated() => $pb.PbList<GetDataResponse>();
  @$core.pragma('dart2js:noInline')
  static GetDataResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetDataResponse>(create);
  static GetDataResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PutDataRequest extends $pb.GeneratedMessage {
  factory PutDataRequest({
    $core.List<$core.int>? data,
    $core.String? paymentMode,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (paymentMode != null) result.paymentMode = paymentMode;
    return result;
  }

  PutDataRequest._();

  factory PutDataRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutDataRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutDataRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'paymentMode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutDataRequest clone() => PutDataRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutDataRequest copyWith(void Function(PutDataRequest) updates) => super.copyWith((message) => updates(message as PutDataRequest)) as PutDataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutDataRequest create() => PutDataRequest._();
  @$core.override
  PutDataRequest createEmptyInstance() => create();
  static $pb.PbList<PutDataRequest> createRepeated() => $pb.PbList<PutDataRequest>();
  @$core.pragma('dart2js:noInline')
  static PutDataRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutDataRequest>(create);
  static PutDataRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

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

class PutDataResponse extends $pb.GeneratedMessage {
  factory PutDataResponse({
    $2.Cost? cost,
    $core.String? dataMap,
  }) {
    final result = create();
    if (cost != null) result.cost = cost;
    if (dataMap != null) result.dataMap = dataMap;
    return result;
  }

  PutDataResponse._();

  factory PutDataResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PutDataResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PutDataResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOM<$2.Cost>(1, _omitFieldNames ? '' : 'cost', subBuilder: $2.Cost.create)
    ..aOS(2, _omitFieldNames ? '' : 'dataMap')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutDataResponse clone() => PutDataResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutDataResponse copyWith(void Function(PutDataResponse) updates) => super.copyWith((message) => updates(message as PutDataResponse)) as PutDataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PutDataResponse create() => PutDataResponse._();
  @$core.override
  PutDataResponse createEmptyInstance() => create();
  static $pb.PbList<PutDataResponse> createRepeated() => $pb.PbList<PutDataResponse>();
  @$core.pragma('dart2js:noInline')
  static PutDataResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutDataResponse>(create);
  static PutDataResponse? _defaultInstance;

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
    $core.String? paymentMode,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (paymentMode != null) result.paymentMode = paymentMode;
    return result;
  }

  DataCostRequest._();

  factory DataCostRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory DataCostRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DataCostRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'paymentMode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataCostRequest clone() => DataCostRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataCostRequest copyWith(void Function(DataCostRequest) updates) => super.copyWith((message) => updates(message as DataCostRequest)) as DataCostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DataCostRequest create() => DataCostRequest._();
  @$core.override
  DataCostRequest createEmptyInstance() => create();
  static $pb.PbList<DataCostRequest> createRepeated() => $pb.PbList<DataCostRequest>();
  @$core.pragma('dart2js:noInline')
  static DataCostRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataCostRequest>(create);
  static DataCostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  /// Optional payment mode the estimate should reflect: "auto" (default),
  /// "merkle", or "single". Empty string is treated as "auto".
  @$pb.TagNumber(2)
  $core.String get paymentMode => $_getSZ(1);
  @$pb.TagNumber(2)
  set paymentMode($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPaymentMode() => $_has(1);
  @$pb.TagNumber(2)
  void clearPaymentMode() => $_clearField(2);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
