# Swift Quickstart

A comprehensive guide to using the Autonomi network with the Swift SDK.

> **📱 Building an iOS (or macOS) app? This is the wrong doc.** This page covers
> the **REST/gRPC SDK**, which needs a locally-running `antd` daemon. For native
> apps, use the in-process Swift bindings — **[`ant-swift`](https://github.com/WithAutonomi/ant-swift)**
> — which embed the Autonomi client directly (no daemon), ship a prebuilt
> `.xcframework` via SwiftPM, and have their own getting-started guide covering
> connect methods, uploads/downloads, cost estimation, and external-signer
> (WalletConnect) payments. Continue below only if you specifically want the
> daemon-backed REST SDK on macOS.

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
    baseURL: URL(string: "http://localhost:8082")!,
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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
let est = try await client.dataCost(payload)
```

## Private Data

```swift
// Store (encrypted)
let secret = "secret message".data(using: .utf8)!
let result = try await client.dataPut(secret)
let dataMap = result.dataMap  // Keep this secret!

// Retrieve (decrypt)
let decrypted = try await client.dataGet(dataMap: dataMap)
print(String(data: decrypted, encoding: .utf8)!)
```

## Files

```swift
// Upload a file
let result = try await client.filePutPublic(path: "/path/to/file.txt")

// Download a file
try await client.fileGetPublic(address: result.address, destPath: "/path/to/output.txt")

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
let est = try await client.fileCost(path: "/path/to/file.txt")
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```swift
let owner = try await client.pointerKeys()[0].address   // a pointer antd can write

let v1 = try await client.dataPutPublic(Data("version 1".utf8), paymentMode: .auto)
let v2 = try await client.dataPutPublic(Data("version 2".utf8), paymentMode: .auto)

_ = try await client.pointerCreate(owner: owner, target: v1.address, kind: .chunk)  // pays; counter 0
_ = try await client.pointerUpdate(owner: owner, target: v2.address, kind: .chunk)  // pays again; counter 1
let target = try await client.pointerResolve(address: owner)    // target.target == v2.address (free)

let finality = try await client.pointerFinality(address: owner) // free
print(finality.status.wire)                                     // "open"
```

Counters are `UInt64`. `pointerTransfer`, `pointerGet`, `pointerController`, `pointerPrepare` and `pointerFinalize` complete the set, on both clients.

Runnable example: the `pointers` example in `antd-swift/Sources/AntdExamples/Main.swift`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-swift
ANTD_POINTER_OWNER=<address> swift run AntdExamples pointers
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

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```swift
let one = try await client.dataPutPublic(Data("one".utf8), paymentMode: .auto)   // pays
let two = try await client.dataPutPublic(Data("two".utf8), paymentMode: .auto)   // pays

let built = try await client.buildManifest(                                      // free
    entries: [
        ManifestEntryInput(path: "notes/one.txt", address: one.address),
        ManifestEntryInput(path: "notes/two.txt", address: two.address),
    ],
    options: BuildManifestOptions(name: "example")
)
print(built.link ?? "too big for a link; share built.manifest (Data) instead")

let decoded = try await client.decodeManifest(built.manifest, resolve: true)     // free
for entry in decoded.entries {
    print(entry.effectiveName, entry.exactSize.map(String.init) ?? "unknown", entry.error ?? "")
}
```

`decodeManifestLink(_:resolve:)` takes a link instead. Use `dataMap:` instead of `address:` for an embedded entry; `BuildManifestOptions(embedRoots: false)` keeps shrunk DataMaps as given. Sizes are `UInt64?`.

Runnable example: the `manifests` example in `antd-swift/Sources/AntdExamples/Main.swift`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-swift
ANTD_BASE_URL=http://localhost:8082 swift run AntdExamples manifests
```

## Examples

```bash
cd antd-swift

swift run AntdExamples 1     # Connect
swift run AntdExamples 2     # Public data
swift run AntdExamples 3     # Chunks
swift run AntdExamples 4     # Files
swift run AntdExamples 6     # Private data
swift run AntdExamples all   # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l swift
ant dev example all -l swift
```
