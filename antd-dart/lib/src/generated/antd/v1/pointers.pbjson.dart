//
//  Generated code. Do not modify.
//  source: antd/v1/pointers.proto
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

@$core.Deprecated('Use listPointerKeysRequestDescriptor instead')
const ListPointerKeysRequest$json = {
  '1': 'ListPointerKeysRequest',
};

/// Descriptor for `ListPointerKeysRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPointerKeysRequestDescriptor = $convert.base64Decode(
    'ChZMaXN0UG9pbnRlcktleXNSZXF1ZXN0');

@$core.Deprecated('Use listPointerKeysResponseDescriptor instead')
const ListPointerKeysResponse$json = {
  '1': 'ListPointerKeysResponse',
  '2': [
    {'1': 'keys', '3': 1, '4': 3, '5': 11, '6': '.antd.v1.PointerKey', '10': 'keys'},
  ],
};

/// Descriptor for `ListPointerKeysResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPointerKeysResponseDescriptor = $convert.base64Decode(
    'ChdMaXN0UG9pbnRlcktleXNSZXNwb25zZRInCgRrZXlzGAEgAygLMhMuYW50ZC52MS5Qb2ludG'
    'VyS2V5UgRrZXlz');

@$core.Deprecated('Use pointerKeyDescriptor instead')
const PointerKey$json = {
  '1': 'PointerKey',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `PointerKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerKeyDescriptor = $convert.base64Decode(
    'CgpQb2ludGVyS2V5EhgKB2FkZHJlc3MYASABKAlSB2FkZHJlc3M=');

@$core.Deprecated('Use pointerWriteRequestDescriptor instead')
const PointerWriteRequest$json = {
  '1': 'PointerWriteRequest',
  '2': [
    {'1': 'owner', '3': 1, '4': 1, '5': 9, '10': 'owner'},
    {'1': 'target', '3': 2, '4': 1, '5': 9, '10': 'target'},
    {'1': 'kind', '3': 3, '4': 1, '5': 9, '10': 'kind'},
  ],
};

/// Descriptor for `PointerWriteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerWriteRequestDescriptor = $convert.base64Decode(
    'ChNQb2ludGVyV3JpdGVSZXF1ZXN0EhQKBW93bmVyGAEgASgJUgVvd25lchIWCgZ0YXJnZXQYAi'
    'ABKAlSBnRhcmdldBISCgRraW5kGAMgASgJUgRraW5k');

@$core.Deprecated('Use pointerWriteResponseDescriptor instead')
const PointerWriteResponse$json = {
  '1': 'PointerWriteResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'state_id', '3': 2, '4': 1, '5': 9, '10': 'stateId'},
    {'1': 'counter', '3': 3, '4': 1, '5': 9, '10': 'counter'},
  ],
};

/// Descriptor for `PointerWriteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerWriteResponseDescriptor = $convert.base64Decode(
    'ChRQb2ludGVyV3JpdGVSZXNwb25zZRIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEhkKCHN0YX'
    'RlX2lkGAIgASgJUgdzdGF0ZUlkEhgKB2NvdW50ZXIYAyABKAlSB2NvdW50ZXI=');

@$core.Deprecated('Use pointerTransferRequestDescriptor instead')
const PointerTransferRequest$json = {
  '1': 'PointerTransferRequest',
  '2': [
    {'1': 'owner', '3': 1, '4': 1, '5': 9, '10': 'owner'},
    {'1': 'recipient', '3': 2, '4': 1, '5': 9, '10': 'recipient'},
  ],
};

/// Descriptor for `PointerTransferRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerTransferRequestDescriptor = $convert.base64Decode(
    'ChZQb2ludGVyVHJhbnNmZXJSZXF1ZXN0EhQKBW93bmVyGAEgASgJUgVvd25lchIcCglyZWNpcG'
    'llbnQYAiABKAlSCXJlY2lwaWVudA==');

