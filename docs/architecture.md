# Architecture Guide

This document explains the Autonomi network mental model, how ant-sdk fits in, and the key concepts you need to build applications.

## What is Autonomi?

Autonomi is a decentralized, peer-to-peer data network. Instead of storing data on a central server (AWS, GCP, etc.), your data is distributed across a global mesh of nodes. Key properties:

- **Content-addressed**: Immutable data is identified by its cryptographic hash. The same content always produces the same address.
- **Self-encrypting**: Private data is encrypted before storage — the network never sees plaintext.
- **Permanent**: Once data is stored, it persists as long as the network exists. There are no monthly bills or expiring storage.
- **Pay-once**: You pay a one-time storage fee in network tokens. No ongoing costs.

## Where ant-sdk Fits

```
Your Application
       │
       │  Python / C# / Kotlin / Swift SDK calls
       ▼
   ┌───────┐
   │ antd  │   Local daemon process
   │       │   REST API (:8082) + gRPC (:50051)
   └───┬───┘
       │
       │  Autonomi client library (Rust)
       ▼
   ┌───────────────┐
   │   Autonomi    │   Decentralized P2P network
   │   Network     │   Thousands of nodes worldwide
   └───────────────┘
```

**antd** is a local gateway daemon. It:

1. Maintains a connection to the Autonomi network
2. Manages your wallet for payments
3. Exposes a clean REST + gRPC API
4. Handles serialization, encryption, chunking, and payment negotiation

Your application code never touches the network directly. You call `client.data_put_public(data)` and antd handles everything.

## Data Primitives

### Immutable Data

#### Data (Public & Private)

The simplest primitive. Store arbitrary bytes, get back an address.

```
Store:    bytes  ──▶  antd  ──▶  address (hex)
Retrieve: address ──▶  antd  ──▶  bytes
```

- **Public**: Anyone with the address can read it.
- **Private**: Data is self-encrypted. You get back a "data map" (encrypted metadata) instead of a raw address. Only someone with the data map can decrypt and read the original data.

Use for: documents, images, configuration snapshots, backups.

#### Chunks

Low-level content-addressed storage. Data is the raw chunk — one block on the network. Most applications should use the higher-level Data API instead, which handles chunking large payloads automatically.

Use for: custom chunking strategies, direct network interaction.

#### Files

Upload/download local files and directories. Under the hood, files are chunked and stored as Data.

```
Upload:    local path  ──▶  antd  ──▶  address
Download:  address     ──▶  antd  ──▶  local path
```

Use for: file hosting, static websites, media storage.

## Payment Model

Every write operation costs network tokens (measured in "atto tokens" — 1 token = 10^18 atto).

```python
# Estimate before committing — returns size, chunks, gas, and payment mode
est = client.data_cost(data)
print(f"This will cost {est.cost} atto tokens ({est.chunk_count} chunks, gas {est.estimated_gas_cost_wei} wei)")

# The actual write returns the real cost
result = client.data_put_public(data)
print(f"Paid {result.cost} atto tokens")
```

- **Cost estimation**: All write operations have a corresponding `*_cost` method.
- **One-time payment**: You pay once. Data persists forever.
- **Reads are free**: Retrieving data doesn't cost tokens.
- **Local testnet**: The EVM testnet provides unlimited funds for development.

## Content Addressing vs Cloud Storage

| Aspect | Cloud (S3, etc.) | Autonomi |
|--------|-------------------|----------|
| Addressing | Arbitrary keys | Content hash (immutable) |
| Persistence | Until you stop paying | Permanent (one-time payment) |
| Access control | IAM policies | Cryptographic keys |
| Redundancy | Configurable | Built-in (network-wide replication) |
| Privacy | Trust the provider | Self-encrypting (zero knowledge) |
| Mutability | Overwrite anything | Immutable by design |
| Cost model | Per-request + storage/month | One-time write fee, reads are free |

## Key Design Patterns

## Security Model

- **Secret keys**: 32-byte hex-encoded keys used for private data operations.
- **Never share secret keys**: Treat them like passwords. The public key (derived from the secret key) is safe to share.
- **Private data**: Self-encrypted using the network's encryption scheme. The data map is needed for decryption.
- **No access revocation**: Once data is public, it cannot be made private. Plan your key management accordingly.

## Event System Status

The daemon defines infrastructure for streaming events to clients, but it is currently **stubbed and non-functional**. Both transport mechanisms exist in code but return empty streams:

- **REST SSE** (`GET /v1/data/public/{addr}/stream`): The route is registered and returns a chunked HTTP response, but no events are emitted. The handler in `antd/src/rest/events.rs` is a stub.
- **gRPC streaming** (`EventService.Subscribe`): The gRPC service is defined in the proto and compiled, but the server-side implementation returns an empty stream immediately.
- **Event types**: `ClientEventDto` is defined in `antd/src/types.rs` with fields for `kind`, `records_paid`, `records_already_paid`, and `tokens_spent`, but all fields are marked `#[allow(dead_code)]`.

These are planned for future implementation. The intended use is upload progress tracking and completion notifications.
