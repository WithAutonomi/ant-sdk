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

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use getPublicDataRequestDescriptor instead')
const GetPublicDataRequest$json = {
  '1': 'GetPublicDataRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `GetPublicDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPublicDataRequestDescriptor = $convert.base64Decode(
    'ChRHZXRQdWJsaWNEYXRhUmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNz');

@$core.Deprecated('Use getPublicDataResponseDescriptor instead')
const GetPublicDataResponse$json = {
  '1': 'GetPublicDataResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `GetPublicDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPublicDataResponseDescriptor = $convert.base64Decode(
    'ChVHZXRQdWJsaWNEYXRhUmVzcG9uc2USEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use putPublicDataRequestDescriptor instead')
const PutPublicDataRequest$json = {
  '1': 'PutPublicDataRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'payment_mode', '3': 2, '4': 1, '5': 9, '10': 'paymentMode'},
  ],
};

/// Descriptor for `PutPublicDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putPublicDataRequestDescriptor = $convert.base64Decode(
    'ChRQdXRQdWJsaWNEYXRhUmVxdWVzdBISCgRkYXRhGAEgASgMUgRkYXRhEiEKDHBheW1lbnRfbW'
    '9kZRgCIAEoCVILcGF5bWVudE1vZGU=');

@$core.Deprecated('Use putPublicDataResponseDescriptor instead')
const PutPublicDataResponse$json = {
  '1': 'PutPublicDataResponse',
  '2': [
    {'1': 'cost', '3': 1, '4': 1, '5': 11, '6': '.antd.v1.Cost', '10': 'cost'},
    {'1': 'address', '3': 2, '4': 1, '5': 9, '10': 'address'},
    {'1': 'chunks_stored', '3': 3, '4': 1, '5': 4, '10': 'chunksStored'},
    {'1': 'payment_mode_used', '3': 4, '4': 1, '5': 9, '10': 'paymentModeUsed'},
  ],
};

/// Descriptor for `PutPublicDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putPublicDataResponseDescriptor = $convert.base64Decode(
    'ChVQdXRQdWJsaWNEYXRhUmVzcG9uc2USIQoEY29zdBgBIAEoCzINLmFudGQudjEuQ29zdFIEY2'
    '9zdBIYCgdhZGRyZXNzGAIgASgJUgdhZGRyZXNzEiMKDWNodW5rc19zdG9yZWQYAyABKARSDGNo'
    'dW5rc1N0b3JlZBIqChFwYXltZW50X21vZGVfdXNlZBgEIAEoCVIPcGF5bWVudE1vZGVVc2Vk');

@$core.Deprecated('Use streamPublicDataRequestDescriptor instead')
const StreamPublicDataRequest$json = {
  '1': 'StreamPublicDataRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'include_progress', '3': 2, '4': 1, '5': 8, '10': 'includeProgress'},
  ],
};

/// Descriptor for `StreamPublicDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamPublicDataRequestDescriptor = $convert.base64Decode(
    'ChdTdHJlYW1QdWJsaWNEYXRhUmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEikKEG'
    'luY2x1ZGVfcHJvZ3Jlc3MYAiABKAhSD2luY2x1ZGVQcm9ncmVzcw==');

@$core.Deprecated('Use dataChunkDescriptor instead')
const DataChunk$json = {
  '1': 'DataChunk',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '9': 0, '10': 'data'},
    {'1': 'progress', '3': 2, '4': 1, '5': 11, '6': '.antd.v1.DownloadProgress', '9': 0, '10': 'progress'},
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `DataChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dataChunkDescriptor = $convert.base64Decode(
    'CglEYXRhQ2h1bmsSFAoEZGF0YRgBIAEoDEgAUgRkYXRhEjcKCHByb2dyZXNzGAIgASgLMhkuYW'
    '50ZC52MS5Eb3dubG9hZFByb2dyZXNzSABSCHByb2dyZXNzQgYKBGtpbmQ=');

@$core.Deprecated('Use downloadProgressDescriptor instead')
const DownloadProgress$json = {
  '1': 'DownloadProgress',
  '2': [
    {'1': 'phase', '3': 1, '4': 1, '5': 9, '10': 'phase'},
    {'1': 'fetched', '3': 2, '4': 1, '5': 4, '10': 'fetched'},
    {'1': 'total', '3': 3, '4': 1, '5': 4, '10': 'total'},
  ],
};

/// Descriptor for `DownloadProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadProgressDescriptor = $convert.base64Decode(
    'ChBEb3dubG9hZFByb2dyZXNzEhQKBXBoYXNlGAEgASgJUgVwaGFzZRIYCgdmZXRjaGVkGAIgAS'
    'gEUgdmZXRjaGVkEhQKBXRvdGFsGAMgASgEUgV0b3RhbA==');

