# Building Apps on the Autonomi Network

You are helping a developer build an application on the **Autonomi** decentralized network using the **ant-sdk** toolkit.

## What You Need to Know

Autonomi is a permanent, decentralized data network. Data is content-addressed (immutable) or owner-addressed (mutable). Storage is pay-once, reads are free.

**How it works:** A local Rust daemon (`antd`) connects to the network and exposes REST + gRPC APIs. Your app talks to antd through a language SDK. The developer never touches the network directly.

```
App  →  SDK  →  antd daemon (localhost)  →  Autonomi Network
```

For detailed API signatures and endpoint documentation, see:
- **[llms.txt](llms.txt)** — concise overview of all REST endpoints, gRPC services, error codes, and SDK links
- **[llms-full.txt](llms-full.txt)** — complete reference with method signatures for all 5 languages, request/response formats, and runnable examples

## Choosing a Language

| Language | SDK | Async Model | Install |
|----------|-----|-------------|---------|
| Python | `antd-py` | sync + async | `pip install antd` |
| TypeScript | `antd-js` | Promises | `npm install antd` |
| C# | `antd-csharp` | `Task<T>` / async-await | `dotnet add package Antd.Sdk` |
| Kotlin | `antd-kotlin` | `suspend` / coroutines | Gradle dependency |
| Swift | `antd-swift` | `async throws` | Swift Package Manager |

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

### Mutable (update over time)

| Primitive | Use When | Example |
|-----------|----------|---------|
| **Pointers** | Mutable reference to other data — like a DNS record | "Latest version" links, mutable URLs |
| **Scratchpads** | Mutable storage with version counter, encrypted on network | User profiles, app settings, session state |
| **Registers** | Simple 32-byte mutable value | Counters, flags, hash pointers |
| **Vaults** | Private encrypted key-value storage (accessed by secret key, not address) | User secrets, encrypted settings |

### Append-only

| Primitive | Use When | Example |
|-----------|----------|---------|
| **Graph Entries** | Building linked data structures | Version history, social graphs, audit logs |

## Common Patterns

### Pattern 1: Immutable Data + Pointer (Versioned Content)

Store each version as immutable data. Use a pointer to track the latest.

```python
# Store v1
v1 = client.data_put_public(b"config v1")
target = PointerTarget(kind="chunk", address=v1.address)
ptr = client.pointer_create(secret_key, target)

# Update to v2 — old data persists as version history
v2 = client.data_put_public(b"config v2")
client.pointer_update(secret_key, PointerTarget(kind="chunk", address=v2.address))

# Anyone with the pointer address always gets the latest
current = client.pointer_get(ptr.address)
data = client.data_get_public(current.target.address)
```

**When to suggest this:** Developer wants mutable content with version history, public readability, or unlimited data size.

### Pattern 2: Scratchpad (Versioned Mutable State)

Store data directly in a scratchpad. Single read operation, built-in counter.

```python
pad = client.scratchpad_create(secret_key, content_type=1, data=b"state v1")
client.scratchpad_update(secret_key, content_type=1, data=b"state v2")

current = client.scratchpad_get(pad.address)
print(current.counter)  # version number
```

**When to suggest this:** Developer wants fast reads, compact mutable state, built-in encryption, or version detection via counter. No version history needed.

### Pattern 3: Register (Tiny Mutable Value)

A single 32-byte hex value. Cheapest mutable primitive.

```python
result = client.register_create(secret_key, "0" * 64)  # 32 bytes = 64 hex chars
client.register_update(secret_key, new_hex_value)
```

**When to suggest this:** Developer needs a counter, flag, or hash pointer. Value must fit in 32 bytes.

### Pattern 4: Vault (Private Key-Value)

Accessed by secret key alone — no network address needed.

```python
client.vault_put(secret_key, data=b"private data", content_type=42)
vault = client.vault_get(secret_key)
```

**When to suggest this:** Developer needs private storage that only they can access. Good for persisting address maps, user preferences, or encryption keys.

### Pattern 5: Graph (Linked History)

DAG nodes with parent/descendant links for building append-only structures.

```python
entry1 = client.graph_entry_put(key1, parents=[], content=content1, descendants=[])
entry2 = client.graph_entry_put(key2, parents=[entry1.address], content=content2, descendants=[])
```

**When to suggest this:** Developer needs an audit log, version chain, social graph, or any linked data structure.

## Key Rules

1. **Every write costs tokens.** Always offer to estimate cost first with the `*_cost` methods. Reads are free.
2. **Data is permanent.** Once stored, it cannot be deleted. Warn developers about storing sensitive data publicly.
3. **Secret keys = ownership.** A 32-byte hex key controls mutable resources. Losing it means losing write access. Sharing it means sharing write access. Never store secret keys on the network unencrypted.
4. **No access revocation.** Once data is public, it stays public. Once a key is shared, it can't be unshared.
5. **Content-addressed = deduplication.** Storing the same bytes twice produces the same address and doesn't cost extra.
6. **The daemon must be running.** All SDK calls go through `antd` on localhost. If the developer hasn't started it, nothing will work. Point them to `ant dev start`.

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
- [llms-full.txt](llms-full.txt) — complete method signatures for all 5 languages, request/response formats, runnable examples
- [docs/architecture.md](docs/architecture.md) — full mental model, data primitive deep-dive, payment model, design patterns
- [docs/tutorial-store-retrieve.md](docs/tutorial-store-retrieve.md) — store text, files, private data, chunks (Python/C#/Kotlin/Swift)
- [docs/tutorial-key-value-store.md](docs/tutorial-key-value-store.md) — build a KV store with registers + pointers
- [docs/tutorial-mutable-config.md](docs/tutorial-mutable-config.md) — mutable config with pointers vs scratchpads
