# Building Apps on the Autonomi Network

You are helping a developer build an application on the **Autonomi** decentralized network using the **ant-sdk** toolkit.

## What You Need to Know

Autonomi is a permanent, decentralized data network. Data is content-addressed and immutable; pointers add owner-signed references that can be moved to new data. Storage is pay-once, every pointer write pays, and reads are free.

**How it works:** A local Rust daemon (`antd`) connects to the network and exposes REST + gRPC APIs. Your app talks to antd through a language SDK. The developer never touches the network directly. All SDKs support automatic daemon discovery via a port file written by antd on startup.

```
App  →  SDK  →  antd daemon (localhost)  →  Autonomi Network
```

**Port discovery:** antd writes `daemon.port` to the platform data dir (`%APPDATA%\ant\` on Windows, `~/.local/share/ant/` on Linux, `~/Library/Application Support/ant/` on macOS). All SDKs provide auto-discover constructors that read this file. When generating client code, prefer the auto-discover constructor (e.g. `NewClientAutoDiscover()` in Go, `RestClient.auto_discover()` in Python) over hardcoded URLs. Default fallback: REST on `localhost:8082`, gRPC on `localhost:50051`.

For detailed API signatures and endpoint documentation, see:
- **[llms.txt](llms.txt)** — concise overview of all REST endpoints, gRPC services, error codes, and SDK links
- **[llms-full.txt](llms-full.txt)** — complete reference with method signatures for all 15 languages, request/response formats, and runnable examples

## Choosing a Language

| Language | SDK | Async Model | Transport | Install |
|----------|-----|-------------|-----------|---------|
| Go | `antd-go` | `context.Context` | REST + gRPC | `go get github.com/WithAutonomi/ant-sdk/antd-go` |
| Python | `antd-py` | sync + async | REST + gRPC | `pip install antd` |
| TypeScript | `antd-js` | Promises | REST | `npm install antd` |
| C# | `antd-csharp` | `Task<T>` / async-await | REST + gRPC | `dotnet add package Autonomi.Antd` |
| Kotlin | `antd-kotlin` | `suspend` / coroutines | REST + gRPC | Gradle dependency |
| Swift | `antd-swift` | `async throws` | REST + gRPC | Swift Package Manager |
| Ruby | `antd-ruby` | sync | REST + gRPC | `gem install antd` |
| PHP | `antd-php` | sync + async | REST | `composer require autonomi/antd` |
| Dart | `antd-dart` | `Future<T>` / async-await | REST + gRPC | `dart pub add antd_client` |
| Lua | `antd-lua` | sync | REST | `luarocks install antd` |
| Elixir | `antd-elixir` | `{:ok, result}` / GenServer | REST + gRPC | `{:antd, "~> 0.1"}` in mix.exs deps |
| Zig | `antd-zig` | error unions / async | REST | Add dependency in build.zig.zon |
| Rust | `antd-rust` | async/await (tokio) | REST + gRPC | `cargo add antd-client` |
| C++ | `antd-cpp` | sync + async (std::future) | REST + gRPC | CMake FetchContent |
| Java | `antd-java` | sync + async (CompletableFuture) | REST + gRPC | Gradle/Maven (com.autonomi:antd-java) |

**Pointers:** every SDK has the pointer API. It runs over gRPC too in C++, C#, Dart, Elixir, Go, Java, Kotlin, Python, Ruby, Rust and Swift; JS/TS, Lua, PHP and Zig are REST only.

**Swift note:** REST/gRPC SDK is macOS only. iOS apps must use the FFI bindings (`ffi/`) which embed the client directly — no daemon needed.

**FFI bindings** (`ffi/`): For mobile or embedded use cases where running a daemon isn't possible. UniFFI generates native C#, Kotlin, and Swift bindings that talk to the network directly. Use this for iOS apps, Android apps, or any environment where a background daemon is impractical. The FFI bindings do not have pointers yet.

## Data Primitives — When to Use What

This is the most important decision. Match the developer's use case to the right primitive:

### Immutable (store once, read forever)

| Primitive | Use When | Example |
|-----------|----------|---------|
| **Data (public)** | Storing content anyone can read | Blog posts, public files, shared configs |
| **Data (private)** | Storing content only you can read | Encrypted backups, secrets, personal docs |
| **Chunks** | You need custom chunking logic | Advanced/low-level use cases only |
| **Files** | Uploading local files or directories | Static sites, media hosting, backups |

### Mutable (an address you can move)

| Primitive | Use When | Example |
|-----------|----------|---------|
| **Pointer** | You need one stable address whose target changes over time | "Latest version" of a site, a release, a config; a name others bookmark |

Scratchpads, registers and vaults are not supported.

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
result = client.data_put(b"secret message")
print(f"Data map: {result.data_map}")

data = client.data_get(result.data_map)
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

# Added in antd 0.10.0: the already-stored preflight. prep.total_chunks is the
# full chunk count; prep.already_stored_count is how many were already on the
# network (no payment/PUT). You pay for (total_chunks - already_stored_count),
# which is why a prepare can come back cheaper than the raw file size implies.
print(f"Stored: {result.chunks_stored} chunks "
      f"({prep.already_stored_count}/{prep.total_chunks} already on-network)")
```

**When to suggest this:** Developer has their own wallet/signer and doesn't want to use antd's built-in wallet. Common in web apps, mobile apps, or enterprise integrations.

### Pattern 4: Pointers (Updatable Address)

A pointer's address is derived from its owner key and never changes; the owner moves it to new data. antd holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (key files from `ant pointer keygen --output <file>`), so calls name the pointer by its address (`owner`). Needs antd 0.16.0 or later (the first release with pointers).

```python
owner = client.pointer_keys()[0]           # a pointer this daemon can write

v1 = client.data_put_public(b"version 1").address
v2 = client.data_put_public(b"version 2").address

client.pointer_create(owner, v1)           # pays (about one chunk); counter 0
client.pointer_update(owner, v2)           # pays again; counter 1
target = client.pointer_resolve(owner).target   # == v2 (free)
record = client.pointer_get(owner)              # counter, target, is_final, transferred_to (free)
f = client.pointer_finality(owner)              # status: open / settling / unconfirmed / final / forked (free)

# Irreversible: hand the pointer over to another existing pointer, for good
# client.pointer_transfer(owner, recipient)     # pays; check finality reaches "final"
# client.pointer_controller(owner)              # follow transfers to whoever decides now

# External signer: prepare signs + quotes, the app pays payForQuotes(), finalize stores
# prep = client.pointer_prepare(owner, PointerOp.UPDATE, target=v2)
# client.pointer_finalize(prep.upload_id, {"0xquotehash": "0xtxhash"})
```

Counters are decimal strings on the wire (a final pointer sits at 2^64−1); SDKs parse them into exact unsigned 64-bit values. Method names follow each SDK's casing: `pointerCreate`, `PointerCreateAsync`, `PointerCreate(ctx, ...)`, and so on.

**When to suggest this:** Developer wants a link that always leads to the latest version of something, without republishing the address.

### Pattern 5: Manifests (One Link for Several Files)

A manifest describes a set of files as one `.ant` document, or as one `ant://manifest/` link when it is small enough. Each entry has an optional `path` (and `size`) and **exactly one** of an `address` (a public file) or a `data_map` (a private file, embedded: the manifest is then its key). Needs antd 0.16.0 or later.

**Nothing is uploaded or paid for.** Build and decode are free and need no wallet, so no confirmation or cost estimate is needed. They read the network only to resolve DataMaps and can time out: retrying is safe. The files must already be uploaded, so get the addresses and DataMaps first:

- public file: `data_put_public` / `file_put_public` return the `address`
- private file: `data_put` / `file_put` return the `data_map` (hex). Keep it secret: anyone with it can read the file
- the manifest does not upload anything; entries are only pointers to what is already there
- every upload result also has `sha256`, the plaintext's SHA-256 (hex; requires antd 0.17.0 or later, none on older daemons). Pass it as the entry's `sha256` so a downloader can check the file

```python
from antd import ManifestEntryInput

a = client.file_put_public("/abs/intro.txt").address     # pays
d = client.file_put("/abs/diary.txt").data_map           # pays; private

# Build (free). Exactly one of address / data_map per entry; paths are relative, no ".."
built = client.build_manifest(
    [ManifestEntryInput(path="intro.txt", address=a),
     ManifestEntryInput(path="private/diary.txt", data_map=d)],
    name="trip",
)
built.link        # "ant://manifest/..." or None when over 1,500 bytes: share built.manifest (raw bytes) instead
# To record a hash: ManifestEntryInput(path="intro.txt", address=r.address, sha256=r.sha256), where r is the upload result

# Decode (free). resolve=True also reads each DataMap to fill in exact_size
m = client.decode_manifest_link(built.link, resolve=True)   # or client.decode_manifest(bytes, resolve=True)
for e in m.entries:                                         # sorted by effective_name
    if e.kind == "public":
        client.file_get_public(e.content_address, dest)    # download by address
    else:
        client.file_get(e.data_map, dest)                  # download by DataMap
```

Rules for the agent:

- Always pick **one** of `address` or `data_map` per entry; both or neither is refused before sending. Paths are portable relative paths. Every SDK raises its one bad-request error (status 400) for an invalid entry, whether the SDK or the daemon caught it, with a message like `1 invalid entries: entries[0]: give data_map or address, not both`.
- `link` is empty/`None` past 1,500 bytes; check for it and fall back to the `.ant` bytes. Embedded DataMaps use far more of that budget than public addresses.
- Embedded entries are private-but-shareable: whoever holds the link or file can read them. Say so before generating code that publishes a link. Public entries can be read by anyone who knows the address.
- `sha256` is optional on an entry (requires antd 0.17.0 or later). Pass it through exactly as an upload returned it; do not compute, check or lowercase it yourself, the daemon validates it and a bad value is the same bad-request error. Entries read it back, none when the manifest records none.
- An unset size is `None`/`null`, never `0`. `exact_size` is trustworthy (read from the network); `size` is only what the creator claimed. One entry's failed `resolve` is in that entry's `error`, not an exception.
- The `.ant` bytes are raw bytes in every SDK; base64 is only the REST wire form. Method names follow each SDK's casing: `buildManifest`, `BuildManifestAsync`, `build_manifest(client, ...)`. JS/TS, Lua, PHP and Zig are REST only; the others also work over gRPC.
- The MCP server has `build_manifest` and `decode_manifest` tools (free).

**When to suggest this:** Developer wants to hand someone a folder-like set of files (with paths and a name) as one link, or to share private files with a link as the key.

## Key Rules

1. **Every write costs tokens.** Always offer to estimate cost first with the `*_cost` methods — they return an `UploadCostEstimate` with `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, and `payment_mode`. Before the first storage operation, the wallet must be approved via `wallet_approve()`. Reads are free.
2. **Data is permanent.** Once stored, it cannot be deleted. Warn developers about storing sensitive data publicly.
3. **No access revocation.** Once data is public, it stays public.
4. **Content-addressed = deduplication.** Storing the same bytes twice produces the same address and doesn't cost extra.
5. **The daemon must be running.** All SDK calls go through `antd` on localhost. If the developer hasn't started it, nothing will work. Point them to `ant dev start`.
6. **Pointer writes pay every time, and are never retried.** Each create, update and transfer pays again on every attempt; never generate retry loops around them. After a failed write, read the pointer (`pointer_get`) before paying again. A create of an existing pointer is refused before paying: use update.
7. **Pointer transfer is irreversible.** Confirm with the developer before generating a `pointer_transfer` call. Pointer keys cannot be rotated, so they must be kept safe.

## Error Handling

All SDKs use the same error hierarchy. Always generate code with proper error handling:

| Error | HTTP | When to Expect |
|-------|------|----------------|
| `NotFoundError` / `NotFoundException` | 404 | Address doesn't exist on network |
| `PaymentError` / `PaymentException` | 402 | Wallet has insufficient funds |
| `AlreadyExistsError` / `AlreadyExistsException` | 409 | Trying to create something that exists |
| `NetworkError` / `NetworkException` | 502 | Daemon can't reach the network |
| `ServiceUnavailableError` / `ServiceUnavailableException` | 503 | Wallet not configured |
| `BadRequestError` / `BadRequestException` | 400 | Invalid parameters, or a pointer owner antd holds no key for |
| `PointerFinalError` / `PointerFinalException` | 409 (`POINTER_FINAL`) | Writing a pointer that was transferred or is otherwise final; usually refused before paying, but a write already paid for when the network refused it keeps that payment |
| `ConflictError` / `ConflictException` | 409 (`CONFLICT`) | A prepared pointer write awaits payment (refused before paying), or an update lost to a newer state (possibly after paying); read the pointer before paying again |
| `CloseGroupShortfallError` / `CloseGroupShortfallException` | 503 (`CLOSE_GROUP_SHORTFALL`) | Too few peers answered; reads may retry, paid writes must not, except a pointer finalize with `retryable` true, which may be repeated with the same `upload_id` against the retained payment |

A pointer whose owner signed two final states is `POINTER_FORKED` (409): `PointerForkedError` in some SDKs, a `ForkError` in Go, JS/TS, Dart, Elixir and PHP, and a `ForkException` in Java.

Python/JS/Swift use `Error` suffix. C#/Kotlin use `Exception` suffix. All inherit from a base `AntdError`/`AntdException`.

## Getting Started Template

When a developer asks to build something, follow this sequence:

1. **Pick the language** — ask if not obvious from context
2. **Start the daemon** — remind them: `ant dev start` (or `pip install -e ant-dev/ && ant dev start`)
3. **Create the client** — use the auto-discover constructor for their language (falls back to defaults if antd port file isn't present)
4. **Check health** — `client.health()` to verify the daemon is running
5. **Match their use case to a primitive** — use the tables above
6. **Estimate cost** — call the `*_cost` method before any write (returns an `UploadCostEstimate` with size/chunks/gas/mode)
7. **Implement with error handling** — always wrap writes in try/catch

## Reference

- [llms.txt](llms.txt) — REST endpoints, gRPC services, error codes, SDK links
- [llms-full.txt](llms-full.txt) — complete method signatures for all 15 languages, request/response formats, runnable examples
- [docs/architecture.md](docs/architecture.md) — full mental model, data primitive deep-dive, payment model, design patterns
- [docs/tutorial-store-retrieve.md](docs/tutorial-store-retrieve.md) — store text, files, private data, chunks (Python, C#, Kotlin and Swift)
- [docs/tutorial-pointers.md](docs/tutorial-pointers.md) — point at a public file, update it, check finality, transfer, external signer
- [docs/tutorial-manifests.md](docs/tutorial-manifests.md) — share a set of files as one `ant://manifest/` link, decode it, download each entry
