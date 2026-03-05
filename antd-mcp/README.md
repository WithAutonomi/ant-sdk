# antd-mcp — MCP Server for Autonomi

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that exposes the Autonomi network as 31 tools for AI agents. Works with Claude Desktop, Claude Code, and any MCP-compatible client.

## Installation

```bash
pip install -e antd-mcp/
```

Requires the `antd` Python SDK (`pip install antd[rest]`).

## Running

```bash
# stdio transport (default — for Claude Desktop)
antd-mcp

# SSE transport (for web-based clients)
antd-mcp --sse
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTD_BASE_URL` | `http://localhost:8080` | antd daemon URL |

## Claude Desktop Configuration

Add to your Claude Desktop config (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "antd-autonomi": {
      "command": "antd-mcp",
      "env": {
        "ANTD_BASE_URL": "http://localhost:8080"
      }
    }
  }
}
```

## Tool Reference

### Data Operations

| # | Tool | Description |
|---|------|-------------|
| 1 | `store_data(text, private?)` | Store text on the network (public or encrypted) |
| 2 | `retrieve_data(address, private?)` | Retrieve text by address |
| 3 | `upload_file(path, is_directory?)` | Upload a local file or directory |
| 4 | `download_file(address, dest_path, is_directory?)` | Download to local path |
| 9 | `get_cost(text?, file_path?)` | Estimate storage cost |
| 10 | `check_balance()` | Check daemon health and network status |

### Chunk Operations

| # | Tool | Description |
|---|------|-------------|
| 11 | `chunk_put(data)` | Store a raw chunk (base64 input) |
| 12 | `chunk_get(address)` | Retrieve a chunk (base64 output) |

### Pointer Operations

| # | Tool | Description |
|---|------|-------------|
| 5 | `create_pointer(owner_secret_key, target_kind, target_address)` | Create a mutable pointer |
| 6 | `update_pointer(owner_secret_key, target_kind, target_address)` | Update pointer target |
| 13 | `get_pointer(address)` | Read pointer details |
| 14 | `pointer_exists(address)` | Check if pointer exists |
| 15 | `pointer_cost(public_key)` | Estimate creation cost |

### Scratchpad Operations

| # | Tool | Description |
|---|------|-------------|
| 7 | `create_scratchpad(owner_secret_key, content_type, data)` | Create versioned scratchpad |
| 8 | `update_scratchpad(owner_secret_key, content_type, data)` | Update scratchpad |
| 16 | `get_scratchpad(address)` | Read scratchpad contents |
| 17 | `scratchpad_exists(address)` | Check if scratchpad exists |
| 18 | `scratchpad_cost(public_key)` | Estimate creation cost |

### Graph Operations

| # | Tool | Description |
|---|------|-------------|
| 19 | `create_graph_entry(owner_secret_key, content, parents?, descendants?)` | Create DAG node |
| 20 | `get_graph_entry(address)` | Read graph entry |
| 21 | `graph_entry_exists(address)` | Check if entry exists |
| 22 | `graph_entry_cost(public_key)` | Estimate creation cost |

### Register Operations

| # | Tool | Description |
|---|------|-------------|
| 23 | `create_register(owner_secret_key, initial_value)` | Create 32-byte register |
| 24 | `get_register(address)` | Read register value |
| 25 | `update_register(owner_secret_key, new_value)` | Update register |
| 26 | `register_cost(public_key)` | Estimate creation cost |

### Vault Operations

| # | Tool | Description |
|---|------|-------------|
| 27 | `vault_put(secret_key, data, content_type)` | Store encrypted vault data |
| 28 | `vault_get(secret_key)` | Retrieve vault data |
| 29 | `vault_cost(secret_key, max_size)` | Estimate storage cost |

### Archive Operations

| # | Tool | Description |
|---|------|-------------|
| 30 | `archive_get(address)` | List files in an archive |
| 31 | `archive_put(entries)` | Create an archive manifest |

## Response Format

All tools return JSON with a `network` field indicating the connected network:

```json
{
  "address": "abc123...",
  "cost": "1000000",
  "network": "local"
}
```

Errors return structured error objects:

```json
{
  "error": "NOT_FOUND",
  "message": "Resource not found",
  "status_code": 404,
  "network": "local"
}
```

## Project Structure

```
antd-mcp/
├── pyproject.toml
└── src/antd_mcp/
    ├── __init__.py
    ├── server.py      # 31 MCP tool definitions
    └── errors.py      # Error formatting
```
