# antd-mcp — MCP Server for Autonomi

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that exposes the Autonomi network as 14 tools for AI agents. Works with Claude Desktop, Claude Code, and any MCP-compatible client.

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
| `ANTD_BASE_URL` | auto-discovered | antd daemon URL (overrides port-file discovery) |

The MCP server automatically discovers the antd daemon via the `daemon.port` file written by antd on startup. Set `ANTD_BASE_URL` only if you need to override this (e.g. connecting to a remote daemon). If neither the env var nor port file is available, falls back to `http://127.0.0.1:8082`.

## Claude Desktop Configuration

Add to your Claude Desktop config (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "antd-autonomi": {
      "command": "antd-mcp"
    }
  }
}
```

The server will auto-discover the daemon via the port file. Add `"env": {"ANTD_BASE_URL": "http://your-host:port"}` only if you need to override discovery.

## Tool Reference

### Data Operations

| # | Tool | Description |
|---|------|-------------|
| 1 | `store_data(text, private?, payment_mode?)` | Store text on the network (public or encrypted) |
| 2 | `retrieve_data(address, private?)` | Retrieve text by address |
| 3 | `upload_file(path, is_directory?, payment_mode?)` | Upload a local file or directory |
| 4 | `download_file(address, dest_path, is_directory?)` | Download to local path |
| 5 | `get_cost(text?, file_path?)` | Estimate storage cost — returns `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, `payment_mode` |
| 6 | `check_balance()` | Check daemon health and network status |

### Wallet Operations

| # | Tool | Description |
|---|------|-------------|
| 7 | `wallet_address()` | Get wallet public address |
| 8 | `wallet_balance()` | Get wallet token and gas balances |
| 9 | `wallet_approve()` | Approve wallet to spend tokens on payment contracts (one-time) |

### Chunk Operations

| # | Tool | Description |
|---|------|-------------|
| 10 | `chunk_put(data)` | Store a raw chunk (base64 input) |
| 11 | `chunk_get(address)` | Retrieve a chunk (base64 output) |

### External Signer (Two-Phase Upload)

| # | Tool | Description |
|---|------|-------------|
| 12 | `prepare_upload(path, is_directory?)` | Prepare a file/directory upload for external signing |
| 13 | `prepare_data_upload(text)` | Prepare a data upload for external signing |
| 14 | `finalize_upload(upload_id, tx_hashes)` | Finalize an externally-signed upload |

### Payment Modes

The `store_data` and `upload_file` tools accept an optional `payment_mode` parameter:

| Mode | Behavior |
|------|----------|
| `"auto"` (default) | Uses merkle batch payments for 64+ chunks, single payments otherwise. Recommended for most use cases. |
| `"merkle"` | Forces merkle batch payments regardless of chunk count (minimum 2 chunks). Saves gas on larger uploads. |
| `"single"` | Forces per-chunk payments. Useful for small data or debugging. |

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
    ├── server.py      # 14 MCP tool definitions
    ├── discover.py    # Daemon port-file discovery
    └── errors.py      # Error formatting
```