@$core.Deprecated('Use pointerTransferResponseDescriptor instead')
const PointerTransferResponse$json = {
  '1': 'PointerTransferResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'state_id', '3': 2, '4': 1, '5': 9, '10': 'stateId'},
    {'1': 'finality', '3': 3, '4': 1, '5': 11, '6': '.antd.v1.PointerFinality', '10': 'finality'},
    {'1': 'finality_error', '3': 4, '4': 1, '5': 9, '10': 'finalityError'},
  ],
};

/// Descriptor for `PointerTransferResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerTransferResponseDescriptor = $convert.base64Decode(
    'ChdQb2ludGVyVHJhbnNmZXJSZXNwb25zZRIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEhkKCH'
    'N0YXRlX2lkGAIgASgJUgdzdGF0ZUlkEjQKCGZpbmFsaXR5GAMgASgLMhguYW50ZC52MS5Qb2lu'
    'dGVyRmluYWxpdHlSCGZpbmFsaXR5EiUKDmZpbmFsaXR5X2Vycm9yGAQgASgJUg1maW5hbGl0eU'
    'Vycm9y');

@$core.Deprecated('Use getPointerRequestDescriptor instead')
const GetPointerRequest$json = {
  '1': 'GetPointerRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `GetPointerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPointerRequestDescriptor = $convert.base64Decode(
    'ChFHZXRQb2ludGVyUmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNz');

@$core.Deprecated('Use pointerRecordDescriptor instead')
const PointerRecord$json = {
  '1': 'PointerRecord',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'owner', '3': 2, '4': 1, '5': 9, '10': 'owner'},
    {'1': 'counter', '3': 3, '4': 1, '5': 9, '10': 'counter'},
    {'1': 'kind', '3': 4, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'kind_tag', '3': 5, '4': 1, '5': 13, '10': 'kindTag'},
    {'1': 'target', '3': 6, '4': 1, '5': 9, '10': 'target'},
    {'1': 'state_id', '3': 7, '4': 1, '5': 9, '10': 'stateId'},
    {'1': 'is_final', '3': 8, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'transferred_to', '3': 9, '4': 1, '5': 9, '10': 'transferredTo'},
  ],
};

/// Descriptor for `PointerRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerRecordDescriptor = $convert.base64Decode(
    'Cg1Qb2ludGVyUmVjb3JkEhgKB2FkZHJlc3MYASABKAlSB2FkZHJlc3MSFAoFb3duZXIYAiABKA'
    'lSBW93bmVyEhgKB2NvdW50ZXIYAyABKAlSB2NvdW50ZXISEgoEa2luZBgEIAEoCVIEa2luZBIZ'
    'CghraW5kX3RhZxgFIAEoDVIHa2luZFRhZxIWCgZ0YXJnZXQYBiABKAlSBnRhcmdldBIZCghzdG'
    'F0ZV9pZBgHIAEoCVIHc3RhdGVJZBIZCghpc19maW5hbBgIIAEoCFIHaXNGaW5hbBIlCg50cmFu'
    'c2ZlcnJlZF90bxgJIAEoCVINdHJhbnNmZXJyZWRUbw==');

@$core.Deprecated('Use resolvePointerRequestDescriptor instead')
const ResolvePointerRequest$json = {
  '1': 'ResolvePointerRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `ResolvePointerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resolvePointerRequestDescriptor = $convert.base64Decode(
    'ChVSZXNvbHZlUG9pbnRlclJlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

@$core.Deprecated('Use pointerResolvedDescriptor instead')
const PointerResolved$json = {
  '1': 'PointerResolved',
  '2': [
    {'1': 'kind', '3': 1, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'kind_tag', '3': 2, '4': 1, '5': 13, '10': 'kindTag'},
    {'1': 'target', '3': 3, '4': 1, '5': 9, '10': 'target'},
  ],
};

/// Descriptor for `PointerResolved`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerResolvedDescriptor = $convert.base64Decode(
    'Cg9Qb2ludGVyUmVzb2x2ZWQSEgoEa2luZBgBIAEoCVIEa2luZBIZCghraW5kX3RhZxgCIAEoDV'
    'IHa2luZFRhZxIWCgZ0YXJnZXQYAyABKAlSBnRhcmdldA==');

