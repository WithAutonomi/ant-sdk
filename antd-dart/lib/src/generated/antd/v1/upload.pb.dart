//
//  Generated code. Do not modify.
//  source: antd/v1/upload.proto
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

import 'common.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class PrepareFileUploadRequest extends $pb.GeneratedMessage {
  factory PrepareFileUploadRequest({
    $core.String? path,
    $core.String? visibility,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (visibility != null) result.visibility = visibility;
    return result;
  }

  PrepareFileUploadRequest._();

  factory PrepareFileUploadRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PrepareFileUploadRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareFileUploadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'visibility')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareFileUploadRequest clone() => PrepareFileUploadRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareFileUploadRequest copyWith(void Function(PrepareFileUploadRequest) updates) => super.copyWith((message) => updates(message as PrepareFileUploadRequest)) as PrepareFileUploadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareFileUploadRequest create() => PrepareFileUploadRequest._();
  @$core.override
  PrepareFileUploadRequest createEmptyInstance() => create();
  static $pb.PbList<PrepareFileUploadRequest> createRepeated() => $pb.PbList<PrepareFileUploadRequest>();
  @$core.pragma('dart2js:noInline')
  static PrepareFileUploadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareFileUploadRequest>(create);
  static PrepareFileUploadRequest? _defaultInstance;

  /// Local filesystem path on the daemon host.
  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  /// Upload visibility: "private" (default — DataMap returned to the caller)
  /// or "public" (DataMap chunk bundled into the same payment batch and
  /// stored on-network; its address is returned on finalize). Empty string
  /// is treated as "private".
  @$pb.TagNumber(2)
  $core.String get visibility => $_getSZ(1);
  @$pb.TagNumber(2)
  set visibility($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVisibility() => $_has(1);
  @$pb.TagNumber(2)
  void clearVisibility() => $_clearField(2);
}

class PrepareDataUploadRequest extends $pb.GeneratedMessage {
  factory PrepareDataUploadRequest({
    $core.List<$core.int>? data,
    $core.String? visibility,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (visibility != null) result.visibility = visibility;
    return result;
  }

  PrepareDataUploadRequest._();

  factory PrepareDataUploadRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PrepareDataUploadRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareDataUploadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'visibility')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareDataUploadRequest clone() => PrepareDataUploadRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareDataUploadRequest copyWith(void Function(PrepareDataUploadRequest) updates) => super.copyWith((message) => updates(message as PrepareDataUploadRequest)) as PrepareDataUploadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareDataUploadRequest create() => PrepareDataUploadRequest._();
  @$core.override
  PrepareDataUploadRequest createEmptyInstance() => create();
  static $pb.PbList<PrepareDataUploadRequest> createRepeated() => $pb.PbList<PrepareDataUploadRequest>();
  @$core.pragma('dart2js:noInline')
  static PrepareDataUploadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareDataUploadRequest>(create);
  static PrepareDataUploadRequest? _defaultInstance;

  /// Raw bytes to upload.
  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  /// Same semantics as PrepareFileUploadRequest.visibility.
  @$pb.TagNumber(2)
  $core.String get visibility => $_getSZ(1);
  @$pb.TagNumber(2)
  set visibility($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVisibility() => $_has(1);
  @$pb.TagNumber(2)
  void clearVisibility() => $_clearField(2);
}

class PrepareUploadResponse extends $pb.GeneratedMessage {
  factory PrepareUploadResponse({
    $core.String? uploadId,
    $core.String? paymentType,
    $core.Iterable<$2.PaymentEntry>? payments,
    $core.int? depth,
    $core.Iterable<PoolCommitmentEntry>? poolCommitments,
    $fixnum.Int64? merklePaymentTimestamp,
    $core.String? totalAmount,
    $core.String? paymentVaultAddress,
    $core.String? paymentTokenAddress,
    $core.String? rpcUrl,
  }) {
    final result = create();
    if (uploadId != null) result.uploadId = uploadId;
    if (paymentType != null) result.paymentType = paymentType;
    if (payments != null) result.payments.addAll(payments);
    if (depth != null) result.depth = depth;
    if (poolCommitments != null) result.poolCommitments.addAll(poolCommitments);
    if (merklePaymentTimestamp != null) result.merklePaymentTimestamp = merklePaymentTimestamp;
    if (totalAmount != null) result.totalAmount = totalAmount;
    if (paymentVaultAddress != null) result.paymentVaultAddress = paymentVaultAddress;
    if (paymentTokenAddress != null) result.paymentTokenAddress = paymentTokenAddress;
    if (rpcUrl != null) result.rpcUrl = rpcUrl;
    return result;
  }

