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

// Store data
let result = try await client.dataPutPublic("Hello, Autonomi!".data(using: .utf8)!)
print("Address: \(result.address)")
print("Cost: \(result.cost) atto tokens")

// Retrieve data
let data = try await client.dataGetPublic(address: result.address)
print(String(data: data, encoding: .utf8)!) // "Hello, Autonomi!"
```

## Transport Options

```swift
// REST (default, recommended)
let restClient = AntdClient.createRest(baseURL: "http://localhost:8082")

// gRPC (requires generated proto stubs)
let grpcClient = AntdClient.createGrpc(target: "localhost:50051")

// Dynamic transport selection
let client = AntdClient.create(transport: "rest") // or "grpc"
```

## API Surface

All methods are `async throws` for use with Swift concurrency.

| Domain | Methods |
|---|---|
| **Health** | `health()` |
| **Data** | `dataPutPublic`, `dataGetPublic`, `dataPutPrivate`, `dataGetPrivate`, `dataCost` |
| **Chunks** | `chunkPut`, `chunkGet` |
| **Files** | `fileUploadPublic`, `fileDownloadPublic`, `dirUploadPublic`, `dirDownloadPublic`, `fileCost` |

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
│       └── Main.swift                # 6 runnable examples
└── Tests/
    └── AntdSdkTests/
        └── SmokeTests.swift
```
