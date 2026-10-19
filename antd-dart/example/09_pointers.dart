// Example 09: Pointers — a mutable reference to public data.
//
// Uploads two small pieces of public data, creates a pointer at the first,
// updates it to the second, reads it back and prints its finality.
//
// The daemon signs with the owner keys it loaded at startup
// (`antd --pointer-keys <file-or-dir>`); set ANTD_POINTER_OWNER to the
// address of one of them (`GET /v1/pointers/keys` lists them). Set
// ANTD_BASE_URL to reach a daemon other than http://localhost:8082.
//
// Every pointer write pays, about the price of one chunk, and every attempt
// pays again, so the example never retries a write.
//
//   ANTD_POINTER_OWNER=<hex> dart run example/09_pointers.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';

Future<void> main() async {
  final owner = Platform.environment['ANTD_POINTER_OWNER'];
  if (owner == null || owner.isEmpty) {
    stderr.writeln('Set ANTD_POINTER_OWNER to a pointer address the daemon '
        'holds a key for.');
    exitCode = 2;
    return;
  }
  final baseUrl = Platform.environment['ANTD_BASE_URL'];
  final client = baseUrl == null ? AntdClient() : AntdClient(baseUrl: baseUrl);

  try {
    // 1. Two pieces of public data to point at.
    final first = await client.dataPutPublic(
        Uint8List.fromList(utf8.encode('pointer target, version 1')));
    final second = await client.dataPutPublic(
        Uint8List.fromList(utf8.encode('pointer target, version 2')));
    print('Uploaded ${first.address} and ${second.address}');

    // 2. Create the pointer at the first. A pointer that already exists is
    // refused before anything is paid, so a re-run goes on to the update.
    try {
      final created = await client.pointerCreate(owner, first.address);
      print('Created pointer ${created.address} '
          '(counter ${created.counter})');
    } on AlreadyExistsError {
      print('Pointer $owner already exists; updating it instead');
    }

    // 3. Point it at the second.
    final updated = await client.pointerUpdate(owner, second.address);
    print('Updated pointer to ${second.address} '
        '(counter ${updated.counter})');

    // 4. Read it back, and follow it to the data.
    final record = await client.pointerGet(owner);
    print('Pointer ${record.address}: target ${record.target}, '
        'kind ${record.kind}, counter ${record.counter}, '
        'final ${record.isFinal}');
    final resolved = await client.pointerResolve(owner);
    final data = await client.dataGetPublic(resolved.target);
    print('Resolves to ${resolved.target}: "${utf8.decode(data)}"');

    // 5. Where the close group says it stands.
    final finality = await client.pointerFinality(owner);
    print('Finality: ${finality.status} '
        '(${finality.answered}/${finality.group} peers answered, '
        'counter ${finality.counter})');
  } on AntdError catch (e) {
    print('Error: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
