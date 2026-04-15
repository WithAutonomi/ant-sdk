// This is a generated file - do not edit.
//
// Generated from antd/v1/common.proto.

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

@$core.Deprecated('Use costDescriptor instead')
const Cost$json = {
  '1': 'Cost',
  '2': [
    {'1': 'atto_tokens', '3': 1, '4': 1, '5': 9, '10': 'attoTokens'},
  ],
};

/// Descriptor for `Cost`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List costDescriptor = $convert
    .base64Decode('CgRDb3N0Eh8KC2F0dG9fdG9rZW5zGAEgASgJUgphdHRvVG9rZW5z');

@$core.Deprecated('Use addressDescriptor instead')
const Address$json = {
  '1': 'Address',
  '2': [
    {'1': 'hex', '3': 1, '4': 1, '5': 9, '10': 'hex'},
  ],
};

/// Descriptor for `Address`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addressDescriptor =
    $convert.base64Decode('CgdBZGRyZXNzEhAKA2hleBgBIAEoCVIDaGV4');

@$core.Deprecated('Use publicKeyProtoDescriptor instead')
const PublicKeyProto$json = {
  '1': 'PublicKeyProto',
  '2': [
    {'1': 'hex', '3': 1, '4': 1, '5': 9, '10': 'hex'},
  ],
};

/// Descriptor for `PublicKeyProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List publicKeyProtoDescriptor =
    $convert.base64Decode('Cg5QdWJsaWNLZXlQcm90bxIQCgNoZXgYASABKAlSA2hleA==');

@$core.Deprecated('Use secretKeyProtoDescriptor instead')
const SecretKeyProto$json = {
  '1': 'SecretKeyProto',
  '2': [
    {'1': 'hex', '3': 1, '4': 1, '5': 9, '10': 'hex'},
  ],
};

/// Descriptor for `SecretKeyProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List secretKeyProtoDescriptor =
    $convert.base64Decode('Cg5TZWNyZXRLZXlQcm90bxIQCgNoZXgYASABKAlSA2hleA==');

@$core.Deprecated('Use graphDescendantDescriptor instead')
const GraphDescendant$json = {
  '1': 'GraphDescendant',
  '2': [
    {'1': 'public_key', '3': 1, '4': 1, '5': 9, '10': 'publicKey'},
    {'1': 'content', '3': 2, '4': 1, '5': 9, '10': 'content'},
  ],
};

/// Descriptor for `GraphDescendant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List graphDescendantDescriptor = $convert.base64Decode(
    'Cg9HcmFwaERlc2NlbmRhbnQSHQoKcHVibGljX2tleRgBIAEoCVIJcHVibGljS2V5EhgKB2Nvbn'
    'RlbnQYAiABKAlSB2NvbnRlbnQ=');
