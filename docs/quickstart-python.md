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
client = AntdClient(transport="rest", base_url="http://localhost:8080")

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

## Pointers (Mutable References)

```python
import os
from antd import PointerTarget

secret_key = os.urandom(32).hex()

# Store two versions of data
v1 = client.data_put_public(b"version 1")
v2 = client.data_put_public(b"version 2")

# Create pointer to v1
target = PointerTarget(kind="chunk", address=v1.address)
ptr = client.pointer_create(secret_key, target)
print(f"Pointer: {ptr.address}")

# Read pointer
pointer = client.pointer_get(ptr.address)
print(f"Points to: {pointer.target.address}")
print(f"Counter: {pointer.counter}")

# Update to v2
new_target = PointerTarget(kind="chunk", address=v2.address)
client.pointer_update(secret_key, new_target)

# Check existence
exists = client.pointer_exists(ptr.address)

# Cost estimation
cost = client.pointer_cost(secret_key)  # Takes public key
```

## Scratchpads (Versioned Mutable Storage)

```python
import os

secret_key = os.urandom(32).hex()

# Create
result = client.scratchpad_create(
    secret_key,
    content_type=1,
    data=b"initial data",
)
print(f"Scratchpad: {result.address}")

# Read
pad = client.scratchpad_get(result.address)
print(f"Data: {pad.data}")
print(f"Counter: {pad.counter}")
print(f"Encoding: {pad.data_encoding}")

# Update
client.scratchpad_update(secret_key, content_type=1, data=b"updated data")

# Check existence
exists = client.scratchpad_exists(result.address)
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

## Registers (32-byte Values)

```python
import os

secret_key = os.urandom(32).hex()

# Create with initial value (64 hex chars = 32 bytes)
initial = "0" * 64
result = client.register_create(secret_key, initial)
print(f"Register: {result.address}")

# Read
reg = client.register_get(result.address)
print(f"Value: {reg.value}")

# Update
new_value = os.urandom(32).hex()
client.register_update(secret_key, new_value)
```

## Vaults (Encrypted Key-Value)

```python
import os

secret_key = os.urandom(32).hex()

# Store
cost = client.vault_put(secret_key, b"vault data", content_type=42)
print(f"Cost: {cost} atto tokens")

# Retrieve
vault = client.vault_get(secret_key)
print(f"Data: {vault.data}")
print(f"Content type: {vault.content_type}")
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
ant dev example pointers
ant dev example all

# Or directly
python antd-py/examples/01_connect.py
python antd-py/examples/02_data.py
```

See `antd-py/examples/` for the complete set of 10 examples.
