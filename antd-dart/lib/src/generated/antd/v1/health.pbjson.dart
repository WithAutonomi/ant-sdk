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
    {'1': 'write_ready', '3': 9, '4': 1, '5': 8, '10': 'writeReady'},
    {'1': 'connected_peers', '3': 10, '4': 1, '5': 13, '10': 'connectedPeers'},
    {'1': 'routing_table_size', '3': 11, '4': 1, '5': 13, '10': 'routingTableSize'},
    {'1': 'rebootstrap_threshold', '3': 12, '4': 1, '5': 13, '10': 'rebootstrapThreshold'},
    {'1': 'last_store_ok_secs_ago', '3': 13, '4': 1, '5': 4, '9': 0, '10': 'lastStoreOkSecsAgo', '17': true},
  ],
  '8': [
    {'1': '_last_store_ok_secs_ago'},
  ],
};

/// Descriptor for `HealthCheckResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List healthCheckResponseDescriptor = $convert.base64Decode(
    'ChNIZWFsdGhDaGVja1Jlc3BvbnNlEhYKBnN0YXR1cxgBIAEoCVIGc3RhdHVzEhgKB25ldHdvcm'
    'sYAiABKAlSB25ldHdvcmsSGAoHdmVyc2lvbhgDIAEoCVIHdmVyc2lvbhIfCgtldm1fbmV0d29y'
    'axgEIAEoCVIKZXZtTmV0d29yaxIlCg51cHRpbWVfc2Vjb25kcxgFIAEoBFINdXB0aW1lU2Vjb2'
    '5kcxIhCgxidWlsZF9jb21taXQYBiABKAlSC2J1aWxkQ29tbWl0EjIKFXBheW1lbnRfdG9rZW5f'
    'YWRkcmVzcxgHIAEoCVITcGF5bWVudFRva2VuQWRkcmVzcxIyChVwYXltZW50X3ZhdWx0X2FkZH'
    'Jlc3MYCCABKAlSE3BheW1lbnRWYXVsdEFkZHJlc3MSHwoLd3JpdGVfcmVhZHkYCSABKAhSCndy'
    'aXRlUmVhZHkSJwoPY29ubmVjdGVkX3BlZXJzGAogASgNUg5jb25uZWN0ZWRQZWVycxIsChJyb3'
    'V0aW5nX3RhYmxlX3NpemUYCyABKA1SEHJvdXRpbmdUYWJsZVNpemUSMwoVcmVib290c3RyYXBf'
    'dGhyZXNob2xkGAwgASgNUhRyZWJvb3RzdHJhcFRocmVzaG9sZBI3ChZsYXN0X3N0b3JlX29rX3'
    'NlY3NfYWdvGA0gASgESABSEmxhc3RTdG9yZU9rU2Vjc0Fnb4gBAUIZChdfbGFzdF9zdG9yZV9v'
    'a19zZWNzX2Fnbw==');

