# Swift Quickstart

A comprehensive guide to using the Autonomi network with the Swift SDK.

> **Platform note:** The REST/gRPC SDK requires a locally-running antd daemon and is designed for **macOS** applications. For **iOS** apps, use the [FFI bindings](../ffi/) which embed the Autonomi client directly — no daemon needed.

## Setup

```bash
# Prerequisites
# - Swift 5.9+ / Xcode 15+
# - macOS 13+
# - antd daemon running (ant dev start)

# Build the SDK
cd antd-swift
swift build
```

Add the SDK as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(path: "../antd-swift"),  // local path or published URL
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "AntdSdk", package: "antd-swift"),
        ]
    ),
]
```

Or scaffold a new project:

```bash
ant dev init swift --name my-project
```

## Connecting

```swift
import AntdSdk

// REST transport (default)
let client = try AntdClient.createRest()

// Custom endpoint
let client2 = try AntdClient.createRest(
    baseURL: URL(string: "http://localhost:8080")!,
    timeout: 30
)

// gRPC transport
let grpcClient = try AntdClient.createGrpc(
    target: "localhost:50051"
)

// Factory method
let auto = try AntdClient.create(transport: .rest)
```

All methods use Swift concurrency (`async throws`). The protocol is `AntdClientProtocol`.

## Health Check

```swift
let status = try await client.health()
print("Healthy: \(status.ok)")
print("Network: \(status.network)")  // "local", "default", "alpha"
```

## Public Data

```swift
// Store
let payload = "Hello, Autonomi!".data(using: .utf8)!
let result = try await client.dataPutPublic(payload)
print("Address: \(result.address)")
print("Cost: \(result.cost) atto tokens")

// Retrieve
let data = try await client.dataGetPublic(address: result.address)
print(String(data: data, encoding: .utf8)!)

// Cost estimation
let cost = try await client.dataCost(payload)
```

## Private Data

```swift
// Store (encrypted)
let secret = "secret message".data(using: .utf8)!
let result = try await client.dataPutPrivate(secret)
let dataMap = result.address  // Keep this secret!

// Retrieve (decrypt)
let decrypted = try await client.dataGetPrivate(dataMap: dataMap)
print(String(data: decrypted, encoding: .utf8)!)
```

## Files

```swift
// Upload a file
let result = try await client.fileUploadPublic(path: "/path/to/file.txt")

// Download a file
try await client.fileDownloadPublic(address: result.address, destPath: "/path/to/output.txt")

// Upload a directory
let dirResult = try await client.dirUploadPublic(path: "/path/to/directory")

// Download a directory
try await client.dirDownloadPublic(address: dirResult.address, destPath: "/path/to/output_dir")

// Cost estimation
let cost = try await client.fileCost(path: "/path/to/file.txt", isPublic: true, includeArchive: false)
```

## Graph Entries (DAG Nodes)

```swift
var keyBytes = [UInt8](repeating: 0, count: 32)
_ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
let secretKey = keyBytes.map { String(format: "%02x", $0) }.joined()

var contentBytes = [UInt8](repeating: 0, count: 32)
_ = SecRandomCopyBytes(kSecRandomDefault, contentBytes.count, &contentBytes)
let content = contentBytes.map { String(format: "%02x", $0) }.joined()

// Create root node
let result = try await client.graphEntryPut(
    ownerSecretKey: secretKey,
    parents: [],
    content: content,
    descendants: []
)

// Read
let entry = try await client.graphEntryGet(address: result.address)
print("Owner: \(entry.owner)")
print("Parents: \(entry.parents.count)")

// Check existence
let exists = try await client.graphEntryExists(address: result.address)
```

## Error Handling

```swift
import AntdSdk

do {
    let data = try await client.dataGetPublic(address: "nonexistent")
} catch let error as NotFoundError {
    print("Not found: \(error.localizedDescription)")
} catch let error as PaymentError {
    print("Payment issue: \(error.localizedDescription)")
} catch let error as NetworkError {
    print("Network unreachable: \(error.localizedDescription)")
} catch let error as AntdError {
    print("Error (\(error.statusCode)): \(error.localizedDescription)")
}
```

Error hierarchy:

| Error | HTTP Code | When |
|-------|-----------|------|
| `BadRequestError` | 400 | Invalid parameters |
| `PaymentError` | 402 | Insufficient funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Duplicate creation |
| `ForkError` | 409 | Version conflict |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |

## Examples

```bash
cd antd-swift

swift run AntdExamples 1     # Connect
swift run AntdExamples 2     # Public data
swift run AntdExamples 3     # Chunks
swift run AntdExamples 4     # Files
swift run AntdExamples 5     # Graph entries
swift run AntdExamples 6     # Private data
swift run AntdExamples all   # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l swift
ant dev example all -l swift
```
