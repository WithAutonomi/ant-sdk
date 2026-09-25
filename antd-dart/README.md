# antd_client (antd-dart)

Dart SDK for the [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon — the gateway to the Autonomi decentralized network.

Published on pub.dev as [`antd_client`](https://pub.dev/packages/antd_client).

## Installation

```bash
dart pub add antd_client
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  antd_client: ^0.1.0
```

## Compatibility

This package talks to a running antd daemon; it does not join the network itself. Dart 3.0+. Tested against antd 0.13.x; the `PartialUploadError.retryable` flag is sent by antd 0.14.0 and later (older daemons report `false`). Both the REST client (`AntdClient`) and the gRPC client (`GrpcAntdClient`) are included; the gRPC stubs are pre-generated, so `protoc` is only needed if you regenerate them.

## Quick Start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';

void main() async {
  final client = AntdClient();

  try {
    // Check daemon health
    final health = await client.health();
    print('OK: ${health.ok}, Network: ${health.network}');

    // Store data
    final result = await client.dataPutPublic(
      Uint8List.fromList(utf8.encode('Hello, Autonomi!')),
    );
    print('Stored at ${result.address} (chunks: ${result.chunksStored})');

    // Retrieve data
    final data = await client.dataGetPublic(result.address);
    print('Retrieved: ${utf8.decode(data)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
```

## Payment Mode

All `*put*` and `*cost*` operations accept a `PaymentMode` parameter that
controls how on-chain payments for stored chunks are bundled:

| Mode | Behavior |
|---|---|
| `PaymentMode.auto` (default) | Daemon picks merkle for large uploads, single for small. |
| `PaymentMode.merkle` | One on-chain transaction with a merkle proof covering all chunks. Cheaper for large uploads. Requires ≥2 chunks. |
| `PaymentMode.single` | N transactions, one per chunk. Works for any chunk count. |

```dart
final result = await client.filePut('/tmp/big.bin', paymentMode: PaymentMode.merkle);
```

## gRPC Transport

The SDK includes a `GrpcAntdClient` class that provides the same async
methods as the REST `AntdClient`, but communicates over gRPC.

### Setup

Add the gRPC dependencies (already included in `pubspec.yaml`):

```yaml
dependencies:
  grpc: ^4.0.1
  protobuf: ^4.1.0
```

Generate the Dart protobuf/gRPC stubs from the proto definitions:

```bash
# Install the Dart protoc plugin (pin to 22.x — newer plugins emit code
# targeting protobuf 6+, which conflicts with web3dart's transitive deps).
dart pub global activate protoc_plugin 22.3.0

# Generate stubs into lib/src/generated/
./tool/generate_proto.sh
```

### Usage

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/src/grpc_client.dart';

void main() async {
  final client = GrpcAntdClient.withChannel();

  // Or custom host/port:
  // final client = GrpcAntdClient(host: 'my-host', port: 50051);

  try {
    final health = await client.health();
    print('OK: ${health.ok}, Network: ${health.network}');

    final result = await client.dataPutPublic(
      Uint8List.fromList(utf8.encode('Hello via gRPC!')),
    );
    print('Stored at ${result.address}');

    final data = await client.dataGetPublic(result.address);
    print('Retrieved: ${utf8.decode(data)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    await client.close();
  }
}
```

The `GrpcAntdClient` throws the same `AntdError` hierarchy as the REST client,
translating gRPC status codes to the appropriate error subclass.

> **Note:** Wallet operations (address, balance, approve) are REST-only. The gRPC `PutDataResponse` / `PutPublicDataResponse` messages only carry the address/dataMap; `chunksStored` / `paymentModeUsed` are populated by REST only.

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```dart
// Default: http://localhost:8082, 5 minute timeout
final client = AntdClient();

// Custom URL
final client = AntdClient(baseUrl: 'http://custom-host:9090');

// Custom timeout
final client = AntdClient(timeout: Duration(seconds: 30));

// Custom HTTP client (e.g. for testing)
final client = AntdClient(httpClient: myHttpClient);
```

## API Reference

All methods return `Future<T>` and can throw `AntdError` subclasses.

The unqualified verb (`dataPut`, `filePut`, `dataGet`, `fileGet`) is the
**private** variant — DataMaps are returned to the caller and not stored
on-network. The `*Public` variants store the DataMap on-network and return
a shareable address.

### Health
| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data
| Method | Description |
|--------|-------------|
| `dataPutPublic(data, {paymentMode})` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `dataGetPublic(address)` | Retrieve public data by address |
| `dataPut(data, {paymentMode})` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `dataGet(dataMap)` | Retrieve private data using a caller-held DataMap |
| `dataCost(data, {paymentMode})` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks
| Method | Description |
|--------|-------------|
| `chunkPut(data)` | Store a raw chunk |
| `chunkGet(address)` | Retrieve a chunk |
| `prepareChunkUpload(data)` | External-signer prepare step |
| `finalizeChunkUpload(uploadId, txHashes)` | External-signer finalize step |

### Files
| Method | Description |
|--------|-------------|
| `filePut(path, {paymentMode})` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `fileGet(dataMap, destPath)` | Download a private file using a caller-held DataMap |
| `filePutPublic(path, {paymentMode})` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `fileGetPublic(address, destPath)` | Download a public file by address |
| `fileCost(path, {isPublic, paymentMode})` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

## Error Handling

All errors extend `AntdError` which implements `Exception`:

```dart
try {
  final data = await client.dataGetPublic(address);
} on NotFoundError catch (e) {
  print('Data not found on network');
} on PaymentError catch (e) {
  print('Insufficient funds');
} on AntdError catch (e) {
  print('Error ${e.statusCode}: ${e.message}');
}
```

| Error Type | HTTP Status | When |
|-----------|-------------|------|
| `BadRequestError` | 400 | Invalid parameters |
| `PaymentError` | 402 | Insufficient funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource exists |
| `ForkError` | 409 | Version conflict |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |
| `PartialUploadError` | 502 (`code: PARTIAL_UPLOAD`) | Finalize stored some chunks, others stayed unstored — see below |

### Partial uploads

A `finalizeUpload` / `finalizeMerkleUpload` / `finalizeChunkUpload` call can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. That is a `PartialUploadError` (a `NetworkError` subclass, so existing `on NetworkError` clauses still catch it) carrying `chunksStored`, `chunksFailed`, `totalChunks` and a `retryable` flag. The on-chain payment persists and the stored chunks stay on the network.

- **`retryable == true`** (antd ≥ 0.14.0) — the daemon kept the paid attempt under the same `upload_id`. Call the **same** finalize method again with the same arguments to store the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound that loop — a persistent failure throws this error on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retryable == false`** — nothing was retained (a merkle finalize with deliberately unpaid batches, or an older daemon that never sends the flag). Re-preparing the same content skips already-stored chunks, so a retry pays only for the remainder.

```dart
try {
  await client.finalizeUpload(uploadId, txHashes);
} on PartialUploadError catch (e) {
  if (e.retryable) {
    // same upload_id, same payment — see finalizeWithRetry in example/07_external_signer.dart
  } else {
    // re-prepare the same content; only the remainder is paid for
  }
}
```

Over gRPC the error arrives as status `ABORTED` whose message starts with `Partial upload:`; the counts and the flag are parsed from that message, and `retryable` is `true` only when all three counts parse and the `paid attempt retained` hint is present (otherwise the counts read as zero and the flag as `false`). Any other `ABORTED` is not a partial upload and surfaces as a plain `AntdError`. See `finalizeWithRetry` in [`example/07_external_signer.dart`](example/07_external_signer.dart) for a bounded retry loop and [`docs/external-signer-flow.md`](../docs/external-signer-flow.md) §6 for the daemon contract.

## Examples

See the [example/](example/) directory:

- `01_connect` — Health check
- `02_data` — Public data storage and retrieval
- `03_chunks` — Raw chunk operations
- `04_files` — File upload/download (public)
- `06_private_data` — Private encrypted data storage
- `07_external_signer` — File + chunk upload via external signer
