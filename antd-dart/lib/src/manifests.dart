// Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
// of files, each with an optional path and size and either an embedded
// DataMap or a public DataMap address. The daemon builds and decodes them
// through ant-core, so callers never re-implement the format. Nothing is
// uploaded or paid for (V2-1580).
//
// The `.ant` bytes are always raw bytes here: REST carries them as base64 in
// JSON and gRPC as `bytes`, and the clients convert.

import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';

/// One file for [AntdClient.buildManifest]. Set exactly one of [dataMap] or
/// [address]; the clients reject an entry with both or neither before
/// sending anything.
class ManifestEntryInput {
  /// The relative path the entry extracts under, subject to the portable
  /// path rules. `null` (or empty): it extracts under its content address.
  final String? path;

  /// The plaintext size to record, as given (the creator's claim). `null`:
  /// none is recorded; readers take the exact size from an embedded root
  /// DataMap.
  final int? size;

  /// A hex DataMap, as the upload methods return it. The entry embeds it:
  /// the manifest is the key to the file.
  final String? dataMap;

  /// A public file's DataMap address (hex, 32 bytes).
  final String? address;

  /// The plaintext's SHA-256 to record, hex (the creator's claim), passed
  /// to the daemon as given. `null` or empty: none is recorded and the key
  /// is omitted. Requires antd 0.17.0 or later.
  final String? sha256;

  const ManifestEntryInput({
    this.path,
    this.size,
    this.dataMap,
    this.address,
    this.sha256,
  });

  /// The REST wire form: unset fields are omitted.
  Map<String, dynamic> toJson() => {
        if (path?.isNotEmpty ?? false) 'path': path,
        if (size != null) 'size': size,
        if (dataMap?.isNotEmpty ?? false)
          'data_map': dataMap
        else
          'address': address,
        if (sha256?.isNotEmpty ?? false) 'sha256': sha256,
      };

  @override
  String toString() => 'ManifestEntryInput(path: $path, size: $size, '
      'dataMap: $dataMap, address: $address, sha256: $sha256)';
}

/// The daemon's message for a decode with neither bytes nor a link.
const manifestDecodeEmptyMessage =
    'needs a manifest (base64 .ant bytes) or a link';

/// Rejects, before anything is sent, every entry with both or neither of
/// `dataMap` and `address` (an empty string counts as unset, as it does for
/// the daemon), or a negative size. Throws a [BadRequestError] (400) whose
/// message is the daemon's own wording, so a refusal here and the daemon's
/// 400 for the same mistake are indistinguishable: every bad entry is
/// listed, at most 20, as `entries[i]: ...`.
void checkManifestEntries(List<ManifestEntryInput> entries) {
  const maxReported = 20;
  final errors = <String>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final hasDataMap = e.dataMap?.isNotEmpty ?? false;
    final hasAddress = e.address?.isNotEmpty ?? false;
    if (hasDataMap && hasAddress) {
      errors.add('entries[$i]: give data_map or address, not both');
    } else if (!hasDataMap && !hasAddress) {
      errors.add('entries[$i]: needs a data_map or an address');
    } else if ((e.size ?? 0) < 0) {
      errors.add('entries[$i]: size must not be negative');
    }
  }
  if (errors.isEmpty) return;
  final shown = errors.take(maxReported).join('; ');
  throw BadRequestError(errors.length > maxReported
      ? '${errors.length} invalid entries: $shown; '
          'and ${errors.length - maxReported} more'
      : '${errors.length} invalid entries: $shown');
}

/// What a manifest says about one entry.
class ManifestEntryInfo {
  /// [path], or the content address in hex when there is none.
  final String effectiveName;

  /// The entry's path, or `null` when it has none.
  final String? path;

  /// The size recorded in the manifest: the creator's claim. `null` when
  /// none was recorded (never 0 for "unset").
  final int? size;

  /// `"embedded"` or `"public"`.
  final String kind;

  /// Hex. The file's public DataMap address, whether or not it was ever
  /// made public; the same for private and public uploads of one file.
  final String contentAddress;

  /// The embedded DataMap in the hex form the download methods accept.
  /// Decode only: `null` for public entries and on build.
  final String? dataMap;

  /// The exact plaintext size: from an embedded root DataMap, or after a
  /// resolving decode. `null` when unknown (never 0 for "unset").
  final int? exactSize;

