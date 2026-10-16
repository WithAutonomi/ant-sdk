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
| **Manifests** | `buildManifest`, `decodeManifest`, `decodeManifestLink`: `.ant` manifests and `ant://` links. Free: nothing is uploaded or paid for. See [Manifests](#manifests). |
| **Files** | `filePut`, `fileGet`, `filePutPublic`, `fileGetPublic`, `fileCost`. Private variants return a caller-held DataMap (NOT stored on-network); public variants store the DataMap on-network at the returned address. All puts and `fileCost` accept a `PaymentMode` parameter. |
| **Pointers** | `pointerKeys`, `pointerCreate`, `pointerUpdate`, `pointerTransfer`, `pointerGet`, `pointerResolve`, `pointerFinality`, `pointerController`, and `pointerPrepare` / `pointerFinalize` for an external signer. See [Pointers](#pointers). |

## Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes. The owner can point it at a new target (a chunk, such as a public upload's address, or another pointer), and can hand it over to another pointer for good with `pointerTransfer`. Both REST and gRPC clients implement the full pointer API (antd with the pointer API, after 0.15.0).

antd signs with the owner keys it loaded at startup (`antd --pointer-keys`). A write names the pointer by its address (`owner`), never by a key. `pointerKeys()` lists the pointers the daemon can write, and an owner it holds no key for is a `BadRequestError`.

> **Every pointer write pays, and every attempt pays again.** `pointerCreate`, `pointerUpdate`, `pointerTransfer` and `pointerFinalize` each cost about one chunk's storage price. The SDK never retries them on its own, and you should not retry them automatically either. Reads (`pointerGet`, `pointerResolve`, `pointerFinality`, `pointerController`, `pointerKeys`) are free to retry.

```swift
let client = AntdClient.createRest()
let owner = "<a pointer address from pointerKeys()>"

let first = try await client.dataPutPublic(Data("v1".utf8), paymentMode: .auto)
let second = try await client.dataPutPublic(Data("v2".utf8), paymentMode: .auto)

let created = try await client.pointerCreate(owner: owner, target: first.address, kind: .chunk)  // pays
let updated = try await client.pointerUpdate(owner: owner, target: second.address, kind: .chunk) // pays again
print(created.counter, updated.counter)                     // 0 1

let record = try await client.pointerGet(address: owner)     // counter, target, isFinal, transferredTo
let target = try await client.pointerResolve(address: owner) // follows the chain to its end
let finality = try await client.pointerFinality(address: owner)
print(record.counter, target.target, finality.status)        // 1 <second.address> open
```

- **Counters are `UInt64`.** The daemon sends them as decimal strings because a final state (a transfer) sits at `UInt64.max` (`PointerRecord.finalCounter`). A counter that is not a plain decimal `UInt64` throws `InternalError` rather than reading as zero.
- **Unset values are `nil`** on both transports (REST sends `null`, gRPC an empty string or an absent message): `PointerFinality.counter`, `.state`, `.majority`, `.transferredTo`, and `PointerRecord.transferredTo`.
- **`PointerRecord.isFinal`** is the wire field `is_final` (`final` is a Swift keyword). `PointerFinalityStatus` is `.open`, `.settling`, `.unconfirmed`, `.final` or `.forked`, with `.unknown(String)` for a status a newer daemon may add. Only `.final` means a transfer is beyond dispute.
- **Addresses** are 64 hex characters. The daemon accepts a `0x` prefix but always returns bare hex, so strip the prefix before comparing.
- **External signer:** `pointerPrepare(owner:op:)` (or `pointerPrepare(owner:op:options:)` with `includeSignedQuotes`) signs a `.create`, `.update` or `.transfer` and returns a wave-batch quote. Pay it with `payForQuotes()`, then call `pointerFinalize(uploadId:txHashes:)`. While the prepared write awaits payment (up to an hour), other writes to that pointer throw `ConflictError`. A finalize that falls short after payment throws `CloseGroupShortfallError` with `retryable == true`. The daemon kept the paid state, so calling `pointerFinalize` again with the same `uploadId` stores it against the same payment. Bound that loop yourself.

Pointer errors:

| Error | HTTP | gRPC | When |
|---|---|---|---|
| `AlreadyExistsError` | 409 `ALREADY_EXISTS` | ALREADY_EXISTS | `pointerCreate` on a pointer that exists (nothing paid) |
| `PointerFinalError` | 409 `POINTER_FINAL` | FAILED_PRECONDITION + `x-antd-error-code: POINTER_FINAL` | write to a transferred or frozen pointer (nothing paid) |
| `PointerForkedError` (a `ForkError`) | 409 `POINTER_FORKED` | FAILED_PRECONDITION + `x-antd-error-code: POINTER_FORKED` | the owner signed rival final states and none holds a majority |
| `ConflictError` | 409 `CONFLICT` | ABORTED + `x-antd-error-code: CONFLICT` | a write while a prepared write to the pointer awaits payment |
| `CloseGroupShortfallError` | 503 `CLOSE_GROUP_SHORTFALL` | UNAVAILABLE + `x-antd-error-code: CLOSE_GROUP_SHORTFALL` | too few of the close group answered or stored; `retryable` only on a retained `pointerFinalize` |

Over REST these map from the error body's `code`; over gRPC from the `x-antd-error-code` trailer, and only when it agrees with the status code (an untagged FAILED_PRECONDITION is still a `PaymentError`).

**Upgrading:** the pointer methods are requirements on `AntdClientProtocol`, with default implementations that throw `NotSupportedError`. So a type of your own that conforms to it (a test double, say) keeps compiling unchanged; implement the methods if it should support pointers. `AntdRestClient` and `AntdGrpcClient` implement all of them. `ForkError` is no longer `final`, so that `PointerForkedError` can subclass it.

One behaviour change: daemons with the pointer API send `CLOSE_GROUP_SHORTFALL` on any path where too few of a close group answered. Before, that was a 500 `InternalError`. Now it is `CloseGroupShortfallError` on both transports, not `ServiceUnavailableError` (REST) or `NetworkError` (gRPC), so catch it by name.

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
| `ForkError` | 409 | ABORTED (not a partial upload or a tagged `CONFLICT`) | Conflicting update |
| `BadRequestError` | 400 | INVALID_ARGUMENT | Invalid input |
| `PaymentError` | 402 | FAILED_PRECONDITION | Insufficient funds |
| `NetworkError` | 502 | UNAVAILABLE | Network unreachable |
| `PartialUploadError` | 502 (`code: "PARTIAL_UPLOAD"`) | ABORTED (message starts with `Partial upload:`) | Finalize stored some chunks but not all; a `NetworkError` subclass (see below) |
| `TooLargeError` | 413 | RESOURCE_EXHAUSTED | Data too large |
| `InternalError` | 500 | INTERNAL | Server error |
| `PointerFinalError`, `PointerForkedError`, `ConflictError`, `CloseGroupShortfallError` | 409 / 503, by `code` | by `x-antd-error-code` trailer | See [Pointers](#pointers) |
| `NotSupportedError` | (client-side, `statusCode` 0) | (client-side) | A pointer or manifest method called on your own `AntdClientProtocol` conformer that does not implement it |

### Partial uploads (external-signer finalize)

A `finalizeUpload` / `finalizeMerkleUpload` where some chunks stayed unstored after the daemon's retries throws `PartialUploadError` with `chunksStored` / `chunksFailed` / `totalChunks` and two flags, `retryable` and `retentionKnown`. The on-chain payment persists and the stored chunks stay on the network. There are three cases:

- **`retryable`** (antd ≥ 0.14.0): the daemon kept the paid attempt under the same `uploadId`. Call the **same** finalize method again with the same `uploadId` and payment artefacts to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure throws `PartialUploadError` on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck.
- **`retentionKnown && !retryable`**: the daemon confirmed it kept nothing (for example a merkle finalize with deliberately unpaid batches). Re-preparing the same content skips already-stored chunks, so a retry pays only for the remainder.
- **`!retentionKnown`**: retention is unknown, and the daemon may still hold the paid attempt. Stop automatic recovery, keep the `uploadId` and the original payment artefacts (transaction hashes or winner pool hash), and reconcile before re-preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their REST partial uploads read as unknown. Over gRPC, a status message without a readable closing retention hint also reads as unknown (see below).

`retryable` implies `retentionKnown`.

Over REST the counts and `retryable` come from the structured error body. The counts must be JSON non-negative integers and `retryable` a JSON boolean: a body where any of them has another JSON type (a quoted `"1"` or `"true"`, a negative number, an array) is not trusted as a partial upload and keeps the status-based mapping, so a 502 stays a plain `NetworkError`. `retentionKnown` is `true` only when the body carries `retryable` as a JSON boolean; an absent or `null` `retryable` reads as unknown.

Over gRPC only an ABORTED status whose message *starts with* the daemon's fixed `Partial upload:` prefix is a partial upload; any other ABORTED, including one that mentions the prefix further in, stays a `ForkError` (or a `ConflictError` when the daemon tags it `CONFLICT`). The counts and retention are parsed from that message (`Partial upload: <stored>/<total> chunks stored, <failed> failed after retries: <reason> (<hint>)`). `retentionKnown` is `true` only when all three counts parsed and the message ends with one of the daemon's two hints: `(paid attempt retained...)` sets `retryable`, and `(stored chunks persist; re-prepare the same content...)` means the daemon confirmed nothing was retained (daemons older than 0.14.0 write only this one). A message whose counts do not parse reads zero counts, unknown retention and `retryable == false`. Readable counts with a missing, truncated or unrecognised hint, or with text after it, keep the counts but also read unknown retention and `retryable == false`: stop and reconcile rather than re-prepare. SDK releases up to 0.13.x mapped every gRPC ABORTED to `ForkError`; a partial-upload ABORTED now maps to `PartialUploadError` (besides `PARTIAL_UPLOAD`, the daemon emits ABORTED only for a tagged `CONFLICT`, which maps to `ConflictError`).

`PartialUploadError` subclasses `NetworkError`, so an existing `catch let e as NetworkError` still catches a partial upload. Catch `PartialUploadError` *before* `NetworkError` and the generic `AntdError` clause:

```swift
var lastFailed: UInt64 = 0
for attempt in 1...5 {
    do {
        let result = try await client.finalizeUpload(uploadId: prep.uploadId, txHashes: txHashes)
        print("stored \(result.chunksStored) chunks")
        break                                   // every chunk stored — done
    } catch let partial as PartialUploadError where partial.retryable {
        if attempt == 5 || (attempt > 1 && partial.chunksFailed >= lastFailed) {
            throw partial                       // stuck, but the paid attempt is retained: resume later with the same uploadId + txHashes
        }
        lastFailed = partial.chunksFailed
        try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)   // back off, then resume
    }
    // A non-retryable PartialUploadError propagates untouched:
    //   partial.retentionKnown  → the daemon kept nothing; re-prepare the same content
    //   !partial.retentionKnown → unknown; stop, keep prep.uploadId + txHashes, reconcile. Do not pay again.
}
```

See `finalizeWithRetry` in `Sources/AntdExamples/Main.swift` and the contract in [`docs/external-signer-flow.md`](../docs/external-signer-flow.md) §6.

## Manifests

A manifest (ADR-0006) is a `.ant` file, or an `ant://manifest/` link, that describes a set of files. Each entry has an optional path and size, and either an embedded DataMap (a private upload's) or a public DataMap address. The daemon builds and decodes manifests, so you never handle the format yourself. Both REST and gRPC clients implement the manifest API, which needs the antd release after 0.15.0.

**Nothing is uploaded or paid for.** The daemon reads the network only to resolve DataMaps: when it embeds roots on build, and for `resolve` on decode. So a call can time out, and it is safe to retry.

```swift
let client = AntdClient.createRest()

let one = try await client.dataPutPublic(Data("one".utf8), paymentMode: .auto)
let two = try await client.dataPutPublic(Data("two".utf8), paymentMode: .auto)

let built = try await client.buildManifest(
    entries: [
        ManifestEntryInput(path: "notes/one.txt", address: one.address),
        ManifestEntryInput(path: "notes/two.txt", address: two.address),
        // or ManifestEntryInput(path: "secret.bin", dataMap: privatePut.dataMap)
    ],
    options: BuildManifestOptions(name: "notes")
)
print(built.manifest.count, built.link ?? "too big for a link")   // the .ant bytes, and the link
for entry in built.entries {
    print(entry.effectiveName, entry.kind, entry.contentAddress)    // notes/one.txt public <hex>
}

let decoded = try await client.decodeManifest(built.manifest, resolve: true)
// or, from the link: try await client.decodeManifestLink(link, resolve: true)
for entry in decoded.entries {
    print(entry.effectiveName, entry.exactSize.map(String.init) ?? "unknown", entry.error ?? "")  // notes/one.txt 3
}
```

- **Entries:** set exactly one of `dataMap` (hex, embedded) or `address` (hex, public) on each `ManifestEntryInput`. An entry with both or neither throws `BadRequestError` before anything is sent. An entry the daemon refuses, such as a path like `../x`, throws `BadRequestError` (HTTP 400, gRPC INVALID_ARGUMENT) whose message names it as `entries[i]`.
- **Bytes:** `BuiltManifest.manifest` and the input to `decodeManifest` are raw `Data` on both transports. REST carries them as base64 in JSON and gRPC as `bytes`; the clients convert.
- **Root embedding:** `BuildManifestOptions().embedRoots` is `true`, the daemon's default: it resolves each shrunk DataMap and embeds the root when it is at most 64 KiB, so recipients skip that fetch. Pass `embedRoots: false` to embed DataMaps exactly as given.
- **Sizes are `UInt64?`.** `size` is the size the creator recorded and `exactSize` the exact plaintext size, from an embedded root DataMap or a resolving decode. An unset size is `nil`, never `0`. Likewise `path`, `link`, `name`, `dataMap` (decode only, for embedded entries), the torrent info hashes and `error` are `nil` when absent.
- **`resolve`** fetches each entry's DataMap, and its wrapper records, to report `exactSize` and confirm it is on the network; content chunks are not fetched. When one entry fails, its `error` says why, and the call still succeeds.
- **Links:** `BuiltManifest.link` is `nil` when the link would pass the recommended 1,500 bytes; share the `.ant` bytes then. `decodeManifestLink` also takes a file link or a bare 64-hex address, which decode as one public entry with no path (`source == "file_link"`).
- **gRPC message size:** a manifest can be 64 MiB, so the gRPC client raises both message limits to 256 MiB for the manifest calls only (per call, through `CallOptions`). Every other call keeps grpc-swift's 4 MiB default.

**Upgrading:** `buildManifest(entries:options:)`, `decodeManifest(_:resolve:)` and `decodeManifestLink(_:resolve:)` are requirements on `AntdClientProtocol`, with default implementations that throw `NotSupportedError`. A type of your own that conforms to it keeps compiling unchanged. `buildManifest(entries:)` is a protocol-extension convenience for the default options.

## Examples

```bash
swift run AntdExamples 1      # Connect
swift run AntdExamples 2      # Public Data
swift run AntdExamples all    # All examples (not pointers)

# Pointers: create, update, resolve, finality. Pays for each write and needs
# a never-written pointer address the daemon holds a key for, so it runs only
# when named. ANTD_BASE_URL overrides the daemon URL.
ANTD_POINTER_OWNER=<address> swift run AntdExamples pointers   # or: 9
```

```bash
# Manifests: two public uploads (each pays), then a free build and a
# resolving decode of the link. Needs the antd release after 0.15.0, so it
# runs only when named. ANTD_BASE_URL overrides the daemon URL.
swift run AntdExamples manifests   # or: 10
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
│   │   ├── Manifests.swift           # Manifest types and protocol defaults
│   │   ├── AntdRestClient+Manifests.swift  # Manifests over REST
│   │   ├── AntdGrpcClient+Manifests.swift  # Manifests over gRPC
│   │   ├── Models.swift              # Data types
│   │   └── Errors.swift              # Error hierarchy
│   └── AntdExamples/
│       └── Main.swift                # Runnable example
└── Tests/
    └── AntdSdkTests/
        └── SmokeTests.swift
```
