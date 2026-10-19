//
//  Generated code. Do not modify.
//  source: antd/v1/manifests.proto
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

enum ManifestEntryInput_Source {
  dataMap, 
  address, 
  notSet
}

/// One file. Exactly one of `data_map` or `address`.
class ManifestEntryInput extends $pb.GeneratedMessage {
  factory ManifestEntryInput({
    $core.String? path,
    $fixnum.Int64? size,
    $core.String? dataMap,
    $core.String? address,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (size != null) result.size = size;
    if (dataMap != null) result.dataMap = dataMap;
    if (address != null) result.address = address;
    return result;
  }

  ManifestEntryInput._();

  factory ManifestEntryInput.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory ManifestEntryInput.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ManifestEntryInput_Source> _ManifestEntryInput_SourceByTag = {
    3 : ManifestEntryInput_Source.dataMap,
    4 : ManifestEntryInput_Source.address,
    0 : ManifestEntryInput_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ManifestEntryInput', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..oo(0, [3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'dataMap')
    ..aOS(4, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ManifestEntryInput clone() => ManifestEntryInput()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ManifestEntryInput copyWith(void Function(ManifestEntryInput) updates) => super.copyWith((message) => updates(message as ManifestEntryInput)) as ManifestEntryInput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ManifestEntryInput create() => ManifestEntryInput._();
  @$core.override
  ManifestEntryInput createEmptyInstance() => create();
  static $pb.PbList<ManifestEntryInput> createRepeated() => $pb.PbList<ManifestEntryInput>();
  @$core.pragma('dart2js:noInline')
  static ManifestEntryInput getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ManifestEntryInput>(create);
  static ManifestEntryInput? _defaultInstance;

  ManifestEntryInput_Source whichSource() => _ManifestEntryInput_SourceByTag[$_whichOneof(0)]!;
  void clearSource() => $_clearField($_whichOneof(0));

  /// Relative path, subject to the portable path rules. Unset or empty: the
  /// entry extracts under its content address.
  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  /// Plaintext size to record, as given (the creator's claim). Unset: none is
  /// recorded; readers take the exact size from an embedded root DataMap.
  @$pb.TagNumber(2)
  $fixnum.Int64 get size => $_getI64(1);
  @$pb.TagNumber(2)
  set size($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearSize() => $_clearField(2);

  /// Hex DataMap, in the form the upload routes return. Embedded.
  @$pb.TagNumber(3)
  $core.String get dataMap => $_getSZ(2);
  @$pb.TagNumber(3)
  set dataMap($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDataMap() => $_has(2);
  @$pb.TagNumber(3)
  void clearDataMap() => $_clearField(3);

  /// Hex address (32 bytes) of a public file's DataMap.
  @$pb.TagNumber(4)
  $core.String get address => $_getSZ(3);
  @$pb.TagNumber(4)
  set address($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAddress() => $_has(3);
  @$pb.TagNumber(4)
  void clearAddress() => $_clearField(4);
}

class BuildManifestRequest extends $pb.GeneratedMessage {
  factory BuildManifestRequest({
    $core.String? name,
    $core.Iterable<$core.String>? torrentInfoHashes,
    $core.bool? embedRoots,
    $core.Iterable<ManifestEntryInput>? entries,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (torrentInfoHashes != null) result.torrentInfoHashes.addAll(torrentInfoHashes);
    if (embedRoots != null) result.embedRoots = embedRoots;
    if (entries != null) result.entries.addAll(entries);
    return result;
  }

  BuildManifestRequest._();

  factory BuildManifestRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory BuildManifestRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BuildManifestRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pPS(2, _omitFieldNames ? '' : 'torrentInfoHashes')
    ..aOB(3, _omitFieldNames ? '' : 'embedRoots')
    ..pc<ManifestEntryInput>(4, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: ManifestEntryInput.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildManifestRequest clone() => BuildManifestRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildManifestRequest copyWith(void Function(BuildManifestRequest) updates) => super.copyWith((message) => updates(message as BuildManifestRequest)) as BuildManifestRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BuildManifestRequest create() => BuildManifestRequest._();
  @$core.override
  BuildManifestRequest createEmptyInstance() => create();
  static $pb.PbList<BuildManifestRequest> createRepeated() => $pb.PbList<BuildManifestRequest>();
  @$core.pragma('dart2js:noInline')
  static BuildManifestRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BuildManifestRequest>(create);
  static BuildManifestRequest? _defaultInstance;

  /// Suggested root directory name (one portable path component).
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// BitTorrent info hashes of the same files: hex, 40 characters for v1
  /// and/or 64 for v2.
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get torrentInfoHashes => $_getList(1);

  /// Resolve shrunk DataMaps and embed the root when it is at most 64 KiB as
  /// written (ADR-0006's policy); fetches wrapper records. Unset: true.
  @$pb.TagNumber(3)
  $core.bool get embedRoots => $_getBF(2);
  @$pb.TagNumber(3)
  set embedRoots($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmbedRoots() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmbedRoots() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<ManifestEntryInput> get entries => $_getList(3);
}

/// What a manifest says about one entry.
class ManifestEntryInfo extends $pb.GeneratedMessage {
  factory ManifestEntryInfo({
    $core.String? effectiveName,
    $core.String? path,
    $fixnum.Int64? size,
    $core.String? kind,
    $core.String? contentAddress,
    $core.String? dataMap,
    $fixnum.Int64? exactSize,
    $core.String? error,
  }) {
    final result = create();
    if (effectiveName != null) result.effectiveName = effectiveName;
    if (path != null) result.path = path;
    if (size != null) result.size = size;
    if (kind != null) result.kind = kind;
    if (contentAddress != null) result.contentAddress = contentAddress;
    if (dataMap != null) result.dataMap = dataMap;
    if (exactSize != null) result.exactSize = exactSize;
    if (error != null) result.error = error;
    return result;
  }

  ManifestEntryInfo._();

  factory ManifestEntryInfo.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory ManifestEntryInfo.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ManifestEntryInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'effectiveName')
    ..aOS(2, _omitFieldNames ? '' : 'path')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'kind')
    ..aOS(5, _omitFieldNames ? '' : 'contentAddress')
    ..aOS(6, _omitFieldNames ? '' : 'dataMap')
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'exactSize', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(8, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ManifestEntryInfo clone() => ManifestEntryInfo()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ManifestEntryInfo copyWith(void Function(ManifestEntryInfo) updates) => super.copyWith((message) => updates(message as ManifestEntryInfo)) as ManifestEntryInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ManifestEntryInfo create() => ManifestEntryInfo._();
  @$core.override
  ManifestEntryInfo createEmptyInstance() => create();
  static $pb.PbList<ManifestEntryInfo> createRepeated() => $pb.PbList<ManifestEntryInfo>();
  @$core.pragma('dart2js:noInline')
  static ManifestEntryInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ManifestEntryInfo>(create);
  static ManifestEntryInfo? _defaultInstance;

  /// `path`, or the content address in hex when there is none.
  @$pb.TagNumber(1)
  $core.String get effectiveName => $_getSZ(0);
  @$pb.TagNumber(1)
  set effectiveName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEffectiveName() => $_has(0);
  @$pb.TagNumber(1)
  void clearEffectiveName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get path => $_getSZ(1);
  @$pb.TagNumber(2)
  set path($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearPath() => $_clearField(2);

  /// The size recorded in the manifest: the creator's claim.
  @$pb.TagNumber(3)
  $fixnum.Int64 get size => $_getI64(2);
  @$pb.TagNumber(3)
  set size($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  /// "embedded" or "public".
  @$pb.TagNumber(4)
  $core.String get kind => $_getSZ(3);
  @$pb.TagNumber(4)
  set kind($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  /// Hex. The file's public DataMap address, whether or not it was ever made
  /// public; the same for private and public uploads of one file.
  @$pb.TagNumber(5)
  $core.String get contentAddress => $_getSZ(4);
  @$pb.TagNumber(5)
  set contentAddress($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasContentAddress() => $_has(4);
  @$pb.TagNumber(5)
  void clearContentAddress() => $_clearField(5);

  /// The embedded DataMap in the hex form the download routes accept.
  /// Decode only; empty for public entries.
  @$pb.TagNumber(6)
  $core.String get dataMap => $_getSZ(5);
  @$pb.TagNumber(6)
  set dataMap($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDataMap() => $_has(5);
  @$pb.TagNumber(6)
  void clearDataMap() => $_clearField(6);

  /// Exact plaintext size: from an embedded root DataMap, or after `resolve`.
  @$pb.TagNumber(7)
  $fixnum.Int64 get exactSize => $_getI64(6);
  @$pb.TagNumber(7)
  set exactSize($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExactSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearExactSize() => $_clearField(7);

  /// Why `resolve` failed for this entry. Empty when it didn't.
  @$pb.TagNumber(8)
  $core.String get error => $_getSZ(7);
  @$pb.TagNumber(8)
  set error($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasError() => $_has(7);
  @$pb.TagNumber(8)
  void clearError() => $_clearField(8);
}

class BuildManifestResponse extends $pb.GeneratedMessage {
  factory BuildManifestResponse({
    $core.List<$core.int>? manifest,
    $core.String? link,
    $core.Iterable<ManifestEntryInfo>? entries,
  }) {
    final result = create();
    if (manifest != null) result.manifest = manifest;
    if (link != null) result.link = link;
    if (entries != null) result.entries.addAll(entries);
    return result;
  }

  BuildManifestResponse._();

  factory BuildManifestResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory BuildManifestResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BuildManifestResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'manifest', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'link')
    ..pc<ManifestEntryInfo>(3, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: ManifestEntryInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildManifestResponse clone() => BuildManifestResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildManifestResponse copyWith(void Function(BuildManifestResponse) updates) => super.copyWith((message) => updates(message as BuildManifestResponse)) as BuildManifestResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BuildManifestResponse create() => BuildManifestResponse._();
  @$core.override
  BuildManifestResponse createEmptyInstance() => create();
  static $pb.PbList<BuildManifestResponse> createRepeated() => $pb.PbList<BuildManifestResponse>();
  @$core.pragma('dart2js:noInline')
  static BuildManifestResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BuildManifestResponse>(create);
  static BuildManifestResponse? _defaultInstance;

  /// The `.ant` bytes.
  @$pb.TagNumber(1)
  $core.List<$core.int> get manifest => $_getN(0);
  @$pb.TagNumber(1)
  set manifest($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasManifest() => $_has(0);
  @$pb.TagNumber(1)
  void clearManifest() => $_clearField(1);

  /// The `ant://manifest/` link, only when it fits the recommended 1,500
  /// bytes. Empty otherwise.
  @$pb.TagNumber(2)
  $core.String get link => $_getSZ(1);
  @$pb.TagNumber(2)
  set link($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLink() => $_has(1);
  @$pb.TagNumber(2)
  void clearLink() => $_clearField(2);

  /// In encoded order (sorted by effective name).
  @$pb.TagNumber(3)
  $pb.PbList<ManifestEntryInfo> get entries => $_getList(2);
}

enum DecodeManifestRequest_Input {
  manifest, 
  link, 
  notSet
}

class DecodeManifestRequest extends $pb.GeneratedMessage {
  factory DecodeManifestRequest({
    $core.List<$core.int>? manifest,
    $core.String? link,
    $core.bool? resolve,
  }) {
    final result = create();
    if (manifest != null) result.manifest = manifest;
    if (link != null) result.link = link;
    if (resolve != null) result.resolve = resolve;
    return result;
  }

  DecodeManifestRequest._();

  factory DecodeManifestRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory DecodeManifestRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DecodeManifestRequest_Input> _DecodeManifestRequest_InputByTag = {
    1 : DecodeManifestRequest_Input.manifest,
    2 : DecodeManifestRequest_Input.link,
    0 : DecodeManifestRequest_Input.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DecodeManifestRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'manifest', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'link')
    ..aOB(3, _omitFieldNames ? '' : 'resolve')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeManifestRequest clone() => DecodeManifestRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeManifestRequest copyWith(void Function(DecodeManifestRequest) updates) => super.copyWith((message) => updates(message as DecodeManifestRequest)) as DecodeManifestRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DecodeManifestRequest create() => DecodeManifestRequest._();
  @$core.override
  DecodeManifestRequest createEmptyInstance() => create();
  static $pb.PbList<DecodeManifestRequest> createRepeated() => $pb.PbList<DecodeManifestRequest>();
  @$core.pragma('dart2js:noInline')
  static DecodeManifestRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DecodeManifestRequest>(create);
  static DecodeManifestRequest? _defaultInstance;

  DecodeManifestRequest_Input whichInput() => _DecodeManifestRequest_InputByTag[$_whichOneof(0)]!;
  void clearInput() => $_clearField($_whichOneof(0));

  /// `.ant` bytes.
  @$pb.TagNumber(1)
  $core.List<$core.int> get manifest => $_getN(0);
  @$pb.TagNumber(1)
  set manifest($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasManifest() => $_has(0);
  @$pb.TagNumber(1)
  void clearManifest() => $_clearField(1);

  /// An `ant://` manifest link, file link, or bare 64-hex address.
  @$pb.TagNumber(2)
  $core.String get link => $_getSZ(1);
  @$pb.TagNumber(2)
  set link($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLink() => $_has(1);
  @$pb.TagNumber(2)
  void clearLink() => $_clearField(2);

  /// Fetch each entry's DataMap (and wrapper records) to report exact sizes
  /// and confirm the DataMap is on the network. Content chunks are not
  /// fetched. One entry's failure is reported in its `error`, not as a
  /// failed call.
  @$pb.TagNumber(3)
  $core.bool get resolve => $_getBF(2);
  @$pb.TagNumber(3)
  set resolve($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResolve() => $_has(2);
  @$pb.TagNumber(3)
  void clearResolve() => $_clearField(3);
}

class DecodeManifestResponse extends $pb.GeneratedMessage {
  factory DecodeManifestResponse({
    $core.String? source,
    $core.String? name,
    $core.String? torrentInfoHashV1,
    $core.String? torrentInfoHashV2,
    $core.Iterable<ManifestEntryInfo>? entries,
  }) {
    final result = create();
    if (source != null) result.source = source;
    if (name != null) result.name = name;
    if (torrentInfoHashV1 != null) result.torrentInfoHashV1 = torrentInfoHashV1;
    if (torrentInfoHashV2 != null) result.torrentInfoHashV2 = torrentInfoHashV2;
    if (entries != null) result.entries.addAll(entries);
    return result;
  }

  DecodeManifestResponse._();

  factory DecodeManifestResponse.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory DecodeManifestResponse.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DecodeManifestResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'torrentInfoHashV1')
    ..aOS(4, _omitFieldNames ? '' : 'torrentInfoHashV2')
    ..pc<ManifestEntryInfo>(5, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: ManifestEntryInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeManifestResponse clone() => DecodeManifestResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeManifestResponse copyWith(void Function(DecodeManifestResponse) updates) => super.copyWith((message) => updates(message as DecodeManifestResponse)) as DecodeManifestResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DecodeManifestResponse create() => DecodeManifestResponse._();
  @$core.override
  DecodeManifestResponse createEmptyInstance() => create();
  static $pb.PbList<DecodeManifestResponse> createRepeated() => $pb.PbList<DecodeManifestResponse>();
  @$core.pragma('dart2js:noInline')
  static DecodeManifestResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DecodeManifestResponse>(create);
  static DecodeManifestResponse? _defaultInstance;

  /// "manifest", or "file_link" for a file link or bare address (reported as
  /// one public entry with no path).
  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// Hex; empty when absent.
  @$pb.TagNumber(3)
  $core.String get torrentInfoHashV1 => $_getSZ(2);
  @$pb.TagNumber(3)
  set torrentInfoHashV1($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTorrentInfoHashV1() => $_has(2);
  @$pb.TagNumber(3)
  void clearTorrentInfoHashV1() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get torrentInfoHashV2 => $_getSZ(3);
  @$pb.TagNumber(4)
  set torrentInfoHashV2($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTorrentInfoHashV2() => $_has(3);
  @$pb.TagNumber(4)
  void clearTorrentInfoHashV2() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<ManifestEntryInfo> get entries => $_getList(4);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
