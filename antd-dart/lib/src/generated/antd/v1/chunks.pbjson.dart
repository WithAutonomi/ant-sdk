// This is a generated file - do not edit.
//
// Generated from antd/v1/chunks.proto.

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

@$core.Deprecated('Use getChunkRequestDescriptor instead')
const GetChunkRequest$json = {
  '1': 'GetChunkRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `GetChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getChunkRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRDaHVua1JlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

@$core.Deprecated('Use getChunkResponseDescriptor instead')
const GetChunkResponse$json = {
  '1': 'GetChunkResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `GetChunkResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getChunkResponseDescriptor = $convert
    .base64Decode('ChBHZXRDaHVua1Jlc3BvbnNlEhIKBGRhdGEYASABKAxSBGRhdGE=');

@$core.Deprecated('Use putChunkRequestDescriptor instead')
const PutChunkRequest$json = {
  '1': 'PutChunkRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PutChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putChunkRequestDescriptor = $convert
    .base64Decode('Cg9QdXRDaHVua1JlcXVlc3QSEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use putChunkResponseDescriptor instead')
const PutChunkResponse$json = {
  '1': 'PutChunkResponse',
  '2': [
    {'1': 'cost', '3': 1, '4': 1, '5': 11, '6': '.antd.v1.Cost', '10': 'cost'},
    {'1': 'address', '3': 2, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `PutChunkResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putChunkResponseDescriptor = $convert.base64Decode(
    'ChBQdXRDaHVua1Jlc3BvbnNlEiEKBGNvc3QYASABKAsyDS5hbnRkLnYxLkNvc3RSBGNvc3QSGA'
    'oHYWRkcmVzcxgCIAEoCVIHYWRkcmVzcw==');
