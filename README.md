# ant-sdk

A developer-friendly SDK for the [Autonomi](https://autonomi.com) decentralized network. Store data, build DAGs, and more — from Go, JavaScript/TypeScript, Python, C#, Kotlin, Swift, Ruby, PHP, Dart, Lua, Elixir, Zig, Rust, C++, Java, or AI agents.

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
| [`antd-ruby/`](antd-ruby/) | Ruby | SDK with sync client, REST transport |
| [`antd-php/`](antd-php/) | PHP | SDK with sync/async clients, REST transport |
| [`antd-dart/`](antd-dart/) | Dart | SDK with async client, REST transport |
| [`antd-lua/`](antd-lua/) | Lua | SDK with sync client, REST transport |
| [`antd-elixir/`](antd-elixir/) | Elixir | SDK with async client, REST transport |
| [`antd-zig/`](antd-zig/) | Zig | SDK with async client, REST transport |
| [`antd-rust/`](antd-rust/) | Rust | SDK with async client, REST transport |
| [`antd-cpp/`](antd-cpp/) | C++ | SDK with sync + async clients, REST transport |
| [`antd-java/`](antd-java/) | Java | SDK with sync + async clients, REST transport (enterprise/ERP) |
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
- **Ruby 3.0+** (optional, for the Ruby SDK)
- **PHP 8.1+** (optional, for the PHP SDK)
- **Dart 3.0+** (optional, for the Dart SDK)
- **Lua 5.4+ / LuaRocks** (optional, for the Lua SDK)
- **Elixir 1.14+** (optional, for the Elixir SDK)
- **Zig 0.12+** (optional, for the Zig SDK)
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

### Write your first app (Ruby)

```ruby
require "antd"

client = Antd::Client.new

status = client.health
puts "Network: #{status.network}"

result = client.data_put_public("Hello, Autonomi!")
puts "Address: #{result.address}"

data = client.data_get_public(result.address)
puts data # "Hello, Autonomi!"
```

### Write your first app (PHP)

```php
<?php
use Autonomi\AntdClient;

$client = AntdClient::create();

$status = $client->health();
echo "Network: {$status->network}\n";

$result = $client->dataPutPublic("Hello, Autonomi!");
echo "Address: {$result->address}\n";

$data = $client->dataGetPublic($result->address);
echo $data . "\n"; // "Hello, Autonomi!"
```

### Write your first app (Dart)

```dart
import 'package:antd/antd.dart';

void main() async {
  final client = AntdClient();

  final status = await client.health();
  print('Network: ${status.network}');

  final result = await client.dataPutPublic(
    'Hello, Autonomi!'.codeUnits,
  );
  print('Address: ${result.address}');

  final data = await client.dataGetPublic(result.address);
  print(String.fromCharCodes(data)); // "Hello, Autonomi!"
}
```

### Write your first app (Lua)

```lua
local antd = require("antd")

local client = antd.Client.new()

local status = client:health()
print("Network: " .. status.network)

local result = client:data_put_public("Hello, Autonomi!")
print("Address: " .. result.address)

local data = client:data_get_public(result.address)
print(data) -- "Hello, Autonomi!"
```

### Write your first app (Elixir)

```elixir
client = Antd.Client.new()

{:ok, status} = Antd.Client.health(client)
IO.puts("Network: #{status.network}")

{:ok, result} = Antd.Client.data_put_public(client, "Hello, Autonomi!")
IO.puts("Address: #{result.address}")

{:ok, data} = Antd.Client.data_get_public(client, result.address)
IO.puts(data) # "Hello, Autonomi!"
```

### Write your first app (Zig)

```zig
const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var client = try antd.Client.init(.{});
    defer client.deinit();

    const status = try client.health();
    std.debug.print("Network: {s}\n", .{status.network});

    const result = try client.dataPutPublic("Hello, Autonomi!");
    std.debug.print("Address: {s}\n", .{result.address});

    const data = try client.dataGetPublic(result.address);
    std.debug.print("{s}\n", .{data}); // "Hello, Autonomi!"
}
```

## Data Primitives

The Autonomi network provides these core primitives, all accessible through the SDKs:

| Primitive | Description |
|-----------|-------------|
| **Data** | Store/retrieve arbitrary byte blobs (public or private/encrypted) |
| **Chunks** | Low-level content-addressed storage |
| **Graph Entries** | Append-only DAG nodes with parent/descendant links |
| **Files** | File/directory upload with archive manifests |

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
- [Go Quickstart](antd-go/README.md) — Go SDK guide
- [JS/TS Quickstart](antd-js/README.md) — JavaScript/TypeScript SDK guide
- [Python Quickstart](docs/quickstart-python.md) — Comprehensive Python SDK guide
- [C# Quickstart](docs/quickstart-csharp.md) — Comprehensive C# SDK guide
- [Kotlin Quickstart](docs/quickstart-kotlin.md) — Comprehensive Kotlin SDK guide
- [Swift Quickstart](docs/quickstart-swift.md) — Comprehensive Swift SDK guide (macOS)
- [Ruby Quickstart](antd-ruby/README.md) — Ruby SDK guide
- [PHP Quickstart](antd-php/README.md) — PHP SDK guide
- [Dart Quickstart](antd-dart/README.md) — Dart SDK guide
- [Lua Quickstart](antd-lua/README.md) — Lua SDK guide
- [Elixir Quickstart](antd-elixir/README.md) — Elixir SDK guide
- [Zig Quickstart](antd-zig/README.md) — Zig SDK guide
- [Rust Quickstart](antd-rust/README.md) — Rust SDK guide
- [C++ Quickstart](antd-cpp/README.md) — C++ SDK guide
- [Java Quickstart](antd-java/README.md) — Java SDK guide

## License

See individual component directories for license information.
