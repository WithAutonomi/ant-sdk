# ant-sdk

A developer-friendly SDK for the [Autonomi](https://autonomi.com) decentralized network. Store data permanently, point at it with updatable pointers, share sets of files as one manifest link, and more — from Go, JavaScript/TypeScript, Python, C#, Kotlin, Swift, Ruby, PHP, Dart, Lua, Elixir, Zig, Rust, C++, Java, or AI agents.

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
| [`antd-mcp/`](antd-mcp/) | Python | MCP server exposing 31 tools for AI agents (Claude, etc.) |
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
- **Foundry** (provides `anvil`) — for the local EVM testnet that the devnet spawns: `curl -sL https://foundry.paradigm.xyz | bash && foundryup`

**Language-specific** (install only what you need):

| Language | Version | Install |
|----------|---------|---------|
| Go | 1.21+ | `go get github.com/WithAutonomi/ant-sdk/antd-go` |
| Node.js / TypeScript | 18+ | `npm install @withautonomi/antd` |
| C# / .NET | 8+ | `dotnet add package Autonomi.Antd` |
| Kotlin | JDK 17+ | Gradle dependency |
| Swift | 5.9+ / Xcode 15+ | Swift Package Manager (macOS only) |
| Ruby | 3.0+ | `gem install antd` |
| PHP | 8.2+ | `composer require autonomi/antd` |
| Dart | 3.0+ | `dart pub add antd_client` |
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
import { createClient } from "@withautonomi/antd";

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

    result, err := client.DataPutPublic(ctx, []byte("Hello, Autonomi!"), antd.PaymentModeAuto)
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
import 'package:antd_client/antd_client.dart';

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
| **Pointers** | Owner-signed, updatable references: a fixed address the owner can point at new data |
| **Manifests** | One `ant://manifest/` link (or `.ant` file) that describes a set of files: paths, plus each file's address or DataMap. Built and decoded for free |

Data, chunks and files are immutable: new content gets a new address. Pointers are the mutable part. Scratchpads, registers and vaults are not supported.

### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes; what it points at (a chunk, such as a public file's address, or another pointer) can be changed by the owner. Publish the pointer's address once, then move it to each new version. Pointers need the first antd release with pointers (after 0.15.0).

- **antd holds the owner keys.** Create one with `ant pointer keygen --output <file>` (the Autonomi `ant` CLI) and start antd with `--pointer-keys <file-or-dir>` (env `ANTD_POINTER_KEYS_DIR`); it loads them at startup. Requests name a pointer by its address, never by a key. Without the flag, pointers can be read but not written. A pointer key cannot be rotated: see [SECURITY.md](SECURITY.md).
- **Every write pays.** A create, update or transfer costs about the price of one chunk, from the daemon wallet or an external signer (`pointer_prepare` / `pointer_finalize`). Every attempt pays again, so the SDKs never retry a paid pointer write. Reads (`get`, `resolve`, `finality`, `controller`, `keys`) are free.
- **Transfer is irreversible.** It hands the pointer over to another pointer for good: readers of the address are redirected to the recipient's pointer, and the old key can change nothing again.
- **Counters are decimal strings** on the wire, because a final pointer sits at 2^64−1. Each SDK parses them into an exact unsigned 64-bit type, or keeps the checked string.

Every SDK has the pointer API and a runnable example (`ANTD_POINTER_OWNER=<address> ant dev example pointers -l <language>`; each example also reads `ANTD_BASE_URL`, except Go and Rust, which use the default URL):

| SDK | Pointer transport | Example |
|-----|-------------------|---------|
| C++ | REST + gRPC | [`antd-cpp/examples/08-pointers.cpp`](antd-cpp/examples/08-pointers.cpp) |
| C# | REST + gRPC | [`antd-csharp/Examples/Program.cs`](antd-csharp/Examples/Program.cs) (`dotnet run -- 8`) |
| Dart | REST + gRPC | [`antd-dart/example/09_pointers.dart`](antd-dart/example/09_pointers.dart) |
| Elixir | REST + gRPC | [`antd-elixir/examples/08_pointers.exs`](antd-elixir/examples/08_pointers.exs) |
| Go | REST + gRPC | [`antd-go/examples/08-pointers/`](antd-go/examples/08-pointers/) |
| Java | REST + gRPC | [`antd-java/examples/.../Example08Pointers.java`](antd-java/examples/src/main/java/com/autonomi/examples/Example08Pointers.java) |
| Kotlin | REST + gRPC | [`antd-kotlin/examples/.../Example08Pointers.kt`](antd-kotlin/examples/src/main/kotlin/com/autonomi/examples/Example08Pointers.kt) |
| Python | REST + gRPC | [`antd-py/examples/09_pointers.py`](antd-py/examples/09_pointers.py) |
| Ruby | REST + gRPC | [`antd-ruby/examples/08_pointers.rb`](antd-ruby/examples/08_pointers.rb) |
| Rust | REST + gRPC | [`antd-rust/examples/09-pointers.rs`](antd-rust/examples/09-pointers.rs) |
| Swift | REST + gRPC | [`antd-swift/Sources/AntdExamples/Main.swift`](antd-swift/Sources/AntdExamples/Main.swift) (`swift run AntdExamples pointers`) |
| JS/TS | REST only | [`antd-js/examples/08-pointers.ts`](antd-js/examples/08-pointers.ts) |
| Lua | REST only | [`antd-lua/examples/08-pointers.lua`](antd-lua/examples/08-pointers.lua) |
| PHP | REST only | [`antd-php/examples/08-pointers.php`](antd-php/examples/08-pointers.php) |
| Zig | REST only | [`antd-zig/examples/09-pointers.zig`](antd-zig/examples/09-pointers.zig) |

The MCP server has 10 pointer tools: the reads are free, `pointer_create`, `pointer_update` and `pointer_transfer` pay from the daemon wallet, and `pointer_transfer` refuses to run without `confirm_irreversible=true`. The FFI bindings (`ffi/`) do not have pointers yet. Walk-through: [Tutorial: Point at a Public File and Update It](docs/tutorial-pointers.md).

### Manifests

A manifest describes a set of files as one `.ant` document, or as one `ant://manifest/` link when it is small enough. Each entry has an optional path and size and either a public file's address or an embedded DataMap (a private file: the manifest is then its key). Share the link and the receiver can decode it, learn what is in the set and download each file with the existing download calls. Manifests need the antd release after 0.15.0.

- **Nothing is uploaded or paid for.** Upload the files first, then build from the addresses and DataMaps the uploads returned. Build and decode read the network only to resolve DataMaps, so they can time out; retrying is safe. The daemon needs no wallet for them.
- **Three calls**, in every SDK: `build_manifest`, `decode_manifest` (raw `.ant` bytes) and `decode_manifest_link` (a manifest link, file link or bare address), cased per language. `resolve` also reads each entry's DataMap from the network to report its `exact_size`. REST carries the `.ant` bytes as base64; the SDKs always take and return raw bytes.
- **Links are limited to 1,500 bytes.** Past that the build still succeeds but returns no link: share the `.ant` bytes instead. Embedded DataMaps cost far more bytes than public addresses.
- **Embedded means the manifest is the key.** Anyone holding the link or file can read every embedded file. Public entries are readable by anyone who knows the address.

Every SDK has the manifest API and a runnable example (`ant dev example manifests -l <language>`; each example also reads `ANTD_BASE_URL`, except Go and Rust, which use the default URL, and each run pays for its two small uploads):

| SDK | Manifest transport | Example |
|-----|--------------------|---------|
| C++ | REST + gRPC | [`antd-cpp/examples/09-manifests.cpp`](antd-cpp/examples/09-manifests.cpp) |
| C# | REST + gRPC | [`antd-csharp/Examples/Example09Manifests.cs`](antd-csharp/Examples/Example09Manifests.cs) (`dotnet run -- 9`) |
| Dart | REST + gRPC | [`antd-dart/example/10_manifests.dart`](antd-dart/example/10_manifests.dart) |
| Elixir | REST + gRPC | [`antd-elixir/examples/09_manifests.exs`](antd-elixir/examples/09_manifests.exs) |
| Go | REST + gRPC | [`antd-go/examples/09-manifests/`](antd-go/examples/09-manifests/) |
| Java | REST + gRPC | [`antd-java/examples/.../Example09Manifests.java`](antd-java/examples/src/main/java/com/autonomi/examples/Example09Manifests.java) |
| Kotlin | REST + gRPC | [`antd-kotlin/examples/.../Example09Manifests.kt`](antd-kotlin/examples/src/main/kotlin/com/autonomi/examples/Example09Manifests.kt) |
| Python | REST + gRPC | [`antd-py/examples/10_manifests.py`](antd-py/examples/10_manifests.py) |
| Ruby | REST + gRPC | [`antd-ruby/examples/09_manifests.rb`](antd-ruby/examples/09_manifests.rb) |
| Rust | REST + gRPC | [`antd-rust/examples/10-manifests.rs`](antd-rust/examples/10-manifests.rs) |
| Swift | REST + gRPC | [`antd-swift/Sources/AntdExamples/Main.swift`](antd-swift/Sources/AntdExamples/Main.swift) (`swift run AntdExamples manifests`) |
| JS/TS | REST only | [`antd-js/examples/09-manifests.ts`](antd-js/examples/09-manifests.ts) |
| Lua | REST only | [`antd-lua/examples/09-manifests.lua`](antd-lua/examples/09-manifests.lua) |
| PHP | REST only | [`antd-php/examples/09-manifests.php`](antd-php/examples/09-manifests.php) |
| Zig | REST only | [`antd-zig/examples/10-manifests.zig`](antd-zig/examples/10-manifests.zig) |

The MCP server has two manifest tools, `build_manifest` and `decode_manifest`, both free. The FFI bindings (`ffi/`) do not have manifests. Walk-through: [Tutorial: Share a Set of Files as One Link](docs/tutorial-manifests.md).

## Developer CLI Reference

```
ant dev start [--ant-node-dir PATH] [--no-build]    # Start local environment
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
- [Tutorial: Point at a Public File and Update It](docs/tutorial-pointers.md) — Pointers: an address you can move to each new version
- [Tutorial: Share a Set of Files as One Link](docs/tutorial-manifests.md) — Manifests: upload files, build a link, decode it and download each entry

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

## Security

See [SECURITY.md](SECURITY.md) for the project's threat model, in-scope security reports, and how to disclose vulnerabilities. Preferred channel is GitHub Private Vulnerability Reporting; the disclosure window defaults to 90 days.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
