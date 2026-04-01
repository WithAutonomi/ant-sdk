# Missing Features

Features developers would likely expect but don't currently exist in the SDK.

---

## 1. Wallet Operations in SDKs

>> Some of these are essential, needs to be added

1. Check wallet balance
2. Transfer tokens
3. View transaction history
4. Create new wallets

### What exists today

- The daemon loads an `EvmWallet` from `AUTONOMI_WALLET_KEY` at startup
- All write operations use this wallet internally via `PaymentOption::Wallet`
- `ant-dev wallet show` prints the key, `ant-dev wallet fund` checks testnet funding
- No wallet REST/gRPC endpoints exist — the wallet is invisible to SDK users
- Cost estimation endpoints exist (`/v1/data/cost`, `/v1/cost/file`) but return string amounts with no way to check if the wallet can cover them

### Approach: Add wallet service to antd

Add a `WalletService` to antd (REST + gRPC):

**New endpoints:**

| Endpoint | Method | Description |
|---|---|---|
| `/v1/wallet/balance` | GET | Return current wallet balance in atto tokens |
| `/v1/wallet/address` | GET | Return the wallet's public address |

**Future consideration (needs more investigation):**

| Endpoint | Method | Description |
|---|---|---|
| `/v1/wallet/transfer` | POST | Transfer tokens to another address |
| `/v1/wallet/history` | GET | List recent transactions |
| `/v1/wallet/create` | POST | Generate a new wallet keypair |

**SDK methods (all languages):**

```
wallet_balance() → string (atto tokens)
wallet_address() → string (hex address)
```

**Why balance and address first:**
- Balance is essential — developers need to know if they can afford a write before attempting it
- Address is needed for funding workflows (testnet faucets, receiving tokens)
- Transfer and history depend on EVM capabilities that need investigation
- Wallet creation may conflict with the daemon's single-wallet-at-startup design

### Implementation notes

- `ant_evm::EvmWallet` likely exposes balance and address methods already — this is a thin wrapper
- The daemon's `AppState` already holds the wallet, so no architectural changes needed
- Balance should be live (queried from EVM), not cached

### Priority

Critical — this is the most immediately useful feature. Developers currently fly blind on whether writes will succeed.

---

## 2. Key / Identity Management

>> Sounds useful, needs more detail

1. Key generation helpers in the SDKs
2. Key derivation (HD wallet-style)
3. Identity or account abstraction
4. Key import and export in standard formats

### What exists today

- The FFI layer (`ffi/rust/ant-ffi/src/keys.rs` and `key_derivation.rs`) has full BLS key types: `SecretKey`, `PublicKey`, `MainSecretKey`, `MainPubkey`, `DerivedSecretKey`, `DerivedPubkey`, `DerivationIndex`, `Signature`
- SDK examples generate throwaway keys with `os.urandom(32).hex()` — no persistence or reuse
- SDK examples generate throwaway keys with `os.urandom(32).hex()` — no persistence or reuse
- The daemon loads its wallet key from `AUTONOMI_WALLET_KEY` env var at startup
- No key-related REST/gRPC endpoints exist

### Approach: Expose key operations via antd

Add a `KeyService` to antd (both REST and gRPC) that wraps the existing FFI primitives:

**New endpoints:**

| Endpoint | Method | Description |
|---|---|---|
| `/v1/keys/generate` | POST | Generate a new random BLS keypair, return hex public + secret key |
| `/v1/keys/public` | POST | Derive public key from a secret key |
| `/v1/keys/derive` | POST | Given a `MainSecretKey` and `DerivationIndex`, return a `DerivedSecretKey` |
| `/v1/keys/derive/public` | POST | Given a `MainPubkey` and `DerivationIndex`, return a `DerivedPubkey` |
| `/v1/keys/derive/index` | POST | Generate a random `DerivationIndex` |
| `/v1/keys/sign` | POST | Sign a message with a secret key |
| `/v1/keys/verify` | POST | Verify a signature against a public key |

**SDK helpers (per-language):**

```
keys_generate() → { secret_key: hex, public_key: hex }
keys_derive(main_secret_key: hex, index: hex) → { derived_secret_key: hex, derived_public_key: hex }
keys_sign(secret_key: hex, message: hex) → hex
keys_verify(public_key: hex, message: hex, signature: hex) → bool
```

