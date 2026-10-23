# antd-py -- Python SDK for Autonomi

Python SDK for the antd daemon. Provides synchronous and asynchronous clients with both REST and gRPC transports.

## Installation

```bash
# REST transport (recommended)
pip install antd[rest]

# gRPC transport
pip install antd[grpc]

# Both transports
pip install antd[all]

# From source (development)
pip install -e ".[all]"
```

## Compatibility

This package talks to a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon; it does not join the network itself. Python 3.10+. Tested against antd 0.12.x; `health()` fields such as `version`/`evm_network` need antd 0.4.0 or newer, and the [pointer](#pointers) methods need antd 0.16.0 or later, the first release with pointers. For a daemon-less client see the `ant-sdk` package (import `ant_ffi`). Not related to the Ant Design UI library.

## Quick Start

```python
from antd import AntdClient

client = AntdClient()  # REST transport, localhost:8082

# Health check
status = client.health()
print(f"{status.network} -- healthy: {status.ok}")

# Store and retrieve data
result = client.data_put_public(b"Hello, Autonomi!")
print(f"Address: {result.address}, chunks: {result.chunks_stored}")

data = client.data_get_public(result.address)
print(data.decode())  # "Hello, Autonomi!"
```

## Transports

```python
from antd import AntdClient, AsyncAntdClient

# REST (default)
client = AntdClient(transport="rest", base_url="http://localhost:8082", timeout=30)

# gRPC (wallet operations and payment_mode are available via REST only)
client = AntdClient(transport="grpc", target="localhost:50051")

# Async REST
aclient = AsyncAntdClient(transport="rest")
status = await aclient.health()
await aclient.close()
```

The gRPC stubs in `src/antd/_proto/` are generated from `antd/proto` and
committed. After changing the protos, regenerate them and commit the result
(CI fails when they drift):

```bash
pip install grpcio-tools==1.80.0   # the version the script pins
python scripts/generate_proto.py
```

## API Reference

### Factory Functions

| Function | Description |
|----------|-------------|
| `AntdClient(transport="rest", **kwargs)` | Create a synchronous client |
| `AsyncAntdClient(transport="rest", **kwargs)` | Create an asynchronous client |

### Client Methods

#### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `health()` | `HealthStatus` | Check daemon health — also surfaces antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |

#### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `data_put_public(data, payment_mode=...)` | `DataPutPublicResult` | Store public data — DataMap is stored on-network |
| `data_get_public(address: str)` | `bytes` | Retrieve public data by address |
| `data_put(data, payment_mode=...)` | `DataPutResult` | Store private (encrypted) data — DataMap returned to caller (NOT stored on-network) |
| `data_get(data_map: str)` | `bytes` | Retrieve private data using a caller-held DataMap |
| `data_cost(data, payment_mode=...)` | `UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

#### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunk_put(data: bytes)` | `PutResult` | Store a raw chunk |
| `chunk_get(address: str)` | `bytes` | Retrieve a chunk |

#### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `file_put(path, payment_mode=...)` | `FilePutResult` | Upload a file privately — DataMap returned to caller (NOT stored on-network) |
| `file_get(data_map, dest_path)` | `None` | Download a private file using a caller-held DataMap |
| `file_put_public(path, payment_mode=...)` | `FilePutPublicResult` | Upload a file publicly — DataMap is stored on-network |
| `file_get_public(address, dest_path)` | `None` | Download a public file by address |
| `file_cost(path, is_public, payment_mode=...)` | `UploadCostEstimate` | Estimate file cost — size, chunks, gas, payment mode |

#### Manifests

A manifest (ADR-0006) describes a set of files as one `.ant` file, or as an `ant://manifest/` link when it is small enough. Each entry has an optional path and size, and either an embedded DataMap (a private file: the manifest is its key) or a public DataMap address. The daemon builds and decodes manifests through ant-core, so the SDK never handles the format. Every method is on all four clients (sync and async, REST and gRPC) with the same signatures, types and errors, and needs antd 0.16.0 or later, the first release with manifests. See `examples/10_manifests.py`.

**Nothing is uploaded or paid for.** Building and decoding only read the network: on build the default embedding policy resolves shrunk DataMaps, and on decode `resolve=True` fetches each entry's DataMap (never its content). A call can therefore time out, and retrying it is safe. Upload the files first (`data_put_public`, `file_put`, ...) and pass their addresses or DataMaps.

The `.ant` bytes are always raw `bytes` in this API: REST carries them as base64 and gRPC as bytes, and the clients convert. Sizes are Python `int`s, and an unset `size` or `exact_size` is `None`, never `0` (0 is an empty file). Over gRPC the manifest calls use a second channel to the same target, with its message limits raised to 256 MiB each way (a manifest can be 64 MiB); every other call keeps gRPC's defaults.

| Method | Returns | Description |
|--------|---------|-------------|
| `build_manifest(entries, *, name=None, torrent_info_hashes=None, embed_roots=True)` | `BuiltManifest` | Build a manifest from `ManifestEntryInput`s, each with exactly one of `data_map` or `address` (both or neither raises `BadRequestError` before sending). `embed_roots=True` (the default) resolves each shrunk DataMap and embeds its root when it is at most 64 KiB, so recipients skip that fetch; `False` embeds DataMaps as given. `link` is `None` when the link would exceed 1,500 bytes |
| `decode_manifest(manifest, resolve=False)` | `DecodedManifest` | Decode `.ant` bytes. With `resolve`, each entry's `exact_size` comes from the network, and a failure lands in that entry's `error` rather than failing the call |
| `decode_manifest_link(link, resolve=False)` | `DecodedManifest` | Decode an `ant://manifest/` link, a file link or a bare 64-hex address (`source="file_link"`: one public entry, no path) |

An invalid entry, such as a bad path (`../x`) or malformed hex, raises `BadRequestError` (HTTP 400 / gRPC `INVALID_ARGUMENT`) with the daemon's message, which names `entries[i]`. One the client refuses before sending (both or neither of `data_map`/`address`, a bad `size`, empty decode input) is the same error with `status_code` 400 and the daemon's wording, such as `2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address`, so one `except` covers both.

```python
from antd import AntdClient, ManifestEntryInput

client = AntdClient()
a = client.data_put_public(b"note one").address   # pays
b = client.data_put_public(b"note two").address   # pays

built = client.build_manifest(                    # free
    [
        ManifestEntryInput(address=a, path="notes/one.txt"),
        ManifestEntryInput(address=b, path="notes/two.txt"),
    ],
    name="example",
)
print(built.link)

decoded = client.decode_manifest_link(built.link, resolve=True)   # free
for e in decoded.entries:
    print(e.effective_name, e.kind, e.exact_size)
```

Run the example with `ANTD_BASE_URL=http://localhost:8082 python examples/10_manifests.py`; it needs a wallet, and pays for its two uploads only.

#### External Signer

Two-phase upload — daemon prepares the payment intent, caller signs + submits the payForQuotes tx, daemon finalizes once the chain confirms. See `examples/07_external_signer.py` + `docs/external-signer-flow.md`. A finalize that stores only some chunks raises `PartialUploadError` — see [Partial uploads](#partial-uploads) for how to finish the upload without paying twice.

| Method | Returns | Description |
|--------|---------|-------------|
| `prepare_upload(path, visibility=None)` | `PrepareUploadResult` | Prepare a file upload for external signing |
| `prepare_upload_public(path)` | `PrepareUploadResult` | Convenience for `prepare_upload(path, visibility="public")` |
| `prepare_data_upload(data, visibility=None)` | `PrepareUploadResult` | Prepare a data upload for external signing |
| `prepare_chunk_upload(data)` | `PrepareChunkResult` | Prepare a single chunk for external-signer publish |
| `finalize_upload(upload_id, tx_hashes)` | `FinalizeUploadResult` | Submit a prepared upload after external payment. `data_map_address` populated when prepare used `visibility="public"`. Raises `PartialUploadError` on a partial store |
| `finalize_merkle_upload(upload_id, winner_pool_hash, store_data_map=False)` | `FinalizeUploadResult` | Submit a prepared merkle-batch upload after selecting the winning pool. Raises `PartialUploadError` on a partial store |
| `finalize_chunk_upload(upload_id, tx_hashes)` | `str` | Submit a prepared chunk after external payment; returns the chunk address |

#### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes; what it points at (a chunk, such as a public data or file address, or another pointer) can be changed by the owner. The daemon holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (files in the format `ant pointer keygen` writes), so every write names the pointer by its address (`owner`), never by a key. Every method is on all four clients (sync and async, REST and gRPC) with the same signatures, types and errors. See `examples/09_pointers.py`.

**Every write pays, and the SDK never retries one.** A create, update or transfer costs about the price of one chunk, and every attempt pays again, so do not retry `pointer_create`, `pointer_update`, `pointer_transfer` or `pointer_finalize` automatically. The one exception is a `pointer_finalize` that raises `CloseGroupShortfallError` with `retryable=True`: the daemon kept the paid state, and repeating the call with the same `upload_id` stores it against the same payment (bound that loop). Reads are free to retry; a read during an update or churn can raise `CloseGroupShortfallError`.

Counters are Python `int`s. The daemon sends them as decimal strings because a final state (a transfer or freeze) sits at `POINTER_FINAL_COUNTER` (2^64−1); a counter that is not a decimal u64 raises `InternalError` instead of reading as 0. Addresses are 64 hex characters; the daemon accepts a `0x` prefix on input but always returns bare lowercase hex, so normalise before comparing.

| Method | Returns | Description |
|--------|---------|-------------|
| `pointer_keys()` | `list[str]` | Addresses of the pointers this daemon holds owner keys for, so can write |
| `pointer_create(owner, target, kind=PointerKind.CHUNK)` | `PointerWriteResult` | Create a pointer, paid by the daemon wallet. `AlreadyExistsError` if it exists, refused before paying |
| `pointer_update(owner, target, kind=PointerKind.CHUNK)` | `PointerWriteResult` | Point a pointer at a new target, paid by the daemon wallet; creates it if missing. `kind=PointerKind.POINTER` makes a forwarding the owner can still change. `PointerFinalError` once transferred or frozen |
| `pointer_transfer(owner, recipient)` | `PointerTransferResult` | Hand a pointer over for good to the recipient's pointer, which must exist: readers of the address are redirected there. Irreversible. Carries the close group's `finality`, or `finality_error` if that check failed |
| `pointer_get(address)` | `PointerRecord` | Read a pointer: `counter`, `target`, `kind`/`kind_tag`, `is_final`, `transferred_to`, the owner's public key. `NotFoundError` if there is none |
| `pointer_resolve(address)` | `PointerTarget` | Follow a chain of pointers (forwardings and transfers) to the target at its end |
| `pointer_finality(address)` | `PointerFinality` | Ask the whole close group where a pointer stands: `status` is a `PointerFinalityStatus` (`OPEN`, `SETTLING`, `UNCONFIRMED`, `FINAL`, `FORKED`, or `UNKNOWN` with the daemon's string in `raw_status`). Check `is_final` before relying on a transfer |
| `pointer_controller(address)` | `PointerController` | Follow transfers to the pointer whose owner now decides |
| `pointer_prepare(owner, op, *, target=None, kind=None, recipient=None, include_signed_quotes=False)` | `PointerPrepareResult` | External signer: the daemon signs `PointerOp.CREATE` / `UPDATE` (pass `target`) or `TRANSFER` (pass `recipient`) and quotes it (wave-batch `payments` for `payForQuotes()`). Needs no daemon wallet. Other writes to the pointer raise `ConflictError` until it is finalized or expires (one hour) |
| `pointer_finalize(upload_id, tx_hashes)` | `PointerFinalizeResult` | External signer: store the prepared write once paid. `CloseGroupShortfallError` with `retryable=True` means repeat the same call |

```python
from antd import AntdClient, PointerFinalityStatus

client = AntdClient()
owner = client.pointer_keys()[0]

v1 = client.data_put_public(b"version 1").address
v2 = client.data_put_public(b"version 2").address

client.pointer_create(owner, v1)          # pays once
client.pointer_update(owner, v2)          # pays once; counter 1
assert client.pointer_resolve(owner).target == v2

f = client.pointer_finality(owner)
print(f.status is PointerFinalityStatus.OPEN, f.counter)
```

## Models

All models are frozen dataclasses (immutable).

| Model | Fields | Description |
|-------|--------|-------------|
| `HealthStatus` | `ok`, `network`, `version`, `evm_network`, `uptime_seconds`, `build_commit`, `payment_token_address`, `payment_vault_address` | Health check result (diagnostic fields require antd ≥ 0.4.0) |
| `PutResult` | `cost`, `address` | Result of `chunk_put` only |
| `DataPutResult` | `data_map`, `chunks_stored`, `payment_mode_used` | Private data put — DataMap returned to caller |
| `DataPutPublicResult` | `address`, `chunks_stored`, `payment_mode_used` | Public data put — DataMap stored on-network |
| `FilePutResult` | `data_map`, `storage_cost_atto`, `gas_cost_wei`, `chunks_stored`, `payment_mode_used` | Private file put — DataMap returned to caller |
| `FilePutPublicResult` | `address`, `storage_cost_atto`, `gas_cost_wei`, `chunks_stored`, `payment_mode_used` | Public file put — DataMap stored on-network |
| `ManifestEntryInput` | `data_map`, `address`, `path`, `size` (keyword-only) | One file for `build_manifest`: exactly one of `data_map` (embedded) or `address` (public) |
| `ManifestEntryInfo` | `effective_name`, `path`, `size`, `kind`, `content_address`, `data_map`, `exact_size`, `error` | What a manifest says about one entry. `kind` is `"embedded"` or `"public"`; `data_map` is set by a decode, for embedded entries; `error` only by a resolving decode |
| `BuiltManifest` | `manifest` (`bytes`), `link`, `entries` | A built manifest: the `.ant` bytes, the link when it fits, the entries sorted by effective name |
| `DecodedManifest` | `source`, `name`, `torrent_info_hash_v1`, `torrent_info_hash_v2`, `entries` | A decoded manifest. `source` is `"manifest"` or `"file_link"` |
| `UploadCostEstimate` | `cost`, `file_size`, `chunk_count`, `estimated_gas_cost_wei`, `payment_mode` | Pre-upload cost breakdown |
| `PointerWriteResult` | `address`, `state_id`, `counter` | State a pointer create/update stored |
| `PointerRecord` | `address`, `owner`, `counter`, `kind`, `kind_tag`, `target`, `state_id`, `is_final`, `transferred_to`; property `target_kind` | A pointer's current state |
| `PointerTarget` | `kind`, `kind_tag`, `target`; property `target_kind` | Where a chain of pointers ends |
| `PointerFinality` | `address`, `group`, `answered`, `status`, `raw_status`, `counter`, `state`, `states`, `majority`, `transferred_to`; property `is_final` | The close group's view of a pointer |
| `PointerFinalState` | `state_id`, `kind`, `kind_tag`, `target`, `holders`, `transferred_to` | One final state in a finality check |
| `PointerController` | `pointer`, `transfers`, `frozen` | Whose pointer decides, after every transfer |
| `PointerTransferResult` | `address`, `state_id`, `finality`, `finality_error` | What a transfer stored |
| `PointerPrepareResult` | `upload_id`, `op`, `address`, `state_id`, `counter`, `payment_type`, `payments`, `total_amount`, `payment_vault_address`, `payment_token_address`, `rpc_url`, `signed_quotes` | A signed pointer write quoted for an external signer |
| `PointerFinalizeResult` | `address`, `state_id`, `counter`, `finality` | What a pointer finalize stored (`finality` for a transfer) |
| `SignedQuoteEntry` | `quote_hash`, `quote`, `commitment_sidecar` | A quote in full signed form (base64), with `include_signed_quotes=True` |

Enums: `PointerKind` (`CHUNK`, `POINTER`), `PointerOp` (`CREATE`, `UPDATE`, `TRANSFER`), `PointerFinalityStatus` (above). Unset values read as `None` on both transports (REST sends `null`, gRPC an empty string or absent message).

## Error Handling

All errors inherit from `AntdError`:

```python
from antd import AntdClient, AntdError, NotFoundError, PaymentError

client = AntdClient()

try:
    data = client.data_get_public("nonexistent_address")
except NotFoundError:
    print("Data not found on the network")
except PaymentError:
    print("Insufficient funds")
except AntdError as e:
    print(f"Error ({e.status_code}): {e}")
```

| Exception | HTTP | gRPC | Description |
|-----------|------|------|-------------|
| `BadRequestError` | 400 | `INVALID_ARGUMENT` | Invalid request parameters |
| `PaymentError` | 402 | `FAILED_PRECONDITION` | Wallet/payment issue |
| `NotFoundError` | 404 | `NOT_FOUND` | Resource not found |
| `AlreadyExistsError` | 409 | `ALREADY_EXISTS` | Resource already exists |
| `ForkError` | 409 | `ABORTED` (non-partial-upload) | Version conflict |
| `TooLargeError` | 413 | `RESOURCE_EXHAUSTED` | Payload too large |
| `InternalError` | 500 | `INTERNAL` | Server error |
| `NetworkError` | 502 | `UNAVAILABLE` | Network unreachable |
| `PartialUploadError` | 502 (`code: "PARTIAL_UPLOAD"`) | `ABORTED` (message starts `Partial upload:`) | Finalize stored some chunks, not all — subclass of `NetworkError`; carries `chunks_stored`, `chunks_failed`, `total_chunks`, `retryable` |
| `PointerFinalError` | 409 (`code: "POINTER_FINAL"`) | `FAILED_PRECONDITION` + `x-antd-error-code: POINTER_FINAL` | The pointer is transferred or frozen; nothing can change it |
| `PointerForkedError` | 409 (`code: "POINTER_FORKED"`) | `FAILED_PRECONDITION` + `x-antd-error-code: POINTER_FORKED` | The owner signed two final states and no majority holds either — subclass of `ForkError` |
| `ConflictError` | 409 (`code: "CONFLICT"`) | `ABORTED` + `x-antd-error-code: CONFLICT` | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state |
| `CloseGroupShortfallError` | 503 (`code: "CLOSE_GROUP_SHORTFALL"`) | `UNAVAILABLE` + `x-antd-error-code: CLOSE_GROUP_SHORTFALL` | Too few of the close group answered or stored; `retryable` is `True` only for a pointer finalize that kept the paid state |

The four pointer-era codes share their status with older errors, so the SDK reads the REST body's `code`, and over gRPC the `x-antd-error-code` trailing metadata, which it trusts only when it agrees with the status code (a `FAILED_PRECONDITION` without the tag is still a `PaymentError`). The daemon tags these on any call, so a chunk or data store whose close group fell short raises `CloseGroupShortfallError` too; daemons before the pointer API sent that as a 500 (`InternalError`).

### Partial uploads

`finalize_upload` / `finalize_merkle_upload` can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. That surfaces as `PartialUploadError` (a `NetworkError` subclass, so existing `except NetworkError` / `except AntdError` blocks still catch it). The on-chain payment persists and the stored chunks stay on the network. `retryable` and `retention_known` say how to finish (`retryable` implies `retention_known`):

- **`retryable`** — the daemon kept the paid attempt (payment proofs + unstored chunks) under the same `upload_id`. Call the **same** finalize method again with the **same arguments** (the same `upload_id` and payment artefacts) to store the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound the loop — a persistent failure raises again on every call, so cap the attempts and treat a `chunks_failed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL (one hour). Sent by antd ≥ 0.14.0.
- **`retention_known and not retryable`** — the daemon confirmed it kept nothing (e.g. a merkle finalize whose signer deliberately left some sub-batches unpaid). Re-prepare the same content: already-stored chunks are skipped, so the retry pays only for the remainder.
- **`not retention_known`** — retention is unknown. The daemon may still hold the paid attempt: it records the resume handle before it returns the error. Stop automatic recovery, keep the `upload_id` and the original payment artefacts (`tx_hashes` / `winner_pool_hash`), and reconcile before re-preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their REST partial uploads read as unknown.

Over gRPC a partial upload used to raise `ForkError`; it now raises `PartialUploadError`. The daemon sends `ABORTED` only for PARTIAL_UPLOAD, so code that caught `ForkError` around a finalize should catch `PartialUploadError`.

Over REST the counts and flags come from the structured error body. Over gRPC a partial upload is an `ABORTED` status whose message **starts with** the daemon's fixed `Partial upload:` prefix, and the counts and flags are parsed from that message. An `ABORTED` that does not start with the prefix (including one that only embeds it, e.g. `upstream error: Partial upload: ...`) is not a partial upload and raises `ForkError` as before. Full contract: `docs/external-signer-flow.md` §6.

Malformed input is read conservatively and never escapes as a raw `ValueError` / `TypeError` / `OverflowError`:

- **REST.** Each count must be a JSON integer from 0 to 2^64−1. A quoted number (`"1"`), bool, float (including `Infinity`), array, object, negative or larger value reads as `0`. `retryable` is `True` only for the JSON literal `true`; `"true"`, `1` and everything else read as `False`. `retention_known` is `True` only when `retryable` is a JSON bool (`true` or `false`); absent, `null` or any other type reads as unknown. Only a string `code` of exactly `"PARTIAL_UPLOAD"` selects `PartialUploadError`. A body that is not a JSON object, or has any other `code`, keeps the plain 502 → `NetworkError` mapping, as does a body Python cannot decode at all. A non-string `error` makes the raw response body the message.
- **gRPC.** The message reads `Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)`. `retention_known` is `True` only when the message starts with that counts pattern, all three counts fit in a u64, and it ends with one of the daemon's two hints. A `(paid attempt retained...)` hint sets `retryable`. A `(stored chunks persist; re-prepare the same content...)` hint means the daemon confirmed nothing was retained; daemons older than 0.14.0 write only this one. A pattern miss or an out-of-range count reads the counts as `0` with both flags `False`. Readable counts with a missing, truncated or unrecognised hint keep the counts, but both flags stay `False`: retention is unknown, not "nothing retained".

```python
import time
from antd import PartialUploadError

def finalize_with_retry(client, upload_id, tx_hashes, max_attempts=5):
    last_failed = None
    for attempt in range(1, max_attempts + 1):
        try:
            return client.finalize_upload(upload_id, tx_hashes)  # every chunk stored
        except PartialUploadError as e:
            if not e.retryable:
                # retention_known: the daemon kept nothing, so re-prepare.
                # Otherwise retention is unknown: stop, keep upload_id and
                # tx_hashes, and reconcile. Never pay again on this alone.
                raise
            stuck = last_failed is not None and e.chunks_failed >= last_failed
            if attempt == max_attempts or stuck:
                raise  # paid attempt still retained under upload_id: retry the same finalize later
            last_failed = e.chunks_failed
            time.sleep(2 * attempt)
```

## Examples

Run examples from the `examples/` directory:

```bash
# Requires antd daemon running on local testnet
python examples/01_connect.py      # Health check
python examples/02_data.py         # Store/retrieve data
python examples/03_chunks.py       # Raw chunks
python examples/04_files.py        # File upload/download
python examples/06_private_data.py # Private data with data maps
python examples/07_external_signer.py # External-signer file + chunk upload
python examples/08_grpc.py          # gRPC transport (requires antd[grpc])
ANTD_POINTER_OWNER=<address> python examples/09_pointers.py  # Create, update, resolve a pointer (pays)
```

The pointer example needs a daemon started with `--pointer-keys` and a wallet; `ANTD_POINTER_OWNER` is one of its `pointer_keys()`. Set `ANTD_BASE_URL` to reach a daemon that is not on `http://localhost:8082`.

Or use the dev CLI:

```bash
ant dev example data
ant dev example all
```
