//
//  Generated code. Do not modify.
//  source: antd/v1/wallet.proto
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

@$core.Deprecated('Use getWalletAddressRequestDescriptor instead')
const GetWalletAddressRequest$json = {
  '1': 'GetWalletAddressRequest',
};

/// Descriptor for `GetWalletAddressRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getWalletAddressRequestDescriptor = $convert.base64Decode(
    'ChdHZXRXYWxsZXRBZGRyZXNzUmVxdWVzdA==');

@$core.Deprecated('Use getWalletAddressResponseDescriptor instead')
const GetWalletAddressResponse$json = {
  '1': 'GetWalletAddressResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `GetWalletAddressResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getWalletAddressResponseDescriptor = $convert.base64Decode(
    'ChhHZXRXYWxsZXRBZGRyZXNzUmVzcG9uc2USGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

@$core.Deprecated('Use getWalletBalanceRequestDescriptor instead')
const GetWalletBalanceRequest$json = {
  '1': 'GetWalletBalanceRequest',
};

/// Descriptor for `GetWalletBalanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getWalletBalanceRequestDescriptor = $convert.base64Decode(
    'ChdHZXRXYWxsZXRCYWxhbmNlUmVxdWVzdA==');

@$core.Deprecated('Use getWalletBalanceResponseDescriptor instead')
const GetWalletBalanceResponse$json = {
  '1': 'GetWalletBalanceResponse',
  '2': [
    {'1': 'balance', '3': 1, '4': 1, '5': 9, '10': 'balance'},
    {'1': 'gas_balance', '3': 2, '4': 1, '5': 9, '10': 'gasBalance'},
  ],
};

/// Descriptor for `GetWalletBalanceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getWalletBalanceResponseDescriptor = $convert.base64Decode(
    'ChhHZXRXYWxsZXRCYWxhbmNlUmVzcG9uc2USGAoHYmFsYW5jZRgBIAEoCVIHYmFsYW5jZRIfCg'
    'tnYXNfYmFsYW5jZRgCIAEoCVIKZ2FzQmFsYW5jZQ==');

@$core.Deprecated('Use walletApproveRequestDescriptor instead')
const WalletApproveRequest$json = {
  '1': 'WalletApproveRequest',
};

/// Descriptor for `WalletApproveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List walletApproveRequestDescriptor = $convert.base64Decode(
    'ChRXYWxsZXRBcHByb3ZlUmVxdWVzdA==');

@$core.Deprecated('Use walletApproveResponseDescriptor instead')
const WalletApproveResponse$json = {
  '1': 'WalletApproveResponse',
  '2': [
    {'1': 'approved', '3': 1, '4': 1, '5': 8, '10': 'approved'},
  ],
};

/// Descriptor for `WalletApproveResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List walletApproveResponseDescriptor = $convert.base64Decode(
    'ChVXYWxsZXRBcHByb3ZlUmVzcG9uc2USGgoIYXBwcm92ZWQYASABKAhSCGFwcHJvdmVk');