**What this does NOT cover (by design):**
- Key storage/persistence — left to the application (keychain, HSM, file, etc.)
- Mnemonic/seed phrases — could be added later but not essential for v1
- Multi-key identity management — application concern

### Priority

High — this unblocks section 3 (sharing) and gives developers a proper key workflow instead of raw `os.urandom(32)`.

---

## 3. Access Control / Sharing

>> Needs further investigation and review. Derived keys could cover this

1. Share private data with another user by their public key
2. Group or team access control
3. Revocable access tokens
4. Encrypted sharing via re-encryption or envelope encryption

### What exists today

- Private data uses self-encryption via the autonomi library. The network never sees plaintext.
- Private put returns an opaque `data_map` (msgpack-serialized). Whoever holds the data_map can decrypt.
- No key exchange or sharing mechanism is exposed in REST/gRPC.

### Approach A: Derived key sharing

The FFI layer already has `MainSecretKey`, `MainPubkey`, `DerivedSecretKey`, `DerivedPubkey`, and `DerivationIndex` types backed by BLS cryptography. These could be exposed through antd to enable sharing:

1. User A holds a `MainSecretKey` and derives a `DerivedSecretKey` using a `DerivationIndex`
2. User A encrypts data with the derived key and stores it
3. User A shares the `DerivationIndex` and their `MainPubkey` with User B
4. User B derives the corresponding `DerivedPubkey` and can verify, but not decrypt
5. For full read access, User A shares the `DerivedSecretKey` directly

**Pros:** Uses existing BLS primitives already in the codebase. Hierarchical — one master key can create many scoped access keys.

**Cons:** No revocation — once a derived key is shared, it cannot be taken back. Group access requires distributing keys to each member.

### Approach B: Envelope encryption

1. Data is encrypted with a random symmetric key (data encryption key, DEK)
2. The DEK is encrypted with each recipient's public key and stored alongside the data
3. Recipients decrypt the DEK with their private key, then decrypt the data

**Pros:** Standard pattern. Supports multiple recipients. Adding a recipient doesn't require re-encrypting the data.

**Cons:** Requires a public key registry or out-of-band key exchange. Revocation still requires re-encrypting with a new DEK and re-sharing.

### Recommendation

Start with Approach A since the BLS derived key primitives already exist in the FFI layer. Expose key derivation endpoints in antd first (ties into section 2), then build sharing on top. Envelope encryption can be added later for multi-recipient use cases.

---

## 4. Data Availability / Persistence

>> Useful, need to check on practical limits of the client

1. Check if data is still available on the network
2. Re-upload or pin data to ensure availability
3. Get replication status of stored data

### What exists today

- No existence check for data or chunks
- No replication status API
- No re-upload or pinning mechanism

### Approach: Add existence checks

Extend the HEAD pattern to data and chunks:

| Endpoint | Method | Description |
|---|---|---|
| `/v1/data/public/{addr}` | HEAD | Check if public data exists at address |
| `/v1/data/private/{data_map}` | HEAD | Check if private data is retrievable |
| `/v1/chunks/{addr}` | HEAD | Check if a chunk exists |

**SDK methods:**

```
data_exists_public(address: hex) → bool
chunk_exists(address: hex) → bool
```

**Implementation:** Attempt a lightweight fetch or use an existence check if the autonomi client exposes one. If not, a `get` with an immediate drop could work but is wasteful.

**Re-upload / pinning:**

Re-uploading the same data to the same address should be a no-op if the data already exists (content-addressed, immutable). The cost endpoint would show the status — if cost is zero, data already exists. This needs verification against the autonomi client behaviour.

**Replication status:**

Likely out of scope for antd — replication is a network-level concern handled by the nodes, not the client. The client can only verify "data is retrievable" or "data is not retrievable."

### Priority

Medium — existence checks are straightforward to add. Replication status is likely out of scope.

---

## 5. Batch Operations

>> Useful, need to check on practical limits of the client

1. Upload multiple files or data items in one call
2. Batch cost estimation
3. Bulk retrieval by multiple addresses

### What exists today

- All operations are single-item: one put, one get, one cost estimate per request
- Each file must be uploaded individually
- The underlying autonomi client library has no batch methods
- gRPC default message size limit is 4MB (not configurable in current code)
- REST uses base64 JSON (no multipart support)

### Approach A: Server-side batch endpoints

Add batch variants of existing endpoints in antd:

