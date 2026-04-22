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
local result, err = client:data_put_private("secret message")
if err then error(err) end
local data_map = result.address  -- Keep this secret!

-- Retrieve (decrypt)
local data, err = client:data_get_private(data_map)
if err then error(err) end
print(data)
```

## Files

```lua
-- Upload a file
local result, err = client:file_upload_public("/path/to/file.txt")
if err then error(err) end
print("File address: " .. result.address)

-- Download a file
local ok, err = client:file_download_public(result.address, "/path/to/output.txt")
if err then error(err) end

-- Upload a directory
local result, err = client:dir_upload_public("/path/to/directory")
if err then error(err) end

-- Download a directory
local ok, err = client:dir_download_public(result.address, "/path/to/output_dir")
if err then error(err) end

-- Cost estimation — returns a table with size, chunks, gas, payment mode
local est, err = client:file_cost("/path/to/file.txt")
if err then error(err) end
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
