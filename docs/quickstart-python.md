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

# Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
est = client.data_cost(b"some data")
print(f"Estimate: {est.file_size} bytes in {est.chunk_count} chunks, {est.cost} atto, gas {est.estimated_gas_cost_wei} wei, mode {est.payment_mode}")
```

## Private Data

Encrypted data — only accessible with the data map.

```python
# Store (self-encrypting)
result = client.data_put(b"secret message")
data_map = result.data_map  # Keep this secret!

# Retrieve (decrypt)
data = client.data_get(data_map)
print(data.decode())
```

## Files

```python
# Upload a file
result = client.file_put_public("/path/to/file.txt")
print(f"File address: {result.address}")

# Download a file
client.file_get_public(result.address, "/path/to/output.txt")

# Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
est = client.file_cost("/path/to/file.txt")
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```python
owner = client.pointer_keys()[0]                # a pointer antd can write

v1 = client.data_put_public(b"version 1").address
v2 = client.data_put_public(b"version 2").address

client.pointer_create(owner, v1)                # pays; counter 0
client.pointer_update(owner, v2)                # pays again; counter 1
target = client.pointer_resolve(owner).target   # == v2 (free)

f = client.pointer_finality(owner)              # free
print(f.status.value, f.counter)                # open 1
```

`pointer_transfer`, `pointer_get`, `pointer_controller`, `pointer_prepare` and `pointer_finalize` complete the set, on the sync and async clients over REST and gRPC alike.

Runnable example: `antd-py/examples/09_pointers.py`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
ANTD_POINTER_OWNER=<address> python antd-py/examples/09_pointers.py
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

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```python
from antd import ManifestEntryInput

a = client.data_put_public(b"note one").address   # pays
b = client.data_put_public(b"note two").address   # pays

built = client.build_manifest(                    # free
    [
        ManifestEntryInput(address=a, path="notes/one.txt"),
        ManifestEntryInput(address=b, path="notes/two.txt"),
    ],
    name="example",
)
print(built.link)                                 # None if over 1,500 bytes: share built.manifest instead

decoded = client.decode_manifest_link(built.link, resolve=True)   # free
for e in decoded.entries:
    print(e.effective_name, e.kind, e.exact_size)
```

`decode_manifest(bytes, resolve=False)` takes raw `.ant` bytes instead of a link. Pass `data_map=` instead of `address=` for an embedded entry, and `embed_roots=False` to keep shrunk DataMaps as given. Works on the sync and async clients, over REST and gRPC.

Runnable example: `antd-py/examples/10_manifests.py`. Its two uploads pay; the manifest calls do not.

```bash
ANTD_BASE_URL=http://localhost:8082 python antd-py/examples/10_manifests.py
```

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
