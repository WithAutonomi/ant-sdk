//
//  Generated code. Do not modify.
//  source: antd/v1/pointers.proto
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

class ListPointerKeysRequest extends $pb.GeneratedMessage {
  factory ListPointerKeysRequest() => create();

  ListPointerKeysRequest._();

  factory ListPointerKeysRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory ListPointerKeysRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ListPointerKeysRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPointerKeysRequest clone() => ListPointerKeysRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPointerKeysRequest copyWith(void Function(ListPointerKeysRequest) updates) => super.copyWith((message) => updates(message as ListPointerKeysRequest)) as ListPointerKeysRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPointerKeysRequest create() => ListPointerKeysRequest._();
  @$core.override
  ListPointerKeysRequest createEmptyInstance() => create();
  static $pb.PbList<ListPointerKeysRequest> createRepeated() => $pb.PbList<ListPointerKeysRequest>();
  @$core.pragma('dart2js:noInline')
  static ListPointerKeysRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListPointerKeysRequest>(create);
  static ListPointerKeysRequest? _defaultInstance;
}

class ListPointerKeysResponse extends $pb.GeneratedMessage {
  factory ListPointerKeysResponse({
    $core.Iterable<PointerKey>? keys,
  }) {
    final result = create();
    if (keys != null) result.keys.addAll(keys);
    return result;
  }

  ListPointerKeysResponse._();

