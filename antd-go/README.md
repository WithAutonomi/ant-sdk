# antd-go

Go SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

```bash
go get github.com/maidsafe/ant-sdk/antd-go
```

## Quick Start

```go
package main

import (
    "context"
    "fmt"
    "log"

    antd "github.com/maidsafe/ant-sdk/antd-go"
)

func main() {
    client := antd.NewClient(antd.DefaultBaseURL)
    ctx := context.Background()

    // Check daemon health
    health, err := client.Health(ctx)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("OK: %v, Network: %s\n", health.OK, health.Network)

    // Store data
    result, err := client.DataPutPublic(ctx, []byte("Hello, Autonomi!"))
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Stored at %s (cost: %s atto)\n", result.Address, result.Cost)

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
// Default: http://localhost:8080, 5 minute timeout
client := antd.NewClient(antd.DefaultBaseURL)

// Custom URL
client := antd.NewClient("http://custom-host:9090")

// Custom timeout
client := antd.NewClient(antd.DefaultBaseURL, antd.WithTimeout(30 * time.Second))

// Custom HTTP client
client := antd.NewClient(antd.DefaultBaseURL, antd.WithHTTPClient(myHTTPClient))
```

## API Reference

All methods take a `context.Context` as the first parameter for cancellation and timeout control.

### Health
| Method | Description |
|--------|-------------|
| `Health(ctx)` | Check daemon status |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `DataPutPublic(ctx, data)` | Store public data |
| `DataGetPublic(ctx, address)` | Retrieve public data |
| `DataPutPrivate(ctx, data)` | Store encrypted private data |
| `DataGetPrivate(ctx, dataMap)` | Retrieve private data |
| `DataCost(ctx, data)` | Estimate storage cost |

### Chunks
| Method | Description |
|--------|-------------|
| `ChunkPut(ctx, data)` | Store a raw chunk |
| `ChunkGet(ctx, address)` | Retrieve a chunk |

### Graph Entries (DAG Nodes)
| Method | Description |
|--------|-------------|
| `GraphEntryPut(ctx, secretKey, parents, content, descendants)` | Create entry |
| `GraphEntryGet(ctx, address)` | Read entry |
| `GraphEntryExists(ctx, address)` | Check if exists |
| `GraphEntryCost(ctx, publicKey)` | Estimate creation cost |

### Files & Directories
| Method | Description |
|--------|-------------|
| `FileUploadPublic(ctx, path)` | Upload a file |
| `FileDownloadPublic(ctx, address, destPath)` | Download a file |
| `DirUploadPublic(ctx, path)` | Upload a directory |
| `DirDownloadPublic(ctx, address, destPath)` | Download a directory |
| `ArchiveGetPublic(ctx, address)` | Get archive manifest |
| `ArchivePutPublic(ctx, archive)` | Create archive manifest |
| `FileCost(ctx, path, isPublic, includeArchive)` | Estimate upload cost |

## gRPC Transport

The SDK also provides a `GrpcClient` that connects to the antd daemon over gRPC.
It exposes the same 19 methods with identical signatures and error types as the REST client.

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

    antd "github.com/maidsafe/ant-sdk/antd-go"
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
    fmt.Printf("OK: %v, Network: %s\n", health.OK, health.Network)

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
- `03-files` — File upload and download
