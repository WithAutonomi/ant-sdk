# Building Apps on the Autonomi Network

You are helping a developer build an application on the **Autonomi** decentralized network using the **ant-sdk** toolkit.

## What You Need to Know

Autonomi is a permanent, decentralized data network. Data is content-addressed (immutable). Storage is pay-once, reads are free.

**How it works:** A local Rust daemon (`antd`) connects to the network and exposes REST + gRPC APIs. Your app talks to antd through a language SDK. The developer never touches the network directly.

```
App  →  SDK  →  antd daemon (localhost)  →  Autonomi Network
```

For detailed API signatures and endpoint documentation, see:
- **[llms.txt](llms.txt)** — concise overview of all REST endpoints, gRPC services, error codes, and SDK links
- **[llms-full.txt](llms-full.txt)** — complete reference with method signatures for all 12 languages, request/response formats, and runnable examples

## Choosing a Language

| Language | SDK | Async Model | Install |
|----------|-----|-------------|---------|
| Go | `antd-go` | `context.Context` | `go get github.com/maidsafe/ant-sdk/antd-go` |
| Python | `antd-py` | sync + async | `pip install antd` |
| TypeScript | `antd-js` | Promises | `npm install antd` |
| C# | `antd-csharp` | `Task<T>` / async-await | `dotnet add package Antd.Sdk` |
| Kotlin | `antd-kotlin` | `suspend` / coroutines | Gradle dependency |
| Swift | `antd-swift` | `async throws` | Swift Package Manager |
| Ruby | `antd-ruby` | sync | `gem install antd` |
| PHP | `antd-php` | sync + async | `composer require autonomi/antd` |
| Dart | `antd-dart` | `Future<T>` / async-await | `dart pub add antd` |
| Lua | `antd-lua` | sync | `luarocks install antd` |
| Elixir | `antd-elixir` | `{:ok, result}` / GenServer | `{:antd, "~> 0.1"}` in mix.exs deps |
| Zig | `antd-zig` | error unions / async | Add dependency in build.zig.zon |
| Rust | `antd-rust` | async/await (tokio) | `cargo add antd-client` |
| C++ | `antd-cpp` | sync (exceptions) | CMake FetchContent |
| Java | `antd-java` | sync (exceptions) | Gradle/Maven (com.autonomi:antd-java) |

**Swift note:** REST/gRPC SDK is macOS only. iOS apps must use the FFI bindings (`ffi/`) which embed the client directly — no daemon needed.

**FFI bindings** (`ffi/`): For mobile or embedded use cases where running a daemon isn't possible. UniFFI generates native C#, Kotlin, and Swift bindings that talk to the network directly. Use this for iOS apps, Android apps, or any environment where a background daemon is impractical.

## Data Primitives — When to Use What

This is the most important decision. Match the developer's use case to the right primitive:

### Immutable (store once, read forever)

| Primitive | Use When | Example |
|-----------|----------|---------|
| **Data (public)** | Storing content anyone can read | Blog posts, public files, shared configs |
| **Data (private)** | Storing content only you can read | Encrypted backups, secrets, personal docs |
| **Chunks** | You need custom chunking logic | Advanced/low-level use cases only |
| **Files** | Uploading local files or directories | Static sites, media hosting, backups |

### Append-only

| Primitive | Use When | Example |
|-----------|----------|---------|
| **Graph Entries** | Building linked data structures | Version history, social graphs, audit logs |

## Common Patterns

### Pattern 1: Immutable Data Storage

Store data permanently on the network. Content-addressed, so duplicate data is free.

```python
# Store public data
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}")

# Retrieve it back
data = client.data_get_public(result.address)
```

**When to suggest this:** Developer wants permanent, immutable content storage with public readability.

### Pattern 2: Private Data Storage

Store encrypted data that only you can read.

```python
result = client.data_put_private(b"secret message")
print(f"Data map: {result.address}")

data = client.data_get_private(result.address)
```

**When to suggest this:** Developer wants encrypted storage that only they can access.

### Pattern 3: Graph (Linked History)

DAG nodes with parent/descendant links for building append-only structures.

```python
entry1 = client.graph_entry_put(key1, parents=[], content=content1, descendants=[])
entry2 = client.graph_entry_put(key2, parents=[entry1.address], content=content2, descendants=[])
```

**When to suggest this:** Developer needs an audit log, version chain, social graph, or any linked data structure.

## Key Rules

1. **Every write costs tokens.** Always offer to estimate cost first with the `*_cost` methods. Reads are free.
2. **Data is permanent.** Once stored, it cannot be deleted. Warn developers about storing sensitive data publicly.
3. **No access revocation.** Once data is public, it stays public.
4. **Content-addressed = deduplication.** Storing the same bytes twice produces the same address and doesn't cost extra.
5. **The daemon must be running.** All SDK calls go through `antd` on localhost. If the developer hasn't started it, nothing will work. Point them to `ant dev start`.

## Error Handling

All SDKs use the same error hierarchy. Always generate code with proper error handling:

| Error | HTTP | When to Expect |
|-------|------|----------------|
| `NotFoundError` / `NotFoundException` | 404 | Address doesn't exist on network |
| `PaymentError` / `PaymentException` | 402 | Wallet has insufficient funds |
| `AlreadyExistsError` / `AlreadyExistsException` | 409 | Trying to create something that exists |
| `NetworkError` / `NetworkException` | 502 | Daemon can't reach the network |
| `BadRequestError` / `BadRequestException` | 400 | Invalid parameters |

Python/JS/Swift use `Error` suffix. C#/Kotlin use `Exception` suffix. All inherit from a base `AntdError`/`AntdException`.

## Getting Started Template

When a developer asks to build something, follow this sequence:

1. **Pick the language** — ask if not obvious from context
2. **Start the daemon** — remind them: `ant dev start` (or `pip install -e ant-dev/ && ant dev start`)
3. **Create the client** — show the 2-line connection code for their language
4. **Check health** — `client.health()` to verify the daemon is running
5. **Match their use case to a primitive** — use the tables above
6. **Estimate cost** — call the `*_cost` method before any write
7. **Implement with error handling** — always wrap writes in try/catch

## Reference

- [llms.txt](llms.txt) — REST endpoints, gRPC services, error codes, SDK links
- [llms-full.txt](llms-full.txt) — complete method signatures for all 12 languages, request/response formats, runnable examples
- [docs/architecture.md](docs/architecture.md) — full mental model, data primitive deep-dive, payment model, design patterns
- [docs/tutorial-store-retrieve.md](docs/tutorial-store-retrieve.md) — store text, files, private data, chunks (all 12 languages)
