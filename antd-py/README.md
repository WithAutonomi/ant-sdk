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
print(f"Address: {result.address}, Cost: {result.cost}")

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
| `data_put(data: bytes, payment_mode=PaymentMode.AUTO)` | `DataPutResult` | Store private (encrypted) data; returns caller-held DataMap |
| `data_get(data_map: str)` | `bytes` | Retrieve private data from a caller-held DataMap |
| `data_put_public(data: bytes, payment_mode=PaymentMode.AUTO)` | `DataPutPublicResult` | Store public data; returns on-network DataMap address |
| `data_get_public(address: str)` | `bytes` | Retrieve public data by address |
| `data_cost(data: bytes, payment_mode=PaymentMode.AUTO)` | `UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

`PaymentMode` is a typed enum (`PaymentMode.AUTO`, `PaymentMode.MERKLE`, `PaymentMode.SINGLE`). Private uploads use the unqualified verb (`data_put` / `data_get`); the `_public` suffix marks the public variant.

#### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunk_put(data: bytes)` | `PutResult` | Store a raw chunk |
| `chunk_get(address: str)` | `bytes` | Retrieve a chunk |

#### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `file_put(path: str, payment_mode=PaymentMode.AUTO)` | `FilePutResult` | Upload a file privately; returns caller-held DataMap |
| `file_get(data_map: str, dest: str)` | `None` | Download a private file from a caller-held DataMap |
| `file_put_public(path: str, payment_mode=PaymentMode.AUTO)` | `FilePutPublicResult` | Upload a file publicly; returns on-network DataMap address |
| `file_get_public(address: str, dest: str)` | `None` | Download a public file by address |
| `file_cost(path: str, is_public: bool, payment_mode=PaymentMode.AUTO)` | `UploadCostEstimate` | Estimate file cost — size, chunks, gas, payment mode |

## Models

All models are frozen dataclasses (immutable).

| Model | Fields | Description |
|-------|--------|-------------|
| `HealthStatus` | `ok: bool`, `network: str` | Health check result |
| `PutResult` | `cost: str`, `address: str` | Write operation result |

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
python examples/08_grpc.py         # gRPC transport (instead of REST)
```

Or use the dev CLI:

```bash
ant dev example data
ant dev example all
```
