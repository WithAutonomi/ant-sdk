# Building Apps on the Autonomi Network

You are helping a developer build an application on the **Autonomi** decentralized network using the **ant-sdk** toolkit.

## What You Need to Know

Autonomi is a permanent, decentralized data network. Data is content-addressed (immutable). Storage is pay-once, reads are free.

**How it works:** A local Rust daemon (`antd`) connects to the network and exposes REST + gRPC APIs. Your app talks to antd through a language SDK. The developer never touches the network directly. All SDKs support automatic daemon discovery via a port file written by antd on startup.

```
App  →  SDK  →  antd daemon (localhost)  →  Autonomi Network
```

**Port discovery:** antd writes `daemon.port` to the platform data dir (`%APPDATA%\ant\` on Windows, `~/.local/share/ant/` on Linux, `~/Library/Application Support/ant/` on macOS). All SDKs provide auto-discover constructors that read this file. When generating client code, prefer the auto-discover constructor (e.g. `NewClientAutoDiscover()` in Go, `RestClient.auto_discover()` in Python) over hardcoded URLs. Default fallback: REST on `localhost:8082`, gRPC on `localhost:50051`.

For detailed API signatures and endpoint documentation, see:
- **[llms.txt](llms.txt)** — concise overview of all REST endpoints, gRPC services, error codes, and SDK links
- **[llms-full.txt](llms-full.txt)** — complete reference with method signatures for all 12 languages, request/response formats, and runnable examples

## Choosing a Language

| Language | SDK | Async Model | Transport | Install |
|----------|-----|-------------|-----------|---------|
| Go | `antd-go` | `context.Context` | REST + gRPC | `go get github.com/WithAutonomi/ant-sdk/antd-go` |
| Python | `antd-py` | sync + async | REST + gRPC | `pip install antd` |
| TypeScript | `antd-js` | Promises | REST | `npm install antd` |
| C# | `antd-csharp` | `Task<T>` / async-await | REST + gRPC | `dotnet add package Antd.Sdk` |
| Kotlin | `antd-kotlin` | `suspend` / coroutines | REST + gRPC | Gradle dependency |
| Swift | `antd-swift` | `async throws` | REST + gRPC | Swift Package Manager |
| Ruby | `antd-ruby` | sync | REST + gRPC | `gem install antd` |
| PHP | `antd-php` | sync + async | REST | `composer require autonomi/antd` |
| Dart | `antd-dart` | `Future<T>` / async-await | REST + gRPC | `dart pub add antd` |
| Lua | `antd-lua` | sync | REST | `luarocks install antd` |
| Elixir | `antd-elixir` | `{:ok, result}` / GenServer | REST + gRPC | `{:antd, "~> 0.1"}` in mix.exs deps |
| Zig | `antd-zig` | error unions / async | REST | Add dependency in build.zig.zon |
| Rust | `antd-rust` | async/await (tokio) | REST + gRPC | `cargo add antd-client` |
| C++ | `antd-cpp` | sync + async (std::future) | REST + gRPC | CMake FetchContent |
| Java | `antd-java` | sync + async (CompletableFuture) | REST + gRPC | Gradle/Maven (com.autonomi:antd-java) |

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

## Common Patterns

### Pattern 1: Immutable Data Storage

Store data permanently on the network. Content-addressed, so duplicate data is free.

```python
# Store public data (payment_mode defaults to "auto")
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}")

# Retrieve it back
data = client.data_get_public(result.address)

# For large uploads, explicitly use merkle batch payments to save gas
result = client.data_put_public(large_data, payment_mode="merkle")
```

All write operations accept an optional `payment_mode` parameter: `"auto"` (default — uses merkle for 64+ chunks), `"merkle"` (force batch payments, min 2 chunks), or `"single"` (per-chunk payments). The `"auto"` mode is recommended for most use cases.

**When to suggest this:** Developer wants permanent, immutable content storage with public readability.

### Pattern 2: Private Data Storage

Store encrypted data that only you can read.

```python
result = client.data_put_private(b"secret message")
print(f"Data map: {result.address}")

data = client.data_get_private(result.address)
```

**When to suggest this:** Developer wants encrypted storage that only they can access.

### Pattern 3: External Signer (Two-Phase Upload)

When the application manages its own wallet (e.g. a browser wallet or hardware signer), use the two-phase upload flow instead of the daemon's built-in wallet. The prepare step returns a `payment_type` that determines the payment contract call:

```python
# Phase 1: Prepare — get payment details
prep = client.prepare_upload("/path/to/file")

if prep.payment_type == "wave_batch":
    # Small files (< 64 chunks): call payForQuotes() with per-quote payments
    # prep.payments, prep.payment_vault_address, prep.total_amount
    # ... external signer submits EVM payForQuotes() transaction ...
    result = client.finalize_upload(prep.upload_id, {"0xquotehash": "0xtxhash", ...})

elif prep.payment_type == "merkle":
    # Large files (>= 64 chunks): call payForMerkleTree() — gas-efficient batch
    # prep.depth, prep.pool_commitments, prep.merkle_payment_timestamp,
    # prep.payment_vault_address
    # ... external signer submits EVM payForMerkleTree() transaction ...
    # ... extract winner_pool_hash from MerklePaymentMade event ...
    result = client.finalize_merkle_upload(prep.upload_id, "0xwinnerpoolhash")

print(f"Stored: {result.chunks_stored} chunks")
```

**When to suggest this:** Developer has their own wallet/signer and doesn't want to use antd's built-in wallet. Common in web apps, mobile apps, or enterprise integrations.

## Key Rules

1. **Every write costs tokens.** Always offer to estimate cost first with the `*_cost` methods (now fully implemented for both data and files). Before the first storage operation, the wallet must be approved via `wallet_approve()`. Reads are free.
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
| `ServiceUnavailableError` / `ServiceUnavailableException` | 503 | Wallet not configured |
| `BadRequestError` / `BadRequestException` | 400 | Invalid parameters |

Python/JS/Swift use `Error` suffix. C#/Kotlin use `Exception` suffix. All inherit from a base `AntdError`/`AntdException`.

## Getting Started Template

When a developer asks to build something, follow this sequence:

1. **Pick the language** — ask if not obvious from context
2. **Start the daemon** — remind them: `ant dev start` (or `pip install -e ant-dev/ && ant dev start`)
3. **Create the client** — use the auto-discover constructor for their language (falls back to defaults if antd port file isn't present)
4. **Check health** — `client.health()` to verify the daemon is running
5. **Match their use case to a primitive** — use the tables above
6. **Estimate cost** — call the `*_cost` method before any write
7. **Implement with error handling** — always wrap writes in try/catch

## Reference

- [llms.txt](llms.txt) — REST endpoints, gRPC services, error codes, SDK links
- [llms-full.txt](llms-full.txt) — complete method signatures for all 12 languages, request/response formats, runnable examples
- [docs/architecture.md](docs/architecture.md) — full mental model, data primitive deep-dive, payment model, design patterns
- [docs/tutorial-store-retrieve.md](docs/tutorial-store-retrieve.md) — store text, files, private data, chunks (all 12 languages)
