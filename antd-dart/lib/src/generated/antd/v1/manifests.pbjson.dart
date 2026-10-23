//
//  Generated code. Do not modify.
//  source: antd/v1/manifests.proto
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

@$core.Deprecated('Use manifestEntryInputDescriptor instead')
const ManifestEntryInput$json = {
  '1': 'ManifestEntryInput',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '9': 1, '10': 'path', '17': true},
    {'1': 'size', '3': 2, '4': 1, '5': 4, '9': 2, '10': 'size', '17': true},
    {'1': 'sha256', '3': 5, '4': 1, '5': 9, '9': 3, '10': 'sha256', '17': true},
    {'1': 'data_map', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'dataMap'},
    {'1': 'address', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'address'},
  ],
  '8': [
    {'1': 'source'},
    {'1': '_path'},
    {'1': '_size'},
    {'1': '_sha256'},
  ],
};

/// Descriptor for `ManifestEntryInput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List manifestEntryInputDescriptor = $convert.base64Decode(
    'ChJNYW5pZmVzdEVudHJ5SW5wdXQSFwoEcGF0aBgBIAEoCUgBUgRwYXRoiAEBEhcKBHNpemUYAi'
    'ABKARIAlIEc2l6ZYgBARIbCgZzaGEyNTYYBSABKAlIA1IGc2hhMjU2iAEBEhsKCGRhdGFfbWFw'
    'GAMgASgJSABSB2RhdGFNYXASGgoHYWRkcmVzcxgEIAEoCUgAUgdhZGRyZXNzQggKBnNvdXJjZU'
    'IHCgVfcGF0aEIHCgVfc2l6ZUIJCgdfc2hhMjU2');

@$core.Deprecated('Use buildManifestRequestDescriptor instead')
const BuildManifestRequest$json = {
  '1': 'BuildManifestRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {'1': 'torrent_info_hashes', '3': 2, '4': 3, '5': 9, '10': 'torrentInfoHashes'},
    {'1': 'embed_roots', '3': 3, '4': 1, '5': 8, '9': 1, '10': 'embedRoots', '17': true},
    {'1': 'entries', '3': 4, '4': 3, '5': 11, '6': '.antd.v1.ManifestEntryInput', '10': 'entries'},
  ],
  '8': [
    {'1': '_name'},
    {'1': '_embed_roots'},
  ],
};

/// Descriptor for `BuildManifestRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List buildManifestRequestDescriptor = $convert.base64Decode(
    'ChRCdWlsZE1hbmlmZXN0UmVxdWVzdBIXCgRuYW1lGAEgASgJSABSBG5hbWWIAQESLgoTdG9ycm'
    'VudF9pbmZvX2hhc2hlcxgCIAMoCVIRdG9ycmVudEluZm9IYXNoZXMSJAoLZW1iZWRfcm9vdHMY'
    'AyABKAhIAVIKZW1iZWRSb290c4gBARI1CgdlbnRyaWVzGAQgAygLMhsuYW50ZC52MS5NYW5pZm'
    'VzdEVudHJ5SW5wdXRSB2VudHJpZXNCBwoFX25hbWVCDgoMX2VtYmVkX3Jvb3Rz');

@$core.Deprecated('Use manifestEntryInfoDescriptor instead')
const ManifestEntryInfo$json = {
  '1': 'ManifestEntryInfo',
  '2': [
    {'1': 'effective_name', '3': 1, '4': 1, '5': 9, '10': 'effectiveName'},
    {'1': 'path', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'path', '17': true},
    {'1': 'size', '3': 3, '4': 1, '5': 4, '9': 1, '10': 'size', '17': true},
    {'1': 'kind', '3': 4, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'content_address', '3': 5, '4': 1, '5': 9, '10': 'contentAddress'},
    {'1': 'data_map', '3': 6, '4': 1, '5': 9, '10': 'dataMap'},
    {'1': 'exact_size', '3': 7, '4': 1, '5': 4, '9': 2, '10': 'exactSize', '17': true},
    {'1': 'error', '3': 8, '4': 1, '5': 9, '10': 'error'},
    {'1': 'sha256', '3': 9, '4': 1, '5': 9, '10': 'sha256'},
  ],
  '8': [
    {'1': '_path'},
    {'1': '_size'},
    {'1': '_exact_size'},
  ],
};

