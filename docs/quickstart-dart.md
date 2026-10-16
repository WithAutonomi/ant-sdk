# Dart Quickstart

A comprehensive guide to using the Autonomi network with the Dart SDK.

## Setup

```bash
# Add the dependency
dart pub add antd_client

# Or add to pubspec.yaml:
# dependencies:
#   antd_client: ^0.1.0

# Start local testnet
ant dev start
```

## Connecting

```dart
import 'package:antd_client/antd_client.dart';

// REST transport (default)
final client = AntdClient();

// Custom endpoint
final client2 = AntdClient(transport: 'rest', baseUrl: 'http://localhost:8082');

// gRPC transport
final grpcClient = AntdClient(transport: 'grpc', target: 'localhost:50051');
```

All network methods are asynchronous and return `Future` values.

## Health Check

```dart
final status = await client.health();
print('Healthy: ${status.ok}');
print('Network: ${status.network}');  // "local", "default", or "alpha"
```

## Public Data

Store and retrieve arbitrary bytes on the network.

```dart
import 'dart:convert';

// Store
final result = await client.dataPutPublic(utf8.encode('Hello, Autonomi!'));
print('Address: ${result.address}');
print('Cost: ${result.cost} atto tokens');

// Retrieve
final data = await client.dataGetPublic(result.address);
print(utf8.decode(data));  // "Hello, Autonomi!"

// Cost estimation — returns size, chunks, gas, and payment mode
final est = await client.dataCost(utf8.encode('some data'));
print('Estimate: ${est.fileSize} bytes in ${est.chunkCount} chunks, ${est.cost} atto, gas ${est.estimatedGasCostWei} wei, mode ${est.paymentMode}');
```

## Private Data

Encrypted data -- only accessible with the data map.

```dart
// Store (self-encrypting)
final result = await client.dataPutPrivate(utf8.encode('secret message'));
final dataMap = result.address;  // Keep this secret!

// Retrieve (decrypt)
final data = await client.dataGetPrivate(dataMap);
print(utf8.decode(data));
```

## Files

```dart
// Upload a file
final result = await client.fileUploadPublic('/path/to/file.txt');
print('File address: ${result.address}');

// Download a file
await client.fileDownloadPublic(result.address, '/path/to/output.txt');

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
final est = await client.fileCost('/path/to/file.txt');
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```dart
final owner = (await client.pointerKeys()).first;   // a pointer antd can write

final v1 = await client.dataPutPublic(Uint8List.fromList(utf8.encode('version 1')));
final v2 = await client.dataPutPublic(Uint8List.fromList(utf8.encode('version 2')));

await client.pointerCreate(owner, v1.address);        // pays; counter 0
await client.pointerUpdate(owner, v2.address);        // pays again; counter 1
final target = await client.pointerResolve(owner);    // target.target == v2.address (free)

final finality = await client.pointerFinality(owner); // free
print(finality.isFinal);                              // false: the owner can still move it
```

Counters are `BigInt`s. `utf8` and `Uint8List` come from `dart:convert` and `dart:typed_data`. `pointerTransfer`, `pointerGet`, `pointerController`, `pointerPrepare` and `pointerFinalize` complete the set, on `GrpcAntdClient` too.

Runnable example: `antd-dart/example/09_pointers.dart`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-dart
ANTD_POINTER_OWNER=<address> dart run example/09_pointers.dart
```

## Error Handling

```dart
import 'package:antd_client/antd_client.dart';

try {
  await client.dataGetPublic('nonexistent');
} on NotFoundException {
  print('Not found');
} on PaymentException {
  print('Payment issue');
} on NetworkException {
  print('Network unreachable');
} on AntdException catch (e) {
  print('Error (${e.statusCode}): ${e.message}');
}
```

Exception hierarchy:

| Exception | HTTP Code | When |
|-----------|-----------|------|
| `BadRequestException` | 400 | Invalid parameters |
| `PaymentException` | 402 | Insufficient funds |
| `NotFoundException` | 404 | Resource not found |
| `AlreadyExistsException` | 409 | Duplicate creation |
| `ForkException` | 409 | Version conflict |
| `TooLargeException` | 413 | Payload too large |
| `InternalException` | 500 | Server error |
| `NetworkException` | 502 | Network unreachable |

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```dart
final one = await client.dataPutPublic(Uint8List.fromList(utf8.encode('one')));   // pays
final two = await client.dataPutPublic(Uint8List.fromList(utf8.encode('two')));   // pays

final built = await client.buildManifest([                                        // free
  ManifestEntryInput(path: 'notes/one.txt', address: one.address),
  ManifestEntryInput(path: 'notes/two.txt', address: two.address),
], name: 'example');
print(built.link);                                // null when over 1,500 bytes: share built.manifest instead

final decoded = await client.decodeManifestLink(built.link!, resolve: true);      // free
for (final e in decoded.entries) {
  print('${e.effectiveName}: ${e.exactSize ?? e.error}');
}
```

`decodeManifest(bytes, resolve: ...)` takes raw `.ant` bytes (`Uint8List`). Use `dataMap:` instead of `address:` for an embedded entry, and `embedRoots: false` to keep shrunk DataMaps as given.

Runnable example: `antd-dart/example/10_manifests.dart`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-dart
ANTD_BASE_URL=http://localhost:8082 dart run example/10_manifests.dart
```

## Examples

```bash
# Run individual examples
ant dev example connect -l dart
ant dev example data -l dart
ant dev example all -l dart

# Or directly
dart run antd-dart/example/01_connect.dart
dart run antd-dart/example/02_data.dart
```

See `antd-dart/example/` for the complete set of examples.