@$core.Deprecated('Use pointerFinalityRequestDescriptor instead')
const PointerFinalityRequest$json = {
  '1': 'PointerFinalityRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `PointerFinalityRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerFinalityRequestDescriptor = $convert.base64Decode(
    'ChZQb2ludGVyRmluYWxpdHlSZXF1ZXN0EhgKB2FkZHJlc3MYASABKAlSB2FkZHJlc3M=');

@$core.Deprecated('Use pointerFinalStateDescriptor instead')
const PointerFinalState$json = {
  '1': 'PointerFinalState',
  '2': [
    {'1': 'state_id', '3': 1, '4': 1, '5': 9, '10': 'stateId'},
    {'1': 'kind', '3': 2, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'kind_tag', '3': 3, '4': 1, '5': 13, '10': 'kindTag'},
    {'1': 'target', '3': 4, '4': 1, '5': 9, '10': 'target'},
    {'1': 'holders', '3': 5, '4': 1, '5': 13, '10': 'holders'},
    {'1': 'transferred_to', '3': 6, '4': 1, '5': 9, '10': 'transferredTo'},
  ],
};

/// Descriptor for `PointerFinalState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerFinalStateDescriptor = $convert.base64Decode(
    'ChFQb2ludGVyRmluYWxTdGF0ZRIZCghzdGF0ZV9pZBgBIAEoCVIHc3RhdGVJZBISCgRraW5kGA'
    'IgASgJUgRraW5kEhkKCGtpbmRfdGFnGAMgASgNUgdraW5kVGFnEhYKBnRhcmdldBgEIAEoCVIG'
    'dGFyZ2V0EhgKB2hvbGRlcnMYBSABKA1SB2hvbGRlcnMSJQoOdHJhbnNmZXJyZWRfdG8YBiABKA'
    'lSDXRyYW5zZmVycmVkVG8=');

@$core.Deprecated('Use pointerFinalityDescriptor instead')
const PointerFinality$json = {
  '1': 'PointerFinality',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'group', '3': 2, '4': 1, '5': 13, '10': 'group'},
    {'1': 'answered', '3': 3, '4': 1, '5': 13, '10': 'answered'},
    {'1': 'status', '3': 4, '4': 1, '5': 9, '10': 'status'},
    {'1': 'counter', '3': 5, '4': 1, '5': 9, '10': 'counter'},
    {'1': 'state', '3': 6, '4': 1, '5': 11, '6': '.antd.v1.PointerFinalState', '10': 'state'},
    {'1': 'states', '3': 7, '4': 3, '5': 11, '6': '.antd.v1.PointerFinalState', '10': 'states'},
    {'1': 'majority', '3': 8, '4': 1, '5': 11, '6': '.antd.v1.PointerFinalState', '10': 'majority'},
    {'1': 'transferred_to', '3': 9, '4': 1, '5': 9, '10': 'transferredTo'},
  ],
};

/// Descriptor for `PointerFinality`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerFinalityDescriptor = $convert.base64Decode(
    'Cg9Qb2ludGVyRmluYWxpdHkSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcxIUCgVncm91cBgCIA'
    'EoDVIFZ3JvdXASGgoIYW5zd2VyZWQYAyABKA1SCGFuc3dlcmVkEhYKBnN0YXR1cxgEIAEoCVIG'
    'c3RhdHVzEhgKB2NvdW50ZXIYBSABKAlSB2NvdW50ZXISMAoFc3RhdGUYBiABKAsyGi5hbnRkLn'
    'YxLlBvaW50ZXJGaW5hbFN0YXRlUgVzdGF0ZRIyCgZzdGF0ZXMYByADKAsyGi5hbnRkLnYxLlBv'
    'aW50ZXJGaW5hbFN0YXRlUgZzdGF0ZXMSNgoIbWFqb3JpdHkYCCABKAsyGi5hbnRkLnYxLlBvaW'
    '50ZXJGaW5hbFN0YXRlUghtYWpvcml0eRIlCg50cmFuc2ZlcnJlZF90bxgJIAEoCVINdHJhbnNm'
    'ZXJyZWRUbw==');

