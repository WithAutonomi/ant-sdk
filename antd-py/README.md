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

# gRPC
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
| `health()` | `HealthStatus` | Check daemon health |

#### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `data_put_public(data: bytes)` | `PutResult` | Store public data |
| `data_get_public(address: str)` | `bytes` | Retrieve public data |
| `data_put_private(data: bytes)` | `PutResult` | Store private (encrypted) data |
| `data_get_private(data_map: str)` | `bytes` | Retrieve private data |
| `data_cost(data: bytes)` | `str` | Estimate storage cost |

#### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunk_put(data: bytes)` | `PutResult` | Store a raw chunk |
| `chunk_get(address: str)` | `bytes` | Retrieve a chunk |

#### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `file_upload_public(path: str)` | `PutResult` | Upload a file |
| `file_download_public(address: str, dest: str)` | `None` | Download a file |
| `dir_upload_public(path: str)` | `PutResult` | Upload a directory |
| `dir_download_public(address: str, dest: str)` | `None` | Download a directory |
| `archive_get_public(address: str)` | `Archive` | Get archive manifest |
| `archive_put_public(archive: Archive)` | `PutResult` | Create archive manifest |
| `file_cost(path: str, is_public: bool, include_archive: bool)` | `str` | Estimate file cost |

## Models

All models are frozen dataclasses (immutable).

| Model | Fields | Description |
|-------|--------|-------------|
| `HealthStatus` | `ok: bool`, `network: str` | Health check result |
| `PutResult` | `cost: str`, `address: str` | Write operation result |
| `ArchiveEntry` | `path`, `address`, `created`, `modified`, `size` | Archive file entry |
| `Archive` | `entries: list[ArchiveEntry]` | Archive manifest |

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
```

Or use the dev CLI:

```bash
ant dev example data
ant dev example all
```
