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

## gRPC Transport

The SDK also provides a `GrpcClient` that connects to the antd daemon over gRPC.
It exposes the same methods with identical signatures and error types as the REST client.

### Generating Proto Stubs

Before using the gRPC client, you must generate the protobuf Go stubs from the
proto definitions in `antd/proto/antd/v1/`:

```bash
# Install protoc plugins
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Generate from the repo root
protoc \
  --proto_path=antd/proto \
  --go_out=antd-go/proto --go_opt=paths=source_relative \
  --go-grpc_out=antd-go/proto --go-grpc_opt=paths=source_relative \
  antd/proto/antd/v1/*.proto
```

This creates the `antd-go/proto/antd/v1/` package imported by `GrpcClient`.

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
