# antd-go

Go SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

```bash
go get github.com/WithAutonomi/ant-sdk/antd-go
```

## Quick Start

```go
package main

import (
    "context"
    "fmt"
    "log"

    antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
    client := antd.NewClient(antd.DefaultBaseURL)
    ctx := context.Background()

    // Check daemon health
    health, err := client.Health(ctx)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("OK: %v, Network: %s, Version: %s, EVM: %s\n",
        health.OK, health.Network, health.Version, health.EvmNetwork)

    // Store data
    result, err := client.DataPutPublic(ctx, []byte("Hello, Autonomi!"), antd.PaymentModeAuto)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Stored at %s (chunks: %d, mode: %s)\n", result.Address, result.ChunksStored, result.PaymentModeUsed)

    // Retrieve data
    data, err := client.DataGetPublic(ctx, result.Address)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Retrieved: %s\n", data)
}
```

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```go
// Auto-discover daemon via port file (recommended)
client, url := antd.NewClientAutoDiscover()

// Explicit URL (default: http://localhost:8082)
client := antd.NewClient(antd.DefaultBaseURL)

// Custom URL
client := antd.NewClient("http://custom-host:9090")

// Custom timeout
client := antd.NewClient(antd.DefaultBaseURL, antd.WithTimeout(30 * time.Second))

// Custom HTTP client
client := antd.NewClient(antd.DefaultBaseURL, antd.WithHTTPClient(myHTTPClient))

// Payment mode is a typed enum passed positionally to put/cost methods.
result, _ := client.DataPutPublic(ctx, data, antd.PaymentModeMerkle)
// antd.PaymentModeAuto   — server picks merkle for 64+ chunks, single otherwise
// antd.PaymentModeMerkle — force batch payments (saves gas, min 2 chunks)
// antd.PaymentModeSingle — per-chunk payments
```

### Put/Get naming convention

Methods follow a "private by default" convention: the unqualified verb is the
private variant; the `_public` suffix marks the public variant.

- `DataPut` / `DataGet` — private. Returns/consumes a caller-held DataMap.
- `DataPutPublic` / `DataGetPublic` — public. Stores/fetches the DataMap on-network.
- `FilePut` / `FileGet` — private file upload/download.
- `FilePutPublic` / `FileGetPublic` — public file upload/download.

## API Reference

All methods take a `context.Context` as the first parameter for cancellation and timeout control.

### Health
| Method | Description |
|--------|-------------|
| `Health(ctx)` | Check daemon status — returns `*HealthStatus` with daemon version, EVM network, uptime, build commit, and payment contract addresses |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `DataPut(ctx, data, paymentMode)` | Store encrypted private data; returns the caller-held DataMap |
| `DataGet(ctx, dataMap)` | Retrieve private data from a caller-held DataMap |
| `DataPutPublic(ctx, data, paymentMode)` | Store public data; returns the on-network DataMap address |
| `DataGetPublic(ctx, address)` | Retrieve public data by address |
| `DataCost(ctx, data, paymentMode)` | Estimate storage cost — returns `*UploadCostEstimate` |

### Chunks
| Method | Description |
|--------|-------------|
| `ChunkPut(ctx, data)` | Store a raw chunk |
| `ChunkGet(ctx, address)` | Retrieve a chunk |

### Files
| Method | Description |
|--------|-------------|
| `FilePut(ctx, path, paymentMode)` | Upload a file privately; returns the caller-held DataMap |
| `FileGet(ctx, dataMap, destPath)` | Download a private file from a caller-held DataMap |
| `FilePutPublic(ctx, path, paymentMode)` | Upload a file publicly; returns the on-network DataMap address |
| `FileGetPublic(ctx, address, destPath)` | Download a public file by address |
| `FileCost(ctx, path, isPublic, paymentMode)` | Estimate upload cost — returns `*UploadCostEstimate` |

### External Signer

Two-phase upload — daemon prepares the payment intent, caller signs + submits the payForQuotes tx, daemon finalizes once the chain confirms. See `examples/07-external-signer/main.go` + `docs/external-signer-flow.md`.

