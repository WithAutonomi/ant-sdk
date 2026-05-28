//
//  Generated code. Do not modify.
//  source: antd/v1/upload.proto
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

@$core.Deprecated('Use prepareFileUploadRequestDescriptor instead')
const PrepareFileUploadRequest$json = {
  '1': 'PrepareFileUploadRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'visibility', '3': 2, '4': 1, '5': 9, '10': 'visibility'},
  ],
};

/// Descriptor for `PrepareFileUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareFileUploadRequestDescriptor = $convert.base64Decode(
    'ChhQcmVwYXJlRmlsZVVwbG9hZFJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aBIeCgp2aXNpYm'
    'lsaXR5GAIgASgJUgp2aXNpYmlsaXR5');

@$core.Deprecated('Use prepareDataUploadRequestDescriptor instead')
const PrepareDataUploadRequest$json = {
  '1': 'PrepareDataUploadRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'visibility', '3': 2, '4': 1, '5': 9, '10': 'visibility'},
  ],
};

/// Descriptor for `PrepareDataUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareDataUploadRequestDescriptor = $convert.base64Decode(
    'ChhQcmVwYXJlRGF0YVVwbG9hZFJlcXVlc3QSEgoEZGF0YRgBIAEoDFIEZGF0YRIeCgp2aXNpYm'
    'lsaXR5GAIgASgJUgp2aXNpYmlsaXR5');

@$core.Deprecated('Use prepareUploadResponseDescriptor instead')
const PrepareUploadResponse$json = {
  '1': 'PrepareUploadResponse',
  '2': [
    {'1': 'upload_id', '3': 1, '4': 1, '5': 9, '10': 'uploadId'},
    {'1': 'payment_type', '3': 2, '4': 1, '5': 9, '10': 'paymentType'},
    {'1': 'payments', '3': 3, '4': 3, '5': 11, '6': '.antd.v1.PaymentEntry', '10': 'payments'},
    {'1': 'depth', '3': 4, '4': 1, '5': 13, '10': 'depth'},
    {'1': 'pool_commitments', '3': 5, '4': 3, '5': 11, '6': '.antd.v1.PoolCommitmentEntry', '10': 'poolCommitments'},
    {'1': 'merkle_payment_timestamp', '3': 6, '4': 1, '5': 4, '10': 'merklePaymentTimestamp'},
    {'1': 'total_amount', '3': 7, '4': 1, '5': 9, '10': 'totalAmount'},
    {'1': 'payment_vault_address', '3': 8, '4': 1, '5': 9, '10': 'paymentVaultAddress'},
    {'1': 'payment_token_address', '3': 9, '4': 1, '5': 9, '10': 'paymentTokenAddress'},
    {'1': 'rpc_url', '3': 10, '4': 1, '5': 9, '10': 'rpcUrl'},
  ],
};

/// Descriptor for `PrepareUploadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareUploadResponseDescriptor = $convert.base64Decode(
    'ChVQcmVwYXJlVXBsb2FkUmVzcG9uc2USGwoJdXBsb2FkX2lkGAEgASgJUgh1cGxvYWRJZBIhCg'
    'xwYXltZW50X3R5cGUYAiABKAlSC3BheW1lbnRUeXBlEjEKCHBheW1lbnRzGAMgAygLMhUuYW50'
    'ZC52MS5QYXltZW50RW50cnlSCHBheW1lbnRzEhQKBWRlcHRoGAQgASgNUgVkZXB0aBJHChBwb2'
    '9sX2NvbW1pdG1lbnRzGAUgAygLMhwuYW50ZC52MS5Qb29sQ29tbWl0bWVudEVudHJ5Ug9wb29s'
    'Q29tbWl0bWVudHMSOAoYbWVya2xlX3BheW1lbnRfdGltZXN0YW1wGAYgASgEUhZtZXJrbGVQYX'
    'ltZW50VGltZXN0YW1wEiEKDHRvdGFsX2Ftb3VudBgHIAEoCVILdG90YWxBbW91bnQSMgoVcGF5'
    'bWVudF92YXVsdF9hZGRyZXNzGAggASgJUhNwYXltZW50VmF1bHRBZGRyZXNzEjIKFXBheW1lbn'
    'RfdG9rZW5fYWRkcmVzcxgJIAEoCVITcGF5bWVudFRva2VuQWRkcmVzcxIXCgdycGNfdXJsGAog'
    'ASgJUgZycGNVcmw=');

@$core.Deprecated('Use poolCommitmentEntryDescriptor instead')
const PoolCommitmentEntry$json = {
  '1': 'PoolCommitmentEntry',
  '2': [
    {'1': 'pool_hash', '3': 1, '4': 1, '5': 9, '10': 'poolHash'},
    {'1': 'candidates', '3': 2, '4': 3, '5': 11, '6': '.antd.v1.CandidateNodeEntry', '10': 'candidates'},
  ],
};