  /// Why a resolving decode failed for this entry; `null` when it did not.
  /// One entry's failure is reported here, not as a failed call.
  final String? error;

  /// The plaintext's SHA-256 recorded in the manifest, lowercase hex: the
  /// creator's claim. `null` when none was recorded. Requires antd 0.17.0
  /// or later.
  final String? sha256;

  const ManifestEntryInfo({
    required this.effectiveName,
    this.path,
    this.size,
    required this.kind,
    required this.contentAddress,
    this.dataMap,
    this.exactSize,
    this.error,
    this.sha256,
  });

  /// The REST wire form, where unset fields are omitted (or `null`).
  factory ManifestEntryInfo.fromJson(Map<String, dynamic> json) {
    return ManifestEntryInfo(
      effectiveName: json['effective_name'] as String? ?? '',
      path: _nonEmpty(json['path']),
      size: (json['size'] as num?)?.toInt(),
      kind: json['kind'] as String? ?? '',
      contentAddress: json['content_address'] as String? ?? '',
      dataMap: _nonEmpty(json['data_map']),
      exactSize: (json['exact_size'] as num?)?.toInt(),
      error: _nonEmpty(json['error']),
      sha256: _nonEmpty(json['sha256']),
    );
  }

  @override
  String toString() => 'ManifestEntryInfo(effectiveName: $effectiveName, '
      'path: $path, size: $size, kind: $kind, '
      'contentAddress: $contentAddress, exactSize: $exactSize, '
      'error: $error, sha256: $sha256)';
}

/// The result of [AntdClient.buildManifest].
class BuiltManifest {
  /// The `.ant` bytes.
  final Uint8List manifest;

  /// The `ant://manifest/` link, or `null` when it does not fit the
  /// recommended 1,500 bytes.
  final String? link;

  /// In encoded order (sorted by effective name).
  final List<ManifestEntryInfo> entries;

  const BuiltManifest({
    required this.manifest,
    this.link,
    required this.entries,
  });

  /// The REST wire form, which carries [manifest] as base64. Malformed
  /// base64 throws [InternalError].
  factory BuiltManifest.fromJson(Map<String, dynamic> json) {
    final Uint8List manifest;
    try {
      manifest = base64.decode(json['manifest'] as String? ?? '');
    } on FormatException catch (e) {
      throw InternalError('manifest is not valid base64: ${e.message}');
    }
    return BuiltManifest(
      manifest: manifest,
      link: _nonEmpty(json['link']),
      entries: _entries(json['entries']),
    );
  }

  @override
  String toString() => 'BuiltManifest(${manifest.length} bytes, '
      'link: $link, entries: $entries)';
}

/// The result of [AntdClient.decodeManifest] and
/// [AntdClient.decodeManifestLink].
class DecodedManifest {
  /// `"manifest"`, or `"file_link"` for a file link or bare address
  /// (reported as one public entry with no path).
  final String source;

  /// The suggested root directory name, or `null` when there is none.
  final String? name;

  /// The BitTorrent v1 info hash (hex), or `null` when absent.
  final String? torrentInfoHashV1;

  /// The BitTorrent v2 info hash (hex), or `null` when absent.
  final String? torrentInfoHashV2;

  /// In encoded order (sorted by effective name).
  final List<ManifestEntryInfo> entries;

  const DecodedManifest({
    required this.source,
    this.name,
    this.torrentInfoHashV1,
    this.torrentInfoHashV2,
    required this.entries,
  });

  /// The REST wire form, where unset fields are omitted.
  factory DecodedManifest.fromJson(Map<String, dynamic> json) {
    return DecodedManifest(
      source: json['source'] as String? ?? '',
      name: _nonEmpty(json['name']),
      torrentInfoHashV1: _nonEmpty(json['torrent_info_hash_v1']),
      torrentInfoHashV2: _nonEmpty(json['torrent_info_hash_v2']),
      entries: _entries(json['entries']),
    );
  }

  @override
  String toString() => 'DecodedManifest(source: $source, name: $name, '
      'torrentInfoHashV1: $torrentInfoHashV1, '
      'torrentInfoHashV2: $torrentInfoHashV2, entries: $entries)';
}

String? _nonEmpty(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

List<ManifestEntryInfo> _entries(Object? raw) => [
      if (raw is List)
        for (final e in raw)
          if (e is Map<String, dynamic>) ManifestEntryInfo.fromJson(e),
    ];
