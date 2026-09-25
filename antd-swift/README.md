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
print("Chunks stored: \(result.chunksStored)")

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
| **Data** | `dataPutPublic`, `dataGetPublic`, `dataPut`, `dataGet`, `dataCost`. Private `dataPut` returns a caller-held DataMap (NOT stored on-network); public `dataPutPublic` stores the DataMap on-network at the returned address. All puts and `dataCost` accept a `PaymentMode` parameter. |
| **Chunks** | `chunkPut`, `chunkGet` |
| **Files** | `filePut`, `fileGet`, `filePutPublic`, `fileGetPublic`, `fileCost`. Private variants return a caller-held DataMap (NOT stored on-network); public variants store the DataMap on-network at the returned address. All puts and `fileCost` accept a `PaymentMode` parameter. |

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
| `ForkError` | 409 | ABORTED (non-partial-upload) | Conflicting update |
| `BadRequestError` | 400 | INVALID_ARGUMENT | Invalid input |
| `PaymentError` | 402 | FAILED_PRECONDITION | Insufficient funds |
| `NetworkError` | 502 | UNAVAILABLE | Network unreachable |
| `PartialUploadError` | 502 (`code: "PARTIAL_UPLOAD"`) | ABORTED (message starts with `Partial upload:`) | Finalize stored some chunks but not all (see below) |
| `TooLargeError` | 413 | RESOURCE_EXHAUSTED | Data too large |
| `InternalError` | 500 | INTERNAL | Server error |

### Partial uploads (external-signer finalize)

A `finalizeUpload` / `finalizeMerkleUpload` where some chunks stayed unstored after the daemon's retries throws `PartialUploadError` with `chunksStored` / `chunksFailed` / `totalChunks` and a `retryable` flag. The on-chain payment persists and the stored chunks stay on the network:

- **`retryable == true`** (antd ≥ 0.14.0): the daemon kept the paid attempt under the same `uploadId`. Call the **same** finalize method again with the same arguments to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure throws `PartialUploadError` on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck.
- **`retryable == false`** (older daemon, or a merkle finalize with deliberately unpaid batches): nothing was retained. Re-preparing the same content skips already-stored chunks, so a retry pays only for the remainder.

Over REST the counts and the flag come from the structured error body (`retryable` is absent on daemons older than 0.14.0 and reads `false`). The counts must be JSON non-negative integers and `retryable` a JSON boolean: a body where any of them has another JSON type (a quoted `"1"` or `"true"`, a negative number, an array) is not trusted as a partial upload and keeps the status-based mapping, so a 502 stays a `NetworkError`. Over gRPC only an ABORTED status whose message *starts with* the daemon's fixed `Partial upload:` prefix is a partial upload; any other ABORTED, including one that mentions the prefix further in, stays a `ForkError`. The counts and the flag are parsed from that message, and `retryable` is `true` only when the counts parsed in full and the `paid attempt retained` hint is present; a message whose counts do not parse reads zero counts and `retryable == false`. Catch `PartialUploadError` *before* the generic `AntdError` clause:

```swift
var lastFailed: UInt64 = 0
for attempt in 1...5 {
    do {
        let result = try await client.finalizeUpload(uploadId: prep.uploadId, txHashes: txHashes)
        print("stored \(result.chunksStored) chunks")
        break                                   // every chunk stored — done
    } catch let partial as PartialUploadError where partial.retryable {
        if attempt == 5 || (attempt > 1 && partial.chunksFailed >= lastFailed) {
            throw partial                       // stuck: paid, partly stored — retry later or re-prepare
        }
        lastFailed = partial.chunksFailed
        try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)   // back off, then resume
    }
}
```

See `finalizeWithRetry` in `Sources/AntdExamples/Main.swift` and the contract in [`docs/external-signer-flow.md`](../docs/external-signer-flow.md) §6.

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
