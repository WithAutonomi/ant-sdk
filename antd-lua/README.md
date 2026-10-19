# antd-lua

Lua SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

```bash
luarocks install antd
```

Or from source:

```bash
cd antd-lua
luarocks make
```

### Dependencies

- Lua >= 5.1 (LuaJIT compatible)
- [luasocket](https://luarocks.org/modules/lunarmodules/luasocket) >= 3.0
- [lua-cjson](https://luarocks.org/modules/openresty/lua-cjson) >= 2.1

### Platform Notes

**Windows:** `luasocket` requires a C compiler that can link against the Lua shared library. If you are using **mingw-w64** with LuaJIT, `luarocks install luasocket` may fail with linker errors (`undefined reference to _initialize_onexit_table`). Known workarounds:

1. **Use MSVC** — Install Visual Studio Build Tools and configure LuaRocks to use `cl.exe`:
   ```
   luarocks config variables.CC cl
   luarocks config variables.LD link
   luarocks install luasocket
   ```

2. **Use a prebuilt Lua distribution** — [LuaBinaries](https://luabinaries.sourceforge.net/) or [OpenResty](https://openresty.org/) ship with prebuilt luasocket.

3. **Use WSL/Linux** — luasocket builds without issues on Linux and macOS.

`lua-cjson` typically builds fine on all platforms.

## Quick Start

```lua
local antd = require("antd")

-- Create a client (default: http://localhost:8082)
local client = antd.new_client()

-- Check daemon health
local health, err = client:health()
if err then
    print("Error: " .. err.message)
    os.exit(1)
end
print("OK: " .. tostring(health.ok) .. ", Network: " .. health.network)

-- Store data
local result, err = client:data_put_public("Hello, Autonomi!")
if err then
    print("Error: " .. err.message)
    os.exit(1)
end
print("Stored at " .. result.address .. " (chunks: " .. result.chunks_stored .. ")")

-- Retrieve data
local data, err = client:data_get_public(result.address)
if err then
    print("Error: " .. err.message)
    os.exit(1)
end
print("Retrieved: " .. data)
```

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```lua
local antd = require("antd")

-- Default: http://localhost:8082, 300 second timeout
local client = antd.new_client()

-- Custom URL
local client = antd.new_client("http://custom-host:9090")

-- Custom timeout (in seconds)
local client = antd.new_client(antd.DEFAULT_BASE_URL, { timeout = 30 })
```

## API Reference

All methods return `value, err` following Lua convention. On success `err` is `nil`. On failure the first return is `nil` and `err` is an error table.

### Health

| Method | Description |
|--------|-------------|
| `client:health()` | Check daemon status |

### Data (Immutable)

| Method | Description |
|--------|-------------|
| `client:data_put_public(data, payment_mode)` | Store public data — returns a `DataPutPublicResult` table (DataMap stored on-network) |
| `client:data_get_public(address)` | Retrieve public data by address |
| `client:data_put(data, payment_mode)` | Store encrypted private data — returns a `DataPutResult` table (DataMap returned to caller) |
| `client:data_get(data_map)` | Retrieve private data using a caller-held DataMap |
| `client:data_cost(data, payment_mode)` | Estimate storage cost — returns a table with `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, `payment_mode` |

### Chunks

| Method | Description |
|--------|-------------|
| `client:chunk_put(data)` | Store a raw chunk |
| `client:chunk_get(address)` | Retrieve a chunk |

### Files

| Method | Description |
|--------|-------------|
| `client:file_put(path, payment_mode)` | Upload a file privately — returns a `FilePutResult` table (DataMap returned to caller) |
| `client:file_get(data_map, dest_path)` | Download a private file using a caller-held DataMap |
| `client:file_put_public(path, payment_mode)` | Upload a file publicly — returns a `FilePutPublicResult` table (DataMap stored on-network) |
| `client:file_get_public(address, dest_path)` | Download a public file by address |
| `client:file_cost(path, is_public, payment_mode)` | Estimate upload cost — returns a table with `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, `payment_mode` |

### Manifests

A manifest (ADR-0006) is one `.ant` file, or one `ant://manifest/` link, that describes a set of files: each entry has an optional path and size, and either an embedded DataMap (the manifest is then the key to the file) or a public file's DataMap address. The daemon builds and decodes manifests, so the format never has to be re-implemented here. The manifest methods need an antd with the manifest API (the antd release after 0.15.0).

**Nothing is uploaded or paid for.** Building a manifest and a resolving decode only read from the network (the embedding policy and `resolve` fetch DataMaps), so they can time out, and they are free to retry. To share a manifest, store its bytes yourself, or hand out the link.

| Method | Description |
|--------|-------------|
| `client:build_manifest(entries, opts)` | Build a manifest from DataMaps and addresses already in hand — returns `{ manifest, link, entries }`. `manifest` is the raw `.ant` bytes; `link` is `nil` when it would not fit the recommended 1,500 bytes |
| `client:decode_manifest(bytes, resolve)` | Decode `.ant` bytes — returns `{ source, name, torrent_info_hash_v1, torrent_info_hash_v2, entries }` |
| `client:decode_manifest_link(link, resolve)` | Decode an `ant://` manifest link, a file link or a bare 64-hex address — same result. A file link or address reads as `source == "file_link"`: one public entry with no path |

Each of `entries` passed to `build_manifest` is `{ path, size, data_map, address }`, with **exactly one** of `data_map` (hex, as the upload methods return it; embedded) or `address` (hex; public). An entry with both or neither is refused as `bad_request` (status 400) before anything is sent, with the daemon's own message, so a client-side refusal reads exactly like the daemon's (every bad entry listed, counted from 0). `path` (the relative path the entry extracts under) and `size` (the plaintext size to record, the creator's claim) are optional. `opts` is `nil` or `{ name, torrent_info_hashes, embed_roots }`: a suggested root directory name, BitTorrent info hashes of the same files (40 hex characters for v1, 64 for v2), and whether to embed roots. `embed_roots` defaults to `true` (when `nil`): the daemon resolves each shrunk DataMap and embeds its root when that is at most 64 KiB, so recipients skip that fetch. `false` embeds shrunk DataMaps exactly as given.

Every entry read back is `{ effective_name, path, size, kind, content_address, data_map, exact_size, error }`. `effective_name` is the path, or the content address when there is none. `kind` is `antd.ManifestEntryKind.EMBEDDED` (`"embedded"`) or `PUBLIC` (`"public"`). `content_address` is the file's public DataMap address, the same for private and public uploads of one file. `data_map` is the embedded DataMap in the hex form the download methods accept (decode only). `exact_size` comes from an embedded root DataMap, or from a decode with `resolve = true`, which fetches each entry's DataMap (not its content). Entries come in encoded order, sorted by effective name.

The `.ant` bytes are a plain Lua string on both sides; base64 is only the REST wire form. Sizes are Lua numbers, exact up to 2^53 (`antd.MAX_MANIFEST_SIZE`), far past any real file; a `size` outside 0..2^53 or not a whole number is refused before sending. **Anything unset reads as `nil`**: a size the manifest does not record is `nil`, never `0`, and `path`, `data_map`, `error`, `link`, `name` and the torrent info hashes are `nil` rather than `""`.

A bad entry or input from the daemon is a `bad_request` (HTTP 400) with the daemon's message, which names each invalid entry counting from 0 (`entries[0]: invalid path "../x": ...`); the SDK's own checks use the same type, status and wording. One entry's `resolve` failure is not a failed call: it comes back in that entry's `error`.

```lua
local antd = require("antd")
local client = antd.new_client()

local built, err = client:build_manifest({
    { path = "notes/one.txt", address = first_address },
    { path = "notes/two.txt", data_map = private_data_map, size = 85 },
}, { name = "notes" })
if err then error(err.type .. ": " .. err.message) end
print(built.link)                                   -- ant://manifest/...

local decoded = assert(client:decode_manifest_link(built.link, true))
for _, e in ipairs(decoded.entries) do
    print(e.effective_name, e.kind, e.exact_size, e.error)
end
```

See [examples/09-manifests.lua](examples/09-manifests.lua) for the full round trip. `spec/live_manifests_spec.lua` builds and decodes manifests of data already on a devnet, and pays for nothing. It stays pending unless `ANTD_TEST_URL` and `ANTD_TEST_MANIFEST_ADDRESSES` (two comma-separated public data addresses) are set; it also reads `ANTD_TEST_MANIFEST_SIZES`, `ANTD_TEST_MANIFEST_DATA_MAP`, `ANTD_TEST_MANIFEST_DATA_MAP_SIZE` and `ANTD_TEST_MANIFEST_LINK` when they are.

### External signer (prepare / finalize)

| Method | Description |
|--------|-------------|
| `client:prepare_upload(path, visibility)` | Get payment intent for a file without paying — returns `upload_id`, `payments`, `payment_type`, vault/token addresses, `rpc_url` |
| `client:prepare_upload_public(path)` | Same, with the DataMap stored on-network at finalize |
| `client:prepare_data_upload(data)` | Same for in-memory bytes |
| `client:finalize_upload(upload_id, tx_hashes)` | Submit a wave-batch upload after external payment — returns a `FinalizeUploadResult` table |
| `client:finalize_merkle_upload(upload_id, winner_pool_hash, store_data_map)` | Submit a merkle-batch upload after external payment |
| `client:prepare_chunk_upload(data)` | Get payment intent for a single chunk |
| `client:finalize_chunk_upload(upload_id, tx_hashes)` | Submit a prepared chunk after external payment; returns the chunk address |

A finalize where some chunks stayed unstored after the daemon's retries returns a `partial_upload` error (HTTP 502, `code: "PARTIAL_UPLOAD"`) — see [Partial uploads](#partial-uploads) below. The full flow is documented in [docs/external-signer-flow.md](../docs/external-signer-flow.md).

### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes; what it points at (a chunk, such as a public file's data map, or another pointer) can be changed by the owner. The daemon holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (files in the format `ant pointer keygen` writes), so every write names the pointer by its address (`owner`), never by a key. The pointer methods need an antd with the pointer API (the release after 0.15.0).

**Every write pays, and the SDK never retries one.** `pointer_create`, `pointer_update`, `pointer_transfer` and `pointer_finalize` each pay about the price of one chunk, and every attempt pays again. Do not retry them automatically: check the error first. Reads are free to retry; a read during an update or churn can fail with `close_group_shortfall`.

**Counters are decimal strings**, such as `"0"` or `"18446744073709551615"`, never Lua numbers. A final state (after a transfer or a freeze) sits at 2^64-1, which no Lua number holds exactly: LuaJIT and Lua 5.1 numbers are doubles, exact only up to 2^53, and Lua 5.4 integers are signed 64-bit. The SDK checks every counter it reads (ASCII digits only, at most 2^64-1) and drops leading zeros, so equal counters are equal strings. A malformed counter is an `internal` error, never a `0`. Compare counters with `antd.compare_pointer_counters(a, b)` (returns `-1`, `0` or `1`), not with `<` on the strings. `antd.POINTER_FINAL_COUNTER` is the final counter, and `antd.parse_pointer_counter(s)` checks one.

Unset values (the daemon's JSON `null`) read as `nil`. The daemon accepts addresses with a `0x` prefix but always returns bare hex, so compare addresses through `antd.normalize_address(addr)`.

| Method | Description |
|--------|-------------|
| `client:pointer_keys()` | The addresses of the pointers this daemon holds owner keys for, so can write — a list of hex strings |
| `client:pointer_create(owner, target, kind)` | Create a pointer, paid by the daemon wallet — returns `{ address, state_id, counter }`. `kind` is `antd.PointerKind.CHUNK` (the default when `nil`) or `antd.PointerKind.POINTER` (a forwarding the owner can still change). `already_exists` if it exists, refused before paying |
| `client:pointer_update(owner, target, kind)` | Point a pointer at a new target, paid by the daemon wallet; creates it if it does not exist. Same result as create. `pointer_final` once transferred or frozen |
| `client:pointer_transfer(owner, recipient)` | Hand a pointer over for good to the recipient's pointer, which must exist: readers of the address are redirected there and the old key can change nothing. Irreversible. Returns `{ address, state_id, finality, finality_error }`; `finality` is `nil` when the check after the write failed, which does not undo the transfer |
| `client:pointer_get(address)` | Read a pointer — returns `{ address, owner, counter, kind, kind_tag, target, state_id, is_final, transferred_to }` (`owner` is the owner's public key; `kind` is `"chunk"`, `"pointer"` or `"unknown"`, with the raw `kind_tag`). `not_found` if there is none |
| `client:pointer_resolve(address)` | Follow a chain of pointers (forwardings and transfers) to the target at its end — returns `{ kind, kind_tag, target }` |
| `client:pointer_finality(address)` | Ask the whole close group where a pointer stands — returns `{ address, group, answered, status, raw_status, counter, state, states, majority, transferred_to }`. `status` is one of `antd.PointerFinalityStatus`: `OPEN`, `SETTLING`, `UNCONFIRMED`, `FINAL`, `FORKED`, or `UNKNOWN` for a status a newer daemon may add (`raw_status` keeps the wire value). Only `"final"` means a transfer is beyond dispute |
| `client:pointer_controller(address)` | Follow transfers to the pointer whose owner now decides — returns `{ pointer, transfers, frozen }` |
| `client:pointer_prepare(owner, op, opts)` | External signer: the daemon signs `op` with its key and quotes it — returns `{ upload_id, op, address, state_id, counter, payment_type, payments, total_amount, payment_vault_address, payment_token_address, rpc_url, signed_quotes }` (wave-batch `payments` for `payForQuotes()`). Build `op` with `antd.pointer_create_op(target, kind)`, `antd.pointer_update_op(target, kind)` or `antd.pointer_transfer_op(recipient)`; `opts` is `{ include_signed_quotes = true }` or `nil`. Needs no daemon wallet and pays nothing. Other writes to the pointer answer `conflict` until it is finalized or expires (one hour) |
| `client:pointer_finalize(upload_id, tx_hashes)` | External signer: store the prepared write once paid — returns `{ address, state_id, counter, finality }` (`finality` for a transfer only). A write that falls short after payment returns `close_group_shortfall` with `retryable == true`: repeat the same call to store it against the same payment |

```lua
local antd = require("antd")
local client = antd.new_client()
local owner = "<a pointer address from client:pointer_keys()>"

local w, err = client:pointer_create(owner, first_address)   -- pays
if err then error(err.type .. ": " .. err.message) end      -- never retry blindly
w, err = client:pointer_update(owner, second_address)        -- pays again
local target = client:pointer_resolve(owner)                 -- free
local f = client:pointer_finality(owner)
print(w.counter, target.target, f.status)                    -- "1"  <second_address>  "open"
```

See [examples/08-pointers.lua](examples/08-pointers.lua) for the full round trip.

## Error Handling

All methods return `nil, err` on failure. Errors are tables with `type`, `status_code`, and `message` fields:

```lua
local errors = require("antd.errors")

local data, err = client:data_get_public(address)
if err then
    if errors.is_antd_error(err) then
        if err.type == "not_found" then
            print("Data not found on network")
        elseif err.type == "payment" then
            print("Insufficient funds")
        end
    end
    print("Error " .. err.status_code .. ": " .. err.message)
end
```

| Error Type | HTTP Status | When |
|-----------|-------------|------|
| `bad_request` | 400 | Invalid parameters |
| `payment` | 402 | Insufficient funds |
| `not_found` | 404 | Resource not found |
| `already_exists` | 409 | Resource exists |
| `fork` | 409 | Version conflict |
| `pointer_final` | 409 | The pointer is transferred or frozen; nothing can change it (`code: "POINTER_FINAL"`) |
| `pointer_forked` | 409 | The pointer's owner signed two final states and no majority holds either (`code: "POINTER_FORKED"`) |
| `conflict` | 409 | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state (`code: "CONFLICT"`) |
| `too_large` | 413 | Payload too large |
| `internal` | 500 | Server error |
| `network` | 502 | Network unreachable |
| `partial_upload` | 502 | Finalize stored some chunks but not all (`code: "PARTIAL_UPLOAD"`) — see below |
| `service_unavailable` | 503 | Wallet not configured, or the daemon is not ready |
| `close_group_shortfall` | 503 | Too few of an address's close group answered or stored (`code: "CLOSE_GROUP_SHORTFALL"`). Carries `retryable`: `true` only for a pointer finalize that kept the paid state (see `client:pointer_finalize`). Reads are free to retry; `errors.is_close_group_shortfall(err)` matches it |

The 409 and 503 rows that share a status are told apart by the body's `code`; a body without one of those codes keeps the status-based type.

### Partial uploads

A `finalize_upload` / `finalize_merkle_upload` can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. The daemon reports that as HTTP 502 with `code: "PARTIAL_UPLOAD"`, and the SDK maps it onto a `partial_upload` error instead of a generic `network` one. On top of the usual `type` / `status_code` / `message` it carries:

| Field | Meaning |
|-------|---------|
| `chunks_stored` | Chunks now on the network |
| `chunks_failed` | Chunks still unstored |
| `total_chunks` | Chunks in the upload |
| `retryable` | `true` when the daemon kept the paid attempt under the same `upload_id` (sent by antd ≥ 0.14.0; absent on older daemons, which reads as `false`) |
| `retention_known` | `true` when the body's `retryable` is a JSON boolean (`true` or `false`), so the daemon said whether it kept the paid attempt; absent, `null` or any other type reads as `false`. `retryable` implies `retention_known` |

The body is read strictly, never coerced. A count is taken only from a JSON number that is a finite, non-negative integer below 2^64; a quoted number such as `"12"`, a boolean, an object, `null`, or a negative, fractional or non-finite number reads as `0`. The check runs on the value cjson decodes (an IEEE-754 double), not on the exact wire digits: a fraction too close to an integer for a double to resolve reads as that integer, integers above 2^53 round, and the largest u64 rounds up to 2^64 and reads as `0`. `retryable` is `true` only for the JSON boolean `true` (a string `"true"` or the number `1` reads `false`), and `retention_known` only when `retryable` is a JSON boolean. The error is only mapped when `code` is exactly the string `"PARTIAL_UPLOAD"`; any other `code` keeps the status-based mapping (a 502 stays `network`), as does a body that is not strict JSON (for example a bare `NaN` or `0x10`). A non-string `error` field falls back to the raw response body as `message`. A malformed body never raises: at worst it maps onto the status-based error.

The on-chain payment persists and the stored chunks stay on the network either way. What to do next depends on what the daemon said about the paid attempt:

- **`retryable`** (antd ≥ 0.14.0; implies `retention_known`) — call the **same** finalize method again with the **same `upload_id` and payment artefacts**. The daemon stores the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure returns `partial_upload` on every call, so cap the attempts and treat a `chunks_failed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retention_known and not retryable`** — the daemon confirmed nothing was retained (a merkle finalize with deliberately unpaid batches). Re-prepare the same content: the prepare skips already-stored chunks, so the retry pays only for the remainder.
- **`not retention_known`** — retention is unknown: the error did not say, as a JSON boolean, whether the paid attempt was kept. The daemon may still hold it (it records the resume handle before it returns the error). Stop automatic recovery, keep the `upload_id` and the original payment artefacts, and reconcile before re-preparing or paying again. **Never pay again on this signal alone.** Daemons older than 0.14.0 never send `retryable`, so their partial uploads read as unknown.

```lua
local errors = require("antd.errors")

local result, err = client:finalize_upload(upload_id, tx_hashes)
if errors.is_partial_upload(err) then
    print(string.format("%d/%d chunks stored, %d still unstored",
        err.chunks_stored, err.total_chunks, err.chunks_failed))
    if err.retryable then
        -- same upload_id, same payment: see finalize_with_retry in
        -- examples/07-external-signer.lua for a bounded loop
        result, err = client:finalize_upload(upload_id, tx_hashes)
    elseif err.retention_known then
        -- confirmed not retained: re-prepare the same content; only the
        -- remainder is quoted and paid
    else
        -- retention unknown: stop, keep upload_id + tx_hashes, and reconcile
        -- before re-preparing or paying again
    end
end
```

See [docs/external-signer-flow.md §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment) for the daemon-side contract and `finalize_with_retry` in [examples/07-external-signer.lua](examples/07-external-signer.lua) for a bounded retry helper.

#### Upgrading: partial uploads are no longer `network` errors

Until the 0.14.0 release, a REST partial upload surfaced as a plain `network` error (HTTP 502) carrying only the message text. It now has `type == "partial_upload"`, still with `status_code == 502`. This is an intentional change: the typed error carries the counts and the retention flags above. Code that matched `err.type == "network"` to catch a failed finalize no longer sees partial uploads. Handle `partial_upload` explicitly (preferred, with `errors.is_partial_upload(err)`), or widen the check:

```lua
-- before: if err.type == "network" then ... end
if err.type == "partial_upload" or err.type == "network" then
    -- a 502 from the daemon: partial store or network failure
end
```

`err.status_code == 502` matches both, as before.

#### Upgrading: new error types with the pointer API

The pointer API brings four error types: `pointer_final`, `pointer_forked`, `conflict` and `close_group_shortfall`. The three 409s only come from the pointer methods, which are new. `close_group_shortfall` is not only for pointers: a daemon with the pointer API reports a close group that fell short on any call (a chunk store, say) as `503 CLOSE_GROUP_SHORTFALL`. This SDK version reads that as `close_group_shortfall`, where an older SDK read it as `service_unavailable`; an older daemon sent it as a 500, read as `internal`. Code that matched `err.type == "service_unavailable"` or `"internal"` to catch it should handle `close_group_shortfall` too. `err.status_code == 503` still matches.

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `06-private-data` — Private encrypted data storage
- `07-external-signer` — Prepare / pay with an external signer / finalize, with a bounded partial-upload retry (shells out to foundry's `cast`)
- `08-pointers` — Create a pointer at public data, update it, resolve and read it, and check its finality. Needs `ANTD_POINTER_OWNER` set to a pointer address the daemon holds a key for; `ANTD_BASE_URL` overrides the daemon URL. Each run pays for two data uploads and two pointer writes
- `09-manifests` — Build a manifest of two public uploads, print its link and entries, and decode the link with `resolve` for exact sizes. `ANTD_BASE_URL` overrides the daemon URL. Each run pays for the two data uploads; the manifest calls pay nothing

Lua can only start a process through `/bin/sh -c`, so `07-external-signer` never puts a daemon-supplied value into a command line as-is. `examples/external_signer_util.lua` validates the prepare response before any process starts: the RPC URL must be http(s) printable ASCII with no whitespace, addresses `0x` + 40 hex digits, amounts decimal uint256, and quote hashes 64 hex digits. It also shell-quotes every argument to `cast` and checks that the transaction hash `cast` returns is `0x` + 64 hex digits. Its errors name the field or the program, never a value or the key. Reuse it (or a real process-spawning library) if you adapt the example. POSIX shells only.

## Testing

Tests use the [busted](https://github.com/lunarmodules/busted) framework:

```bash
luarocks install busted
busted spec/
```

`spec/external_signer_util_spec.lua` runs real commands through `/bin/sh` (`printf`, `touch`, `sh`), so it needs a POSIX shell. It does not need `cast`.

`spec/live_pointers_spec.lua` is a pointer round trip against a live daemon on a devnet. It stays pending unless `ANTD_TEST_URL` (the daemon's REST URL) and `ANTD_TEST_POINTER_OWNERS` (two comma-separated, never-written pointer addresses the daemon holds keys for) are set. The daemon's wallet pays for every write, and the run leaves the first pointer transferred and the second with a pending prepared write, so each pair works once:

```bash
ANTD_TEST_URL=http://127.0.0.1:8082 \
ANTD_TEST_POINTER_OWNERS=<hex>,<hex> busted spec/live_pointers_spec.lua
```
