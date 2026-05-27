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
| `FinalizeMerkleUpload(ctx, uploadID, winnerPoolHash, storeDataMap)` | Submit a prepared merkle upload after external payment |
| `FinalizeChunkUpload(ctx, uploadID, txHashes)` | Submit a prepared chunk after external payment; returns the chunk address |

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