  PrepareUploadResponse._();

  factory PrepareUploadResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PrepareUploadResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareUploadResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uploadId')
    ..aOS(2, _omitFieldNames ? '' : 'paymentType')
    ..pc<$2.PaymentEntry>(3, _omitFieldNames ? '' : 'payments', $pb.PbFieldType.PM, subBuilder: $2.PaymentEntry.create)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'depth', $pb.PbFieldType.OU3)
    ..pc<PoolCommitmentEntry>(5, _omitFieldNames ? '' : 'poolCommitments', $pb.PbFieldType.PM, subBuilder: PoolCommitmentEntry.create)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'merklePaymentTimestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(7, _omitFieldNames ? '' : 'totalAmount')
    ..aOS(8, _omitFieldNames ? '' : 'paymentVaultAddress')
    ..aOS(9, _omitFieldNames ? '' : 'paymentTokenAddress')
    ..aOS(10, _omitFieldNames ? '' : 'rpcUrl')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareUploadResponse clone() => PrepareUploadResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareUploadResponse copyWith(void Function(PrepareUploadResponse) updates) => super.copyWith((message) => updates(message as PrepareUploadResponse)) as PrepareUploadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareUploadResponse create() => PrepareUploadResponse._();
  @$core.override
  PrepareUploadResponse createEmptyInstance() => create();
  static $pb.PbList<PrepareUploadResponse> createRepeated() => $pb.PbList<PrepareUploadResponse>();
  @$core.pragma('dart2js:noInline')
  static PrepareUploadResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareUploadResponse>(create);
  static PrepareUploadResponse? _defaultInstance;

  /// Opaque token to pass back to FinalizeUpload.
  @$pb.TagNumber(1)
  $core.String get uploadId => $_getSZ(0);
  @$pb.TagNumber(1)
  set uploadId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUploadId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUploadId() => $_clearField(1);

  /// "wave_batch" or "merkle" — determines which fields are populated and
  /// which contract call the external signer must make.
  @$pb.TagNumber(2)
  $core.String get paymentType => $_getSZ(1);
  @$pb.TagNumber(2)
  set paymentType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPaymentType() => $_has(1);
  @$pb.TagNumber(2)
  void clearPaymentType() => $_clearField(2);

  /// --- Wave-batch fields (populated when payment_type == "wave_batch") ---
  /// Per-quote payment entries for `payForQuotes()`.
  @$pb.TagNumber(3)
  $pb.PbList<$2.PaymentEntry> get payments => $_getList(2);