@$core.Deprecated('Use pointerControllerRequestDescriptor instead')
const PointerControllerRequest$json = {
  '1': 'PointerControllerRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `PointerControllerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerControllerRequestDescriptor = $convert.base64Decode(
    'ChhQb2ludGVyQ29udHJvbGxlclJlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

@$core.Deprecated('Use pointerControllerDescriptor instead')
const PointerController$json = {
  '1': 'PointerController',
  '2': [
    {'1': 'pointer', '3': 1, '4': 1, '5': 9, '10': 'pointer'},
    {'1': 'transfers', '3': 2, '4': 3, '5': 9, '10': 'transfers'},
    {'1': 'frozen', '3': 3, '4': 1, '5': 8, '10': 'frozen'},
  ],
};

/// Descriptor for `PointerController`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerControllerDescriptor = $convert.base64Decode(
    'ChFQb2ludGVyQ29udHJvbGxlchIYCgdwb2ludGVyGAEgASgJUgdwb2ludGVyEhwKCXRyYW5zZm'
    'VycxgCIAMoCVIJdHJhbnNmZXJzEhYKBmZyb3plbhgDIAEoCFIGZnJvemVu');

@$core.Deprecated('Use preparePointerRequestDescriptor instead')
const PreparePointerRequest$json = {
  '1': 'PreparePointerRequest',
  '2': [
    {'1': 'owner', '3': 1, '4': 1, '5': 9, '10': 'owner'},
    {'1': 'op', '3': 2, '4': 1, '5': 9, '10': 'op'},
    {'1': 'target', '3': 3, '4': 1, '5': 9, '10': 'target'},
    {'1': 'kind', '3': 4, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'recipient', '3': 5, '4': 1, '5': 9, '10': 'recipient'},
    {'1': 'include_signed_quotes', '3': 6, '4': 1, '5': 8, '10': 'includeSignedQuotes'},
  ],
};

/// Descriptor for `PreparePointerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List preparePointerRequestDescriptor = $convert.base64Decode(
    'ChVQcmVwYXJlUG9pbnRlclJlcXVlc3QSFAoFb3duZXIYASABKAlSBW93bmVyEg4KAm9wGAIgAS'
    'gJUgJvcBIWCgZ0YXJnZXQYAyABKAlSBnRhcmdldBISCgRraW5kGAQgASgJUgRraW5kEhwKCXJl'
    'Y2lwaWVudBgFIAEoCVIJcmVjaXBpZW50EjIKFWluY2x1ZGVfc2lnbmVkX3F1b3RlcxgGIAEoCF'
    'ITaW5jbHVkZVNpZ25lZFF1b3Rlcw==');

@$core.Deprecated('Use preparePointerResponseDescriptor instead')
const PreparePointerResponse$json = {
  '1': 'PreparePointerResponse',
  '2': [
    {'1': 'upload_id', '3': 1, '4': 1, '5': 9, '10': 'uploadId'},
    {'1': 'op', '3': 2, '4': 1, '5': 9, '10': 'op'},
    {'1': 'address', '3': 3, '4': 1, '5': 9, '10': 'address'},
    {'1': 'state_id', '3': 4, '4': 1, '5': 9, '10': 'stateId'},
    {'1': 'counter', '3': 5, '4': 1, '5': 9, '10': 'counter'},
    {'1': 'payment_type', '3': 6, '4': 1, '5': 9, '10': 'paymentType'},
    {'1': 'payments', '3': 7, '4': 3, '5': 11, '6': '.antd.v1.PaymentEntry', '10': 'payments'},
    {'1': 'total_amount', '3': 8, '4': 1, '5': 9, '10': 'totalAmount'},
    {'1': 'payment_vault_address', '3': 9, '4': 1, '5': 9, '10': 'paymentVaultAddress'},
    {'1': 'payment_token_address', '3': 10, '4': 1, '5': 9, '10': 'paymentTokenAddress'},
    {'1': 'rpc_url', '3': 11, '4': 1, '5': 9, '10': 'rpcUrl'},
    {'1': 'signed_quotes', '3': 12, '4': 3, '5': 11, '6': '.antd.v1.SignedQuoteEntry', '10': 'signedQuotes'},
  ],
};

