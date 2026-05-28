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

class PrepareChunkRequest extends $pb.GeneratedMessage {
  factory PrepareChunkRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  PrepareChunkRequest._();

  factory PrepareChunkRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PrepareChunkRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareChunkRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareChunkRequest clone() => PrepareChunkRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareChunkRequest copyWith(void Function(PrepareChunkRequest) updates) => super.copyWith((message) => updates(message as PrepareChunkRequest)) as PrepareChunkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareChunkRequest create() => PrepareChunkRequest._();
  @$core.override
  PrepareChunkRequest createEmptyInstance() => create();
  static $pb.PbList<PrepareChunkRequest> createRepeated() => $pb.PbList<PrepareChunkRequest>();
  @$core.pragma('dart2js:noInline')
  static PrepareChunkRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareChunkRequest>(create);
  static PrepareChunkRequest? _defaultInstance;

  /// Raw chunk bytes — at most one ant-protocol chunk.
  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

/// Mirrors REST `PrepareChunkResponse`. Single-chunk publishes are always
/// wave-batch, so there are no merkle fields. When `already_stored = true`
/// the payment fields are empty / zero and the caller can skip FinalizeChunk
/// entirely.
class PrepareChunkResponse extends $pb.GeneratedMessage {
  factory PrepareChunkResponse({
    $core.String? address,
    $core.bool? alreadyStored,
    $core.String? uploadId,
    $core.String? paymentType,
    $core.Iterable<$2.PaymentEntry>? payments,
    $core.String? totalAmount,
    $core.String? paymentVaultAddress,
    $core.String? paymentTokenAddress,
    $core.String? rpcUrl,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (alreadyStored != null) result.alreadyStored = alreadyStored;
    if (uploadId != null) result.uploadId = uploadId;
    if (paymentType != null) result.paymentType = paymentType;
    if (payments != null) result.payments.addAll(payments);
    if (totalAmount != null) result.totalAmount = totalAmount;
    if (paymentVaultAddress != null) result.paymentVaultAddress = paymentVaultAddress;
    if (paymentTokenAddress != null) result.paymentTokenAddress = paymentTokenAddress;
    if (rpcUrl != null) result.rpcUrl = rpcUrl;
    return result;
  }

  PrepareChunkResponse._();

  factory PrepareChunkResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PrepareChunkResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareChunkResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOB(2, _omitFieldNames ? '' : 'alreadyStored')
    ..aOS(3, _omitFieldNames ? '' : 'uploadId')
    ..aOS(4, _omitFieldNames ? '' : 'paymentType')
    ..pc<$2.PaymentEntry>(5, _omitFieldNames ? '' : 'payments', $pb.PbFieldType.PM, subBuilder: $2.PaymentEntry.create)
    ..aOS(6, _omitFieldNames ? '' : 'totalAmount')
    ..aOS(7, _omitFieldNames ? '' : 'paymentVaultAddress')
    ..aOS(8, _omitFieldNames ? '' : 'paymentTokenAddress')
    ..aOS(9, _omitFieldNames ? '' : 'rpcUrl')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareChunkResponse clone() => PrepareChunkResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareChunkResponse copyWith(void Function(PrepareChunkResponse) updates) => super.copyWith((message) => updates(message as PrepareChunkResponse)) as PrepareChunkResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareChunkResponse create() => PrepareChunkResponse._();
  @$core.override
  PrepareChunkResponse createEmptyInstance() => create();
  static $pb.PbList<PrepareChunkResponse> createRepeated() => $pb.PbList<PrepareChunkResponse>();
  @$core.pragma('dart2js:noInline')
  static PrepareChunkResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareChunkResponse>(create);
  static PrepareChunkResponse? _defaultInstance;

  /// Content-addressed BLAKE3 of the chunk bytes (hex with 0x prefix,
  /// 32 bytes).
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  /// True if the chunk was already stored on the network. In that case no
  /// payment or finalize call is needed; all subsequent fields are empty.
  @$pb.TagNumber(2)
  $core.bool get alreadyStored => $_getBF(1);
  @$pb.TagNumber(2)
  set alreadyStored($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAlreadyStored() => $_has(1);
  @$pb.TagNumber(2)
  void clearAlreadyStored() => $_clearField(2);

  /// Opaque token to pass back to FinalizeChunk. Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(3)
  $core.String get uploadId => $_getSZ(2);
  @$pb.TagNumber(3)
  set uploadId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUploadId() => $_has(2);
  @$pb.TagNumber(3)
  void clearUploadId() => $_clearField(3);

  /// Always "wave_batch" for single-chunk publishes. Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(4)
  $core.String get paymentType => $_getSZ(3);
  @$pb.TagNumber(4)
  set paymentType($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPaymentType() => $_has(3);
  @$pb.TagNumber(4)
  void clearPaymentType() => $_clearField(4);

  /// Per-quote payment entries for `payForQuotes()`. Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(5)
  $pb.PbList<$2.PaymentEntry> get payments => $_getList(4);

  /// Total amount to pay (atto tokens as decimal string). Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(6)
  $core.String get totalAmount => $_getSZ(5);
  @$pb.TagNumber(6)
  set totalAmount($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalAmount() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalAmount() => $_clearField(6);

  /// Unified payment vault contract address (hex with 0x prefix). Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(7)
  $core.String get paymentVaultAddress => $_getSZ(6);
  @$pb.TagNumber(7)
  set paymentVaultAddress($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPaymentVaultAddress() => $_has(6);
  @$pb.TagNumber(7)
  void clearPaymentVaultAddress() => $_clearField(7);

  /// Payment token contract address (hex with 0x prefix). Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(8)
  $core.String get paymentTokenAddress => $_getSZ(7);
  @$pb.TagNumber(8)
  set paymentTokenAddress($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPaymentTokenAddress() => $_has(7);
  @$pb.TagNumber(8)
  void clearPaymentTokenAddress() => $_clearField(8);

  /// EVM RPC URL for submitting transactions. Empty when
  /// `already_stored == true`.
  @$pb.TagNumber(9)
  $core.String get rpcUrl => $_getSZ(8);
  @$pb.TagNumber(9)
  set rpcUrl($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRpcUrl() => $_has(8);
  @$pb.TagNumber(9)
  void clearRpcUrl() => $_clearField(9);
}

class FinalizeChunkRequest extends $pb.GeneratedMessage {
  factory FinalizeChunkRequest({
    $core.String? uploadId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? txHashes,
  }) {
    final result = create();
    if (uploadId != null) result.uploadId = uploadId;
    if (txHashes != null) result.txHashes.addEntries(txHashes);
    return result;
  }

  FinalizeChunkRequest._();

  factory FinalizeChunkRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FinalizeChunkRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FinalizeChunkRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uploadId')
    ..m<$core.String, $core.String>(2, _omitFieldNames ? '' : 'txHashes', entryClassName: 'FinalizeChunkRequest.TxHashesEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('antd.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeChunkRequest clone() => FinalizeChunkRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeChunkRequest copyWith(void Function(FinalizeChunkRequest) updates) => super.copyWith((message) => updates(message as FinalizeChunkRequest)) as FinalizeChunkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizeChunkRequest create() => FinalizeChunkRequest._();
  @$core.override
  FinalizeChunkRequest createEmptyInstance() => create();
  static $pb.PbList<FinalizeChunkRequest> createRepeated() => $pb.PbList<FinalizeChunkRequest>();
  @$core.pragma('dart2js:noInline')
  static FinalizeChunkRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FinalizeChunkRequest>(create);
  static FinalizeChunkRequest? _defaultInstance;

  /// The upload_id returned from PrepareChunk.
  @$pb.TagNumber(1)
  $core.String get uploadId => $_getSZ(0);
  @$pb.TagNumber(1)
  set uploadId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUploadId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUploadId() => $_clearField(1);

  /// Map of quote_hash (hex) → tx_hash (hex) from the on-chain payment.
  @$pb.TagNumber(2)
  $pb.PbMap<$core.String, $core.String> get txHashes => $_getMap(1);
}

class FinalizeChunkResponse extends $pb.GeneratedMessage {
  factory FinalizeChunkResponse({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  FinalizeChunkResponse._();

  factory FinalizeChunkResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FinalizeChunkResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FinalizeChunkResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeChunkResponse clone() => FinalizeChunkResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeChunkResponse copyWith(void Function(FinalizeChunkResponse) updates) => super.copyWith((message) => updates(message as FinalizeChunkResponse)) as FinalizeChunkResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizeChunkResponse create() => FinalizeChunkResponse._();
  @$core.override
  FinalizeChunkResponse createEmptyInstance() => create();
  static $pb.PbList<FinalizeChunkResponse> createRepeated() => $pb.PbList<FinalizeChunkResponse>();
  @$core.pragma('dart2js:noInline')
  static FinalizeChunkResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FinalizeChunkResponse>(create);
  static FinalizeChunkResponse? _defaultInstance;

  /// Network address of the stored chunk (hex with 0x prefix, 32 bytes).
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
