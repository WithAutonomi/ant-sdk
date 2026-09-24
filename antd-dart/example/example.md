# antd_client examples

Each script is a standalone `main()` that talks to a running antd daemon
(default `http://localhost:8082` for REST, `localhost:50051` for gRPC).
Start one with `ant dev start`, then:

```bash
dart run example/01_connect.dart
```

| Script | Shows |
|---|---|
| [`01_connect.dart`](01_connect.dart) | Connect and check daemon health |
| [`02_data.dart`](02_data.dart) | Public data put/get and cost estimation |
| [`03_chunks.dart`](03_chunks.dart) | Raw chunk put/get |
| [`04_files.dart`](04_files.dart) | Public file upload and download |
| [`06_private_data.dart`](06_private_data.dart) | Private (self-encrypted) data put/get |
| [`07_external_signer.dart`](07_external_signer.dart) | Prepare, pay with your own wallet, finalize |

Minimal REST usage:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';

void main() async {
  final client = AntdClient();
  try {
    final health = await client.health();
    print('OK: ${health.ok}, network: ${health.network}');

    final result = await client.dataPutPublic(
      Uint8List.fromList(utf8.encode('Hello, Autonomi!')),
    );
    print('Stored at ${result.address}');

    final data = await client.dataGetPublic(result.address);
    print(utf8.decode(data));
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
```
