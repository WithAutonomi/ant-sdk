# antd-dart

Dart SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  antd: ^0.1.0
```

Or install via command line:

```bash
dart pub add antd
```

## Quick Start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:antd/antd.dart';

void main() async {
  final client = AntdClient();

  try {
    // Check daemon health
    final health = await client.health();
    print('OK: ${health.ok}, Network: ${health.network}');

    // Store data publicly (shareable address)
    final payload = Uint8List.fromList(utf8.encode('Hello, Autonomi!'));
    final result = await client.dataPutPublic(payload, paymentMode: PaymentMode.auto);
    print('Stored at ${result.address}');
    print('  chunks: ${result.chunksStored}, mode: ${result.paymentModeUsed}');

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

import 'package:antd/src/grpc_client.dart';

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
| `dataPut(data, {paymentMode})` | Store encrypted private data — returns `DataPutResult { dataMap, chunksStored, paymentModeUsed }` |
| `dataGet(dataMap)` | Retrieve private data |
| `dataPutPublic(data, {paymentMode})` | Store public data — returns `DataPutPublicResult { address, chunksStored, paymentModeUsed }` |
| `dataGetPublic(address)` | Retrieve public data |
| `dataCost(data, {paymentMode})` | Estimate storage cost |

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
| `filePut(path, {paymentMode})` | Upload a private file — returns `FilePutResult { dataMap, ... }` |
| `fileGet(dataMap, destPath)` | Download a private file |
| `filePutPublic(path, {paymentMode})` | Upload a public file — returns `FilePutPublicResult { address, ... }` |
| `fileGetPublic(address, destPath)` | Download a public file |
| `fileCost(path, {isPublic, paymentMode})` | Estimate upload cost |

### Wallet
| Method | Description |
|--------|-------------|
| `walletAddress()` | Wallet address |
| `walletBalance()` | Token + gas balance |
| `walletApprove()` | One-time token approval |

### External Signer (Two-Phase Upload)
| Method | Description |
|--------|-------------|
| `prepareUpload(path, {visibility})` | Prepare file upload for external signer |
| `prepareUploadPublic(path)` | Convenience for public prepare |
| `prepareDataUpload(data, {visibility})` | Prepare data upload |
| `finalizeUpload(uploadId, txHashes)` | Wave-batch finalize |
| `finalizeMerkleUpload(uploadId, winnerPoolHash)` | Merkle finalize |

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

## Examples

See the [example/](example/) directory:

- `01_connect` — Health check
- `02_data` — Public data storage and retrieval
- `03_chunks` — Raw chunk operations
- `04_files` — File upload/download (public)
- `06_private_data` — Private encrypted data storage
- `07_external_signer` — File + chunk upload via external signer