| Method | Description |
|--------|-------------|
| `PrepareUpload(ctx, path)` | Prepare a file upload for external signing — returns `*PrepareUploadResult` |
| `PrepareUploadPublic(ctx, path)` | Convenience for a public-visibility prepare — returns `*PrepareUploadResult` |
| `PrepareDataUpload(ctx, data)` | Prepare a data upload for external signing — returns `*PrepareUploadResult` |
| `PrepareChunkUpload(ctx, data)` | Prepare a single chunk for external-signer publish — returns `*PrepareChunkResult` |
| `FinalizeUpload(ctx, uploadID, txHashes, storeDataMap)` | Submit a prepared upload after external payment — returns `*FinalizeUploadResult` |
| `FinalizeMerkleUpload(ctx, uploadID, winnerPoolHash, storeDataMap)` | Submit a prepared single-batch merkle upload after external payment |
| `FinalizeMerkleUploadMulti(ctx, uploadID, winnerPoolHashes, storeDataMap)` | Submit a merkle upload paid in one or more batches (antd ≥ 0.12.0) — one winner hash per `MerkleBatches` entry, `""` for an unpaid batch |
| `FinalizeChunkUpload(ctx, uploadID, txHashes)` | Submit a prepared chunk after external payment; returns the chunk address |

Merkle uploads larger than one merkle tree (256 fresh chunks ≈ 1 GiB) arrive as multiple entries in `PrepareUploadResult.MerkleBatches`; pay one `payForMerkleTree2()` transaction per entry and finalize with `FinalizeMerkleUploadMulti`.

A finalize where some chunks stayed unstored after the daemon's retries returns `*PartialUploadError` with `ChunksStored` / `ChunksFailed` / `TotalChunks` and two flags, `Retryable` and `RetentionKnown` (`Retryable` implies `RetentionKnown`). `PartialUploadError` embeds `AntdError`, not `NetworkError`, so match it with `var perr *antd.PartialUploadError; errors.As(err, &perr)` — an `errors.As` check for `*antd.NetworkError` does not catch it. Recovery depends on the flags:

- `Retryable` (antd ≥ 0.14.0): the daemon kept the paid attempt under the same `upload_id`. Call the **same** finalize method again with the same `upload_id` and payment artefacts to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop (cap the attempts; a `ChunksFailed` that stops shrinking means stuck).
- `RetentionKnown && !Retryable`: the daemon confirmed nothing was retained (a daemon-wallet upload, or a merkle finalize with deliberately unpaid batches). Re-preparing the same content skips stored chunks, so a retry pays only for the remainder.
- `!RetentionKnown`: retention is unknown. The daemon may still hold the paid attempt (it records the resume handle before returning the error), so stop automatic recovery, keep the `upload_id` and the original payment artefacts, and reconcile before re-preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their REST partial uploads read as unknown.

The fields are read conservatively: over REST a count that is not a JSON non-negative integer (≤ 2^64−1) reads as 0, and `RetentionKnown` is set only when the body's `retryable` is a JSON bool (whose value then sets `Retryable`); over gRPC both flags depend on the counts and the closing retention hint parsing from the status message (see [gRPC Error Mapping](#grpc-error-mapping)). See `finalizeWithRetry` in `examples/07-external-signer/main.go`.

### Pointers

A pointer is a small, owner-signed, mutable reference (the antd release after 0.15.0, the first with pointers). Its address is derived from its owner's key and never changes. What it points at (a chunk, such as a public file's data map, or another pointer) can be updated by the owner, and the owner can hand the pointer over to another pointer for good. The daemon signs with owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so writes name the pointer by its address (`owner`) and no key ever crosses the API.

| Method | Description |
|--------|-------------|
| `PointerKeys(ctx)` | Addresses of the pointers this daemon can write |
| `PointerCreate(ctx, owner, target, kind)` | Create a pointer, paid by the daemon wallet; `AlreadyExistsError` if it exists. `kind` is `PointerTargetChunk` (default when `""`) or `PointerTargetPointer` |
| `PointerUpdate(ctx, owner, target, kind)` | Point a pointer at a new target, creating it if needed; `PointerFinalError` if it was handed over or frozen |
| `PointerTransfer(ctx, owner, recipient)` | Hand a pointer over to the recipient's pointer, irreversibly — returns `*PointerTransferResult` with the close group's finality |
| `PointerGet(ctx, address)` | Read a pointer — returns `*PointerRecord`; `NotFoundError` if none |
| `PointerResolve(ctx, address)` | Follow a chain of pointers to its target — returns `*PointerTarget` |
| `PointerFinality(ctx, address)` | Ask the whole close group where a pointer stands — only `PointerFinal` means a transfer is beyond dispute |
| `PointerController(ctx, address)` | Follow transfers to the pointer whose owner now decides |
| `PointerPrepare(ctx, PointerPrepareRequest)` | Sign a create, update or transfer and quote it for an external signer (no daemon wallet needed) |
| `PointerFinalize(ctx, uploadID, txHashes)` | Store a prepared write once `payForQuotes()` has paid it |

