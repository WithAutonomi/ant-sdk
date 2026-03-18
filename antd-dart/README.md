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

    // Store data
    final result = await client.dataPutPublic(
      Uint8List.fromList(utf8.encode('Hello, Autonomi!')),
    );
    print('Stored at ${result.address} (cost: ${result.cost} atto)');

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

## gRPC Transport

The SDK includes a `GrpcAntdClient` class that provides the same 19 async
methods as the REST `AntdClient`, but communicates over gRPC.

### Setup

Add the gRPC dependencies (already included in `pubspec.yaml`):

```yaml
dependencies:
  grpc: ^4.0.1
  protobuf: ^3.1.0
```

Generate the Dart protobuf/gRPC stubs from the proto definitions:

```bash
# Install the Dart protoc plugin
dart pub global activate protoc_plugin

# Generate stubs into lib/src/generated/
protoc --dart_out=grpc:lib/src/generated \
  -I../../antd/proto \
  antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
  antd/v1/chunks.proto antd/v1/graph.proto antd/v1/files.proto
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

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```dart
// Default: http://localhost:8080, 5 minute timeout
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

### Health
| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `dataPutPublic(data)` | Store public data |
| `dataGetPublic(address)` | Retrieve public data |
| `dataPutPrivate(data)` | Store encrypted private data |
| `dataGetPrivate(dataMap)` | Retrieve private data |
| `dataCost(data)` | Estimate storage cost |

### Chunks
| Method | Description |
|--------|-------------|
| `chunkPut(data)` | Store a raw chunk |
| `chunkGet(address)` | Retrieve a chunk |

### Graph Entries (DAG Nodes)
| Method | Description |
|--------|-------------|
| `graphEntryPut(secretKey, parents, content, descendants)` | Create entry |
| `graphEntryGet(address)` | Read entry |
| `graphEntryExists(address)` | Check if exists |
| `graphEntryCost(publicKey)` | Estimate creation cost |

### Files & Directories
| Method | Description |
|--------|-------------|
| `fileUploadPublic(path)` | Upload a file |
| `fileDownloadPublic(address, destPath)` | Download a file |
| `dirUploadPublic(path)` | Upload a directory |
| `dirDownloadPublic(address, destPath)` | Download a directory |
| `archiveGetPublic(address)` | Get archive manifest |
| `archivePutPublic(archive)` | Create archive manifest |
| `fileCost(path, {isPublic, includeArchive})` | Estimate upload cost |

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
- `04_files` — File and directory upload/download
- `05_graph` — Graph entry (DAG node) operations
- `06_private_data` — Private encrypted data storage
