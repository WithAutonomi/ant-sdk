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

### Pointers (Mutable References)
| Method | Description |
|--------|-------------|
| `PointerCreate(ctx, secretKey, target)` | Create a pointer |
| `PointerGet(ctx, address)` | Read a pointer |
| `PointerExists(ctx, address)` | Check if pointer exists |
| `PointerUpdate(ctx, secretKey, target)` | Update pointer target |
| `PointerCost(ctx, publicKey)` | Estimate creation cost |

### Scratchpads (Versioned Mutable State)
| Method | Description |
|--------|-------------|
| `ScratchpadCreate(ctx, secretKey, contentType, data)` | Create a scratchpad |
| `ScratchpadGet(ctx, address)` | Read a scratchpad |
| `ScratchpadExists(ctx, address)` | Check if exists |
| `ScratchpadUpdate(ctx, secretKey, contentType, data)` | Update scratchpad |
| `ScratchpadCost(ctx, publicKey)` | Estimate creation cost |

### Graph Entries (DAG Nodes)
| Method | Description |
|--------|-------------|
| `GraphEntryPut(ctx, secretKey, parents, content, descendants)` | Create entry |
| `GraphEntryGet(ctx, address)` | Read entry |
| `GraphEntryExists(ctx, address)` | Check if exists |
| `GraphEntryCost(ctx, publicKey)` | Estimate creation cost |

### Registers (32-byte Mutable Values)
| Method | Description |
|--------|-------------|
| `RegisterCreate(ctx, secretKey, initialValue)` | Create register |
| `RegisterGet(ctx, address)` | Read register |
| `RegisterUpdate(ctx, secretKey, newValue)` | Update register |
| `RegisterCost(ctx, publicKey)` | Estimate creation cost |

### Vaults (Private Encrypted Storage)
| Method | Description |
|--------|-------------|
| `VaultGet(ctx, secretKey)` | Retrieve vault data |
| `VaultPut(ctx, secretKey, data, contentType)` | Store vault data |
| `VaultCost(ctx, secretKey, maxSize)` | Estimate storage cost |

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
- `03-pointers` — Mutable references
- `04-scratchpads` — Versioned mutable state
- `05-files` — File upload and download