/// Descriptor for `PreparePointerResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List preparePointerResponseDescriptor = $convert.base64Decode(
    'ChZQcmVwYXJlUG9pbnRlclJlc3BvbnNlEhsKCXVwbG9hZF9pZBgBIAEoCVIIdXBsb2FkSWQSDg'
    'oCb3AYAiABKAlSAm9wEhgKB2FkZHJlc3MYAyABKAlSB2FkZHJlc3MSGQoIc3RhdGVfaWQYBCAB'
    'KAlSB3N0YXRlSWQSGAoHY291bnRlchgFIAEoCVIHY291bnRlchIhCgxwYXltZW50X3R5cGUYBi'
    'ABKAlSC3BheW1lbnRUeXBlEjEKCHBheW1lbnRzGAcgAygLMhUuYW50ZC52MS5QYXltZW50RW50'
    'cnlSCHBheW1lbnRzEiEKDHRvdGFsX2Ftb3VudBgIIAEoCVILdG90YWxBbW91bnQSMgoVcGF5bW'
    'VudF92YXVsdF9hZGRyZXNzGAkgASgJUhNwYXltZW50VmF1bHRBZGRyZXNzEjIKFXBheW1lbnRf'
    'dG9rZW5fYWRkcmVzcxgKIAEoCVITcGF5bWVudFRva2VuQWRkcmVzcxIXCgdycGNfdXJsGAsgAS'
    'gJUgZycGNVcmwSPgoNc2lnbmVkX3F1b3RlcxgMIAMoCzIZLmFudGQudjEuU2lnbmVkUXVvdGVF'
    'bnRyeVIMc2lnbmVkUXVvdGVz');

@$core.Deprecated('Use finalizePointerRequestDescriptor instead')
const FinalizePointerRequest$json = {
  '1': 'FinalizePointerRequest',
  '2': [
    {'1': 'upload_id', '3': 1, '4': 1, '5': 9, '10': 'uploadId'},
    {'1': 'tx_hashes', '3': 2, '4': 3, '5': 11, '6': '.antd.v1.FinalizePointerRequest.TxHashesEntry', '10': 'txHashes'},
  ],
  '3': [FinalizePointerRequest_TxHashesEntry$json],
};

@$core.Deprecated('Use finalizePointerRequestDescriptor instead')
const FinalizePointerRequest_TxHashesEntry$json = {
  '1': 'TxHashesEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `FinalizePointerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finalizePointerRequestDescriptor = $convert.base64Decode(
    'ChZGaW5hbGl6ZVBvaW50ZXJSZXF1ZXN0EhsKCXVwbG9hZF9pZBgBIAEoCVIIdXBsb2FkSWQSSg'
    'oJdHhfaGFzaGVzGAIgAygLMi0uYW50ZC52MS5GaW5hbGl6ZVBvaW50ZXJSZXF1ZXN0LlR4SGFz'
    'aGVzRW50cnlSCHR4SGFzaGVzGjsKDVR4SGFzaGVzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFA'
    'oFdmFsdWUYAiABKAlSBXZhbHVlOgI4AQ==');

@$core.Deprecated('Use finalizePointerResponseDescriptor instead')
const FinalizePointerResponse$json = {
  '1': 'FinalizePointerResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'state_id', '3': 2, '4': 1, '5': 9, '10': 'stateId'},
    {'1': 'counter', '3': 3, '4': 1, '5': 9, '10': 'counter'},
    {'1': 'finality', '3': 4, '4': 1, '5': 11, '6': '.antd.v1.PointerFinality', '10': 'finality'},
  ],
};

/// Descriptor for `FinalizePointerResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finalizePointerResponseDescriptor = $convert.base64Decode(
    'ChdGaW5hbGl6ZVBvaW50ZXJSZXNwb25zZRIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEhkKCH'
    'N0YXRlX2lkGAIgASgJUgdzdGF0ZUlkEhgKB2NvdW50ZXIYAyABKAlSB2NvdW50ZXISNAoIZmlu'
    'YWxpdHkYBCABKAsyGC5hbnRkLnYxLlBvaW50ZXJGaW5hbGl0eVIIZmluYWxpdHk=');

