# antd — Autonomi Network Daemon

A REST + gRPC gateway daemon that connects your applications to the Autonomi decentralized network. Written in Rust using Axum (REST) and Tonic (gRPC).

## Building

```bash
cd antd
cargo build           # Debug build
cargo build --release # Release build
```

## Running

```bash
# Default (connects to the default Autonomi network)
cargo run

# Local testnet
AUTONOMI_WALLET_KEY="your_key" ANT_PEERS="/ip4/..." cargo run -- --network local

# With all options
cargo run -- \
  --rest-addr 0.0.0.0:8082 \
  --grpc-addr 0.0.0.0:50051 \
  --network local \
  --peers "/ip4/127.0.0.1/udp/..." \
  --cors
```

Or use the `ant dev start` CLI to start a full local testnet automatically.

## Configuration

All options can be set via CLI flags or environment variables:

| Flag | Env Var | Default | Description |
|------|---------|---------|-------------|
| `--rest-addr` | `ANTD_REST_ADDR` | `0.0.0.0:8082` | REST API listen address |
| `--grpc-addr` | `ANTD_GRPC_ADDR` | `0.0.0.0:50051` | gRPC listen address |
| `--network` | `ANTD_NETWORK` | `default` | Network mode: `default`, `local`, `alpha` |
| `--peers` | `ANTD_PEERS` | *(none)* | Comma-separated bootstrap peer multiaddrs |
| `--cors` | `ANTD_CORS` | `false` | Enable CORS headers for browser access |

Additional environment variables consumed by the underlying Autonomi client:

| Env Var | Description |
|---------|-------------|
| `AUTONOMI_WALLET_KEY` | Hex-encoded wallet secret key for payments |
| `ANT_PEERS` | Bootstrap peer multiaddrs (alternative to `--peers`) |

## Network Modes

- **`default`** — Connects to the public Autonomi mainnet.
- **`local`** — Connects to a local testnet started via `antctl local run`. Requires `ANT_PEERS` from the bootstrap cache.
- **`alpha`** — Connects to the alpha/test network.

## API Endpoints

### REST API (default: `http://localhost:8082`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/v1/data/public` | Store public data |
| `GET` | `/v1/data/public/{address}` | Retrieve public data |
| `POST` | `/v1/data/private` | Store private (encrypted) data |
| `POST` | `/v1/data/private/get` | Retrieve private data by data map |
| `POST` | `/v1/data/cost` | Estimate data storage cost |
| `POST` | `/v1/chunks` | Store a raw chunk |
| `GET` | `/v1/chunks/{address}` | Retrieve a chunk |
| `POST` | `/v1/graph` | Create a graph entry |
| `GET` | `/v1/graph/{address}` | Get a graph entry |
| `HEAD` | `/v1/graph/{address}` | Check graph entry existence |
| `POST` | `/v1/graph/cost` | Estimate graph entry cost |
| `POST` | `/v1/files/upload` | Upload a file |
| `POST` | `/v1/files/download` | Download a file |
| `POST` | `/v1/files/upload/dir` | Upload a directory |
| `POST` | `/v1/files/download/dir` | Download a directory |
| `GET` | `/v1/files/archive/{address}` | Get archive manifest |
| `POST` | `/v1/files/archive` | Create archive manifest |
| `POST` | `/v1/files/cost` | Estimate file upload cost |

### gRPC API (default: `localhost:50051`)

gRPC services mirror the REST API. Proto definitions are in `proto/antd/v1/`:

- `HealthService` — Health check
- `DataService` — Public/private data operations
- `ChunkService` — Raw chunk operations
- `GraphService` — Graph entry operations
- `FileService` — File upload/download
- `EventService` — Event streaming

## Project Structure

```
antd/
├── Cargo.toml
├── build.rs                # Proto code generation
├── proto/antd/v1/          # gRPC proto definitions
│   ├── health.proto
│   ├── common.proto
│   ├── data.proto
│   ├── chunks.proto
│   ├── graph.proto
│   ├── files.proto
│   └── events.proto
└── src/
    ├── main.rs             # Entry point
    ├── config.rs           # CLI/env configuration
    ├── error.rs            # Error types
    ├── state.rs            # Shared daemon state
    ├── types.rs            # Common types
    ├── rest/               # Axum REST handlers
    │   ├── mod.rs
    │   ├── data.rs
    │   ├── chunks.rs
    │   ├── graph.rs
    │   ├── files.rs
    │   └── events.rs
    └── grpc/               # Tonic gRPC service
        ├── mod.rs
        └── service.rs
```
