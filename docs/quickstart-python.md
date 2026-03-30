# Python Quickstart

A comprehensive guide to using the Autonomi network with the Python SDK.

## Setup

```bash
# Install with REST transport
pip install antd[rest]

# Start local testnet
pip install -e ant-dev/
ant dev start
```

## Connecting

```python
from antd import AntdClient, AsyncAntdClient

# Synchronous client (REST, default)
client = AntdClient()

# Async client
aclient = AsyncAntdClient()

# Custom endpoint
client = AntdClient(transport="rest", base_url="http://localhost:8082")

# gRPC transport
client = AntdClient(transport="grpc", target="localhost:50051")
```

## Health Check

```python
status = client.health()
print(f"Healthy: {status.ok}")
print(f"Network: {status.network}")  # "local", "default", or "alpha"
```

## Public Data

Store and retrieve arbitrary bytes on the network.

```python
# Store
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Retrieve
data = client.data_get_public(result.address)
print(data.decode())  # "Hello, Autonomi!"

# Cost estimation
cost = client.data_cost(b"some data")
print(f"Would cost: {cost} atto tokens")
```

## Private Data

Encrypted data — only accessible with the data map.

```python
# Store (self-encrypting)
result = client.data_put_private(b"secret message")
data_map = result.address  # Keep this secret!

# Retrieve (decrypt)
data = client.data_get_private(data_map)
print(data.decode())
```

## Files

```python
# Upload a file
result = client.file_upload_public("/path/to/file.txt")
print(f"File address: {result.address}")

# Download a file
client.file_download_public(result.address, "/path/to/output.txt")

# Upload a directory
result = client.dir_upload_public("/path/to/directory")

# Download a directory
client.dir_download_public(result.address, "/path/to/output_dir")

# Cost estimation
cost = client.file_cost("/path/to/file.txt")
```

## Graph Entries (DAG Nodes)

```python
import os
from antd import GraphDescendant

key = os.urandom(32).hex()
content = os.urandom(32).hex()

# Create a root node
result = client.graph_entry_put(
    key,
    parents=[],
    content=content,
    descendants=[],
)
print(f"Graph entry: {result.address}")

# Read
entry = client.graph_entry_get(result.address)
print(f"Owner: {entry.owner}")
print(f"Content: {entry.content}")
print(f"Parents: {entry.parents}")
print(f"Descendants: {entry.descendants}")

# Check existence
exists = client.graph_entry_exists(result.address)
```

## Async Usage

```python
import asyncio
from antd import AsyncAntdClient

async def main():
    client = AsyncAntdClient()

    status = await client.health()
    print(f"Network: {status.network}")

    result = await client.data_put_public(b"async data")
    data = await client.data_get_public(result.address)
    print(data.decode())

    await client.close()

asyncio.run(main())
```

## Error Handling

```python
from antd import (
    AntdError,
    NotFoundError,
    AlreadyExistsError,
    BadRequestError,
    PaymentError,
    NetworkError,
    ForkError,
    TooLargeError,
    InternalError,
)

try:
    client.data_get_public("nonexistent")
except NotFoundError:
    print("Not found")
except PaymentError:
    print("Payment issue")
except NetworkError:
    print("Network unreachable")
except AntdError as e:
    print(f"Error ({e.status_code}): {e}")
```

## Interactive Playground

```bash
ant dev playground
```

Opens a Python REPL with `client` pre-connected and all types imported.

## Examples

```bash
# Run individual examples
ant dev example connect
ant dev example data
ant dev example all

# Or directly
python antd-py/examples/01_connect.py
python antd-py/examples/02_data.py
```

See `antd-py/examples/` for the complete set of examples.
