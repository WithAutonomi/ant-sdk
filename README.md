# ant-sdk

A developer-friendly SDK for the [Autonomi](https://autonomi.com) decentralized network. Store data, manage mutable pointers, build DAGs, and more — from Python, C#, or AI agents.

## Architecture

```
┌─────────────┐  ┌──────────────┐  ┌──────────────┐
│  antd-py    │  │ antd-csharp  │  │  antd-mcp    │
│ Python SDK  │  │   C# SDK     │  │  MCP Server  │
└──────┬──────┘  └──────┬───────┘  └──────┬───────┘
       │  REST / gRPC   │                 │ REST
       └────────┬───────┘─────────────────┘
                │
         ┌──────┴──────┐
         │    antd     │
         │ Rust Daemon │
         │ REST + gRPC │
         └──────┬──────┘
                │
         ┌──────┴──────┐
         │  Autonomi   │
         │   Network   │
         └─────────────┘
```

**antd** is a local gateway daemon (written in Rust) that exposes the Autonomi network via REST and gRPC APIs. The SDKs and MCP server talk to antd — your application code never touches the network directly.

## Components

| Component | Language | Description |
|-----------|----------|-------------|
| [`antd/`](antd/) | Rust | REST + gRPC gateway daemon |
| [`antd-py/`](antd-py/) | Python | SDK with sync/async clients, REST + gRPC transports |
| [`antd-csharp/`](antd-csharp/) | C# | SDK with async client, REST + gRPC transports |
| [`antd-mcp/`](antd-mcp/) | Python | MCP server exposing 31 tools for AI agents (Claude, etc.) |
| [`ant-dev/`](ant-dev/) | Python | Developer CLI for local environment management |

## Quickstart (5 minutes)

### Prerequisites

- **Rust** toolchain (for building antd and the Autonomi network)
- **Python 3.10+** (for the Python SDK and dev CLI)
- **.NET 8 SDK** (optional, for the C# SDK)
- **autonomi** repo cloned as a sibling: `git clone https://github.com/maidsafe/autonomi ../autonomi`

### Option A: Using the `ant` CLI

```bash
# Install the dev CLI
pip install -e ant-dev/

# Start a local testnet (EVM + Autonomi network + antd daemon)
ant dev start

# Check status
ant dev status

# Run an example
ant dev example data

# Interactive playground
ant dev playground

# Tear down
ant dev stop
```

### Option B: Using shell scripts

```bash
# Unix
./scripts/start-local.sh

# Windows (PowerShell)
.\scripts\start-local.ps1
```

### Write your first app (Python)

```python
from antd import AntdClient

client = AntdClient()

# Check daemon health
status = client.health()
print(f"Network: {status.network}")

# Store data on the network
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Retrieve it back
data = client.data_get_public(result.address)
print(data.decode())  # "Hello, Autonomi!"
```

### Write your first app (C#)

```csharp
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var status = await client.HealthAsync();
Console.WriteLine($"Network: {status.Network}");

var result = await client.DataPutPublicAsync(
    Encoding.UTF8.GetBytes("Hello, Autonomi!")
);
Console.WriteLine($"Address: {result.Address}");

var data = await client.DataGetPublicAsync(result.Address);
Console.WriteLine(Encoding.UTF8.GetString(data));
```

## Data Primitives

The Autonomi network provides these core primitives, all accessible through the SDKs:

| Primitive | Mutability | Description |
|-----------|-----------|-------------|
| **Data** | Immutable | Store/retrieve arbitrary byte blobs (public or private/encrypted) |
| **Chunks** | Immutable | Low-level content-addressed storage |
| **Pointers** | Mutable | Owner-controlled references to other resources |
| **Scratchpads** | Mutable | Versioned mutable storage with counter |
| **Graph Entries** | Append-only | DAG nodes with parent/descendant links |
| **Registers** | Mutable | 32-byte owned mutable values |
| **Vaults** | Mutable | Private encrypted key-value storage |
| **Files** | Immutable | File/directory upload with archive manifests |

## Developer CLI Reference

```
ant dev start [--autonomi-dir PATH] [--no-build]    # Start local environment
ant dev stop                                         # Tear down everything
ant dev status                                       # Show running processes + health
ant dev example <name> [-l python|csharp]             # Run named example
ant dev init <language> [--name NAME] [--dir PATH]    # Scaffold new project
ant dev wallet [show|fund]                            # Show/fund test wallet
ant dev logs [--follow]                               # Stream antd logs
ant dev reset                                         # Stop + clean + restart
ant dev playground [--transport rest|grpc]             # Interactive Python REPL
```

## Documentation

- [Architecture Guide](docs/architecture.md) — Autonomi mental model, data primitives, payment model
- [Tutorial: Store & Retrieve Data](docs/tutorial-store-retrieve.md) — Your first read/write operations
- [Tutorial: Key-Value Store](docs/tutorial-key-value-store.md) — Build a KV store with registers + pointers
- [Tutorial: Mutable Config](docs/tutorial-mutable-config.md) — Mutable config via pointers and scratchpads
- [Python Quickstart](docs/quickstart-python.md) — Comprehensive Python SDK guide
- [C# Quickstart](docs/quickstart-csharp.md) — Comprehensive C# SDK guide

## License

See individual component directories for license information.
