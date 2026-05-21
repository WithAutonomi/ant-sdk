//
//  Generated code. Do not modify.
//  source: antd/v1/events.proto
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

class SubscribeRequest extends $pb.GeneratedMessage {
  factory SubscribeRequest() => create();

  SubscribeRequest._();

  factory SubscribeRequest.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory SubscribeRequest.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SubscribeRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeRequest clone() => SubscribeRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeRequest copyWith(void Function(SubscribeRequest) updates) => super.copyWith((message) => updates(message as SubscribeRequest)) as SubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SubscribeRequest create() => SubscribeRequest._();
  @$core.override
  SubscribeRequest createEmptyInstance() => create();
  static $pb.PbList<SubscribeRequest> createRepeated() => $pb.PbList<SubscribeRequest>();
  @$core.pragma('dart2js:noInline')
  static SubscribeRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SubscribeRequest>(create);
  static SubscribeRequest? _defaultInstance;
}

class ClientEventProto extends $pb.GeneratedMessage {
  factory ClientEventProto({
    $core.String? kind,
    $fixnum.Int64? recordsPaid,
    $fixnum.Int64? recordsAlreadyPaid,
    $core.String? tokensSpent,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (recordsPaid != null) result.recordsPaid = recordsPaid;
    if (recordsAlreadyPaid != null) result.recordsAlreadyPaid = recordsAlreadyPaid;
    if (tokensSpent != null) result.tokensSpent = tokensSpent;
    return result;
  }

  ClientEventProto._();

  factory ClientEventProto.fromBuffer($core.List<$core.int> data, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(data, registry);
  factory ClientEventProto.fromJson($core.String json, [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClientEventProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'antd.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'kind')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'recordsPaid', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'recordsAlreadyPaid', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'tokensSpent')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientEventProto clone() => ClientEventProto()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientEventProto copyWith(void Function(ClientEventProto) updates) => super.copyWith((message) => updates(message as ClientEventProto)) as ClientEventProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClientEventProto create() => ClientEventProto._();
  @$core.override
  ClientEventProto createEmptyInstance() => create();
  static $pb.PbList<ClientEventProto> createRepeated() => $pb.PbList<ClientEventProto>();
  @$core.pragma('dart2js:noInline')
  static ClientEventProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClientEventProto>(create);
  static ClientEventProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get kind => $_getSZ(0);
  @$pb.TagNumber(1)
  set kind($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get recordsPaid => $_getI64(1);
  @$pb.TagNumber(2)
  set recordsPaid($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRecordsPaid() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecordsPaid() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get recordsAlreadyPaid => $_getI64(2);
  @$pb.TagNumber(3)
  set recordsAlreadyPaid($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRecordsAlreadyPaid() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecordsAlreadyPaid() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get tokensSpent => $_getSZ(3);
  @$pb.TagNumber(4)
  set tokensSpent($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTokensSpent() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensSpent() => $_clearField(4);
}


const $core.bool _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