Counters are `uint64`; a final state is at `PointerFinalCounter` (2^64−1). Every write pays, about the price of one chunk, and every attempt pays again, so never retry `PointerCreate`, `PointerUpdate` or `PointerTransfer` automatically. Reads are free to retry: a `*CloseGroupShortfallError` on a read usually clears once an update in flight settles. A `PointerFinalize` that falls short after payment returns `*CloseGroupShortfallError` with `Retryable` set: the daemon kept the paid state, so call it again with the same `uploadID`. While a prepared write awaits payment, other writes to that pointer return `*ConflictError`.

### Manifests

A manifest (ADR-0006) is a `.ant` file, or an `ant://manifest/` link when it fits in 1,500 bytes, that lists a set of files (the antd release after 0.15.0, the first with manifests). Each entry has an optional path and size and either an embedded DataMap (kind `"embedded"`: the manifest is the key to the file) or a public file's DataMap address (kind `"public"`). The daemon builds and decodes manifests through ant-core, so the format, content addresses and portable path rules are never re-implemented here. Nothing is uploaded or paid for: you build from DataMaps and addresses you already hold, and keep or share the bytes or the link yourself.

| Method | Description |
|--------|-------------|
| `BuildManifest(ctx, entries, opts)` | Build a manifest from `[]ManifestEntryInput`, each with exactly one of `DataMap` or `Address` (checked before sending) — returns `*BuiltManifest` with the `.ant` bytes, the link (empty when it doesn't fit) and each entry's effective name and content address. `opts` may be nil |
| `DecodeManifest(ctx, manifest, resolve)` | Decode `.ant` bytes — returns `*DecodedManifest` with the name, torrent info hashes and entries, embedded DataMaps included |
| `DecodeManifestLink(ctx, link, resolve)` | Decode an `ant://manifest/` link, a file link or a bare 64-hex address (a file link reads as `Source` `"file_link"`: one public entry with no path) |

The bytes are raw `[]byte` on both transports; the REST client does the base64. `Size` (the creator's claim) and `ExactSize` are `*uint64`, and nil means unset, never 0. By default `BuildManifest` resolves each shrunk DataMap and embeds its root when that is at most 64 KiB, so recipients skip the fetch; set `BuildManifestOptions.KeepShrunkDataMaps` to embed DataMaps exactly as given. With `resolve`, a decode fetches each entry's DataMap (not its content) to fill `ExactSize` and confirm it is on the network, and one entry's failure comes back in that entry's `Error`, not as a failed call. The embedding policy and `resolve` read from the network, so they can time out, and retrying is safe. An invalid entry or input is a `*BadRequestError` whose message names it (`entries[i]: ...`).

A manifest can be 64 MiB, past the gRPC client's 32 MiB default receive ceiling, so `GrpcClient` raises the limit to 256 MiB on each manifest call; `WithGrpcMaxRecvMsgSize` doesn't apply to these calls.

```go
// public is a DataPutPublic result, private a DataPut result.
built, err := client.BuildManifest(ctx, []antd.ManifestEntryInput{
    {Path: "notes/one.txt", Address: public.Address},
    {Path: "notes/two.txt", DataMap: private.DataMap},
}, &antd.BuildManifestOptions{Name: "notes"})
if err != nil {
    log.Fatal(err)
}
fmt.Println(built.Link) // ant://manifest/...

decoded, err := client.DecodeManifestLink(ctx, built.Link, true)
if err != nil {
    log.Fatal(err)
}
for _, e := range decoded.Entries {
    if e.ExactSize != nil {
        fmt.Printf("%s (%s): %d bytes\n", e.EffectiveName, e.Kind, *e.ExactSize)
    }
}
```

## gRPC Transport

The SDK also provides a `GrpcClient` that connects to the antd daemon over gRPC.
It exposes the same methods with identical signatures and error types as the REST client.

### Generating Proto Stubs

The protobuf Go stubs imported by `GrpcClient` (the `antd-go/proto/antd/v1/`
package) are generated from `antd/proto/antd/v1/` and committed, so nothing
needs generating to use the gRPC client. After changing the protos, regenerate
them and commit the result (CI fails when they drift):

```bash
# Needs Go and protoc 34.1 on PATH; the script builds protoc-gen-go and
# protoc-gen-go-grpc at the versions pinned at its top.
antd-go/scripts/generate-protos.sh
```

### Usage

```go
package main

import (
    "context"
    "fmt"
    "log"

    antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
    // Connect via gRPC (default: localhost:50051)
    client, err := antd.NewGrpcClient(antd.DefaultGrpcTarget)
    if err != nil {
        log.Fatal(err)
    }
    defer client.Close()

    ctx := context.Background()

    // All methods are identical to the REST client
    health, err := client.Health(ctx)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("OK: %v, Network: %s, Version: %s, EVM: %s\n",
        health.OK, health.Network, health.Version, health.EvmNetwork)

    result, err := client.DataPutPublic(ctx, []byte("Hello via gRPC!"))
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Stored at %s (cost: %s atto)\n", result.Address, result.Cost)
}
```

### Configuration

```go
// Default: localhost:50051, 5 minute timeout
client, _ := antd.NewGrpcClient(antd.DefaultGrpcTarget)

// Custom timeout
client, _ := antd.NewGrpcClient("localhost:50051",
    antd.WithGrpcTimeout(30 * time.Second))

// Custom dial options (e.g. TLS)
client, _ := antd.NewGrpcClient("secure-host:443",
    antd.WithDialOptions(grpc.WithTransportCredentials(creds)))

// Response size ceiling (default antd.DefaultGrpcMaxRecvMsgSize, 32 MiB —
// sized so a full wave-batch prepare with signed quotes decodes; grpc-go's
// own 4 MiB default would reject it with a 413 TooLargeError)
client, _ := antd.NewGrpcClient("localhost:50051",
    antd.WithGrpcMaxRecvMsgSize(64 * 1024 * 1024))
```

> **Note:** Wallet operations (address, balance, approve) and payment_mode are available via REST only.

### gRPC Error Mapping

gRPC status codes are mapped to the same typed errors as the REST client:

| gRPC Code | Error Type |
|-----------|-----------|
| `InvalidArgument` | `BadRequestError` |
| `FailedPrecondition` | `PaymentError` |
| `NotFound` | `NotFoundError` |
| `AlreadyExists` | `AlreadyExistsError` |
| `ResourceExhausted` | `TooLargeError` |
| `Internal` | `InternalError` |
| `Unavailable` | `NetworkError` |
| `Aborted` (message starts with `Partial upload:`) | `PartialUploadError` |
| `Aborted` (any other message) | `AntdError` |

The pointer methods also read the daemon's `x-antd-error-code` trailer, which takes precedence: `POINTER_FINAL` → `PointerFinalError`, `POINTER_FORKED` → `ForkError`, `CONFLICT` → `ConflictError`, `CLOSE_GROUP_SHORTFALL` → `CloseGroupShortfallError` (`Retryable` when the message says the paid attempt was retained). Over REST the same types come from the error body's `code`.

A partial upload's counts and retention are parsed from the status message (`Partial upload: <stored>/<total> chunks stored, <failed> failed after retries: <reason> (<hint>)`). `RetentionKnown` is true only when that counts pattern matched, all three counts fit a `uint64`, and the message ends with one of the daemon's two hints: `(paid attempt retained...)` sets `Retryable`, and `(stored chunks persist; re-prepare the same content...)` means the daemon confirmed nothing was retained (daemons older than 0.14.0 write only this one). A garbled or out-of-range count reads 0 and leaves both flags false. Readable counts with a missing, truncated or unrecognised hint keep the counts, but both flags stay false. In both cases retention is unknown, so stop and reconcile rather than re-prepare.

## Error Handling

All errors can be checked with `errors.As`:

```go
import "errors"

result, err := client.DataGetPublic(ctx, address)
if err != nil {
    var notFound *antd.NotFoundError
    if errors.As(err, &notFound) {
        fmt.Println("Data not found on network")
    }
    var payment *antd.PaymentError
    if errors.As(err, &payment) {
        fmt.Println("Insufficient funds")
    }
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

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public and private data storage
- `03-chunks` — Raw chunk store/retrieve
- `04-files` — File upload and download
- `06-private-data` — Private (encrypted) data round-trip via data_map
- `07-external-signer` — External-signer file + chunk upload (anvil signer)
- `08-pointers` — Create, update, read and resolve a pointer, then check its finality (needs `ANTD_POINTER_OWNER`; each write pays)
- `09-manifests` — Build a manifest of two public uploads, then decode its link with exact sizes (the two uploads pay; the manifest calls don't)