/// Descriptor for `PoolCommitmentEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List poolCommitmentEntryDescriptor = $convert.base64Decode(
    'ChNQb29sQ29tbWl0bWVudEVudHJ5EhsKCXBvb2xfaGFzaBgBIAEoCVIIcG9vbEhhc2gSOwoKY2'
    'FuZGlkYXRlcxgCIAMoCzIbLmFudGQudjEuQ2FuZGlkYXRlTm9kZUVudHJ5UgpjYW5kaWRhdGVz');

@$core.Deprecated('Use candidateNodeEntryDescriptor instead')
const CandidateNodeEntry$json = {
  '1': 'CandidateNodeEntry',
  '2': [
    {'1': 'rewards_address', '3': 1, '4': 1, '5': 9, '10': 'rewardsAddress'},
    {'1': 'amount', '3': 2, '4': 1, '5': 9, '10': 'amount'},
  ],
};

/// Descriptor for `CandidateNodeEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List candidateNodeEntryDescriptor = $convert.base64Decode(
    'ChJDYW5kaWRhdGVOb2RlRW50cnkSJwoPcmV3YXJkc19hZGRyZXNzGAEgASgJUg5yZXdhcmRzQW'
    'RkcmVzcxIWCgZhbW91bnQYAiABKAlSBmFtb3VudA==');

@$core.Deprecated('Use finalizeUploadRequestDescriptor instead')
const FinalizeUploadRequest$json = {
  '1': 'FinalizeUploadRequest',
  '2': [
    {'1': 'upload_id', '3': 1, '4': 1, '5': 9, '10': 'uploadId'},
    {'1': 'tx_hashes', '3': 2, '4': 3, '5': 11, '6': '.antd.v1.FinalizeUploadRequest.TxHashesEntry', '10': 'txHashes'},
    {'1': 'winner_pool_hash', '3': 3, '4': 1, '5': 9, '10': 'winnerPoolHash'},
    {'1': 'store_data_map', '3': 4, '4': 1, '5': 8, '10': 'storeDataMap'},
  ],
  '3': [FinalizeUploadRequest_TxHashesEntry$json],
};

@$core.Deprecated('Use finalizeUploadRequestDescriptor instead')
const FinalizeUploadRequest_TxHashesEntry$json = {
  '1': 'TxHashesEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `FinalizeUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finalizeUploadRequestDescriptor = $convert.base64Decode(
    'ChVGaW5hbGl6ZVVwbG9hZFJlcXVlc3QSGwoJdXBsb2FkX2lkGAEgASgJUgh1cGxvYWRJZBJJCg'
    'l0eF9oYXNoZXMYAiADKAsyLC5hbnRkLnYxLkZpbmFsaXplVXBsb2FkUmVxdWVzdC5UeEhhc2hl'
    'c0VudHJ5Ugh0eEhhc2hlcxIoChB3aW5uZXJfcG9vbF9oYXNoGAMgASgJUg53aW5uZXJQb29sSG'
    'FzaBIkCg5zdG9yZV9kYXRhX21hcBgEIAEoCFIMc3RvcmVEYXRhTWFwGjsKDVR4SGFzaGVzRW50'
    'cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AQ==');

@$core.Deprecated('Use finalizeUploadResponseDescriptor instead')
const FinalizeUploadResponse$json = {
  '1': 'FinalizeUploadResponse',
  '2': [
    {'1': 'data_map', '3': 1, '4': 1, '5': 9, '10': 'dataMap'},
    {'1': 'address', '3': 2, '4': 1, '5': 9, '10': 'address'},
    {'1': 'data_map_address', '3': 3, '4': 1, '5': 9, '10': 'dataMapAddress'},
    {'1': 'chunks_stored', '3': 4, '4': 1, '5': 4, '10': 'chunksStored'},
  ],
};

/// Descriptor for `FinalizeUploadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finalizeUploadResponseDescriptor = $convert.base64Decode(
    'ChZGaW5hbGl6ZVVwbG9hZFJlc3BvbnNlEhkKCGRhdGFfbWFwGAEgASgJUgdkYXRhTWFwEhgKB2'
    'FkZHJlc3MYAiABKAlSB2FkZHJlc3MSKAoQZGF0YV9tYXBfYWRkcmVzcxgDIAEoCVIOZGF0YU1h'
    'cEFkZHJlc3MSIwoNY2h1bmtzX3N0b3JlZBgEIAEoBFIMY2h1bmtzU3RvcmVk');

