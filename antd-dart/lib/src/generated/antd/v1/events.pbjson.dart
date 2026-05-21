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

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use subscribeRequestDescriptor instead')
const SubscribeRequest$json = {
  '1': 'SubscribeRequest',
};

/// Descriptor for `SubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subscribeRequestDescriptor = $convert.base64Decode(
    'ChBTdWJzY3JpYmVSZXF1ZXN0');

@$core.Deprecated('Use clientEventProtoDescriptor instead')
const ClientEventProto$json = {
  '1': 'ClientEventProto',
  '2': [
    {'1': 'kind', '3': 1, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'records_paid', '3': 2, '4': 1, '5': 4, '10': 'recordsPaid'},
    {'1': 'records_already_paid', '3': 3, '4': 1, '5': 4, '10': 'recordsAlreadyPaid'},
    {'1': 'tokens_spent', '3': 4, '4': 1, '5': 9, '10': 'tokensSpent'},
  ],
};

/// Descriptor for `ClientEventProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientEventProtoDescriptor = $convert.base64Decode(
    'ChBDbGllbnRFdmVudFByb3RvEhIKBGtpbmQYASABKAlSBGtpbmQSIQoMcmVjb3Jkc19wYWlkGA'
    'IgASgEUgtyZWNvcmRzUGFpZBIwChRyZWNvcmRzX2FscmVhZHlfcGFpZBgDIAEoBFIScmVjb3Jk'
    'c0FscmVhZHlQYWlkEiEKDHRva2Vuc19zcGVudBgEIAEoCVILdG9rZW5zU3BlbnQ=');

