//
//  Generated code. Do not modify.
//  source: antd/v1/chunks.proto
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
final $typed_data.Uint8List getChunkResponseDescriptor = $convert.base64Decode(
    'ChBHZXRDaHVua1Jlc3BvbnNlEhIKBGRhdGEYASABKAxSBGRhdGE=');

@$core.Deprecated('Use putChunkRequestDescriptor instead')
const PutChunkRequest$json = {
  '1': 'PutChunkRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PutChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putChunkRequestDescriptor = $convert.base64Decode(
    'Cg9QdXRDaHVua1JlcXVlc3QSEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

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

@$core.Deprecated('Use prepareChunkRequestDescriptor instead')
const PrepareChunkRequest$json = {
  '1': 'PrepareChunkRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PrepareChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareChunkRequestDescriptor = $convert.base64Decode(
    'ChNQcmVwYXJlQ2h1bmtSZXF1ZXN0EhIKBGRhdGEYASABKAxSBGRhdGE=');

@$core.Deprecated('Use prepareChunkResponseDescriptor instead')
const PrepareChunkResponse$json = {
  '1': 'PrepareChunkResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'already_stored', '3': 2, '4': 1, '5': 8, '10': 'alreadyStored'},
    {'1': 'upload_id', '3': 3, '4': 1, '5': 9, '10': 'uploadId'},
    {'1': 'payment_type', '3': 4, '4': 1, '5': 9, '10': 'paymentType'},
    {'1': 'payments', '3': 5, '4': 3, '5': 11, '6': '.antd.v1.PaymentEntry', '10': 'payments'},
    {'1': 'total_amount', '3': 6, '4': 1, '5': 9, '10': 'totalAmount'},
    {'1': 'payment_vault_address', '3': 7, '4': 1, '5': 9, '10': 'paymentVaultAddress'},
    {'1': 'payment_token_address', '3': 8, '4': 1, '5': 9, '10': 'paymentTokenAddress'},
    {'1': 'rpc_url', '3': 9, '4': 1, '5': 9, '10': 'rpcUrl'},
  ],
};

/// Descriptor for `PrepareChunkResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareChunkResponseDescriptor = $convert.base64Decode(
    'ChRQcmVwYXJlQ2h1bmtSZXNwb25zZRIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEiUKDmFscm'
    'VhZHlfc3RvcmVkGAIgASgIUg1hbHJlYWR5U3RvcmVkEhsKCXVwbG9hZF9pZBgDIAEoCVIIdXBs'
    'b2FkSWQSIQoMcGF5bWVudF90eXBlGAQgASgJUgtwYXltZW50VHlwZRIxCghwYXltZW50cxgFIA'
    'MoCzIVLmFudGQudjEuUGF5bWVudEVudHJ5UghwYXltZW50cxIhCgx0b3RhbF9hbW91bnQYBiAB'
    'KAlSC3RvdGFsQW1vdW50EjIKFXBheW1lbnRfdmF1bHRfYWRkcmVzcxgHIAEoCVITcGF5bWVudF'
    'ZhdWx0QWRkcmVzcxIyChVwYXltZW50X3Rva2VuX2FkZHJlc3MYCCABKAlSE3BheW1lbnRUb2tl'
    'bkFkZHJlc3MSFwoHcnBjX3VybBgJIAEoCVIGcnBjVXJs');

@$core.Deprecated('Use finalizeChunkRequestDescriptor instead')
const FinalizeChunkRequest$json = {
  '1': 'FinalizeChunkRequest',
  '2': [
    {'1': 'upload_id', '3': 1, '4': 1, '5': 9, '10': 'uploadId'},
    {'1': 'tx_hashes', '3': 2, '4': 3, '5': 11, '6': '.antd.v1.FinalizeChunkRequest.TxHashesEntry', '10': 'txHashes'},
  ],
  '3': [FinalizeChunkRequest_TxHashesEntry$json],
};

@$core.Deprecated('Use finalizeChunkRequestDescriptor instead')
const FinalizeChunkRequest_TxHashesEntry$json = {
  '1': 'TxHashesEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `FinalizeChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finalizeChunkRequestDescriptor = $convert.base64Decode(
    'ChRGaW5hbGl6ZUNodW5rUmVxdWVzdBIbCgl1cGxvYWRfaWQYASABKAlSCHVwbG9hZElkEkgKCX'
    'R4X2hhc2hlcxgCIAMoCzIrLmFudGQudjEuRmluYWxpemVDaHVua1JlcXVlc3QuVHhIYXNoZXNF'
    'bnRyeVIIdHhIYXNoZXMaOwoNVHhIYXNoZXNFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YW'
    'x1ZRgCIAEoCVIFdmFsdWU6AjgB');

@$core.Deprecated('Use finalizeChunkResponseDescriptor instead')
const FinalizeChunkResponse$json = {
  '1': 'FinalizeChunkResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `FinalizeChunkResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finalizeChunkResponseDescriptor = $convert.base64Decode(
    'ChVGaW5hbGl6ZUNodW5rUmVzcG9uc2USGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

