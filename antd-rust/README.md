# antd-rust

Rust SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

```bash
cargo add antd-client
```

Or add to your `Cargo.toml`:

```toml
[dependencies]
antd-client = "0.1"
```

## Quick Start

```rust
use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Check daemon health
    let health = client.health().await?;
    println!("OK: {}, Network: {}", health.ok, health.network);

    // Store data
    let result = client.data_put_public(b"Hello, Autonomi!").await?;
    println!("Stored at {} (chunks: {})", result.address, result.chunks_stored);

    // Retrieve data
    let data = client.data_get_public(&result.address).await?;
    println!("Retrieved: {}", String::from_utf8_lossy(&data));
    Ok(())
}
```

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```rust
use antd_client::{Client, DEFAULT_BASE_URL};
use std::time::Duration;

// Default: http://localhost:8082, 5 minute timeout
let client = Client::new(DEFAULT_BASE_URL);

// Custom URL
let client = Client::new("http://custom-host:9090");

// Custom timeout
let client = Client::with_timeout(DEFAULT_BASE_URL, Duration::from_secs(30));
```

## API Reference

All methods are `async` and return `Result<T, AntdError>`.

### Health
| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `data_put_public(data, payment_mode)` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `data_get_public(address)` | Retrieve public data by address |
| `data_put(data, payment_mode)` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `data_get(data_map)` | Retrieve private data using a caller-held DataMap |
| `data_cost(data, payment_mode)` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks
| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Files
| Method | Description |
|--------|-------------|
| `file_put(path, payment_mode)` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `file_get(data_map, dest_path)` | Download a private file using a caller-held DataMap |
| `file_put_public(path, payment_mode)` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `file_get_public(address, dest_path)` | Download a public file by address |
| `file_cost(path, is_public, payment_mode)` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

## gRPC Transport

The SDK also provides a gRPC client with the same async methods. It connects to the
antd daemon's gRPC endpoint (default `localhost:50051`) using [tonic](https://github.com/hyperium/tonic).

```rust
use antd_client::{GrpcClient, DEFAULT_GRPC_ENDPOINT};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = GrpcClient::new(DEFAULT_GRPC_ENDPOINT).await?;

    // Check daemon health
    let health = client.health().await?;
    println!("OK: {}, Network: {}", health.ok, health.network);

    // Store data
    let result = client.data_put_public(b"Hello, Autonomi!").await?;
    println!("Stored at {} (chunks: {})", result.address, result.chunks_stored);

    // Retrieve data
    let data = client.data_get_public(&result.address).await?;
    println!("Retrieved: {}", String::from_utf8_lossy(&data));
    Ok(())
}
```

The `GrpcClient` has identical method signatures to the REST `Client`, so switching
transports requires only changing the constructor. gRPC status codes are automatically
mapped to `AntdError` variants via the `Grpc` error variant.

> **Note:** Wallet operations (address, balance, approve) and payment_mode are available via REST only.

## Error Handling

All errors are returned as `AntdError` variants. Use `match` for specific handling:

```rust
use antd_client::AntdError;

match client.data_get_public("some_address").await {
    Ok(data) => println!("Got {} bytes", data.len()),
    Err(AntdError::NotFound(msg)) => println!("Data not found: {msg}"),
    Err(AntdError::Payment(msg)) => println!("Insufficient funds: {msg}"),
    Err(e) => println!("Other error: {e}"),
}
```

| Error Variant | HTTP Status | When |
|--------------|-------------|------|
| `BadRequest` | 400 | Invalid parameters |
| `Payment` | 402 | Insufficient funds |
| `NotFound` | 404 | Resource not found |
| `AlreadyExists` | 409 | Resource exists |
| `Fork` | 409 | Version conflict |
| `TooLarge` | 413 | Payload too large |
| `Internal` | 500 | Server error |
| `Network` | 502 | Network unreachable |
| `Http` | - | REST transport error |
| `Json` | - | Serialization error |
| `Grpc` | - | gRPC transport/status error |

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `06-private-data` — Private encrypted data storage
- `08-grpc` — gRPC transport (instead of REST)

Run an example:

```bash
cargo run --example 01-connect
```
