# Dart Quickstart

A comprehensive guide to using the Autonomi network with the Dart SDK.

## Setup

```bash
# Add the dependency
dart pub add antd

# Or add to pubspec.yaml:
# dependencies:
#   antd: ^0.1.0

# Start local testnet
ant dev start
```

## Connecting

```dart
import 'package:antd/antd.dart';

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

// Upload a directory
final dirResult = await client.dirUploadPublic('/path/to/directory');

// Download a directory
await client.dirDownloadPublic(dirResult.address, '/path/to/output_dir');

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
final est = await client.fileCost('/path/to/file.txt');
```


## Error Handling

```dart
import 'package:antd/antd.dart';

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

## Examples

```bash
# Run individual examples
ant dev example connect -l dart
ant dev example data -l dart
ant dev example all -l dart

# Or directly
dart run antd-dart/examples/01_connect.dart
dart run antd-dart/examples/02_data.dart
```

See `antd-dart/examples/` for the complete set of examples.
