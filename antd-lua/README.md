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

-- Create a client (default: http://localhost:8080)
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
print("Stored at " .. result.address .. " (cost: " .. result.cost .. " atto)")

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

-- Default: http://localhost:8080, 300 second timeout
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
| `client:data_put_public(data)` | Store public data |
| `client:data_get_public(address)` | Retrieve public data |
| `client:data_put_private(data)` | Store encrypted private data |
| `client:data_get_private(data_map)` | Retrieve private data |
| `client:data_cost(data)` | Estimate storage cost |

### Chunks

| Method | Description |
|--------|-------------|
| `client:chunk_put(data)` | Store a raw chunk |
| `client:chunk_get(address)` | Retrieve a chunk |

### Graph Entries (DAG Nodes)

| Method | Description |
|--------|-------------|
| `client:graph_entry_put(secret_key, parents, content, descendants)` | Create entry |
| `client:graph_entry_get(address)` | Read entry |
| `client:graph_entry_exists(address)` | Check if exists |
| `client:graph_entry_cost(public_key)` | Estimate creation cost |

### Files & Directories

| Method | Description |
|--------|-------------|
| `client:file_upload_public(path)` | Upload a file |
| `client:file_download_public(address, dest_path)` | Download a file |
| `client:dir_upload_public(path)` | Upload a directory |
| `client:dir_download_public(address, dest_path)` | Download a directory |
| `client:archive_get_public(address)` | Get archive manifest |
| `client:archive_put_public(archive)` | Create archive manifest |
| `client:file_cost(path, is_public, include_archive)` | Estimate upload cost |

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

## Models

Constructor functions are available for creating model tables:

```lua
local antd = require("antd")

local entry = antd.new_archive_entry("file.txt", "abc123", 1000, 2000, 42)
local archive = antd.new_archive({ entry })
local descendant = antd.new_graph_descendant("public_key_hex", "content_hex")
```

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `05-graph` — Graph entry (DAG node) operations
- `06-private-data` — Private encrypted data storage

## Testing

Tests use the [busted](https://github.com/lunarmodules/busted) framework:

```bash
luarocks install busted
busted spec/
```
