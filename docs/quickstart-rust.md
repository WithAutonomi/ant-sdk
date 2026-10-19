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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
let est = client.file_cost("/path/to/file.txt").await?;
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```rust
use antd_client::{PaymentMode, PointerKind};

let owner = client.pointer_keys().await?[0].address.clone();   // a pointer antd can write

let v1 = client.data_put_public(b"version 1", PaymentMode::Auto).await?.address;
let v2 = client.data_put_public(b"version 2", PaymentMode::Auto).await?.address;

client.pointer_create(&owner, &v1, PointerKind::Chunk).await?;  // pays; counter 0
client.pointer_update(&owner, &v2, PointerKind::Chunk).await?;  // pays again; counter 1
let target = client.pointer_resolve(&owner).await?.target;      // == v2 (free)

let finality = client.pointer_finality(&owner).await?;          // free
println!("{:?}", finality.status);                              // Open
```

Counters are `u64`. `pointer_transfer`, `pointer_get`, `pointer_controller`, `pointer_prepare` (and `pointer_prepare_with_options`) and `pointer_finalize` complete the set, on `GrpcClient` too.

Runnable example: `antd-rust/examples/09-pointers.rs`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes). This example talks to `http://localhost:8082`; it does not read `ANTD_BASE_URL`:

```bash
cd antd-rust
ANTD_POINTER_OWNER=<address> cargo run --example 09-pointers
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

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```rust
use antd_client::{BuildManifestOptions, ManifestEntryInput, PaymentMode};

let one = client.data_put_public(b"first file", PaymentMode::Auto).await?;    // pays
let two = client.data_put_public(b"second file", PaymentMode::Auto).await?;   // pays

let built = client                                                            // free
    .build_manifest_with_options(
        &[
            ManifestEntryInput::public(&one.address).with_path("notes/one.txt"),
            ManifestEntryInput::public(&two.address).with_path("notes/two.txt"),
        ],
        &BuildManifestOptions { name: Some("example".into()), ..Default::default() },
    )
    .await?;
// built.link is None when over 1,500 bytes: share built.manifest (Vec<u8>) instead

let decoded = match &built.link {
    Some(link) => client.decode_manifest_link(link, true).await?,             // free
    None => client.decode_manifest(&built.manifest, true).await?,
};
for e in &decoded.entries {
    println!("{}: {:?} bytes", e.effective_name, e.exact_size);
}
```

`build_manifest(&entries)` uses the default options. `ManifestEntryInput::embedded(hex)` makes an embedded entry; `BuildManifestOptions` has `keep_shrunk_data_maps` (default `false`: roots are embedded). Sizes are `Option<u64>`. On `GrpcClient` too.

Runnable example: `antd-rust/examples/10-manifests.rs`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-rust
ANTD_BASE_URL=http://localhost:8082 cargo run --example 10-manifests
```

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
