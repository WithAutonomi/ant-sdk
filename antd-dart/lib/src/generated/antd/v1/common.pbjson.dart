//
//  Generated code. Do not modify.
//  source: antd/v1/common.proto
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

@$core.Deprecated('Use costDescriptor instead')
const Cost$json = {
  '1': 'Cost',
  '2': [
    {'1': 'atto_tokens', '3': 1, '4': 1, '5': 9, '10': 'attoTokens'},
    {'1': 'file_size', '3': 2, '4': 1, '5': 4, '10': 'fileSize'},
    {'1': 'chunk_count', '3': 3, '4': 1, '5': 13, '10': 'chunkCount'},
    {'1': 'estimated_gas_cost_wei', '3': 4, '4': 1, '5': 9, '10': 'estimatedGasCostWei'},
    {'1': 'payment_mode', '3': 5, '4': 1, '5': 9, '10': 'paymentMode'},
  ],
};

/// Descriptor for `Cost`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List costDescriptor = $convert.base64Decode(
    'CgRDb3N0Eh8KC2F0dG9fdG9rZW5zGAEgASgJUgphdHRvVG9rZW5zEhsKCWZpbGVfc2l6ZRgCIA'
    'EoBFIIZmlsZVNpemUSHwoLY2h1bmtfY291bnQYAyABKA1SCmNodW5rQ291bnQSMwoWZXN0aW1h'
    'dGVkX2dhc19jb3N0X3dlaRgEIAEoCVITZXN0aW1hdGVkR2FzQ29zdFdlaRIhCgxwYXltZW50X2'
    '1vZGUYBSABKAlSC3BheW1lbnRNb2Rl');

@$core.Deprecated('Use addressDescriptor instead')
const Address$json = {
  '1': 'Address',
  '2': [
    {'1': 'hex', '3': 1, '4': 1, '5': 9, '10': 'hex'},
  ],
};

/// Descriptor for `Address`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addressDescriptor = $convert.base64Decode(
    'CgdBZGRyZXNzEhAKA2hleBgBIAEoCVIDaGV4');

@$core.Deprecated('Use publicKeyProtoDescriptor instead')
const PublicKeyProto$json = {
  '1': 'PublicKeyProto',
  '2': [
    {'1': 'hex', '3': 1, '4': 1, '5': 9, '10': 'hex'},
  ],
};

/// Descriptor for `PublicKeyProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List publicKeyProtoDescriptor = $convert.base64Decode(
    'Cg5QdWJsaWNLZXlQcm90bxIQCgNoZXgYASABKAlSA2hleA==');

@$core.Deprecated('Use secretKeyProtoDescriptor instead')
const SecretKeyProto$json = {
  '1': 'SecretKeyProto',
  '2': [
    {'1': 'hex', '3': 1, '4': 1, '5': 9, '10': 'hex'},
  ],
};

/// Descriptor for `SecretKeyProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List secretKeyProtoDescriptor = $convert.base64Decode(
    'Cg5TZWNyZXRLZXlQcm90bxIQCgNoZXgYASABKAlSA2hleA==');

@$core.Deprecated('Use paymentEntryDescriptor instead')
const PaymentEntry$json = {
  '1': 'PaymentEntry',
  '2': [
    {'1': 'quote_hash', '3': 1, '4': 1, '5': 9, '10': 'quoteHash'},
    {'1': 'rewards_address', '3': 2, '4': 1, '5': 9, '10': 'rewardsAddress'},
    {'1': 'amount', '3': 3, '4': 1, '5': 9, '10': 'amount'},
  ],
};

/// Descriptor for `PaymentEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List paymentEntryDescriptor = $convert.base64Decode(
    'CgxQYXltZW50RW50cnkSHQoKcXVvdGVfaGFzaBgBIAEoCVIJcXVvdGVIYXNoEicKD3Jld2FyZH'
    'NfYWRkcmVzcxgCIAEoCVIOcmV3YXJkc0FkZHJlc3MSFgoGYW1vdW50GAMgASgJUgZhbW91bnQ=');