  /// --- Merkle fields (populated when payment_type == "merkle") ---
  /// Merkle tree depth (1..=8).
  @$pb.TagNumber(4)
  $core.int get depth => $_getIZ(3);
  @$pb.TagNumber(4)
  set depth($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDepth() => $_has(3);
  @$pb.TagNumber(4)
  void clearDepth() => $_clearField(4);

  /// Pool commitments for `payForMerkleTree2()`.
  @$pb.TagNumber(5)
  $pb.PbList<PoolCommitmentEntry> get poolCommitments => $_getList(4);

  /// Timestamp for the merkle payment (unix seconds).
  @$pb.TagNumber(6)
  $fixnum.Int64 get merklePaymentTimestamp => $_getI64(5);
  @$pb.TagNumber(6)
  set merklePaymentTimestamp($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMerklePaymentTimestamp() => $_has(5);
  @$pb.TagNumber(6)
  void clearMerklePaymentTimestamp() => $_clearField(6);

  /// --- Common fields (always populated) ---
  /// Total amount to pay in atto tokens as a decimal string. For merkle this
  /// is "0" since the cost is determined on-chain.
  @$pb.TagNumber(7)
  $core.String get totalAmount => $_getSZ(6);
  @$pb.TagNumber(7)
  set totalAmount($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotalAmount() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalAmount() => $_clearField(7);

  /// Unified payment vault contract address (hex with 0x prefix).
  @$pb.TagNumber(8)
  $core.String get paymentVaultAddress => $_getSZ(7);
  @$pb.TagNumber(8)
  set paymentVaultAddress($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPaymentVaultAddress() => $_has(7);
  @$pb.TagNumber(8)
  void clearPaymentVaultAddress() => $_clearField(8);

  /// Payment token contract address (hex with 0x prefix).
  @$pb.TagNumber(9)
  $core.String get paymentTokenAddress => $_getSZ(8);
  @$pb.TagNumber(9)
  set paymentTokenAddress($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPaymentTokenAddress() => $_has(8);
  @$pb.TagNumber(9)
  void clearPaymentTokenAddress() => $_clearField(9);

  /// EVM RPC URL for submitting transactions.
  @$pb.TagNumber(10)
  $core.String get rpcUrl => $_getSZ(9);
  @$pb.TagNumber(10)
  set rpcUrl($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRpcUrl() => $_has(9);
  @$pb.TagNumber(10)
  void clearRpcUrl() => $_clearField(10);
}

/// A pool commitment entry for the merkle payment contract.
class PoolCommitmentEntry extends $pb.GeneratedMessage {
  factory PoolCommitmentEntry({
    $core.String? poolHash,
    $core.Iterable<CandidateNodeEntry>? candidates,
  }) {
    final result = create();
    if (poolHash != null) result.poolHash = poolHash;
    if (candidates != null) result.candidates.addAll(candidates);
    return result;
  }

  PoolCommitmentEntry._();

  factory PoolCommitmentEntry.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PoolCommitmentEntry.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PoolCommitmentEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'poolHash')
    ..pc<CandidateNodeEntry>(2, _omitFieldNames ? '' : 'candidates', $pb.PbFieldType.PM, subBuilder: CandidateNodeEntry.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PoolCommitmentEntry clone() => PoolCommitmentEntry()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PoolCommitmentEntry copyWith(void Function(PoolCommitmentEntry) updates) => super.copyWith((message) => updates(message as PoolCommitmentEntry)) as PoolCommitmentEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PoolCommitmentEntry create() => PoolCommitmentEntry._();
  @$core.override
  PoolCommitmentEntry createEmptyInstance() => create();
  static $pb.PbList<PoolCommitmentEntry> createRepeated() => $pb.PbList<PoolCommitmentEntry>();
  @$core.pragma('dart2js:noInline')
  static PoolCommitmentEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PoolCommitmentEntry>(create);
  static PoolCommitmentEntry? _defaultInstance;

  /// Pool hash (hex with 0x prefix, 32 bytes).
  @$pb.TagNumber(1)
  $core.String get poolHash => $_getSZ(0);
  @$pb.TagNumber(1)
  set poolHash($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPoolHash() => $_has(0);
  @$pb.TagNumber(1)
  void clearPoolHash() => $_clearField(1);

  /// Exactly 16 candidate nodes.
  @$pb.TagNumber(2)
  $pb.PbList<CandidateNodeEntry> get candidates => $_getList(1);
}

/// A candidate node: rewards address + price (amount).
class CandidateNodeEntry extends $pb.GeneratedMessage {
  factory CandidateNodeEntry({
    $core.String? rewardsAddress,
    $core.String? amount,
  }) {
    final result = create();
    if (rewardsAddress != null) result.rewardsAddress = rewardsAddress;
    if (amount != null) result.amount = amount;
    return result;
  }

  CandidateNodeEntry._();

  factory CandidateNodeEntry.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory CandidateNodeEntry.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CandidateNodeEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'rewardsAddress')
    ..aOS(2, _omitFieldNames ? '' : 'amount')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CandidateNodeEntry clone() => CandidateNodeEntry()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CandidateNodeEntry copyWith(void Function(CandidateNodeEntry) updates) => super.copyWith((message) => updates(message as CandidateNodeEntry)) as CandidateNodeEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CandidateNodeEntry create() => CandidateNodeEntry._();
  @$core.override
  CandidateNodeEntry createEmptyInstance() => create();
  static $pb.PbList<CandidateNodeEntry> createRepeated() => $pb.PbList<CandidateNodeEntry>();
  @$core.pragma('dart2js:noInline')
  static CandidateNodeEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CandidateNodeEntry>(create);
  static CandidateNodeEntry? _defaultInstance;

  /// Node's rewards address (hex with 0x prefix, 20 bytes).
  @$pb.TagNumber(1)
  $core.String get rewardsAddress => $_getSZ(0);
  @$pb.TagNumber(1)
  set rewardsAddress($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRewardsAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearRewardsAddress() => $_clearField(1);

  /// Node's price as a decimal string (maps to the contract's `amount` field).
  @$pb.TagNumber(2)
  $core.String get amount => $_getSZ(1);
  @$pb.TagNumber(2)
  set amount($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmount() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmount() => $_clearField(2);
}

class FinalizeUploadRequest extends $pb.GeneratedMessage {
  factory FinalizeUploadRequest({
    $core.String? uploadId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? txHashes,
    $core.String? winnerPoolHash,
    $core.bool? storeDataMap,
  }) {
    final result = create();
    if (uploadId != null) result.uploadId = uploadId;
    if (txHashes != null) result.txHashes.addEntries(txHashes);
    if (winnerPoolHash != null) result.winnerPoolHash = winnerPoolHash;
    if (storeDataMap != null) result.storeDataMap = storeDataMap;
    return result;
  }

  FinalizeUploadRequest._();

  factory FinalizeUploadRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FinalizeUploadRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FinalizeUploadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uploadId')
    ..m<$core.String, $core.String>(2, _omitFieldNames ? '' : 'txHashes', entryClassName: 'FinalizeUploadRequest.TxHashesEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('antd.v1'))
    ..aOS(3, _omitFieldNames ? '' : 'winnerPoolHash')
    ..aOB(4, _omitFieldNames ? '' : 'storeDataMap')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeUploadRequest clone() => FinalizeUploadRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeUploadRequest copyWith(void Function(FinalizeUploadRequest) updates) => super.copyWith((message) => updates(message as FinalizeUploadRequest)) as FinalizeUploadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizeUploadRequest create() => FinalizeUploadRequest._();
  @$core.override
  FinalizeUploadRequest createEmptyInstance() => create();
  static $pb.PbList<FinalizeUploadRequest> createRepeated() => $pb.PbList<FinalizeUploadRequest>();
  @$core.pragma('dart2js:noInline')
  static FinalizeUploadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FinalizeUploadRequest>(create);
  static FinalizeUploadRequest? _defaultInstance;

  /// The upload_id returned from a Prepare* call.
  @$pb.TagNumber(1)
  $core.String get uploadId => $_getSZ(0);
  @$pb.TagNumber(1)
  set uploadId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUploadId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUploadId() => $_clearField(1);

  /// Wave-batch: map of quote_hash (hex) → tx_hash (hex) from the on-chain
  /// payment. Required when the prepared upload was wave-batch, must be
  /// empty otherwise.
  @$pb.TagNumber(2)
  $pb.PbMap<$core.String, $core.String> get txHashes => $_getMap(1);

  /// Merkle: winner pool hash (hex with 0x prefix, 32 bytes) from the
  /// `MerklePaymentMade` event. Required when the prepared upload was
  /// merkle, must be empty otherwise.
  @$pb.TagNumber(3)
  $core.String get winnerPoolHash => $_getSZ(2);
  @$pb.TagNumber(3)
  set winnerPoolHash($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWinnerPoolHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearWinnerPoolHash() => $_clearField(3);

  /// If true, store the DataMap on-network via the daemon's internal wallet
  /// and return its address. If false (default), return the raw DataMap
  /// for caller-side storage. Equivalent to the REST `store_data_map`
  /// field.
  @$pb.TagNumber(4)
  $core.bool get storeDataMap => $_getBF(3);
  @$pb.TagNumber(4)
  set storeDataMap($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStoreDataMap() => $_has(3);
  @$pb.TagNumber(4)
  void clearStoreDataMap() => $_clearField(4);
}

class FinalizeUploadResponse extends $pb.GeneratedMessage {
  factory FinalizeUploadResponse({
    $core.String? dataMap,
    $core.String? address,
    $core.String? dataMapAddress,
    $fixnum.Int64? chunksStored,
  }) {
    final result = create();
    if (dataMap != null) result.dataMap = dataMap;
    if (address != null) result.address = address;
    if (dataMapAddress != null) result.dataMapAddress = dataMapAddress;
    if (chunksStored != null) result.chunksStored = chunksStored;
    return result;
  }

  FinalizeUploadResponse._();

  factory FinalizeUploadResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FinalizeUploadResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FinalizeUploadResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dataMap')
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..aOS(3, _omitFieldNames ? '' : 'dataMapAddress')
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'chunksStored', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeUploadResponse clone() => FinalizeUploadResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeUploadResponse copyWith(void Function(FinalizeUploadResponse) updates) => super.copyWith((message) => updates(message as FinalizeUploadResponse)) as FinalizeUploadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizeUploadResponse create() => FinalizeUploadResponse._();
  @$core.override
  FinalizeUploadResponse createEmptyInstance() => create();
  static $pb.PbList<FinalizeUploadResponse> createRepeated() => $pb.PbList<FinalizeUploadResponse>();
  @$core.pragma('dart2js:noInline')
  static FinalizeUploadResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FinalizeUploadResponse>(create);
  static FinalizeUploadResponse? _defaultInstance;

  /// Hex-encoded rmp_serde-serialized DataMap. Always returned.
  @$pb.TagNumber(1)
  $core.String get dataMap => $_getSZ(0);
  @$pb.TagNumber(1)
  set dataMap($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDataMap() => $_has(0);
  @$pb.TagNumber(1)
  void clearDataMap() => $_clearField(1);

  /// Network address of the stored DataMap, only set when the legacy
  /// `store_data_map = true` path published the DataMap via the daemon's
  /// internal wallet. New callers should prefer `visibility = "public"`
  /// on prepare and read `data_map_address` instead.
  @$pb.TagNumber(2)
  $core.String get address => $_getSZ(1);
  @$pb.TagNumber(2)
  set address($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddress() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddress() => $_clearField(2);

  /// Network address of the bundled DataMap chunk when the upload was
  /// prepared with `visibility = "public"`. The DataMap chunk's payment
  /// is part of the same external-signer batch as the data chunks, so
  /// no separate daemon-wallet payment is required.
  @$pb.TagNumber(3)
  $core.String get dataMapAddress => $_getSZ(2);
  @$pb.TagNumber(3)
  set dataMapAddress($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDataMapAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearDataMapAddress() => $_clearField(3);

  /// Number of chunks stored on the network.
  @$pb.TagNumber(4)
  $fixnum.Int64 get chunksStored => $_getI64(3);
  @$pb.TagNumber(4)
  set chunksStored($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasChunksStored() => $_has(3);
  @$pb.TagNumber(4)
  void clearChunksStored() => $_clearField(4);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
