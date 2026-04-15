// This is a generated file - do not edit.
//
// Generated from antd/v1/files.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use uploadFileRequestDescriptor instead')
const UploadFileRequest$json = {
  '1': 'UploadFileRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `UploadFileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadFileRequestDescriptor = $convert
    .base64Decode('ChFVcGxvYWRGaWxlUmVxdWVzdBISCgRwYXRoGAEgASgJUgRwYXRo');

@$core.Deprecated('Use uploadPublicResponseDescriptor instead')
const UploadPublicResponse$json = {
  '1': 'UploadPublicResponse',
  '2': [
    {'1': 'address', '3': 2, '4': 1, '5': 9, '10': 'address'},
    {'1': 'storage_cost_atto', '3': 3, '4': 1, '5': 9, '10': 'storageCostAtto'},
    {'1': 'gas_cost_wei', '3': 4, '4': 1, '5': 9, '10': 'gasCostWei'},
    {'1': 'chunks_stored', '3': 5, '4': 1, '5': 4, '10': 'chunksStored'},
    {'1': 'payment_mode_used', '3': 6, '4': 1, '5': 9, '10': 'paymentModeUsed'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
  '10': ['cost'],
};

/// Descriptor for `UploadPublicResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadPublicResponseDescriptor = $convert.base64Decode(
    'ChRVcGxvYWRQdWJsaWNSZXNwb25zZRIYCgdhZGRyZXNzGAIgASgJUgdhZGRyZXNzEioKEXN0b3'
    'JhZ2VfY29zdF9hdHRvGAMgASgJUg9zdG9yYWdlQ29zdEF0dG8SIAoMZ2FzX2Nvc3Rfd2VpGAQg'
    'ASgJUgpnYXNDb3N0V2VpEiMKDWNodW5rc19zdG9yZWQYBSABKARSDGNodW5rc1N0b3JlZBIqCh'
    'FwYXltZW50X21vZGVfdXNlZBgGIAEoCVIPcGF5bWVudE1vZGVVc2VkSgQIARACUgRjb3N0');

@$core.Deprecated('Use downloadPublicRequestDescriptor instead')
const DownloadPublicRequest$json = {
  '1': 'DownloadPublicRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'dest_path', '3': 2, '4': 1, '5': 9, '10': 'destPath'},
  ],
};

/// Descriptor for `DownloadPublicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadPublicRequestDescriptor = $convert.base64Decode(
    'ChVEb3dubG9hZFB1YmxpY1JlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcxIbCglkZX'
    'N0X3BhdGgYAiABKAlSCGRlc3RQYXRo');

@$core.Deprecated('Use downloadResponseDescriptor instead')
const DownloadResponse$json = {
  '1': 'DownloadResponse',
};

/// Descriptor for `DownloadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadResponseDescriptor =
    $convert.base64Decode('ChBEb3dubG9hZFJlc3BvbnNl');

@$core.Deprecated('Use fileCostRequestDescriptor instead')
const FileCostRequest$json = {
  '1': 'FileCostRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'is_public', '3': 2, '4': 1, '5': 8, '10': 'isPublic'},
  ],
};

/// Descriptor for `FileCostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileCostRequestDescriptor = $convert.base64Decode(
    'Cg9GaWxlQ29zdFJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aBIbCglpc19wdWJsaWMYAiABKA'
    'hSCGlzUHVibGlj');
