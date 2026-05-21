//
//  Generated code. Do not modify.
//  source: antd/v1/health.proto
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

@$core.Deprecated('Use healthCheckRequestDescriptor instead')
const HealthCheckRequest$json = {
  '1': 'HealthCheckRequest',
};

/// Descriptor for `HealthCheckRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List healthCheckRequestDescriptor = $convert.base64Decode(
    'ChJIZWFsdGhDaGVja1JlcXVlc3Q=');

@$core.Deprecated('Use healthCheckResponseDescriptor instead')
const HealthCheckResponse$json = {
  '1': 'HealthCheckResponse',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 9, '10': 'status'},
    {'1': 'network', '3': 2, '4': 1, '5': 9, '10': 'network'},
    {'1': 'version', '3': 3, '4': 1, '5': 9, '10': 'version'},
    {'1': 'evm_network', '3': 4, '4': 1, '5': 9, '10': 'evmNetwork'},
    {'1': 'uptime_seconds', '3': 5, '4': 1, '5': 4, '10': 'uptimeSeconds'},
    {'1': 'build_commit', '3': 6, '4': 1, '5': 9, '10': 'buildCommit'},
    {'1': 'payment_token_address', '3': 7, '4': 1, '5': 9, '10': 'paymentTokenAddress'},
    {'1': 'payment_vault_address', '3': 8, '4': 1, '5': 9, '10': 'paymentVaultAddress'},
  ],
};

/// Descriptor for `HealthCheckResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List healthCheckResponseDescriptor = $convert.base64Decode(
    'ChNIZWFsdGhDaGVja1Jlc3BvbnNlEhYKBnN0YXR1cxgBIAEoCVIGc3RhdHVzEhgKB25ldHdvcm'
    'sYAiABKAlSB25ldHdvcmsSGAoHdmVyc2lvbhgDIAEoCVIHdmVyc2lvbhIfCgtldm1fbmV0d29y'
    'axgEIAEoCVIKZXZtTmV0d29yaxIlCg51cHRpbWVfc2Vjb25kcxgFIAEoBFINdXB0aW1lU2Vjb2'
    '5kcxIhCgxidWlsZF9jb21taXQYBiABKAlSC2J1aWxkQ29tbWl0EjIKFXBheW1lbnRfdG9rZW5f'
    'YWRkcmVzcxgHIAEoCVITcGF5bWVudFRva2VuQWRkcmVzcxIyChVwYXltZW50X3ZhdWx0X2FkZH'
    'Jlc3MYCCABKAlSE3BheW1lbnRWYXVsdEFkZHJlc3M=');

