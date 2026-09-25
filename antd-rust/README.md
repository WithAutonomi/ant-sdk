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

## Compatibility

This crate talks to a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon; it does not join the network itself. Rust 1.82+. Tested against antd 0.12.x. The gRPC client code is pre-generated and committed, so consumers need neither `protoc` nor the daemon's `.proto` files. For a daemon-less client see the `ant-ffi` crate in this repository.

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
transports requires only changing the constructor. gRPC status codes are surfaced through
the `Grpc` error variant, except an `ABORTED` whose message starts with `Partial upload:`,
which is a partial store and maps to `AntdError::PartialUpload`; any other `ABORTED` stays
the generic `Grpc` error (see [Error Handling](#error-handling)).

`GrpcClient::connect` decodes responses up to `DEFAULT_MAX_RECV_MESSAGE_BYTES` (32 MiB,
sized so a full wave-batch prepare with `include_signed_quotes` fits; tonic's own 4 MiB
default would reject it with an `OutOfRange` status). Use
`GrpcClient::connect_with_max_message_size(endpoint, bytes)` to change the ceiling.

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
| `PartialUpload` | 502 (`code: PARTIAL_UPLOAD`) / gRPC `ABORTED` with a `Partial upload:` message | A finalize stored some chunks but not all; carries counts and `retryable` |
| `ServiceUnavailable` | 503 | Wallet not configured |
| `Http` | - | REST transport error |
| `Json` | - | Serialization error |
| `Grpc` | - | gRPC transport/status error |

### Partial stores (external-signer finalize)

`finalize_upload`, `finalize_merkle_upload` and `finalize_chunk_upload` can fail *after*
the signer has paid: some chunks store, others miss quorum after the daemon's own retries.
That comes back as `AntdError::PartialUpload { chunks_stored, chunks_failed, total_chunks,
retryable, message }`. The on-chain payment persists and the stored chunks stay on the
network; `retryable` says how to finish the upload:

- `retryable == true` — antd ≥ 0.14.0 kept the paid attempt under the same `upload_id`.
  Call the **same** finalize method again with the same arguments to store the remainder
  against the same payment — no re-prepare, no second signature, no double payment. Bound
  that loop: a persistent failure returns `PartialUpload` on every call, so cap the
  attempts and treat a `chunks_failed` that stops shrinking as stuck. The retained attempt
  expires with the daemon's pending-upload TTL.
- `retryable == false` — nothing was retained (a merkle finalize with deliberately unpaid
  batches, or an older daemon that never sends the flag). Re-preparing the same content
  skips already-stored chunks, so a retry pays only for the remainder.

Over REST the counts and flag come from the daemon's error body; over gRPC they are parsed
from the `ABORTED` status message. Only an `ABORTED` whose message starts with the daemon's
fixed `Partial upload:` prefix maps to `PartialUpload`; any other `ABORTED` — even one
quoting that text further in — is the generic `Grpc` error. Over gRPC the counts gate the
flag: `retryable` is `true` only when all three counts parse as `u64` and the message
carries the `paid attempt retained` hint. Garbled or overflowing counts read as zero with
`retryable == false`, hint or not, so an unreadable message falls back to re-preparing. See
`finalize_with_retry` in [`examples/07-external-signer.rs`](examples/07-external-signer.rs)
and §6 of [`docs/external-signer-flow.md`](../docs/external-signer-flow.md).

```rust
use antd_client::AntdError;

match client.finalize_upload(&upload_id, &tx_hashes).await {
    Ok(fin) => println!("stored {} chunks", fin.chunks_stored),
    Err(AntdError::PartialUpload { chunks_stored, chunks_failed, retryable: true, .. }) => {
        // Same upload_id, same payment: call finalize_upload again (bounded).
        println!("{chunks_stored} stored, {chunks_failed} to retry against the same payment");
    }
    Err(AntdError::PartialUpload { retryable: false, .. }) => {
        // Nothing retained: re-prepare the same content to pay for the remainder only.
    }
    Err(e) => return Err(e.into()),
}
```

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `06-private-data` — Private encrypted data storage
- `07-external-signer` — Prepare / pay externally / finalize, with a bounded retry on `PartialUpload`
- `08-grpc` — gRPC transport (instead of REST)

Run an example:

```bash
cargo run --example 01-connect
```
