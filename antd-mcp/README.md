# antd-mcp — MCP Server for Autonomi

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that exposes the Autonomi network as 31 tools for AI agents (19 storage tools, 10 pointer tools, and the 2 manifest tools when the installed SDK supports them). Works with Claude Desktop, Claude Code, and any MCP-compatible client.

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
| 1 | `store_data(text, private?, payment_mode?)` | Store text on the network. With `private=True`, the returned `address` is the caller-held DataMap (not stored on-network — keep it safe). Also returns `sha256`, the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `null` on older daemons. |
| 2 | `retrieve_data(address, private?)` | Retrieve text by address. Pass `private=True` if `address` is a caller-held DataMap from a private store. |
| 3 | `upload_file(path, private?, payment_mode?)` | Upload a local file. With `private=True`, the returned `address` is the caller-held DataMap. Also returns `sha256`, the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `null` on older daemons. |
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
| 16 | `finalize_upload(upload_id, tx_hashes)` | Finalize a wave-batch upload. Returns `address`, `chunks_stored`, `data_map`, and (for public uploads) `data_map_address`, plus `sha256`, the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `null` on older daemons. A partial store returns a `PARTIAL_UPLOAD` error (see [Partial uploads](#partial-uploads)). |
| 17 | `finalize_merkle_upload(upload_id, winner_pool_hash)` | Finalize a merkle-batch upload. Returns the same fields as `finalize_upload` (including `sha256`); same `PARTIAL_UPLOAD` behaviour. |
| 18 | `prepare_chunk_upload(data_base64)` | Prepare a single raw chunk for external-signer publish. Returns either `already_stored=True` (no payment needed) or a wave-batch payment intent. |
| 19 | `finalize_chunk_upload(upload_id, tx_hashes)` | Submit a prepared chunk to the network after external payment. Returns `address`. |

### Pointers

A pointer is a small, owner-signed, mutable reference: its address never changes, and its owner can move its target (a chunk, such as a public `store_data` / `upload_file` address, or another pointer). The daemon holds the owner keys (`antd --pointer-keys`), so every write names the pointer by its address (`owner`). See [Pointer payments, counters and errors](#pointer-payments-counters-and-errors) before using the write tools.

| # | Tool | Description |
|---|------|-------------|
| 20 | `pointer_keys()` | List the pointer addresses this daemon holds owner keys for, so can write. Free. |
| 21 | `pointer_get(address, include_owner_key?)` | Read a pointer: `counter` (decimal string), `target`, `kind` / `kind_tag`, `state_id`, `is_final`, `transferred_to`. The owner's ML-DSA-65 public key (~3,900 hex chars) only with `include_owner_key=True`. Free. |
| 22 | `pointer_resolve(address)` | Follow forwardings and transfers to the target at the end of the chain: `target`, `kind`, `kind_tag`. Free. |
| 23 | `pointer_finality(address)` | Ask the whole close group where a pointer stands: `status` is `open`, `settling`, `unconfirmed`, `final`, `forked`, or `unknown` (daemon string in `raw_status`). Only `final` means a transfer is beyond dispute. Free. |
| 24 | `pointer_controller(address)` | Follow transfers to the pointer whose owner now decides: `pointer`, `transfers`, `frozen`. Free. |
| 25 | `pointer_create(owner, target, kind?)` | Create a pointer (`kind` `"chunk"`, the default, or `"pointer"`). **Pays** from the daemon wallet. `ALREADY_EXISTS` if it exists, refused before paying. |
| 26 | `pointer_update(owner, target, kind?)` | Point a pointer at a new target; creates it if missing. **Pays** from the daemon wallet. `POINTER_FINAL` once transferred or frozen, usually refused before paying. |
| 27 | `pointer_transfer(owner, recipient, confirm_irreversible?)` | **Irreversible.** Hand the pointer over to the recipient's pointer for good: it becomes final and its readers are sent on to the recipient. **Pays** from the daemon wallet. Refuses with `CONFIRMATION_REQUIRED`, sending nothing, unless `confirm_irreversible=true`. Returns the close group's `finality`. |
| 28 | `pointer_prepare(owner, op, target?, kind?, recipient?)` | External signer: the daemon signs `op` (`"create"` / `"update"` with `target`, or `"transfer"` with `recipient`) and quotes it. Returns `upload_id`, `counter` and wave-batch `payments`. Pays nothing itself; other writes to the pointer get `CONFLICT` until it is finalized or expires (one hour). |
| 29 | `pointer_finalize(upload_id, tx_hashes)` | External signer: store the prepared write after `payForQuotes()`. Returns `counter`, and `finality` for a transfer. |

### Manifests

A manifest (a `.ant` file, or an `ant://manifest/` link to one) bundles files that are already on the network, each with an optional relative path. The `link` is what you share. Both tools are **free**: nothing is uploaded and nothing is paid, so neither asks for confirmation. They are annotated read-only. Upload the files first (`store_data`, `upload_file`) and pass the `address` (public) or `data_map` (private, embedded in the manifest) they returned.

| # | Tool | Description |
|---|------|-------------|
| 30 | `build_manifest(entries, name?, torrent_info_hashes?, embed_roots?)` | Each entry is `{path?, size?, sha256?, data_map? \| address?}`: give exactly one of `data_map` or `address`. `sha256` is the file's plaintext SHA-256 (hex) to record; requires antd 0.17.0 or later; it is passed through as given and the daemon rejects a malformed one with `BAD_REQUEST`. Returns `manifest_base64` (the `.ant` bytes), `link` (null when the manifest exceeds 1,500 bytes; share the file instead) and `entries` (each with `sha256`, the hash the manifest records or `null`; requires antd 0.17.0 or later). `embed_roots` defaults to true. A bad entry returns `BAD_REQUEST` with a message naming `entries[i]`. |
| 31 | `decode_manifest(manifest_base64? \| link?, resolve?)` | Give exactly one of the base64 `.ant` bytes or a `link` (manifest link, file link or bare address). Returns `source` (`manifest` or `file_link`), `name`, the torrent hashes and `entries` (each with `sha256`, the hash the manifest records or `null`; requires antd 0.17.0 or later). With `resolve=true` it also reads each entry's root from the network to fill in `exact_size`; one entry's failure is in its `error`, not a failed call. |

Unset sizes and unset `sha256` values are `null`, never 0 or an empty string. These tools need an antd daemon with the manifest API (antd 0.16.0 or later) and an [`antd`](https://pypi.org/project/antd/) Python SDK that has `build_manifest`. With an older SDK the server still starts and serves its other tools; it just does not register the manifest tools.

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

The `sha256` fields on upload and manifest results need both an antd daemon 0.17.0 or later and an [`antd`](https://pypi.org/project/antd/) Python SDK 0.4.0 or later. With an older daemon or SDK they are `null`.

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

### Pointer payments, counters and errors

The pointer tools need an antd daemon with the pointer API and an [`antd`](https://pypi.org/project/antd/) Python SDK 0.3.0 or later. With an older SDK the server still starts and serves the other 19 tools; it just does not register the pointer tools.

**Every write pays, and no tool retries.** `pointer_create`, `pointer_update` and `pointer_transfer` each pay from the daemon wallet, about the price of one chunk, with the same posture as `store_data` / `upload_file` / `chunk_put`: no confirmation step and no automatic retry. Every repeat pays again, so check the pointer (`pointer_get`) before repeating a failed write. The reads are free.

**Transfers are irreversible.** A transfer makes the pointer final forever: nobody, its owner included, can update or transfer it again, and its readers are sent on to the recipient's pointer. On top of the paid-tool posture, `pointer_transfer` refuses to run unless `confirm_irreversible` is `true`. Without it the tool sends and pays nothing and returns:

```json
{
  "error": "CONFIRMATION_REQUIRED",
  "message": "pointer_transfer would hand the pointer <owner> over to <recipient> forever: ... Nothing was sent or paid. Confirm with the user, then call again with confirm_irreversible=true.",
  "network": "local"
}
```

The tool is also annotated `destructiveHint: true`, `idempotentHint: false` for clients that prompt on those hints.

**Counters are decimal strings**, never JSON numbers. A final pointer (transferred or frozen) sits at counter `"18446744073709551615"` (2^64−1), which JSON clients that read numbers as doubles, and LLMs, round. Compare counters as strings of digits or as big integers. An unset counter (finality other than `open`) is `null`.

**Errors.** Four pointer-era codes carry a `hint` saying what to do next:

| `error` | HTTP | Meaning |
|---------|------|---------|
| `POINTER_FINAL` | 409 | The pointer is transferred or frozen; nothing can change it. Usually refused before paying, but a write already paid for when the network refused it keeps that payment. Do not retry. |
| `POINTER_FORKED` | 409 | The owner signed two different final states and no majority holds either. Do not retry. |
| `CONFLICT` | 409 | A prepared write to the pointer awaits payment (refused before paying), or an update lost to a newer state while in flight (possibly after paying). The `hint` says which; read the pointer before paying for another write. |
| `CLOSE_GROUP_SHORTFALL` | 503 | Too few of the close group answered or stored. Carries `retryable`. |

`CLOSE_GROUP_SHORTFALL` with `retryable: true` comes only from `pointer_finalize`. It means **retry the finalize, the payment was kept**: call `pointer_finalize` again with the same `upload_id` and the daemon stores the paid state against the same payment, with no second payment. Bound the retries; the kept attempt expires after one hour.

```json
{
  "error": "CLOSE_GROUP_SHORTFALL",
  "message": "Close group shortfall: ... (paid attempt retained: call finalize again with the same upload_id ...)",
  "status_code": 503,
  "retryable": true,
  "hint": "Retry the finalize, the payment was kept: call pointer_finalize again with the same upload_id ...",
  "network": "local"
}
```

With `retryable: false`, a read is free to retry later, but do not repeat a paid write automatically: it may already have been paid for. A create of an existing pointer stays `ALREADY_EXISTS`.

## Project Structure

```
antd-mcp/
├── pyproject.toml
└── src/antd_mcp/
    ├── __init__.py
    ├── server.py      # 29 MCP tool definitions
    ├── discover.py    # Daemon port-file discovery
    └── errors.py      # Error formatting
```
