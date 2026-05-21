//
//  Generated code. Do not modify.
//  source: antd/v1/files.proto
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

@$core.Deprecated('Use putFileRequestDescriptor instead')
const PutFileRequest$json = {
  '1': 'PutFileRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'payment_mode', '3': 2, '4': 1, '5': 9, '10': 'paymentMode'},
  ],
};

/// Descriptor for `PutFileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putFileRequestDescriptor = $convert.base64Decode(
    'Cg5QdXRGaWxlUmVxdWVzdBISCgRwYXRoGAEgASgJUgRwYXRoEiEKDHBheW1lbnRfbW9kZRgCIA'
    'EoCVILcGF5bWVudE1vZGU=');

@$core.Deprecated('Use putFilePublicResponseDescriptor instead')
const PutFilePublicResponse$json = {
  '1': 'PutFilePublicResponse',
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

/// Descriptor for `PutFilePublicResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putFilePublicResponseDescriptor = $convert.base64Decode(
    'ChVQdXRGaWxlUHVibGljUmVzcG9uc2USGAoHYWRkcmVzcxgCIAEoCVIHYWRkcmVzcxIqChFzdG'
    '9yYWdlX2Nvc3RfYXR0bxgDIAEoCVIPc3RvcmFnZUNvc3RBdHRvEiAKDGdhc19jb3N0X3dlaRgE'
    'IAEoCVIKZ2FzQ29zdFdlaRIjCg1jaHVua3Nfc3RvcmVkGAUgASgEUgxjaHVua3NTdG9yZWQSKg'
    'oRcGF5bWVudF9tb2RlX3VzZWQYBiABKAlSD3BheW1lbnRNb2RlVXNlZEoECAEQAlIEY29zdA==');

@$core.Deprecated('Use putFileResponseDescriptor instead')
const PutFileResponse$json = {
  '1': 'PutFileResponse',
  '2': [
    {'1': 'data_map', '3': 1, '4': 1, '5': 9, '10': 'dataMap'},
    {'1': 'storage_cost_atto', '3': 2, '4': 1, '5': 9, '10': 'storageCostAtto'},
    {'1': 'gas_cost_wei', '3': 3, '4': 1, '5': 9, '10': 'gasCostWei'},
    {'1': 'chunks_stored', '3': 4, '4': 1, '5': 4, '10': 'chunksStored'},
    {'1': 'payment_mode_used', '3': 5, '4': 1, '5': 9, '10': 'paymentModeUsed'},
  ],
};

/// Descriptor for `PutFileResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putFileResponseDescriptor = $convert.base64Decode(
    'Cg9QdXRGaWxlUmVzcG9uc2USGQoIZGF0YV9tYXAYASABKAlSB2RhdGFNYXASKgoRc3RvcmFnZV'
    '9jb3N0X2F0dG8YAiABKAlSD3N0b3JhZ2VDb3N0QXR0bxIgCgxnYXNfY29zdF93ZWkYAyABKAlS'
    'Cmdhc0Nvc3RXZWkSIwoNY2h1bmtzX3N0b3JlZBgEIAEoBFIMY2h1bmtzU3RvcmVkEioKEXBheW'
    '1lbnRfbW9kZV91c2VkGAUgASgJUg9wYXltZW50TW9kZVVzZWQ=');

@$core.Deprecated('Use getFilePublicRequestDescriptor instead')
const GetFilePublicRequest$json = {
  '1': 'GetFilePublicRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'dest_path', '3': 2, '4': 1, '5': 9, '10': 'destPath'},
  ],
};

/// Descriptor for `GetFilePublicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFilePublicRequestDescriptor = $convert.base64Decode(
    'ChRHZXRGaWxlUHVibGljUmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEhsKCWRlc3'
    'RfcGF0aBgCIAEoCVIIZGVzdFBhdGg=');

@$core.Deprecated('Use getFileRequestDescriptor instead')
const GetFileRequest$json = {
  '1': 'GetFileRequest',
  '2': [
    {'1': 'data_map', '3': 1, '4': 1, '5': 9, '10': 'dataMap'},
    {'1': 'dest_path', '3': 2, '4': 1, '5': 9, '10': 'destPath'},
  ],
};

/// Descriptor for `GetFileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFileRequestDescriptor = $convert.base64Decode(
    'Cg5HZXRGaWxlUmVxdWVzdBIZCghkYXRhX21hcBgBIAEoCVIHZGF0YU1hcBIbCglkZXN0X3BhdG'
    'gYAiABKAlSCGRlc3RQYXRo');

@$core.Deprecated('Use getFileResponseDescriptor instead')
const GetFileResponse$json = {
  '1': 'GetFileResponse',
};

/// Descriptor for `GetFileResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFileResponseDescriptor = $convert.base64Decode(
    'Cg9HZXRGaWxlUmVzcG9uc2U=');

@$core.Deprecated('Use fileCostRequestDescriptor instead')
const FileCostRequest$json = {
  '1': 'FileCostRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'is_public', '3': 2, '4': 1, '5': 8, '10': 'isPublic'},
    {'1': 'payment_mode', '3': 3, '4': 1, '5': 9, '10': 'paymentMode'},
  ],
};

/// Descriptor for `FileCostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileCostRequestDescriptor = $convert.base64Decode(
    'Cg9GaWxlQ29zdFJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aBIbCglpc19wdWJsaWMYAiABKA'
    'hSCGlzUHVibGljEiEKDHBheW1lbnRfbW9kZRgDIAEoCVILcGF5bWVudE1vZGU=');

