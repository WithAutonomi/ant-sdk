# ant-sdk

A developer-friendly SDK for the [Autonomi](https://autonomi.com) decentralized network. Store data permanently and more — from Go, JavaScript/TypeScript, Python, C#, Kotlin, Swift, Ruby, PHP, Dart, Lua, Elixir, Zig, Rust, C++, Java, or AI agents.

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

### Port Discovery

All SDKs support automatic daemon discovery. When antd starts, it writes a `daemon.port` file containing the REST and gRPC ports to a platform-specific location:

| Platform | Path |
|----------|------|
| Windows | `%APPDATA%\ant\sdk\daemon.port` |
| Linux | `~/.local/share/ant/sdk/daemon.port` (or `$XDG_DATA_HOME/ant/sdk/`) |
| macOS | `~/Library/Application Support/ant/sdk/daemon.port` |

The `sdk` subdirectory keeps antd's port file separate from the ant-node daemon, which writes to the same `ant` umbrella dir.

Every SDK provides an auto-discover constructor that reads this file and connects automatically:

```python
# Python
client, url = RestClient.auto_discover()
```

```go
// Go
client, url := antd.NewClientAutoDiscover()
```

```typescript
// TypeScript
const { client, url } = RestClient.autoDiscover();
```

This is especially useful in managed mode, where a parent process (e.g. indelible) spawns antd with `--rest-port 0` to let the OS assign a free port. The SDK discovers the actual port via the port file without any hardcoded configuration.

If no port file is found, all SDKs fall back to the default REST endpoint (`http://localhost:8082`) or gRPC target (`localhost:50051`).

### External Signer Support

All SDKs support two-phase uploads for applications that manage their own wallet (browser wallets, hardware signers, etc.):

1. **`prepare_upload(path)`** -- returns payment details (quote hashes, amounts, contract addresses, RPC URL)
2. Your application submits EVM payment transactions using its own signer
3. **`finalize_upload(upload_id, tx_hashes)`** -- confirms payments and stores data on the network

### Payment Modes

All data and file upload operations accept an optional `payment_mode` parameter (defaults to `"auto"`):

- **`auto`** — Uses merkle batch payments for uploads of 64+ chunks, single payments otherwise. Recommended for most use cases.
- **`merkle`** — Forces merkle batch payments regardless of chunk count (minimum 2 chunks). Saves gas on larger uploads.
- **`single`** — Forces per-chunk payments. Useful for small data or debugging.

## Components

### Infrastructure

| Component | Language | Description |
|-----------|----------|-------------|
| [`antd/`](antd/) | Rust | REST + gRPC gateway daemon |
| [`antd-mcp/`](antd-mcp/) | Python | MCP server exposing 14 tools for AI agents (Claude, etc.) |
| [`ant-dev/`](ant-dev/) | Python | Developer CLI for local environment management |

### Language SDKs

| SDK | Language | Async | Transport | Notes |
|-----|----------|-------|-----------|-------|
| [`antd-go/`](antd-go/) | Go | context-based | REST + gRPC | |
| [`antd-js/`](antd-js/) | TypeScript | async/await | REST | |
| [`antd-py/`](antd-py/) | Python | sync + async | REST + gRPC | |
| [`antd-csharp/`](antd-csharp/) | C# | async | REST + gRPC | |
| [`antd-kotlin/`](antd-kotlin/) | Kotlin | coroutines | REST + gRPC | |
| [`antd-swift/`](antd-swift/) | Swift | async/await | REST + gRPC | macOS only |
| [`antd-ruby/`](antd-ruby/) | Ruby | sync | REST + gRPC | |
| [`antd-php/`](antd-php/) | PHP | sync + async | REST | Guzzle promises |
| [`antd-dart/`](antd-dart/) | Dart | async/await | REST + gRPC | |
| [`antd-lua/`](antd-lua/) | Lua | sync | REST | |
| [`antd-elixir/`](antd-elixir/) | Elixir | async (BEAM) | REST + gRPC | {:ok,result} tuples |
| [`antd-zig/`](antd-zig/) | Zig | sync | REST | |
| [`antd-rust/`](antd-rust/) | Rust | async/await | REST + gRPC | tokio + tonic |
| [`antd-cpp/`](antd-cpp/) | C++ | sync + async | REST + gRPC | std::future |
| [`antd-java/`](antd-java/) | Java | sync + async | REST + gRPC | CompletableFuture |

## Quickstart (5 minutes)

### Prerequisites

**Required:**

- **Rust** toolchain — for building antd
- **Python 3.10+** — for the dev CLI (`ant-dev`) and MCP server
- **ant-node** repo cloned as sibling (for local testnet only): `git clone https://github.com/WithAutonomi/ant-node ../ant-node`

**Language-specific** (install only what you need):

| Language | Version | Install |
|----------|---------|---------|
| Go | 1.21+ | `go get github.com/WithAutonomi/ant-sdk/antd-go` |
| Node.js / TypeScript | 18+ | `npm install antd` |
| C# / .NET | 8+ | `dotnet add package Antd.Sdk` |
| Kotlin | JDK 17+ | Gradle dependency |
| Swift | 5.9+ / Xcode 15+ | Swift Package Manager (macOS only) |
| Ruby | 3.0+ | `gem install antd` |
| PHP | 8.1+ | `composer require autonomi/antd` |
| Dart | 3.0+ | `dart pub add antd` |
| Lua | 5.1+ / LuaRocks | `luarocks install antd` |
| Elixir | 1.14+ | `{:antd, "~> 0.1"}` in mix.exs |
| Zig | 0.14+ | build.zig.zon dependency |
| Rust (client) | 2021 edition | `cargo add antd-client` |
| C++ | C++20 | CMake FetchContent |
| Java | 17+ | Gradle/Maven (com.autonomi:antd-java) |

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

# Store data on the network (payment_mode defaults to "auto")
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Retrieve it back
data = client.data_get_public(result.address)
print(data.decode())  # "Hello, Autonomi!"

# For large uploads, you can explicitly set payment_mode:
# result = client.data_put_public(large_data, payment_mode="merkle")
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

    antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
    client, _ := antd.NewClientAutoDiscover()
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
| **Files** | File/directory upload and download |

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

### Quickstart Guides

| Language | Guide |
|----------|-------|
| Go | [antd-go/README.md](antd-go/README.md) |
| JS/TS | [antd-js/README.md](antd-js/README.md) |
| Python | [docs/quickstart-python.md](docs/quickstart-python.md) |
| C# | [docs/quickstart-csharp.md](docs/quickstart-csharp.md) |
| Kotlin | [docs/quickstart-kotlin.md](docs/quickstart-kotlin.md) |
| Swift | [docs/quickstart-swift.md](docs/quickstart-swift.md) — macOS only |
| Ruby | [docs/quickstart-ruby.md](docs/quickstart-ruby.md) |
| PHP | [docs/quickstart-php.md](docs/quickstart-php.md) |
| Dart | [docs/quickstart-dart.md](docs/quickstart-dart.md) |
| Lua | [docs/quickstart-lua.md](docs/quickstart-lua.md) |
| Elixir | [docs/quickstart-elixir.md](docs/quickstart-elixir.md) |
| Zig | [docs/quickstart-zig.md](docs/quickstart-zig.md) |
| Rust | [docs/quickstart-rust.md](docs/quickstart-rust.md) |
| C++ | [docs/quickstart-cpp.md](docs/quickstart-cpp.md) |
| Java | [docs/quickstart-java.md](docs/quickstart-java.md) |

## License

See individual component directories for license information.
