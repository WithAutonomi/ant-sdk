# antd-py -- Python SDK for Autonomi

Python SDK for the antd daemon. Provides synchronous and asynchronous clients with both REST and gRPC transports.

## Installation

```bash
# REST transport (recommended)
pip install antd[rest]

# gRPC transport
pip install antd[grpc]

# Both transports
pip install antd[all]

# From source (development)
pip install -e ".[all]"
```

## Quick Start

```python
from antd import AntdClient

client = AntdClient()  # REST transport, localhost:8082

# Health check
status = client.health()
print(f"{status.network} -- healthy: {status.ok}")

# Store and retrieve data
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}, chunks: {result.chunks_stored}")

data = client.data_get_public(result.address)
print(data.decode())  # "Hello, Autonomi!"
```

## Transports

```python
from antd import AntdClient, AsyncAntdClient

# REST (default)
client = AntdClient(transport="rest", base_url="http://localhost:8082", timeout=30)

# gRPC (wallet operations and payment_mode are available via REST only)
client = AntdClient(transport="grpc", target="localhost:50051")

# Async REST
aclient = AsyncAntdClient(transport="rest")
status = await aclient.health()
await aclient.close()
```

## API Reference

### Factory Functions

| Function | Description |
|----------|-------------|
| `AntdClient(transport="rest", **kwargs)` | Create a synchronous client |
| `AsyncAntdClient(transport="rest", **kwargs)` | Create an asynchronous client |

### Client Methods

#### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `health()` | `HealthStatus` | Check daemon health — also surfaces antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |

#### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `data_put_public(data, payment_mode=...)` | `DataPutPublicResult` | Store public data — DataMap is stored on-network |
| `data_get_public(address: str)` | `bytes` | Retrieve public data by address |
| `data_put(data, payment_mode=...)` | `DataPutResult` | Store private (encrypted) data — DataMap returned to caller (NOT stored on-network) |
| `data_get(data_map: str)` | `bytes` | Retrieve private data using a caller-held DataMap |
| `data_cost(data, payment_mode=...)` | `UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

#### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunk_put(data: bytes)` | `PutResult` | Store a raw chunk |
| `chunk_get(address: str)` | `bytes` | Retrieve a chunk |

#### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `file_put(path, payment_mode=...)` | `FilePutResult` | Upload a file privately — DataMap returned to caller (NOT stored on-network) |
| `file_get(data_map, dest_path)` | `None` | Download a private file using a caller-held DataMap |
| `file_put_public(path, payment_mode=...)` | `FilePutPublicResult` | Upload a file publicly — DataMap is stored on-network |
| `file_get_public(address, dest_path)` | `None` | Download a public file by address |
| `file_cost(path, is_public, payment_mode=...)` | `UploadCostEstimate` | Estimate file cost — size, chunks, gas, payment mode |

#### External Signer

Two-phase upload — daemon prepares the payment intent, caller signs + submits the payForQuotes tx, daemon finalizes once the chain confirms. See `examples/07_external_signer.py` + `docs/external-signer-flow.md`.

| Method | Returns | Description |
|--------|---------|-------------|
| `prepare_upload(path, visibility=None)` | `PrepareUploadResult` | Prepare a file upload for external signing |
| `prepare_upload_public(path)` | `PrepareUploadResult` | Convenience for `prepare_upload(path, visibility="public")` |
| `prepare_data_upload(data, visibility=None)` | `PrepareUploadResult` | Prepare a data upload for external signing |
| `prepare_chunk_upload(data)` | `PrepareChunkResult` | Prepare a single chunk for external-signer publish |
| `finalize_upload(upload_id, tx_hashes)` | `FinalizeUploadResult` | Submit a prepared upload after external payment. `data_map_address` populated when prepare used `visibility="public"` |
| `finalize_chunk_upload(upload_id, tx_hashes)` | `str` | Submit a prepared chunk after external payment; returns the chunk address |

## Models

All models are frozen dataclasses (immutable).

| Model | Fields | Description |
|-------|--------|-------------|
| `HealthStatus` | `ok`, `network`, `version`, `evm_network`, `uptime_seconds`, `build_commit`, `payment_token_address`, `payment_vault_address` | Health check result (diagnostic fields require antd ≥ 0.4.0) |
| `PutResult` | `cost`, `address` | Result of `chunk_put` only |
| `DataPutResult` | `data_map`, `chunks_stored`, `payment_mode_used` | Private data put — DataMap returned to caller |
| `DataPutPublicResult` | `address`, `chunks_stored`, `payment_mode_used` | Public data put — DataMap stored on-network |
| `FilePutResult` | `data_map`, `storage_cost_atto`, `gas_cost_wei`, `chunks_stored`, `payment_mode_used` | Private file put — DataMap returned to caller |
| `FilePutPublicResult` | `address`, `storage_cost_atto`, `gas_cost_wei`, `chunks_stored`, `payment_mode_used` | Public file put — DataMap stored on-network |
| `UploadCostEstimate` | `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, `payment_mode` | Pre-upload cost breakdown |

## Error Handling

All errors inherit from `AntdError`:

```python
from antd import AntdClient, AntdError, NotFoundError, PaymentError

client = AntdClient()

try:
    data = client.data_get_public("nonexistent_address")
except NotFoundError:
    print("Data not found on the network")
except PaymentError:
    print("Insufficient funds")
except AntdError as e:
    print(f"Error ({e.status_code}): {e}")
```

| Exception | HTTP | gRPC | Description |
|-----------|------|------|-------------|
| `BadRequestError` | 400 | `INVALID_ARGUMENT` | Invalid request parameters |
| `PaymentError` | 402 | `FAILED_PRECONDITION` | Wallet/payment issue |
| `NotFoundError` | 404 | `NOT_FOUND` | Resource not found |
| `AlreadyExistsError` | 409 | `ALREADY_EXISTS` | Resource already exists |
| `ForkError` | 409 | `ABORTED` | Version conflict |
| `TooLargeError` | 413 | `RESOURCE_EXHAUSTED` | Payload too large |
| `InternalError` | 500 | `INTERNAL` | Server error |
| `NetworkError` | 502 | `UNAVAILABLE` | Network unreachable |

## Examples

Run examples from the `examples/` directory:

```bash
# Requires antd daemon running on local testnet
python examples/01_connect.py      # Health check
python examples/02_data.py         # Store/retrieve data
python examples/03_chunks.py       # Raw chunks
python examples/04_files.py        # File upload/download
python examples/06_private_data.py # Private data with data maps
python examples/07_external_signer.py # External-signer file + chunk upload
python examples/08_grpc.py          # gRPC transport (requires antd[grpc])
python examples/08_grpc.py         # gRPC transport (instead of REST)
```

Or use the dev CLI:

```bash
ant dev example data
ant dev example all
```
