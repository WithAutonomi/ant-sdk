// Example 10: Manifests — one `ant://` link for a set of files (ADR-0006).
//
// Uploads two small pieces of public data, builds a manifest that names them
// notes/one.txt and notes/two.txt, prints its link and entries, then decodes
// the link, resolving each entry to its exact size.
//
// Building and decoding a manifest uploads and pays for nothing; only the two
// data uploads pay. Set ANTD_BASE_URL to reach a daemon other than
// http://localhost:8082.
//
//   dart run example/10_manifests.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';

Future<void> main() async {
  final baseUrl = Platform.environment['ANTD_BASE_URL'];
  final client = baseUrl == null || baseUrl.isEmpty
      ? AntdClient()
      : AntdClient(baseUrl: baseUrl);

  try {
    // 1. Two pieces of public data (these uploads pay).
    final one = await client.dataPutPublic(
        Uint8List.fromList(utf8.encode('First note, stored as public data.')));
    final two = await client.dataPutPublic(Uint8List.fromList(
        utf8.encode('Second note: a manifest names files and links them.')));
    print('Uploaded ${one.address} and ${two.address}');

    // 2. A manifest naming them (free: nothing is uploaded).
    final built = await client.buildManifest([
      ManifestEntryInput(path: 'notes/one.txt', address: one.address),
      ManifestEntryInput(path: 'notes/two.txt', address: two.address),
    ], name: 'example');
    print('Manifest: ${built.manifest.length} bytes');
    print('Link: ${built.link ?? '(too long for a link)'}');
    for (final e in built.entries) {
      print('  ${e.effectiveName} -> ${e.contentAddress}');
    }

    // 3. Decode the link, resolving each entry's DataMap for its exact size.
    final link = built.link;
    if (link == null) return;
    final decoded = await client.decodeManifestLink(link, resolve: true);
    print('Decoded "${decoded.name}" (${decoded.source}):');
    for (final e in decoded.entries) {
      final size = e.exactSize == null ? 'unknown' : '${e.exactSize} bytes';
      print('  ${e.effectiveName}: $size'
          '${e.error == null ? '' : ' (${e.error})'}');
    }
  } on AntdError catch (e) {
    print('Error: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
