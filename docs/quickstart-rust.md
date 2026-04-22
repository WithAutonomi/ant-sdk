# Rust Quickstart

A comprehensive guide to using the Autonomi network with the Rust SDK.

## Setup

```bash
# Prerequisites
# - Rust 1.75+: https://rustup.rs/
# - antd daemon running (ant dev start)

# Add the dependency
cargo add antd-client
cargo add tokio --features full
```

Or scaffold a new project:

```bash
ant dev init rust --name my-project
```

## Connecting

```rust
use antd_client::Client;

#[tokio::main]
async fn main() -> Result<(), antd_client::AntdError> {
    // REST transport (default)
    let client = Client::new()?;

    // Custom endpoint
    let client = Client::builder()
        .transport("rest")
        .base_url("http://localhost:8082")
        .timeout(std::time::Duration::from_secs(30))
        .build()?;

    // gRPC transport
    let client = Client::builder()
        .transport("grpc")
        .target("localhost:50051")
        .build()?;

    Ok(())
}
```

## Health Check

```rust
let status = client.health().await?;
println!("Healthy: {}", status.ok);
println!("Network: {}", status.network); // "local", "default", "alpha"
```

## Public Data

```rust
// Store
let result = client.data_put_public(b"Hello, Autonomi!").await?;
println!("Address: {}", result.address);
println!("Cost: {} atto tokens", result.cost);

// Retrieve
let data = client.data_get_public(&result.address).await?;
println!("{}", String::from_utf8_lossy(&data)); // "Hello, Autonomi!"

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
let est = client.data_cost(b"some data").await?;
println!(
    "Estimate: {} bytes in {} chunks, {} atto, gas {} wei, mode {}",
    est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode,
);
```

## Private Data

```rust
// Store (self-encrypting)
let result = client.data_put_private(b"secret message").await?;
let data_map = &result.address; // Keep this secret!

// Retrieve (decrypt)
let data = client.data_get_private(data_map).await?;
println!("{}", String::from_utf8_lossy(&data));
```

## Files

```rust
// Upload a file
let result = client.file_upload_public("/path/to/file.txt").await?;
println!("File address: {}", result.address);

// Download a file
client.file_download_public(&result.address, "/path/to/output.txt").await?;

// Upload a directory
let dir_result = client.dir_upload_public("/path/to/directory").await?;

// Download a directory
client.dir_download_public(&dir_result.address, "/path/to/output_dir").await?;

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
let est = client.file_cost("/path/to/file.txt").await?;
```


## Error Handling

```rust
use antd_client::{AntdError, Result};

match client.data_get_public("nonexistent").await {
    Ok(data) => println!("Got {} bytes", data.len()),
    Err(AntdError::NotFound { .. }) => println!("Not found"),
    Err(AntdError::Payment { .. }) => println!("Payment issue"),
    Err(AntdError::Network { .. }) => println!("Network unreachable"),
    Err(e) => println!("Error: {e}"),
}
```

Error variants:

| Variant | HTTP Code | When |
|---------|-----------|------|
| `AntdError::BadRequest` | 400 | Invalid parameters |
| `AntdError::Payment` | 402 | Insufficient funds |
| `AntdError::NotFound` | 404 | Resource not found |
| `AntdError::AlreadyExists` | 409 | Duplicate creation |
| `AntdError::Fork` | 409 | Version conflict |
| `AntdError::TooLarge` | 413 | Payload too large |
| `AntdError::Internal` | 500 | Server error |
| `AntdError::Network` | 502 | Network unreachable |

All variants carry a `message: String` field with details.

## Examples

```bash
cd antd-rust/examples

cargo run --example 01_connect
cargo run --example 02_data
cargo run --example 03_chunks
cargo run --example 04_files
cargo run --example 06_private
```

Or use the dev CLI:

```bash
ant dev example data -l rust
ant dev example all -l rust
```