| Endpoint | Method | Description |
|---|---|---|
| `/v1/data/public/batch` | POST | Put multiple data items, return array of results |
| `/v1/data/public/batch` | GET | Get multiple items by address array |
| `/v1/data/cost/batch` | POST | Estimate cost for multiple items |
| `/v1/chunks/batch` | POST | Put multiple chunks |

Request/response would be arrays of the existing single-item types. The daemon loops internally and returns partial results (some may succeed, some may fail).

**Pros:** Single HTTP round-trip. Daemon can potentially parallelise internally.

**Cons:** Large payloads risk timeouts and memory pressure. Error handling is more complex (partial success). Needs configurable size limits.

### Approach B: Client-side parallel helpers

Add SDK-level batch methods that fire multiple requests concurrently:

```python
# Python example
results = await client.data_put_public_batch([b"data1", b"data2", b"data3"], concurrency=5)
```

Each SDK would manage a concurrency pool and fire individual requests in parallel.

**Pros:** No daemon changes. Works today. Natural backpressure via concurrency limit.

**Cons:** More HTTP overhead (one request per item). Error handling still complex.

### Recommendation

Start with Approach B (client-side parallelism) — it requires no daemon changes and gives immediate value. Add Approach A later for high-throughput use cases once the underlying autonomi library is better understood for batch safety.

---

## 6. Progress / Resumable Uploads

>> Useful, need to check on practical limits of the client

1. Upload progress callbacks from SDKs
2. Resumable uploads for large files
3. Chunked upload with automatic retry

### What exists today

- Event system infrastructure exists in both REST (SSE) and gRPC (streaming) but is **stubbed and non-functional**
- gRPC `EventService.Subscribe` returns an empty stream
- REST events code is marked `#[allow(dead_code)]`
- Event types are defined: `UploadComplete` with `records_paid`, `records_already_paid`, `tokens_spent`
- Download streaming works (`/v1/data/public/{addr}/stream` and gRPC `StreamPublic`)
- File uploads are atomic — the daemon calls autonomi client, blocks until done, returns result
- All SDKs use a 5-minute default timeout

### Approach: Wire up the event system

The event infrastructure already exists. The work is connecting it to actual upload operations:

1. **Wire upload events:** When the autonomi client emits progress during uploads, forward those events through the existing SSE/gRPC stream channels
2. **Add upload ID:** Return an upload ID from put operations so progress events can be correlated
3. **Expand event types:** Add `UploadProgress` with fields like `bytes_processed`, `total_bytes`, `chunks_stored`, `total_chunks`

**SDK integration:**

```python
# Python example - callback style
def on_progress(event):
    print(f"{event.bytes_processed}/{event.total_bytes}")

result = await client.file_upload_public("/path/to/file", on_progress=on_progress)
```

**Resumable uploads:**

This is harder and may not be feasible without changes to the autonomi client library. The current upload model is atomic — the library handles chunking internally with no way to resume from a specific chunk. This needs investigation into what the autonomi library supports.

### Priority

Medium — progress events are valuable for UX but not blocking. Resumable uploads need upstream investigation.

---

# Out of Scope

## Search / Query / Listing

1. List all data stored by the current user/wallet
2. Search stored data by metadata or tags
3. Browse stored files
4. Filter or paginate results

>> This is out of scope for the core sdk as the network is decentralised. This is offered by other products

## Data Update / Versioning

1. Update data and get a stable pointer to the latest version
2. Version history or changelog for a piece of data
3. High-level mutable reference abstraction
4. Diff or compare between versions

>> As there is no mutable data, this is out of scope. Also this would be handled by a higher level application

## Higher-Level Abstractions

1. JSON document store (serialize and deserialize objects)
2. Key-value store
3. Append-only log abstraction
4. Pub/sub or message queue patterns
5. DNS-like naming (human-readable names to addresses)

>> Covered by higher level applications

## SDK Middleware / Hooks

1. Request and response interceptors
2. Automatic retry with backoff
3. Client-side caching layer
4. Logging and telemetry hooks
5. Rate limiting

>> These are handled at a higher level by individual applications

## Connection Management

1. Connection pool management
2. Failover to backup daemon
3. Load balancing across multiple antd instances

>> Out of scope per design, daemon intended to be imbedded per application

## CLI Data Management

1. Direct put and get commands from the terminal
2. Local address book of stored items
3. Human-readable aliases for addresses

>> covered by the ant-client / ant-cli offering