/// Descriptor for `ManifestEntryInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List manifestEntryInfoDescriptor = $convert.base64Decode(
    'ChFNYW5pZmVzdEVudHJ5SW5mbxIlCg5lZmZlY3RpdmVfbmFtZRgBIAEoCVINZWZmZWN0aXZlTm'
    'FtZRIXCgRwYXRoGAIgASgJSABSBHBhdGiIAQESFwoEc2l6ZRgDIAEoBEgBUgRzaXpliAEBEhIK'
    'BGtpbmQYBCABKAlSBGtpbmQSJwoPY29udGVudF9hZGRyZXNzGAUgASgJUg5jb250ZW50QWRkcm'
    'VzcxIZCghkYXRhX21hcBgGIAEoCVIHZGF0YU1hcBIiCgpleGFjdF9zaXplGAcgASgESAJSCWV4'
    'YWN0U2l6ZYgBARIUCgVlcnJvchgIIAEoCVIFZXJyb3ISFgoGc2hhMjU2GAkgASgJUgZzaGEyNT'
    'ZCBwoFX3BhdGhCBwoFX3NpemVCDQoLX2V4YWN0X3NpemU=');

@$core.Deprecated('Use buildManifestResponseDescriptor instead')
const BuildManifestResponse$json = {
  '1': 'BuildManifestResponse',
  '2': [
    {'1': 'manifest', '3': 1, '4': 1, '5': 12, '10': 'manifest'},
    {'1': 'link', '3': 2, '4': 1, '5': 9, '10': 'link'},
    {'1': 'entries', '3': 3, '4': 3, '5': 11, '6': '.antd.v1.ManifestEntryInfo', '10': 'entries'},
  ],
};

/// Descriptor for `BuildManifestResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List buildManifestResponseDescriptor = $convert.base64Decode(
    'ChVCdWlsZE1hbmlmZXN0UmVzcG9uc2USGgoIbWFuaWZlc3QYASABKAxSCG1hbmlmZXN0EhIKBG'
    'xpbmsYAiABKAlSBGxpbmsSNAoHZW50cmllcxgDIAMoCzIaLmFudGQudjEuTWFuaWZlc3RFbnRy'
    'eUluZm9SB2VudHJpZXM=');

@$core.Deprecated('Use decodeManifestRequestDescriptor instead')
const DecodeManifestRequest$json = {
  '1': 'DecodeManifestRequest',
  '2': [
    {'1': 'manifest', '3': 1, '4': 1, '5': 12, '9': 0, '10': 'manifest'},
    {'1': 'link', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'link'},
    {'1': 'resolve', '3': 3, '4': 1, '5': 8, '10': 'resolve'},
  ],
  '8': [
    {'1': 'input'},
  ],
};

/// Descriptor for `DecodeManifestRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List decodeManifestRequestDescriptor = $convert.base64Decode(
    'ChVEZWNvZGVNYW5pZmVzdFJlcXVlc3QSHAoIbWFuaWZlc3QYASABKAxIAFIIbWFuaWZlc3QSFA'
    'oEbGluaxgCIAEoCUgAUgRsaW5rEhgKB3Jlc29sdmUYAyABKAhSB3Jlc29sdmVCBwoFaW5wdXQ=');

@$core.Deprecated('Use decodeManifestResponseDescriptor instead')
const DecodeManifestResponse$json = {
  '1': 'DecodeManifestResponse',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {'1': 'torrent_info_hash_v1', '3': 3, '4': 1, '5': 9, '10': 'torrentInfoHashV1'},
    {'1': 'torrent_info_hash_v2', '3': 4, '4': 1, '5': 9, '10': 'torrentInfoHashV2'},
    {'1': 'entries', '3': 5, '4': 3, '5': 11, '6': '.antd.v1.ManifestEntryInfo', '10': 'entries'},
  ],
  '8': [
    {'1': '_name'},
  ],
};

/// Descriptor for `DecodeManifestResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List decodeManifestResponseDescriptor = $convert.base64Decode(
    'ChZEZWNvZGVNYW5pZmVzdFJlc3BvbnNlEhYKBnNvdXJjZRgBIAEoCVIGc291cmNlEhcKBG5hbW'
    'UYAiABKAlIAFIEbmFtZYgBARIvChR0b3JyZW50X2luZm9faGFzaF92MRgDIAEoCVIRdG9ycmVu'
    'dEluZm9IYXNoVjESLwoUdG9ycmVudF9pbmZvX2hhc2hfdjIYBCABKAlSEXRvcnJlbnRJbmZvSG'
    'FzaFYyEjQKB2VudHJpZXMYBSADKAsyGi5hbnRkLnYxLk1hbmlmZXN0RW50cnlJbmZvUgdlbnRy'
    'aWVzQgcKBV9uYW1l');

