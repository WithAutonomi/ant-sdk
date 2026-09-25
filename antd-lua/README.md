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

The on-chain payment persists and the stored chunks stay on the network either way. What to do next depends on `retryable`:

- **`retryable == true`** — call the **same** finalize method again with the **same arguments**. The daemon stores the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure returns `partial_upload` on every call, so cap the attempts and treat a `chunks_failed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retryable == false`** — nothing was retained (older daemon, or a merkle finalize with deliberately unpaid batches). Re-prepare the same content: the prepare skips already-stored chunks, so the retry pays only for the remainder.

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
    else
        -- re-prepare the same content; only the remainder is quoted and paid
    end
end
```

See [docs/external-signer-flow.md §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment) for the daemon-side contract and `finalize_with_retry` in [examples/07-external-signer.lua](examples/07-external-signer.lua) for a bounded retry helper.

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `06-private-data` — Private encrypted data storage
- `07-external-signer` — Prepare / pay with an external signer / finalize, with a bounded partial-upload retry (shells out to foundry's `cast`)

## Testing

Tests use the [busted](https://github.com/lunarmodules/busted) framework:

```bash
luarocks install busted
busted spec/
```
