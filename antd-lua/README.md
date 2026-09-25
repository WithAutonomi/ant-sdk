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
| `too_large` | 413 | Payload too large |
| `internal` | 500 | Server error |
| `network` | 502 | Network unreachable |
| `partial_upload` | 502 | Finalize stored some chunks but not all (`code: "PARTIAL_UPLOAD"`) — see below |

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

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `06-private-data` — Private encrypted data storage
- `07-external-signer` — Prepare / pay with an external signer / finalize, with a bounded partial-upload retry (shells out to foundry's `cast`)

Lua can only start a process through `/bin/sh -c`, so `07-external-signer` never puts a daemon-supplied value into a command line as-is. `examples/external_signer_util.lua` validates the prepare response before any process starts: the RPC URL must be http(s) printable ASCII with no whitespace, addresses `0x` + 40 hex digits, amounts decimal uint256, and quote hashes 64 hex digits. It also shell-quotes every argument to `cast` and checks that the transaction hash `cast` returns is `0x` + 64 hex digits. Its errors name the field or the program, never a value or the key. Reuse it (or a real process-spawning library) if you adapt the example. POSIX shells only.

## Testing

Tests use the [busted](https://github.com/lunarmodules/busted) framework:

```bash
luarocks install busted
busted spec/
```

`spec/external_signer_util_spec.lua` runs real commands through `/bin/sh` (`printf`, `touch`, `sh`), so it needs a POSIX shell. It does not need `cast`.
