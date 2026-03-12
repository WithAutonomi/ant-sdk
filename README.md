# ant-sdk

A developer-friendly SDK for the [Autonomi](https://autonomi.com) decentralized network. Store data, manage mutable pointers, build DAGs, and more — from Go, JavaScript/TypeScript, Python, C#, Kotlin, Swift, or AI agents.

## Architecture

```
              ┌─────────────┐
              │  Autonomi   │
              │   Network   │
              └──────┬──────┘
                     │
              ┌──────┴──────┐
              │  ant-core   │
              │ Client API  │
              └──────┬──────┘
                     │
   ┌─────────────────┼─────────────────┬╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
   │                 │                 │                   ╎
┌──┴───────────┐ ┌───┴──────────┐ ┌────┴────────────┐ ┌╌╌╌┴╌╌╌╌╌╌╌╌╌╌╌┐
│     antd     │ │   Bindings   │ │    ant-mcp      │ ╎    ant-wasm    ╎
│ Rust Daemon  │ │  FFI Mobile  │ │   MCP Server    │ ╎  WebAssembly   ╎
└──┬────────┬──┘ └──────────────┘ └─────────────────┘ └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘
   │        │                                               WIP
┌──┴───┐ ┌──┴───┐
│ REST │ │ gRPC │
└──────┘ └──────┘
```

**antd** is a local gateway daemon (written in Rust) that exposes the Autonomi network via REST and gRPC APIs. The SDKs and MCP server talk to antd — your application code never touches the network directly.

## Components

| Component | Language | Description |
|-----------|----------|-------------|
| [`antd/`](antd/) | Rust | REST + gRPC gateway daemon |
| [`antd-go/`](antd-go/) | Go | SDK with context-based client, REST transport |
| [`antd-js/`](antd-js/) | TypeScript | SDK with async client, REST transport |
| [`antd-py/`](antd-py/) | Python | SDK with sync/async clients, REST + gRPC transports |
| [`antd-csharp/`](antd-csharp/) | C# | SDK with async client, REST + gRPC transports |
| [`antd-kotlin/`](antd-kotlin/) | Kotlin | SDK with coroutine-based client, REST + gRPC transports |
| [`antd-swift/`](antd-swift/) | Swift | SDK with async/await client, REST + gRPC transports (macOS) |
| [`antd-mcp/`](antd-mcp/) | Python | MCP server exposing 31 tools for AI agents (Claude, etc.) |
| [`ant-dev/`](ant-dev/) | Python | Developer CLI for local environment management |

## Quickstart (5 minutes)

### Prerequisites

- **Rust** toolchain (for building antd and the Autonomi network)
- **Go 1.21+** (optional, for the Go SDK)
- **Node.js 18+** (optional, for the JS/TS SDK)
- **Python 3.10+** (for the Python SDK and dev CLI)
- **.NET 8 SDK** (optional, for the C# SDK)
- **JDK 17+** (optional, for the Kotlin SDK)
- **Swift 5.9+ / Xcode 15+** (optional, for the Swift SDK — macOS only)
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

### Write your first app (JavaScript/TypeScript)

```typescript
import { createClient } from "antd";

const client = createClient();

const status = await client.health();
console.log(`Network: ${status.network}`);

const result = await client.dataPutPublic(Buffer.from("Hello, Autonomi!"));
console.log(`Address: ${result.address}`);

const data = await client.dataGetPublic(result.address);
console.log(data.toString()); // "Hello, Autonomi!"
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

### Write your first app (Kotlin)

```kotlin
import com.autonomi.sdk.*
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = AntdClient.createRest()

    val status = client.health()
    println("Network: ${status.network}")

    val result = client.dataPutPublic(
        "Hello, Autonomi!".toByteArray()
    )
    println("Address: ${result.address}")

    val data = client.dataGetPublic(result.address)
    println(String(data)) // "Hello, Autonomi!"

    client.close()
}
```

### Write your first app (Go)

```go
package main

import (
    "context"
    "fmt"
    "log"

    antd "github.com/maidsafe/ant-sdk/antd-go"
)

func main() {
    client := antd.NewClient(antd.DefaultBaseURL)
    ctx := context.Background()

    health, err := client.Health(ctx)
    if err != nil { log.Fatal(err) }
    fmt.Printf("Network: %s\n", health.Network)

    result, err := client.DataPutPublic(ctx, []byte("Hello, Autonomi!"))
    if err != nil { log.Fatal(err) }
    fmt.Printf("Address: %s\n", result.Address)

    data, err := client.DataGetPublic(ctx, result.Address)
    if err != nil { log.Fatal(err) }
    fmt.Println(string(data)) // "Hello, Autonomi!"
}
```

### Write your first app (Swift)

> REST/gRPC SDK requires macOS. For iOS, use the [FFI bindings](ffi/) instead.

```swift
import AntdSdk

let client = try AntdClient.createRest()

let status = try await client.health()
print("Network: \(status.network)")

let result = try await client.dataPutPublic(
    "Hello, Autonomi!".data(using: .utf8)!
)
print("Address: \(result.address)")

let data = try await client.dataGetPublic(address: result.address)
print(String(data: data, encoding: .utf8)!) // "Hello, Autonomi!"
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
- [Go Quickstart](antd-go/README.md) — Go SDK guide
- [JS/TS Quickstart](antd-js/README.md) — JavaScript/TypeScript SDK guide
- [Python Quickstart](docs/quickstart-python.md) — Comprehensive Python SDK guide
- [C# Quickstart](docs/quickstart-csharp.md) — Comprehensive C# SDK guide
- [Kotlin Quickstart](docs/quickstart-kotlin.md) — Comprehensive Kotlin SDK guide
- [Swift Quickstart](docs/quickstart-swift.md) — Comprehensive Swift SDK guide (macOS)

## License

See individual component directories for license information.
