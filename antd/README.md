# antd — Autonomi Network Daemon

A REST + gRPC gateway daemon that connects your applications to the Autonomi decentralized network. Written in Rust using Axum (REST) and Tonic (gRPC).

## Building

```bash
cd antd
cargo build           # Debug build
cargo build --release # Release build
```

antd depends on `ant-core` (from [WithAutonomi/ant-client](https://github.com/WithAutonomi/ant-client)) which is fetched automatically via Cargo git dependency. No sibling repos are needed to build antd itself.

## Running

```bash
# Default (connects to the default Autonomi network)
cargo run

# Local testnet (use `ant dev start` to start a devnet first)
ANTD_PEERS="/ip4/..." \
AUTONOMI_WALLET_KEY="hex_key" \
EVM_RPC_URL="http://127.0.0.1:8545" \
EVM_PAYMENT_TOKEN_ADDRESS="0x..." \
EVM_PAYMENT_VAULT_ADDRESS="0x..." \
cargo run -- --network local

# With dynamic ports (for managed mode / port discovery)
cargo run -- --network local --rest-port 0 --grpc-port 0
```

Or use the `ant dev start` CLI to start a full local testnet automatically:

```bash
pip install -e ant-dev/
ant dev start    # Starts devnet + antd with all env vars configured
```

Note: `ant dev start` requires the [ant-node](https://github.com/WithAutonomi/ant-node) repo cloned as a sibling to ant-sdk (for the `ant-devnet` binary).

## Configuration

All options can be set via CLI flags or environment variables:

| Flag | Env Var | Default | Description |
|------|---------|---------|-------------|
| `--rest-addr` | `ANTD_REST_ADDR` | `127.0.0.1:8082` | REST API listen address (loopback only by default — see [Security](#security-defaults)) |
| `--grpc-addr` | `ANTD_GRPC_ADDR` | `127.0.0.1:50051` | gRPC listen address (loopback only by default — see [Security](#security-defaults)) |
| `--rest-port` | `ANTD_REST_PORT` | *(from addr)* | Override REST port (use 0 for OS-assigned) |
| `--grpc-port` | `ANTD_GRPC_PORT` | *(from addr)* | Override gRPC port (use 0 for OS-assigned) |
| `--network` | `ANTD_NETWORK` | `default` | Network mode: `default`, `local` |
| `--peers` | `ANTD_PEERS` | *(none)* | Comma-separated bootstrap peer multiaddrs |
| `--cors` | `ANTD_CORS` | `false` | Enable CORS headers (restricted to localhost) |

### Wallet & EVM Configuration

| Env Var | Description |
|---------|-------------|
| `AUTONOMI_WALLET_KEY` | Hex-encoded wallet private key for payments (direct wallet mode) |
| `EVM_RPC_URL` | EVM JSON-RPC endpoint (default: `http://127.0.0.1:8545`) |
| `EVM_PAYMENT_TOKEN_ADDRESS` | Payment token contract address |
| `EVM_PAYMENT_VAULT_ADDRESS` | Payment vault contract address |

antd supports two wallet modes:
- **Direct wallet**: Set `AUTONOMI_WALLET_KEY` — antd signs payment transactions internally
- **External signer**: Set only `EVM_RPC_URL` (no private key) — use the two-phase upload API (`/v1/upload/prepare` + `/v1/upload/finalize`) to sign transactions externally

## Security defaults

antd binds to `127.0.0.1` only by default on both REST and gRPC. It does not implement authentication on either transport — the security model assumes the host running antd is trusted and that network exposure is opt-in.

To expose antd on the network (e.g. a LAN service, a container with port mapping), pass an explicit bind address:

```bash
antd --rest-addr 0.0.0.0:8082 --grpc-addr 0.0.0.0:50051
# or
ANTD_REST_ADDR=0.0.0.0:8082 ANTD_GRPC_ADDR=0.0.0.0:50051 antd
```

When binding to a non-loopback address you are responsible for firewalling the ports — anything reachable on those ports can read your wallet balance, trigger `wallet/approve` transactions, and upload through your paid account. Most users should leave the defaults alone.

## Port Discovery

On startup, antd writes a `daemon.port` file containing the actual REST port, gRPC port, and PID. All SDKs read this file for automatic daemon discovery. See the [root README](../README.md#port-discovery) for details.

## API Endpoints

### REST API (default: `http://localhost:8082`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| **Health** | | |
| `GET` | `/health` | Health check and network status |
| **Data** | (private = unqualified verb; `_public` is the suffix) | |
| `POST` | `/v1/data` | Store private (encrypted) data (accepts `payment_mode`); returns the DataMap to the caller |
| `POST` | `/v1/data/get` | Retrieve private data by DataMap (body: `{data_map}`) |
| `POST` | `/v1/data/public` | Store public data (accepts `payment_mode`); also stores the DataMap on-network and returns its address |
| `GET` | `/v1/data/public/{address}` | Retrieve public data by address |
| `POST` | `/v1/data/cost` | Estimate data storage cost (accepts `payment_mode`) |
| **Chunks** | | |
| `POST` | `/v1/chunks` | Store a raw chunk |
| `GET` | `/v1/chunks/{address}` | Retrieve a chunk |
| **Files** | (same convention as data) | |
| `POST` | `/v1/files` | Upload a file privately (accepts `payment_mode`); returns the DataMap |
| `POST` | `/v1/files/get` | Download a file from a DataMap (body: `{data_map, dest_path}`) |
| `POST` | `/v1/files/public` | Upload a file publicly (accepts `payment_mode`); stores the DataMap on-network and returns its address |
| `POST` | `/v1/files/public/get` | Download a public file by address (body: `{address, dest_path}`) |
| `POST` | `/v1/files/cost` | Estimate file upload cost (accepts `payment_mode`) |
| **External Signer** | | |
| `POST` | `/v1/data/prepare` | Prepare data upload for external signing |
| `POST` | `/v1/upload/prepare` | Prepare file upload for external signing |
| `POST` | `/v1/upload/finalize` | Finalize upload with external tx hashes |
| **Wallet** | | |
| `GET` | `/v1/wallet/address` | Get wallet public address |
| `GET` | `/v1/wallet/balance` | Get token and gas balances |
| `POST` | `/v1/wallet/approve` | Approve token spend for payment contracts |
### gRPC API (default: `localhost:50051`)

gRPC services mirror the REST API. Proto definitions are in `proto/antd/v1/`:

- `HealthService` — Health check
- `DataService` — Public/private data operations
- `ChunkService` — Raw chunk operations
- `FileService` — File upload/download *(stub)*
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
│   ├── files.proto
│   └── events.proto
└── src/
    ├── main.rs             # Entry point, P2P node + client setup
    ├── config.rs           # CLI/env configuration
    ├── error.rs            # Error types + ant-core error mapping
    ├── state.rs            # Shared daemon state (Client, pending uploads)
    ├── port_file.rs        # Port file write/cleanup for SDK discovery
    ├── types.rs            # Request/response types
    ├── rest/               # Axum REST handlers
    │   ├── mod.rs          # Router + CORS
    │   ├── data.rs         # Data put/get/cost
    │   ├── chunks.rs       # Chunk put/get
    │   ├── files.rs        # File/dir upload/download/cost
    │   ├── upload.rs       # External signer two-phase upload
    │   ├── wallet.rs       # Wallet address/balance/approve
    │   └── events.rs       # Event streaming (stub)
    └── grpc/               # Tonic gRPC service
        ├── mod.rs
        └── service.rs
```
