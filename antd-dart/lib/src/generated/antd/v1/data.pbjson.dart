// This is a generated file - do not edit.
//
// Generated from antd/v1/data.proto.

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

@$core.Deprecated('Use getPublicDataRequestDescriptor instead')
const GetPublicDataRequest$json = {
  '1': 'GetPublicDataRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `GetPublicDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPublicDataRequestDescriptor =
    $convert.base64Decode(
        'ChRHZXRQdWJsaWNEYXRhUmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNz');

@$core.Deprecated('Use getPublicDataResponseDescriptor instead')
const GetPublicDataResponse$json = {
  '1': 'GetPublicDataResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `GetPublicDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPublicDataResponseDescriptor =
    $convert.base64Decode(
        'ChVHZXRQdWJsaWNEYXRhUmVzcG9uc2USEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use putPublicDataRequestDescriptor instead')
const PutPublicDataRequest$json = {
  '1': 'PutPublicDataRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PutPublicDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putPublicDataRequestDescriptor = $convert
    .base64Decode('ChRQdXRQdWJsaWNEYXRhUmVxdWVzdBISCgRkYXRhGAEgASgMUgRkYXRh');

@$core.Deprecated('Use putPublicDataResponseDescriptor instead')
const PutPublicDataResponse$json = {
  '1': 'PutPublicDataResponse',
  '2': [
    {'1': 'cost', '3': 1, '4': 1, '5': 11, '6': '.antd.v1.Cost', '10': 'cost'},
    {'1': 'address', '3': 2, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `PutPublicDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putPublicDataResponseDescriptor = $convert.base64Decode(
    'ChVQdXRQdWJsaWNEYXRhUmVzcG9uc2USIQoEY29zdBgBIAEoCzINLmFudGQudjEuQ29zdFIEY2'
    '9zdBIYCgdhZGRyZXNzGAIgASgJUgdhZGRyZXNz');

@$core.Deprecated('Use streamPublicDataRequestDescriptor instead')
const StreamPublicDataRequest$json = {
  '1': 'StreamPublicDataRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `StreamPublicDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamPublicDataRequestDescriptor =
    $convert.base64Decode(
        'ChdTdHJlYW1QdWJsaWNEYXRhUmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNz');

@$core.Deprecated('Use dataChunkDescriptor instead')
const DataChunk$json = {
  '1': 'DataChunk',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `DataChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dataChunkDescriptor =
    $convert.base64Decode('CglEYXRhQ2h1bmsSEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use getPrivateDataRequestDescriptor instead')
const GetPrivateDataRequest$json = {
  '1': 'GetPrivateDataRequest',
  '2': [
    {'1': 'data_map', '3': 1, '4': 1, '5': 9, '10': 'dataMap'},
  ],
};

/// Descriptor for `GetPrivateDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPrivateDataRequestDescriptor =
    $convert.base64Decode(
        'ChVHZXRQcml2YXRlRGF0YVJlcXVlc3QSGQoIZGF0YV9tYXAYASABKAlSB2RhdGFNYXA=');

@$core.Deprecated('Use getPrivateDataResponseDescriptor instead')
const GetPrivateDataResponse$json = {
  '1': 'GetPrivateDataResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `GetPrivateDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPrivateDataResponseDescriptor =
    $convert.base64Decode(
        'ChZHZXRQcml2YXRlRGF0YVJlc3BvbnNlEhIKBGRhdGEYASABKAxSBGRhdGE=');

@$core.Deprecated('Use putPrivateDataRequestDescriptor instead')
const PutPrivateDataRequest$json = {
  '1': 'PutPrivateDataRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PutPrivateDataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putPrivateDataRequestDescriptor =
    $convert.base64Decode(
        'ChVQdXRQcml2YXRlRGF0YVJlcXVlc3QSEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use putPrivateDataResponseDescriptor instead')
const PutPrivateDataResponse$json = {
  '1': 'PutPrivateDataResponse',
  '2': [
    {'1': 'cost', '3': 1, '4': 1, '5': 11, '6': '.antd.v1.Cost', '10': 'cost'},
    {'1': 'data_map', '3': 2, '4': 1, '5': 9, '10': 'dataMap'},
  ],
};

/// Descriptor for `PutPrivateDataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putPrivateDataResponseDescriptor =
    $convert.base64Decode(
        'ChZQdXRQcml2YXRlRGF0YVJlc3BvbnNlEiEKBGNvc3QYASABKAsyDS5hbnRkLnYxLkNvc3RSBG'
        'Nvc3QSGQoIZGF0YV9tYXAYAiABKAlSB2RhdGFNYXA=');

@$core.Deprecated('Use dataCostRequestDescriptor instead')
const DataCostRequest$json = {
  '1': 'DataCostRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `DataCostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dataCostRequestDescriptor = $convert
    .base64Decode('Cg9EYXRhQ29zdFJlcXVlc3QSEgoEZGF0YRgBIAEoDFIEZGF0YQ==');
