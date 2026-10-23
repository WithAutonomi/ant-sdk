# Lua Quickstart

A comprehensive guide to using the Autonomi network with the Lua SDK.

## Setup

```bash
# Install via LuaRocks
luarocks install antd

# Start local testnet
ant dev start
```

## Connecting

```lua
local antd = require("antd")

-- REST transport (default)
local client = antd.new_client()

-- Custom endpoint
local client = antd.new_client({
    transport = "rest",
    base_url = "http://localhost:8082",
})

-- gRPC transport
local client = antd.new_client({
    transport = "grpc",
    target = "localhost:50051",
})
```

## Health Check

```lua
local status, err = client:health()
if err then
    print("Error: " .. err)
    return
end
print("Healthy: " .. tostring(status.ok))
print("Network: " .. status.network)  -- "local", "default", or "alpha"
```

## Public Data

Store and retrieve arbitrary bytes on the network.

```lua
-- Store
local result, err = client:data_put_public("Hello, Autonomi!")
if err then error(err) end
print("Address: " .. result.address)
print("Cost: " .. result.cost .. " atto tokens")

-- Retrieve
local data, err = client:data_get_public(result.address)
if err then error(err) end
print(data)  -- "Hello, Autonomi!"

-- Cost estimation — returns a table with cost, file_size, chunk_count,
-- estimated_gas_cost_wei, payment_mode
local est, err = client:data_cost("some data")
if err then error(err) end
print(string.format("Estimate: %d bytes in %d chunks, %s atto, gas %s wei, mode %s",
    est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode))
```

## Private Data

Encrypted data -- only accessible with the data map.

```lua
-- Store (self-encrypting)
local result, err = client:data_put("secret message")
if err then error(err) end
local data_map = result.data_map  -- Keep this secret!

-- Retrieve (decrypt)
local data, err = client:data_get(data_map)
if err then error(err) end
print(data)
```

## Files

```lua
-- Upload a file
local result, err = client:file_put_public("/path/to/file.txt")
if err then error(err) end
print("File address: " .. result.address)

-- Download a file
local ok, err = client:file_get_public(result.address, "/path/to/output.txt")
if err then error(err) end

-- Cost estimation — returns a table with size, chunks, gas, payment mode
local est, err = client:file_cost("/path/to/file.txt")
if err then error(err) end
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs antd 0.16.0 or later (the first release with pointers). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```lua
local keys, err = client:pointer_keys()
if err then error(err.message) end
local owner = keys[1]                                      -- a pointer antd can write

local v1 = assert(client:data_put_public("version 1"))
local v2 = assert(client:data_put_public("version 2"))

local w, err = client:pointer_create(owner, v1.address)   -- pays; counter "0"
if err then error(err.type .. ": " .. err.message) end    -- never retry blindly
w, err = client:pointer_update(owner, v2.address)         -- pays again; counter "1"
if err then error(err.type .. ": " .. err.message) end

local target = client:pointer_resolve(owner)               -- target.target == v2.address (free)
local f = client:pointer_finality(owner)                   -- f.status == "open"
```

Counters are checked decimal strings, never Lua numbers: compare them with `antd.compare_pointer_counters(a, b)`. `pointer_transfer`, `pointer_get`, `pointer_controller`, `pointer_prepare` and `pointer_finalize` complete the set (REST only).

Runnable example: `antd-lua/examples/08-pointers.lua`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-lua
ANTD_POINTER_OWNER=<address> lua examples/08-pointers.lua
```

## Error Handling

The Lua SDK uses the `nil, err` return pattern. The `err` value is a table with `code` and `message` fields.

```lua
local data, err = client:data_get_public("nonexistent")
if err then
    if err.code == 404 then
        print("Not found")
    elseif err.code == 402 then
        print("Payment issue")
    elseif err.code == 502 then
        print("Network unreachable")
    else
        print(string.format("Error (%d): %s", err.code, err.message))
    end
end
```

Error codes:

| Code | Field `err.code` | When |
|------|-------------------|------|
| 400 | `bad_request` | Invalid parameters |
| 402 | `payment` | Insufficient funds |
| 404 | `not_found` | Resource not found |
| 409 | `already_exists` / `fork` | Duplicate creation or version conflict |
| 413 | `too_large` | Payload too large |
| 500 | `internal` | Server error |
| 502 | `network` | Network unreachable |

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs antd 0.16.0 or later. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```lua
local one = assert(client:data_put_public("first file"))    -- pays
local two = assert(client:data_put_public("second file"))   -- pays

local built, err = client:build_manifest({                   -- free
    { path = "notes/one.txt", address = one.address },
    { path = "notes/two.txt", address = two.address },
}, { name = "example" })
if err then error(err.type .. ": " .. err.message) end
print(built.link)                -- nil when over 1,500 bytes: share built.manifest (a string) instead

local decoded = assert(client:decode_manifest_link(built.link, true))   -- free
for _, e in ipairs(decoded.entries) do
    print(e.effective_name, e.kind, e.exact_size, e.error)
end
```

`client:decode_manifest(bytes, resolve)` takes raw `.ant` bytes. Use `data_map = ...` instead of `address = ...` for an embedded entry; `opts` may set `embed_roots = false`. An unset size is `nil`, never `0`.

Every upload result (`DataPutResult`, `DataPutPublicResult`, `FilePutResult`, `FilePutPublicResult` and, for external-signer uploads, `FinalizeUploadResult`) also has `sha256` (`nil` when none): the plaintext's SHA-256 (hex). To record it in a manifest, pass it as the entry's `sha256`: an entry table takes `sha256 = hex`, and entries read back carry `sha256`. Requires antd 0.17.0 or later; the SDK sends it only when set and does not check it.

Runnable example: `antd-lua/examples/09-manifests.lua`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-lua
ANTD_BASE_URL=http://localhost:8082 lua examples/09-manifests.lua
```

## Examples

```bash
# Run individual examples
ant dev example connect -l lua
ant dev example data -l lua
ant dev example all -l lua

# Or directly
lua antd-lua/examples/01_connect.lua
lua antd-lua/examples/02_data.lua
```

See `antd-lua/examples/` for the complete set of examples.
