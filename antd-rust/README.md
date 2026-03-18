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
    println!("Stored at {} (cost: {} atto)", result.address, result.cost);

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

// Default: http://localhost:8080, 5 minute timeout
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
| `data_put_public(data)` | Store public data |
| `data_get_public(address)` | Retrieve public data |
| `data_put_private(data)` | Store encrypted private data |
| `data_get_private(data_map)` | Retrieve private data |
| `data_cost(data)` | Estimate storage cost |

### Chunks
| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Graph Entries (DAG Nodes)
| Method | Description |
|--------|-------------|
| `graph_entry_put(secret_key, parents, content, descendants)` | Create entry |
| `graph_entry_get(address)` | Read entry |
| `graph_entry_exists(address)` | Check if exists |
| `graph_entry_cost(public_key)` | Estimate creation cost |

### Files & Directories
| Method | Description |
|--------|-------------|
| `file_upload_public(path)` | Upload a file |
| `file_download_public(address, dest_path)` | Download a file |
| `dir_upload_public(path)` | Upload a directory |
| `dir_download_public(address, dest_path)` | Download a directory |
| `archive_get_public(address)` | Get archive manifest |
| `archive_put_public(archive)` | Create archive manifest |
| `file_cost(path, is_public, include_archive)` | Estimate upload cost |

## gRPC Transport

The SDK also provides a gRPC client with the same 19 async methods. It connects to the
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
    println!("Stored at {} (cost: {} atto)", result.address, result.cost);

    // Retrieve data
    let data = client.data_get_public(&result.address).await?;
    println!("Retrieved: {}", String::from_utf8_lossy(&data));
    Ok(())
}
```

The `GrpcClient` has identical method signatures to the REST `Client`, so switching
transports requires only changing the constructor. gRPC status codes are automatically
mapped to `AntdError` variants via the `Grpc` error variant.

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
- `05-graph` — Graph entry (DAG node) operations
- `06-private-data` — Private encrypted data storage

Run an example:

```bash
cargo run --example 01-connect
```