@$core.Deprecated('Use getDataRequestDescriptor instead')
const GetDataRequest$json = {
  '1': 'GetDataRequest',
  '2': [
    {'1': 'data_map', '3': 1, '4': 1, '5': 9, '10': 'dataMap'},
  ],
};

/// Descriptor for `GetDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getDataRequestDescriptor = $convert.base64Decode(
    'Cg5HZXREYXRhUmVxdWVzdBIZCghkYXRhX21hcBgBIAEoCVIHZGF0YU1hcA==');

@$core.Deprecated('Use streamDataRequestDescriptor instead')
const StreamDataRequest$json = {
  '1': 'StreamDataRequest',
  '2': [
    {'1': 'data_map', '3': 1, '4': 1, '5': 9, '10': 'dataMap'},
    {'1': 'include_progress', '3': 2, '4': 1, '5': 8, '10': 'includeProgress'},
  ],
};

/// Descriptor for `StreamDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamDataRequestDescriptor = $convert.base64Decode(
    'ChFTdHJlYW1EYXRhUmVxdWVzdBIZCghkYXRhX21hcBgBIAEoCVIHZGF0YU1hcBIpChBpbmNsdW'
    'RlX3Byb2dyZXNzGAIgASgIUg9pbmNsdWRlUHJvZ3Jlc3M=');

@$core.Deprecated('Use getDataResponseDescriptor instead')
const GetDataResponse$json = {
  '1': 'GetDataResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `GetDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getDataResponseDescriptor = $convert.base64Decode(
    'Cg9HZXREYXRhUmVzcG9uc2USEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use putDataRequestDescriptor instead')
const PutDataRequest$json = {
  '1': 'PutDataRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'payment_mode', '3': 2, '4': 1, '5': 9, '10': 'paymentMode'},
  ],
};

/// Descriptor for `PutDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putDataRequestDescriptor = $convert.base64Decode(
    'Cg5QdXREYXRhUmVxdWVzdBISCgRkYXRhGAEgASgMUgRkYXRhEiEKDHBheW1lbnRfbW9kZRgCIA'
    'EoCVILcGF5bWVudE1vZGU=');

@$core.Deprecated('Use putDataResponseDescriptor instead')
const PutDataResponse$json = {
  '1': 'PutDataResponse',
  '2': [
    {'1': 'cost', '3': 1, '4': 1, '5': 11, '6': '.antd.v1.Cost', '10': 'cost'},
    {'1': 'data_map', '3': 2, '4': 1, '5': 9, '10': 'dataMap'},
    {'1': 'chunks_stored', '3': 3, '4': 1, '5': 4, '10': 'chunksStored'},
    {'1': 'payment_mode_used', '3': 4, '4': 1, '5': 9, '10': 'paymentModeUsed'},
  ],
};

/// Descriptor for `PutDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putDataResponseDescriptor = $convert.base64Decode(
    'Cg9QdXREYXRhUmVzcG9uc2USIQoEY29zdBgBIAEoCzINLmFudGQudjEuQ29zdFIEY29zdBIZCg'
    'hkYXRhX21hcBgCIAEoCVIHZGF0YU1hcBIjCg1jaHVua3Nfc3RvcmVkGAMgASgEUgxjaHVua3NT'
    'dG9yZWQSKgoRcGF5bWVudF9tb2RlX3VzZWQYBCABKAlSD3BheW1lbnRNb2RlVXNlZA==');

@$core.Deprecated('Use dataCostRequestDescriptor instead')
const DataCostRequest$json = {
  '1': 'DataCostRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'payment_mode', '3': 2, '4': 1, '5': 9, '10': 'paymentMode'},
  ],
};

/// Descriptor for `DataCostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dataCostRequestDescriptor = $convert.base64Decode(
    'Cg9EYXRhQ29zdFJlcXVlc3QSEgoEZGF0YRgBIAEoDFIEZGF0YRIhCgxwYXltZW50X21vZGUYAi'
    'ABKAlSC3BheW1lbnRNb2Rl');

