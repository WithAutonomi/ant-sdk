# antd-swift

Swift SDK for the [Autonomi](https://autonomi.com) decentralized network. Talks to the **antd** daemon via REST or gRPC.

> **Platform note:** The REST/gRPC SDK requires a locally-running `antd` daemon and is designed for **macOS** applications. For iOS apps, use the [FFI bindings](../ffi/) which embed the Autonomi client directly — no daemon needed.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/example/antd-swift.git", from: "0.1.0"),
]
```

> **Note**: Until published, use as a local package dependency.

## Prerequisites

- Swift 5.9+ / Xcode 15+
- macOS 13+ (for REST/gRPC client)
- A running `antd` daemon (see [ant-sdk README](../README.md))

## Quick Start

```swift
import AntdSdk

let client = AntdClient.createRest()

// Check health
let status = try await client.health()
print("Network: \(status.network)")

// Store data publicly (shareable address)
let payload = "Hello, Autonomi!".data(using: .utf8)!
let result = try await client.dataPutPublic(payload, paymentMode: .auto)
print("Address: \(result.address)")
print("Chunks stored: \(result.chunksStored), mode: \(result.paymentModeUsed)")

// Retrieve data
let data = try await client.dataGetPublic(address: result.address)
print(String(data: data, encoding: .utf8)!) // "Hello, Autonomi!"
```

## Transport Options

```swift
// REST (default, recommended)
let restClient = AntdClient.createRest(baseURL: "http://localhost:8082")

// gRPC (requires generated proto stubs; wallet operations are REST-only)
let grpcClient = AntdClient.createGrpc(target: "localhost:50051")

// Dynamic transport selection
let client = AntdClient.create(transport: "rest") // or "grpc"
```

## Payment Mode

All `*put*` and `*cost*` operations take a `PaymentMode` parameter that controls how on-chain payments for stored chunks are bundled:

| Mode | Behavior |
|---|---|
| `.auto` (default) | Daemon picks merkle for large uploads, single for small. |
| `.merkle` | One on-chain transaction with a merkle proof covering all chunks. Cheaper for large uploads. Requires ≥2 chunks. |
| `.single` | N transactions, one per chunk. Works for any chunk count. |

```swift
let result = try await client.filePut(path: "/tmp/big.bin", paymentMode: .merkle)
```

## API Surface

All methods are `async throws` for use with Swift concurrency.

| Domain | Methods |
|---|---|
| **Health** | `health()` |
| **Data** | `dataPut`, `dataGet`, `dataPutPublic`, `dataGetPublic`, `dataCost` |
| **Chunks** | `chunkPut`, `chunkGet`, `prepareChunkUpload`, `finalizeChunkUpload` |
| **Files** | `filePut`, `fileGet`, `filePutPublic`, `fileGetPublic`, `fileCost` |
| **Wallet** | `walletAddress`, `walletBalance`, `walletApprove` |
| **External Signer** | `prepareUpload`, `prepareUploadPublic`, `prepareDataUpload`, `finalizeUpload`, `finalizeMerkleUpload` |

The unqualified verb (`dataPut`, `filePut`, `dataGet`, `fileGet`) is the **private** variant — DataMaps are returned to the caller and not stored on-network. The `*Public` variants store the DataMap on-network and return a shareable address.

## Error Handling

All errors extend `AntdError` with a `statusCode` property:

```swift
do {
    let data = try await client.dataGetPublic(address: "nonexistent")
} catch let error as NotFoundError {
    print("Not found: \(error.message)")
} catch let error as PaymentError {
    print("Payment required: \(error.message)")
} catch let error as AntdError {
    print("Error (\(error.statusCode)): \(error.message)")
}
```

| Error | HTTP | gRPC | Description |
|---|---|---|---|
| `NotFoundError` | 404 | NOT_FOUND | Resource not found |
| `AlreadyExistsError` | 409 | ALREADY_EXISTS | Resource already exists |
| `ForkError` | 409 | ABORTED | Conflicting update |
| `BadRequestError` | 400 | INVALID_ARGUMENT | Invalid input |
| `PaymentError` | 402 | FAILED_PRECONDITION | Insufficient funds |
| `NetworkError` | 502 | UNAVAILABLE | Network unreachable |
| `TooLargeError` | 413 | RESOURCE_EXHAUSTED | Data too large |
| `InternalError` | 500 | INTERNAL | Server error |

## Examples

```bash
swift run AntdExamples 1      # Connect
swift run AntdExamples 2      # Public Data
swift run AntdExamples all    # All examples
```

## Building

```bash
swift build
swift test
swift run AntdExamples
```

## Project Structure

```
antd-swift/
├── Package.swift
├── Sources/
│   ├── AntdSdk/
│   │   ├── AntdClientProtocol.swift  # Client protocol
│   │   ├── AntdClient.swift          # Factory
│   │   ├── AntdRestClient.swift      # REST implementation
│   │   ├── AntdGrpcClient.swift      # gRPC implementation
│   │   ├── Models.swift              # Data types
│   │   └── Errors.swift              # Error hierarchy
│   └── AntdExamples/
│       └── Main.swift                # Runnable example
└── Tests/
    └── AntdSdkTests/
        └── SmokeTests.swift
```
