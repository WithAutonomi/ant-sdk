# antd-mcp — MCP Server for Autonomi

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that exposes the Autonomi network as 19 tools for AI agents. Works with Claude Desktop, Claude Code, and any MCP-compatible client.

## Installation

```bash
# Run without installing (recommended for MCP client configs)
uvx antd-mcp

# Or install as a tool
pipx install antd-mcp

# Or into an environment
pip install antd-mcp
```

Python 3.10+. Pulls in the [`antd`](https://pypi.org/project/antd/) Python SDK (REST transport) automatically. Needs a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon (tested against antd 0.12.x).

From a source checkout: `pip install -e antd-mcp/`.

Add it to Claude Code in one line:

```bash
claude mcp add antd-autonomi -- uvx antd-mcp
```

## Running

```bash
# stdio transport (default — for Claude Desktop)
antd-mcp

# Streamable HTTP transport (for web-based clients; the current MCP HTTP transport)
antd-mcp --http

# Legacy SSE transport
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
      "command": "uvx",
      "args": ["antd-mcp"]
    }
  }
}
```

The server will auto-discover the daemon via the port file. Add `"env": {"ANTD_BASE_URL": "http://your-host:port"}` only if you need to override discovery.

## Tool Reference

### Data Operations

| # | Tool | Description |
|---|------|-------------|
| 1 | `store_data(text, private?, payment_mode?)` | Store text on the network. With `private=True`, the returned `address` is the caller-held DataMap (not stored on-network — keep it safe). |
| 2 | `retrieve_data(address, private?)` | Retrieve text by address. Pass `private=True` if `address` is a caller-held DataMap from a private store. |
| 3 | `upload_file(path, private?, payment_mode?)` | Upload a local file. With `private=True`, the returned `address` is the caller-held DataMap. |
| 4 | `download_file(address, dest_path, private?)` | Download to local path — the **daemon** writes the file (daemon and MCP server must share a filesystem). Pass `private=True` if `address` is a caller-held DataMap from a private upload. |
| 5 | `stream_download_file(address, dest_path, private?)` | Like `download_file`, but streams the bytes back to the MCP server process and writes `dest_path` on **this** host with constant memory (suits large objects / no shared filesystem). Returns `bytes_written`. |
| 6 | `get_cost(text?, file_path?, payment_mode?)` | Estimate storage cost — returns `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, `payment_mode` |
| 7 | `check_health()` | Check daemon health and network status |

### Wallet Operations

| # | Tool | Description |
|---|------|-------------|
| 8 | `wallet_address()` | Get wallet public address |
| 9 | `wallet_balance()` | Get wallet token and gas balances |
| 10 | `wallet_approve()` | Approve wallet to spend tokens on payment contracts (one-time) |

### Chunk Operations

| # | Tool | Description |
|---|------|-------------|
| 11 | `chunk_put(data)` | Store a raw chunk (base64 input) |
| 12 | `chunk_get(address)` | Retrieve a chunk (base64 output) |

### External Signer (Two-Phase Upload)

| # | Tool | Description |
|---|------|-------------|
| 13 | `prepare_upload(path, visibility?)` | Prepare a file upload for external signing. Pass `visibility="public"` to bundle the DataMap chunk into the same payment batch (the `data_map_address` on finalize is the shareable retrieval handle). |
| 14 | `prepare_upload_public(path)` | Convenience wrapper for `prepare_upload(path, visibility="public")`. |
| 15 | `prepare_data_upload(text)` | Prepare a data upload for external signing |
| 16 | `finalize_upload(upload_id, tx_hashes)` | Finalize a wave-batch upload. Returns `address`, `chunks_stored`, `data_map`, and (for public uploads) `data_map_address`. A partial store returns a `PARTIAL_UPLOAD` error (see [Partial uploads](#partial-uploads)). |
| 17 | `finalize_merkle_upload(upload_id, winner_pool_hash)` | Finalize a merkle-batch upload. Returns the same fields as `finalize_upload`; same `PARTIAL_UPLOAD` behaviour. |
| 18 | `prepare_chunk_upload(data_base64)` | Prepare a single raw chunk for external-signer publish. Returns either `already_stored=True` (no payment needed) or a wave-batch payment intent. |
| 19 | `finalize_chunk_upload(upload_id, tx_hashes)` | Submit a prepared chunk to the network after external payment. Returns `address`. |

### Payment Modes

The `store_data`, `upload_file`, and `get_cost` tools accept an optional `payment_mode` parameter:

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

### Partial uploads

`finalize_upload` / `finalize_merkle_upload` can fail *after* the payment went through: some chunks store, others miss quorum after the daemon's own retries. The error object then carries the counts and a `retryable` flag so the agent can decide what to do:

```json
{
  "error": "PARTIAL_UPLOAD",
  "message": "Partial upload: 300/312 chunks stored, 12 failed after retries: ...",
  "status_code": 502,
  "chunks_stored": 300,
  "chunks_failed": 12,
  "total_chunks": 312,
  "retryable": true,
  "retention_known": true,
  "network": "local"
}
```

The payment and the stored chunks persist either way.

- **`retryable: true`** — the daemon kept the paid attempt under the same `upload_id` (antd ≥ 0.14.0). Call the **same** finalize tool again with the **same arguments**; it stores the remainder against the same payment — no re-prepare, no second payment. Bound the retries: stop after a few attempts, or when `chunks_failed` stops shrinking. The retained attempt expires with the daemon's pending-upload TTL (one hour).
- **`retention_known: true`, `retryable: false`** — the daemon confirmed it kept nothing (e.g. a merkle finalize with deliberately unpaid batches). Run the prepare step again for the same content; already-stored chunks are skipped, so only the remainder is paid for.
- **`retention_known: false`** — retention is unknown. The daemon may still hold the paid attempt: it records the resume handle before it returns the error. Stop automatic recovery, keep the `upload_id` and the payment details you passed, and reconcile before preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their partial uploads read as unknown.

`retryable: true` always comes with `retention_known: true`.

These fields come from the antd SDK, which reads the daemon's response strictly. A count that is not a non-negative JSON integer (at most 2^64−1) reads as `0`. `retryable` is `true` only when the daemon sent the JSON literal `true`, and `retention_known` is `true` only when `retryable` was a JSON bool. A malformed partial-upload response therefore never shows up as `UNEXPECTED`. It arrives as `PARTIAL_UPLOAD` with the unreadable fields at `0` / `false` (an unreadable `retryable` means retention unknown). If the body is unreadable, or its `code` is not exactly `"PARTIAL_UPLOAD"`, it arrives as a plain `NETWORK_ERROR` without the partial-upload fields.

Full contract: `docs/external-signer-flow.md` §6 in the ant-sdk repo.

## Project Structure

```
antd-mcp/
├── pyproject.toml
└── src/antd_mcp/
    ├── __init__.py
    ├── server.py      # 19 MCP tool definitions
    ├── discover.py    # Daemon port-file discovery
    └── errors.py      # Error formatting
```