  factory ListPointerKeysResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory ListPointerKeysResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ListPointerKeysResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..pc<PointerKey>(1, _omitFieldNames ? '' : 'keys', $pb.PbFieldType.PM, subBuilder: PointerKey.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPointerKeysResponse clone() => ListPointerKeysResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPointerKeysResponse copyWith(void Function(ListPointerKeysResponse) updates) => super.copyWith((message) => updates(message as ListPointerKeysResponse)) as ListPointerKeysResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPointerKeysResponse create() => ListPointerKeysResponse._();
  @$core.override
  ListPointerKeysResponse createEmptyInstance() => create();
  static $pb.PbList<ListPointerKeysResponse> createRepeated() => $pb.PbList<ListPointerKeysResponse>();
  @$core.pragma('dart2js:noInline')
  static ListPointerKeysResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListPointerKeysResponse>(create);
  static ListPointerKeysResponse? _defaultInstance;

  /// The pointers this daemon holds owner keys for.
  @$pb.TagNumber(1)
  $pb.PbList<PointerKey> get keys => $_getList(0);
}

class PointerKey extends $pb.GeneratedMessage {
  factory PointerKey({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  PointerKey._();

  factory PointerKey.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerKey.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerKey', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerKey clone() => PointerKey()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerKey copyWith(void Function(PointerKey) updates) => super.copyWith((message) => updates(message as PointerKey)) as PointerKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerKey create() => PointerKey._();
  @$core.override
  PointerKey createEmptyInstance() => create();
  static $pb.PbList<PointerKey> createRepeated() => $pb.PbList<PointerKey>();
  @$core.pragma('dart2js:noInline')
  static PointerKey getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerKey>(create);
  static PointerKey? _defaultInstance;

  /// The pointer's address, derived from the owner key.
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class PointerWriteRequest extends $pb.GeneratedMessage {
  factory PointerWriteRequest({
    $core.String? owner,
    $core.String? target,
    $core.String? kind,
  }) {
    final result = create();
    if (owner != null) result.owner = owner;
    if (target != null) result.target = target;
    if (kind != null) result.kind = kind;
    return result;
  }

  PointerWriteRequest._();

  factory PointerWriteRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerWriteRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerWriteRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'owner')
    ..aOS(2, _omitFieldNames ? '' : 'target')
    ..aOS(3, _omitFieldNames ? '' : 'kind')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerWriteRequest clone() => PointerWriteRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerWriteRequest copyWith(void Function(PointerWriteRequest) updates) => super.copyWith((message) => updates(message as PointerWriteRequest)) as PointerWriteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerWriteRequest create() => PointerWriteRequest._();
  @$core.override
  PointerWriteRequest createEmptyInstance() => create();
  static $pb.PbList<PointerWriteRequest> createRepeated() => $pb.PbList<PointerWriteRequest>();
  @$core.pragma('dart2js:noInline')
  static PointerWriteRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerWriteRequest>(create);
  static PointerWriteRequest? _defaultInstance;

  /// Address of the pointer to write.
  @$pb.TagNumber(1)
  $core.String get owner => $_getSZ(0);
  @$pb.TagNumber(1)
  set owner($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOwner() => $_has(0);
  @$pb.TagNumber(1)
  void clearOwner() => $_clearField(1);

  /// Address to point at.
  @$pb.TagNumber(2)
  $core.String get target => $_getSZ(1);
  @$pb.TagNumber(2)
  set target($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTarget() => $_has(1);
  @$pb.TagNumber(2)
  void clearTarget() => $_clearField(2);

  /// "chunk" (default when empty) or "pointer".
  @$pb.TagNumber(3)
  $core.String get kind => $_getSZ(2);
  @$pb.TagNumber(3)
  set kind($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);
}

class PointerWriteResponse extends $pb.GeneratedMessage {
  factory PointerWriteResponse({
    $core.String? address,
    $core.String? stateId,
    $core.String? counter,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (stateId != null) result.stateId = stateId;
    if (counter != null) result.counter = counter;
    return result;
  }

  PointerWriteResponse._();

  factory PointerWriteResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerWriteResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerWriteResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'stateId')
    ..aOS(3, _omitFieldNames ? '' : 'counter')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerWriteResponse clone() => PointerWriteResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerWriteResponse copyWith(void Function(PointerWriteResponse) updates) => super.copyWith((message) => updates(message as PointerWriteResponse)) as PointerWriteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerWriteResponse create() => PointerWriteResponse._();
  @$core.override
  PointerWriteResponse createEmptyInstance() => create();
  static $pb.PbList<PointerWriteResponse> createRepeated() => $pb.PbList<PointerWriteResponse>();
  @$core.pragma('dart2js:noInline')
  static PointerWriteResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerWriteResponse>(create);
  static PointerWriteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stateId => $_getSZ(1);
  @$pb.TagNumber(2)
  set stateId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStateId() => $_has(1);
  @$pb.TagNumber(2)
  void clearStateId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get counter => $_getSZ(2);
  @$pb.TagNumber(3)
  set counter($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCounter() => $_has(2);
  @$pb.TagNumber(3)
  void clearCounter() => $_clearField(3);
}

class PointerTransferRequest extends $pb.GeneratedMessage {
  factory PointerTransferRequest({
    $core.String? owner,
    $core.String? recipient,
  }) {
    final result = create();
    if (owner != null) result.owner = owner;
    if (recipient != null) result.recipient = recipient;
    return result;
  }

  PointerTransferRequest._();

  factory PointerTransferRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerTransferRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerTransferRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'owner')
    ..aOS(2, _omitFieldNames ? '' : 'recipient')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerTransferRequest clone() => PointerTransferRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerTransferRequest copyWith(void Function(PointerTransferRequest) updates) => super.copyWith((message) => updates(message as PointerTransferRequest)) as PointerTransferRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerTransferRequest create() => PointerTransferRequest._();
  @$core.override
  PointerTransferRequest createEmptyInstance() => create();
  static $pb.PbList<PointerTransferRequest> createRepeated() => $pb.PbList<PointerTransferRequest>();
  @$core.pragma('dart2js:noInline')
  static PointerTransferRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerTransferRequest>(create);
  static PointerTransferRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get owner => $_getSZ(0);
  @$pb.TagNumber(1)
  set owner($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOwner() => $_has(0);
  @$pb.TagNumber(1)
  void clearOwner() => $_clearField(1);

  /// Address of the recipient's pointer, which must already exist.
  @$pb.TagNumber(2)
  $core.String get recipient => $_getSZ(1);
  @$pb.TagNumber(2)
  set recipient($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRecipient() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecipient() => $_clearField(2);
}

class PointerTransferResponse extends $pb.GeneratedMessage {
  factory PointerTransferResponse({
    $core.String? address,
    $core.String? stateId,
    PointerFinality? finality,
    $core.String? finalityError,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (stateId != null) result.stateId = stateId;
    if (finality != null) result.finality = finality;
    if (finalityError != null) result.finalityError = finalityError;
    return result;
  }

  PointerTransferResponse._();

  factory PointerTransferResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerTransferResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerTransferResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'stateId')
    ..aOM<PointerFinality>(3, _omitFieldNames ? '' : 'finality', subBuilder: PointerFinality.create)
    ..aOS(4, _omitFieldNames ? '' : 'finalityError')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerTransferResponse clone() => PointerTransferResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerTransferResponse copyWith(void Function(PointerTransferResponse) updates) => super.copyWith((message) => updates(message as PointerTransferResponse)) as PointerTransferResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerTransferResponse create() => PointerTransferResponse._();
  @$core.override
  PointerTransferResponse createEmptyInstance() => create();
  static $pb.PbList<PointerTransferResponse> createRepeated() => $pb.PbList<PointerTransferResponse>();
  @$core.pragma('dart2js:noInline')
  static PointerTransferResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerTransferResponse>(create);
  static PointerTransferResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stateId => $_getSZ(1);
  @$pb.TagNumber(2)
  set stateId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStateId() => $_has(1);
  @$pb.TagNumber(2)
  void clearStateId() => $_clearField(2);

  /// The close group's view once the write landed. Unset when that check
  /// failed, which does not undo the transfer; see `finality_error`.
  @$pb.TagNumber(3)
  PointerFinality get finality => $_getN(2);
  @$pb.TagNumber(3)
  set finality(PointerFinality value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFinality() => $_has(2);
  @$pb.TagNumber(3)
  void clearFinality() => $_clearField(3);
  @$pb.TagNumber(3)
  PointerFinality ensureFinality() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get finalityError => $_getSZ(3);
  @$pb.TagNumber(4)
  set finalityError($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFinalityError() => $_has(3);
  @$pb.TagNumber(4)
  void clearFinalityError() => $_clearField(4);
}

class GetPointerRequest extends $pb.GeneratedMessage {
  factory GetPointerRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  GetPointerRequest._();

  factory GetPointerRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory GetPointerRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPointerRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPointerRequest clone() => GetPointerRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPointerRequest copyWith(void Function(GetPointerRequest) updates) => super.copyWith((message) => updates(message as GetPointerRequest)) as GetPointerRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPointerRequest create() => GetPointerRequest._();
  @$core.override
  GetPointerRequest createEmptyInstance() => create();
  static $pb.PbList<GetPointerRequest> createRepeated() => $pb.PbList<GetPointerRequest>();
  @$core.pragma('dart2js:noInline')
  static GetPointerRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPointerRequest>(create);
  static GetPointerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class PointerRecord extends $pb.GeneratedMessage {
  factory PointerRecord({
    $core.String? address,
    $core.String? owner,
    $core.String? counter,
    $core.String? kind,
    $core.int? kindTag,
    $core.String? target,
    $core.String? stateId,
    $core.bool? isFinal,
    $core.String? transferredTo,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (owner != null) result.owner = owner;
    if (counter != null) result.counter = counter;
    if (kind != null) result.kind = kind;
    if (kindTag != null) result.kindTag = kindTag;
    if (target != null) result.target = target;
    if (stateId != null) result.stateId = stateId;
    if (isFinal != null) result.isFinal = isFinal;
    if (transferredTo != null) result.transferredTo = transferredTo;
    return result;
  }

  PointerRecord._();

  factory PointerRecord.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerRecord.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerRecord', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'owner')
    ..aOS(3, _omitFieldNames ? '' : 'counter')
    ..aOS(4, _omitFieldNames ? '' : 'kind')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'kindTag', $pb.PbFieldType.OU3)
    ..aOS(6, _omitFieldNames ? '' : 'target')
    ..aOS(7, _omitFieldNames ? '' : 'stateId')
    ..aOB(8, _omitFieldNames ? '' : 'isFinal')
    ..aOS(9, _omitFieldNames ? '' : 'transferredTo')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerRecord clone() => PointerRecord()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerRecord copyWith(void Function(PointerRecord) updates) => super.copyWith((message) => updates(message as PointerRecord)) as PointerRecord;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerRecord create() => PointerRecord._();
  @$core.override
  PointerRecord createEmptyInstance() => create();
  static $pb.PbList<PointerRecord> createRepeated() => $pb.PbList<PointerRecord>();
  @$core.pragma('dart2js:noInline')
  static PointerRecord getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerRecord>(create);
  static PointerRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  /// Owner's ML-DSA-65 public key (hex, 1,952 bytes).
  @$pb.TagNumber(2)
  $core.String get owner => $_getSZ(1);
  @$pb.TagNumber(2)
  set owner($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOwner() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwner() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get counter => $_getSZ(2);
  @$pb.TagNumber(3)
  set counter($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCounter() => $_has(2);
  @$pb.TagNumber(3)
  void clearCounter() => $_clearField(3);

  /// "chunk", "pointer", or "unknown"; `kind_tag` is the raw value.
  @$pb.TagNumber(4)
  $core.String get kind => $_getSZ(3);
  @$pb.TagNumber(4)
  set kind($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get kindTag => $_getIZ(4);
  @$pb.TagNumber(5)
  set kindTag($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasKindTag() => $_has(4);
  @$pb.TagNumber(5)
  void clearKindTag() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get target => $_getSZ(5);
  @$pb.TagNumber(6)
  set target($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTarget() => $_has(5);
  @$pb.TagNumber(6)
  void clearTarget() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get stateId => $_getSZ(6);
  @$pb.TagNumber(7)
  set stateId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStateId() => $_has(6);
  @$pb.TagNumber(7)
  void clearStateId() => $_clearField(7);

  /// At the final counter: nothing can replace this state.
  @$pb.TagNumber(8)
  $core.bool get isFinal => $_getBF(7);
  @$pb.TagNumber(8)
  set isFinal($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIsFinal() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsFinal() => $_clearField(8);

  /// Set when the final state hands the pointer over to another.
  @$pb.TagNumber(9)
  $core.String get transferredTo => $_getSZ(8);
  @$pb.TagNumber(9)
  set transferredTo($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTransferredTo() => $_has(8);
  @$pb.TagNumber(9)
  void clearTransferredTo() => $_clearField(9);
}

class ResolvePointerRequest extends $pb.GeneratedMessage {
  factory ResolvePointerRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  ResolvePointerRequest._();

  factory ResolvePointerRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory ResolvePointerRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ResolvePointerRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolvePointerRequest clone() => ResolvePointerRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolvePointerRequest copyWith(void Function(ResolvePointerRequest) updates) => super.copyWith((message) => updates(message as ResolvePointerRequest)) as ResolvePointerRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ResolvePointerRequest create() => ResolvePointerRequest._();
  @$core.override
  ResolvePointerRequest createEmptyInstance() => create();
  static $pb.PbList<ResolvePointerRequest> createRepeated() => $pb.PbList<ResolvePointerRequest>();
  @$core.pragma('dart2js:noInline')
  static ResolvePointerRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ResolvePointerRequest>(create);
  static ResolvePointerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class PointerResolved extends $pb.GeneratedMessage {
  factory PointerResolved({
    $core.String? kind,
    $core.int? kindTag,
    $core.String? target,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (kindTag != null) result.kindTag = kindTag;
    if (target != null) result.target = target;
    return result;
  }

  PointerResolved._();

  factory PointerResolved.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerResolved.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerResolved', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'kind')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'kindTag', $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'target')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerResolved clone() => PointerResolved()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerResolved copyWith(void Function(PointerResolved) updates) => super.copyWith((message) => updates(message as PointerResolved)) as PointerResolved;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerResolved create() => PointerResolved._();
  @$core.override
  PointerResolved createEmptyInstance() => create();
  static $pb.PbList<PointerResolved> createRepeated() => $pb.PbList<PointerResolved>();
  @$core.pragma('dart2js:noInline')
  static PointerResolved getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerResolved>(create);
  static PointerResolved? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get kind => $_getSZ(0);
  @$pb.TagNumber(1)
  set kind($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get kindTag => $_getIZ(1);
  @$pb.TagNumber(2)
  set kindTag($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKindTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearKindTag() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get target => $_getSZ(2);
  @$pb.TagNumber(3)
  set target($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTarget() => $_has(2);
  @$pb.TagNumber(3)
  void clearTarget() => $_clearField(3);
}

class PointerFinalityRequest extends $pb.GeneratedMessage {
  factory PointerFinalityRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  PointerFinalityRequest._();

  factory PointerFinalityRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerFinalityRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerFinalityRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerFinalityRequest clone() => PointerFinalityRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerFinalityRequest copyWith(void Function(PointerFinalityRequest) updates) => super.copyWith((message) => updates(message as PointerFinalityRequest)) as PointerFinalityRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerFinalityRequest create() => PointerFinalityRequest._();
  @$core.override
  PointerFinalityRequest createEmptyInstance() => create();
  static $pb.PbList<PointerFinalityRequest> createRepeated() => $pb.PbList<PointerFinalityRequest>();
  @$core.pragma('dart2js:noInline')
  static PointerFinalityRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerFinalityRequest>(create);
  static PointerFinalityRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class PointerFinalState extends $pb.GeneratedMessage {
  factory PointerFinalState({
    $core.String? stateId,
    $core.String? kind,
    $core.int? kindTag,
    $core.String? target,
    $core.int? holders,
    $core.String? transferredTo,
  }) {
    final result = create();
    if (stateId != null) result.stateId = stateId;
    if (kind != null) result.kind = kind;
    if (kindTag != null) result.kindTag = kindTag;
    if (target != null) result.target = target;
    if (holders != null) result.holders = holders;
    if (transferredTo != null) result.transferredTo = transferredTo;
    return result;
  }

  PointerFinalState._();

  factory PointerFinalState.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerFinalState.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerFinalState', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stateId')
    ..aOS(2, _omitFieldNames ? '' : 'kind')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'kindTag', $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'target')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'holders', $pb.PbFieldType.OU3)
    ..aOS(6, _omitFieldNames ? '' : 'transferredTo')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerFinalState clone() => PointerFinalState()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerFinalState copyWith(void Function(PointerFinalState) updates) => super.copyWith((message) => updates(message as PointerFinalState)) as PointerFinalState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerFinalState create() => PointerFinalState._();
  @$core.override
  PointerFinalState createEmptyInstance() => create();
  static $pb.PbList<PointerFinalState> createRepeated() => $pb.PbList<PointerFinalState>();
  @$core.pragma('dart2js:noInline')
  static PointerFinalState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerFinalState>(create);
  static PointerFinalState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stateId => $_getSZ(0);
  @$pb.TagNumber(1)
  set stateId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStateId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStateId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get kind => $_getSZ(1);
  @$pb.TagNumber(2)
  set kind($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get kindTag => $_getIZ(2);
  @$pb.TagNumber(3)
  set kindTag($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKindTag() => $_has(2);
  @$pb.TagNumber(3)
  void clearKindTag() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get target => $_getSZ(3);
  @$pb.TagNumber(4)
  set target($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTarget() => $_has(3);
  @$pb.TagNumber(4)
  void clearTarget() => $_clearField(4);

  /// How many peers of the close group hold it.
  @$pb.TagNumber(5)
  $core.int get holders => $_getIZ(4);
  @$pb.TagNumber(5)
  set holders($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHolders() => $_has(4);
  @$pb.TagNumber(5)
  void clearHolders() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get transferredTo => $_getSZ(5);
  @$pb.TagNumber(6)
  set transferredTo($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTransferredTo() => $_has(5);
  @$pb.TagNumber(6)
  void clearTransferredTo() => $_clearField(6);
}

class PointerFinality extends $pb.GeneratedMessage {
  factory PointerFinality({
    $core.String? address,
    $core.int? group,
    $core.int? answered,
    $core.String? status,
    $core.String? counter,
    PointerFinalState? state,
    $core.Iterable<PointerFinalState>? states,
    PointerFinalState? majority,
    $core.String? transferredTo,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (group != null) result.group = group;
    if (answered != null) result.answered = answered;
    if (status != null) result.status = status;
    if (counter != null) result.counter = counter;
    if (state != null) result.state = state;
    if (states != null) result.states.addAll(states);
    if (majority != null) result.majority = majority;
    if (transferredTo != null) result.transferredTo = transferredTo;
    return result;
  }

  PointerFinality._();

  factory PointerFinality.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerFinality.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerFinality', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'group', $pb.PbFieldType.OU3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'answered', $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'status')
    ..aOS(5, _omitFieldNames ? '' : 'counter')
    ..aOM<PointerFinalState>(6, _omitFieldNames ? '' : 'state', subBuilder: PointerFinalState.create)
    ..pc<PointerFinalState>(7, _omitFieldNames ? '' : 'states', $pb.PbFieldType.PM, subBuilder: PointerFinalState.create)
    ..aOM<PointerFinalState>(8, _omitFieldNames ? '' : 'majority', subBuilder: PointerFinalState.create)
    ..aOS(9, _omitFieldNames ? '' : 'transferredTo')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerFinality clone() => PointerFinality()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerFinality copyWith(void Function(PointerFinality) updates) => super.copyWith((message) => updates(message as PointerFinality)) as PointerFinality;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerFinality create() => PointerFinality._();
  @$core.override
  PointerFinality createEmptyInstance() => create();
  static $pb.PbList<PointerFinality> createRepeated() => $pb.PbList<PointerFinality>();
  @$core.pragma('dart2js:noInline')
  static PointerFinality getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerFinality>(create);
  static PointerFinality? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get group => $_getIZ(1);
  @$pb.TagNumber(2)
  set group($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGroup() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroup() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get answered => $_getIZ(2);
  @$pb.TagNumber(3)
  set answered($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAnswered() => $_has(2);
  @$pb.TagNumber(3)
  void clearAnswered() => $_clearField(3);

  /// "open", "settling", "unconfirmed", "final" or "forked". Only "final"
  /// means one final state, held by a majority, with no rival seen.
  @$pb.TagNumber(4)
  $core.String get status => $_getSZ(3);
  @$pb.TagNumber(4)
  set status($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);

  /// open: the counter a read would return; empty if none is corroborated.
  @$pb.TagNumber(5)
  $core.String get counter => $_getSZ(4);
  @$pb.TagNumber(5)
  set counter($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCounter() => $_has(4);
  @$pb.TagNumber(5)
  void clearCounter() => $_clearField(5);

  /// settling / unconfirmed / final: the one final state seen.
  @$pb.TagNumber(6)
  PointerFinalState get state => $_getN(5);
  @$pb.TagNumber(6)
  set state(PointerFinalState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasState() => $_has(5);
  @$pb.TagNumber(6)
  void clearState() => $_clearField(6);
  @$pb.TagNumber(6)
  PointerFinalState ensureState() => $_ensure(5);

  /// forked: every final state seen, most-held first.
  @$pb.TagNumber(7)
  $pb.PbList<PointerFinalState> get states => $_getList(6);

  /// forked: the state a majority holds, which reads return.
  @$pb.TagNumber(8)
  PointerFinalState get majority => $_getN(7);
  @$pb.TagNumber(8)
  set majority(PointerFinalState value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasMajority() => $_has(7);
  @$pb.TagNumber(8)
  void clearMajority() => $_clearField(8);
  @$pb.TagNumber(8)
  PointerFinalState ensureMajority() => $_ensure(7);

  /// Set once the pointer is beyond dispute handed over (status "final").
  @$pb.TagNumber(9)
  $core.String get transferredTo => $_getSZ(8);
  @$pb.TagNumber(9)
  set transferredTo($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTransferredTo() => $_has(8);
  @$pb.TagNumber(9)
  void clearTransferredTo() => $_clearField(9);
}

class PointerControllerRequest extends $pb.GeneratedMessage {
  factory PointerControllerRequest({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  PointerControllerRequest._();

  factory PointerControllerRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerControllerRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerControllerRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerControllerRequest clone() => PointerControllerRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerControllerRequest copyWith(void Function(PointerControllerRequest) updates) => super.copyWith((message) => updates(message as PointerControllerRequest)) as PointerControllerRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerControllerRequest create() => PointerControllerRequest._();
  @$core.override
  PointerControllerRequest createEmptyInstance() => create();
  static $pb.PbList<PointerControllerRequest> createRepeated() => $pb.PbList<PointerControllerRequest>();
  @$core.pragma('dart2js:noInline')
  static PointerControllerRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerControllerRequest>(create);
  static PointerControllerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class PointerController extends $pb.GeneratedMessage {
  factory PointerController({
    $core.String? pointer,
    $core.Iterable<$core.String>? transfers,
    $core.bool? frozen,
  }) {
    final result = create();
    if (pointer != null) result.pointer = pointer;
    if (transfers != null) result.transfers.addAll(transfers);
    if (frozen != null) result.frozen = frozen;
    return result;
  }

  PointerController._();

  factory PointerController.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PointerController.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PointerController', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'pointer')
    ..pPS(2, _omitFieldNames ? '' : 'transfers')
    ..aOB(3, _omitFieldNames ? '' : 'frozen')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerController clone() => PointerController()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerController copyWith(void Function(PointerController) updates) => super.copyWith((message) => updates(message as PointerController)) as PointerController;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerController create() => PointerController._();
  @$core.override
  PointerController createEmptyInstance() => create();
  static $pb.PbList<PointerController> createRepeated() => $pb.PbList<PointerController>();
  @$core.pragma('dart2js:noInline')
  static PointerController getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PointerController>(create);
  static PointerController? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pointer => $_getSZ(0);
  @$pb.TagNumber(1)
  set pointer($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPointer() => $_has(0);
  @$pb.TagNumber(1)
  void clearPointer() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get transfers => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get frozen => $_getBF(2);
  @$pb.TagNumber(3)
  set frozen($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFrozen() => $_has(2);
  @$pb.TagNumber(3)
  void clearFrozen() => $_clearField(3);
}

class PreparePointerRequest extends $pb.GeneratedMessage {
  factory PreparePointerRequest({
    $core.String? owner,
    $core.String? op,
    $core.String? target,
    $core.String? kind,
    $core.String? recipient,
    $core.bool? includeSignedQuotes,
  }) {
    final result = create();
    if (owner != null) result.owner = owner;
    if (op != null) result.op = op;
    if (target != null) result.target = target;
    if (kind != null) result.kind = kind;
    if (recipient != null) result.recipient = recipient;
    if (includeSignedQuotes != null) result.includeSignedQuotes = includeSignedQuotes;
    return result;
  }

  PreparePointerRequest._();

  factory PreparePointerRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PreparePointerRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PreparePointerRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'owner')
    ..aOS(2, _omitFieldNames ? '' : 'op')
    ..aOS(3, _omitFieldNames ? '' : 'target')
    ..aOS(4, _omitFieldNames ? '' : 'kind')
    ..aOS(5, _omitFieldNames ? '' : 'recipient')
    ..aOB(6, _omitFieldNames ? '' : 'includeSignedQuotes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreparePointerRequest clone() => PreparePointerRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreparePointerRequest copyWith(void Function(PreparePointerRequest) updates) => super.copyWith((message) => updates(message as PreparePointerRequest)) as PreparePointerRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PreparePointerRequest create() => PreparePointerRequest._();
  @$core.override
  PreparePointerRequest createEmptyInstance() => create();
  static $pb.PbList<PreparePointerRequest> createRepeated() => $pb.PbList<PreparePointerRequest>();
  @$core.pragma('dart2js:noInline')
  static PreparePointerRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreparePointerRequest>(create);
  static PreparePointerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get owner => $_getSZ(0);
  @$pb.TagNumber(1)
  set owner($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOwner() => $_has(0);
  @$pb.TagNumber(1)
  void clearOwner() => $_clearField(1);

  /// "create", "update" or "transfer".
  @$pb.TagNumber(2)
  $core.String get op => $_getSZ(1);
  @$pb.TagNumber(2)
  set op($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOp() => $_has(1);
  @$pb.TagNumber(2)
  void clearOp() => $_clearField(2);

  /// create / update.
  @$pb.TagNumber(3)
  $core.String get target => $_getSZ(2);
  @$pb.TagNumber(3)
  set target($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTarget() => $_has(2);
  @$pb.TagNumber(3)
  void clearTarget() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get kind => $_getSZ(3);
  @$pb.TagNumber(4)
  set kind($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  /// transfer.
  @$pb.TagNumber(5)
  $core.String get recipient => $_getSZ(4);
  @$pb.TagNumber(5)
  set recipient($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecipient() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecipient() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeSignedQuotes => $_getBF(5);
  @$pb.TagNumber(6)
  set includeSignedQuotes($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeSignedQuotes() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeSignedQuotes() => $_clearField(6);
}

class PreparePointerResponse extends $pb.GeneratedMessage {
  factory PreparePointerResponse({
    $core.String? uploadId,
    $core.String? op,
    $core.String? address,
    $core.String? stateId,
    $core.String? counter,
    $core.String? paymentType,
    $core.Iterable<$2.PaymentEntry>? payments,
    $core.String? totalAmount,
    $core.String? paymentVaultAddress,
    $core.String? paymentTokenAddress,
    $core.String? rpcUrl,
    $core.Iterable<$2.SignedQuoteEntry>? signedQuotes,
  }) {
    final result = create();
    if (uploadId != null) result.uploadId = uploadId;
    if (op != null) result.op = op;
    if (address != null) result.address = address;
    if (stateId != null) result.stateId = stateId;
    if (counter != null) result.counter = counter;
    if (paymentType != null) result.paymentType = paymentType;
    if (payments != null) result.payments.addAll(payments);
    if (totalAmount != null) result.totalAmount = totalAmount;
    if (paymentVaultAddress != null) result.paymentVaultAddress = paymentVaultAddress;
    if (paymentTokenAddress != null) result.paymentTokenAddress = paymentTokenAddress;
    if (rpcUrl != null) result.rpcUrl = rpcUrl;
    if (signedQuotes != null) result.signedQuotes.addAll(signedQuotes);
    return result;
  }

  PreparePointerResponse._();

  factory PreparePointerResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory PreparePointerResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PreparePointerResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uploadId')
    ..aOS(2, _omitFieldNames ? '' : 'op')
    ..aOS(3, _omitFieldNames ? '' : 'address')
    ..aOS(4, _omitFieldNames ? '' : 'stateId')
    ..aOS(5, _omitFieldNames ? '' : 'counter')
    ..aOS(6, _omitFieldNames ? '' : 'paymentType')
    ..pc<$2.PaymentEntry>(7, _omitFieldNames ? '' : 'payments', $pb.PbFieldType.PM, subBuilder: $2.PaymentEntry.create)
    ..aOS(8, _omitFieldNames ? '' : 'totalAmount')
    ..aOS(9, _omitFieldNames ? '' : 'paymentVaultAddress')
    ..aOS(10, _omitFieldNames ? '' : 'paymentTokenAddress')
    ..aOS(11, _omitFieldNames ? '' : 'rpcUrl')
    ..pc<$2.SignedQuoteEntry>(12, _omitFieldNames ? '' : 'signedQuotes', $pb.PbFieldType.PM, subBuilder: $2.SignedQuoteEntry.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreparePointerResponse clone() => PreparePointerResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreparePointerResponse copyWith(void Function(PreparePointerResponse) updates) => super.copyWith((message) => updates(message as PreparePointerResponse)) as PreparePointerResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PreparePointerResponse create() => PreparePointerResponse._();
  @$core.override
  PreparePointerResponse createEmptyInstance() => create();
  static $pb.PbList<PreparePointerResponse> createRepeated() => $pb.PbList<PreparePointerResponse>();
  @$core.pragma('dart2js:noInline')
  static PreparePointerResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreparePointerResponse>(create);
  static PreparePointerResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get uploadId => $_getSZ(0);
  @$pb.TagNumber(1)
  set uploadId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUploadId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUploadId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get op => $_getSZ(1);
  @$pb.TagNumber(2)
  set op($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOp() => $_has(1);
  @$pb.TagNumber(2)
  void clearOp() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get address => $_getSZ(2);
  @$pb.TagNumber(3)
  set address($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get stateId => $_getSZ(3);
  @$pb.TagNumber(4)
  set stateId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStateId() => $_has(3);
  @$pb.TagNumber(4)
  void clearStateId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get counter => $_getSZ(4);
  @$pb.TagNumber(5)
  set counter($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCounter() => $_has(4);
  @$pb.TagNumber(5)
  void clearCounter() => $_clearField(5);

  /// Always "wave_batch".
  @$pb.TagNumber(6)
  $core.String get paymentType => $_getSZ(5);
  @$pb.TagNumber(6)
  set paymentType($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPaymentType() => $_has(5);
  @$pb.TagNumber(6)
  void clearPaymentType() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<$2.PaymentEntry> get payments => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get totalAmount => $_getSZ(7);
  @$pb.TagNumber(8)
  set totalAmount($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTotalAmount() => $_has(7);
  @$pb.TagNumber(8)
  void clearTotalAmount() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get paymentVaultAddress => $_getSZ(8);
  @$pb.TagNumber(9)
  set paymentVaultAddress($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPaymentVaultAddress() => $_has(8);
  @$pb.TagNumber(9)
  void clearPaymentVaultAddress() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get paymentTokenAddress => $_getSZ(9);
  @$pb.TagNumber(10)
  set paymentTokenAddress($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasPaymentTokenAddress() => $_has(9);
  @$pb.TagNumber(10)
  void clearPaymentTokenAddress() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get rpcUrl => $_getSZ(10);
  @$pb.TagNumber(11)
  set rpcUrl($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasRpcUrl() => $_has(10);
  @$pb.TagNumber(11)
  void clearRpcUrl() => $_clearField(11);

  @$pb.TagNumber(12)
  $pb.PbList<$2.SignedQuoteEntry> get signedQuotes => $_getList(11);
}

class FinalizePointerRequest extends $pb.GeneratedMessage {
  factory FinalizePointerRequest({
    $core.String? uploadId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? txHashes,
  }) {
    final result = create();
    if (uploadId != null) result.uploadId = uploadId;
    if (txHashes != null) result.txHashes.addEntries(txHashes);
    return result;
  }

  FinalizePointerRequest._();

  factory FinalizePointerRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FinalizePointerRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FinalizePointerRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uploadId')
    ..m<$core.String, $core.String>(2, _omitFieldNames ? '' : 'txHashes', entryClassName: 'FinalizePointerRequest.TxHashesEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('antd.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizePointerRequest clone() => FinalizePointerRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizePointerRequest copyWith(void Function(FinalizePointerRequest) updates) => super.copyWith((message) => updates(message as FinalizePointerRequest)) as FinalizePointerRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizePointerRequest create() => FinalizePointerRequest._();
  @$core.override
  FinalizePointerRequest createEmptyInstance() => create();
  static $pb.PbList<FinalizePointerRequest> createRepeated() => $pb.PbList<FinalizePointerRequest>();
  @$core.pragma('dart2js:noInline')
  static FinalizePointerRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FinalizePointerRequest>(create);
  static FinalizePointerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get uploadId => $_getSZ(0);
  @$pb.TagNumber(1)
  set uploadId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUploadId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUploadId() => $_clearField(1);

  /// quote_hash (hex) → tx_hash (hex). Ignored when repeating a finalize
  /// that failed after payment.
  @$pb.TagNumber(2)
  $pb.PbMap<$core.String, $core.String> get txHashes => $_getMap(1);
}

class FinalizePointerResponse extends $pb.GeneratedMessage {
  factory FinalizePointerResponse({
    $core.String? address,
    $core.String? stateId,
    $core.String? counter,
    PointerFinality? finality,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (stateId != null) result.stateId = stateId;
    if (counter != null) result.counter = counter;
    if (finality != null) result.finality = finality;
    return result;
  }

  FinalizePointerResponse._();

  factory FinalizePointerResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory FinalizePointerResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FinalizePointerResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'stateId')
    ..aOS(3, _omitFieldNames ? '' : 'counter')
    ..aOM<PointerFinality>(4, _omitFieldNames ? '' : 'finality', subBuilder: PointerFinality.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizePointerResponse clone() => FinalizePointerResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizePointerResponse copyWith(void Function(FinalizePointerResponse) updates) => super.copyWith((message) => updates(message as FinalizePointerResponse)) as FinalizePointerResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizePointerResponse create() => FinalizePointerResponse._();
  @$core.override
  FinalizePointerResponse createEmptyInstance() => create();
  static $pb.PbList<FinalizePointerResponse> createRepeated() => $pb.PbList<FinalizePointerResponse>();
  @$core.pragma('dart2js:noInline')
  static FinalizePointerResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FinalizePointerResponse>(create);
  static FinalizePointerResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stateId => $_getSZ(1);
  @$pb.TagNumber(2)
  set stateId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStateId() => $_has(1);
  @$pb.TagNumber(2)
  void clearStateId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get counter => $_getSZ(2);
  @$pb.TagNumber(3)
  set counter($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCounter() => $_has(2);
  @$pb.TagNumber(3)
  void clearCounter() => $_clearField(3);

  /// transfer only.
  @$pb.TagNumber(4)
  PointerFinality get finality => $_getN(3);
  @$pb.TagNumber(4)
  set finality(PointerFinality value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFinality() => $_has(3);
  @$pb.TagNumber(4)
  void clearFinality() => $_clearField(4);
  @$pb.TagNumber(4)
  PointerFinality ensureFinality() => $_ensure(3);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
