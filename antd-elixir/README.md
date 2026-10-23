# antd-elixir

Elixir SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

Add `antd` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:antd, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Create a client
client = Antd.Client.new()

# Check daemon health
{:ok, health} = Antd.Client.health(client)
IO.puts("OK: #{health.ok}, Network: #{health.network}")

# Store public data (public methods keep the `_public` suffix)
{:ok, result} = Antd.Client.data_put_public(client, "Hello, Autonomi!")
IO.puts("Stored at #{result.address} (chunks: #{result.chunks_stored})")

# Retrieve data
{:ok, data} = Antd.Client.data_get_public(client, result.address)
IO.puts("Retrieved: #{data}")
```

Pipe operator style with bang variants:

```elixir
client = Antd.Client.new()

"Hello, Autonomi!"
|> then(&Antd.Client.data_put_public!(client, &1))
|> Map.get(:address)
|> then(&Antd.Client.data_get_public!(client, &1))
|> IO.puts()
```

## Naming convention (private vs. public)

The SDK follows the antd daemon's `put` / `get` convention:

- **Private = unqualified verb.** `data_put`, `data_get`, `file_put`, `file_get`
  upload privately. The returned DataMap is the caller-held handle and is
  NOT stored on-network.
- **Public = `_public` suffix.** `data_put_public`, `data_get_public`,
  `file_put_public`, `file_get_public` store the DataMap on-network as an
  extra chunk; the returned `address` is the shareable retrieval handle.
- **Chunks** (`chunk_put` / `chunk_get`) have no public/private split.

## Payment mode

Put and cost methods accept an optional `:payment_mode` keyword:

```elixir
{:ok, _} = Antd.Client.data_put(client, payload, payment_mode: :merkle)
{:ok, _} = Antd.Client.file_put_public(client, path, payment_mode: :single)
```

`Antd.PaymentMode` defines three atoms:

| Atom      | Wire string | Meaning                                                  |
|-----------|-------------|----------------------------------------------------------|
| `:auto`   | `"auto"`    | Server picks (merkle for 64+ chunks, single otherwise).  |
| `:merkle` | `"merkle"`  | Force merkle-batch (saves gas, min 2 chunks).            |
| `:single` | `"single"`  | Force per-chunk payments (works for any chunk count).    |

`:auto` is the default. The empty wire value is treated as `"auto"` by the
daemon so older clients omitting the field stay compatible.

`get` methods (data_get / data_get_public / file_get / file_get_public)
do NOT take `:payment_mode`.

## gRPC Transport

The SDK includes an `Antd.GrpcClient` module that provides the same
functions as the REST `Antd.Client`, but communicates over gRPC.

### Setup

The `grpc` and `protobuf` hex packages are already listed in `mix.exs`. Fetch
them with:

```bash
mix deps.get
```

The Elixir protobuf/gRPC stubs in `lib/antd/v1/` are generated from the proto
definitions and committed. After changing the protos, regenerate them and
commit the result (CI fails when they drift):

```bash
mix escript.install hex protobuf 0.16.0   # protoc-gen-elixir, as the script pins
./scripts/generate-protos.sh              # needs protoc and ~/.mix/escripts on PATH
```

### Usage

```elixir
# Connect to the daemon
{:ok, client} = Antd.GrpcClient.new()

# Or custom target:
# {:ok, client} = Antd.GrpcClient.new("my-host:50051")

# Check health
{:ok, health} = Antd.GrpcClient.health(client)
IO.puts("OK: #{health.ok}, Network: #{health.network}")

# Store data
{:ok, result} = Antd.GrpcClient.data_put_public(client, "Hello via gRPC!")
IO.puts("Stored at #{result.address}")

# Retrieve data
{:ok, data} = Antd.GrpcClient.data_get_public(client, result.address)
IO.puts("Retrieved: #{data}")
```

All functions return `{:ok, result}` or `{:error, exception}` tuples, just like
the REST client. Bang variants (e.g. `health!/1`) are also available. gRPC
status codes are translated to the same `Antd.*Error` hierarchy.

The pointer functions also read the daemon's `x-antd-error-code` metadata,
which takes precedence when it agrees with the status code:
`FAILED_PRECONDITION` + `POINTER_FINAL` → `Antd.PointerFinalError`,
`FAILED_PRECONDITION` + `POINTER_FORKED` → `Antd.ForkError`, `ABORTED` +
`CONFLICT` → `Antd.ConflictError`, and `UNAVAILABLE` + `CLOSE_GROUP_SHORTFALL`
→ `Antd.CloseGroupShortfallError` (`retryable` when the message closes with
the `(paid attempt retained...)` hint). Without the tag a `FAILED_PRECONDITION`
is still an `Antd.PaymentError`. grpc-elixir's default adapter drops the
metadata of a failed call, so `Antd.GrpcClient.new/1` connects through
`Antd.GrpcAdapter`, which is that adapter plus the failed call's metadata for
callers that pass `return_headers: true`; every other call behaves as before.
Each pointer function takes a `:timeout` option in milliseconds (default 5
minutes, since a write quotes, pays and stores before it answers).

> **Note:** The gRPC client covers wallet operations (address, balance, approve)
> and the external-signer two-phase upload, like REST.

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```elixir
# Default: http://localhost:8082, 5 minute timeout
client = Antd.Client.new()

# Custom URL
client = Antd.Client.new("http://custom-host:9090")

# Custom timeout (in milliseconds)
client = Antd.Client.new("http://localhost:8082", timeout: 30_000)
```

## API Reference

All functions take a `%Antd.Client{}` as the first argument. Each returns `{:ok, result}` or `{:error, exception}`. Bang variants (e.g. `health!/1`) raise on error.

### Health

| Function | Description |
|----------|-------------|
| `health(client)` | Check daemon status |

### Data

| Function | Description |
|----------|-------------|
| `data_put_public(client, data, opts \\ [])` | Store public data — returns `Antd.DataPutPublicResult` (DataMap stored on-network). `opts`: `payment_mode: :auto | :merkle | :single`. The result's `sha256` is the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `nil` on older daemons. |
| `data_get_public(client, address)` | Retrieve public data by address |
| `data_stream_public(client, address)` | Stream public data by address with constant memory — returns `{:ok, Enumerable}` of binary chunks |
| `data_put(client, data, opts \\ [])` | Store encrypted private data — returns `Antd.DataPutResult` (DataMap returned to caller). `opts`: `payment_mode:`. The result's `sha256` is the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `nil` on older daemons. |
| `data_get(client, data_map)` | Retrieve private data using a caller-held DataMap |
| `data_stream(client, data_map)` | Stream private data for a caller-held DataMap with constant memory — returns `{:ok, Enumerable}` of binary chunks |
| `data_cost(client, data, opts \\ [])` | Estimate storage cost — returns `Antd.UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks

| Function | Description |
|----------|-------------|
| `chunk_put(client, data)` | Store a raw chunk |
| `chunk_get(client, address)` | Retrieve a chunk |

### Files

| Function | Description |
|----------|-------------|
| `file_put(client, path, opts \\ [])` | Upload a file privately — returns `Antd.FilePutResult` (DataMap returned to caller). `opts`: `payment_mode:`. The result's `sha256` is the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `nil` on older daemons. |
| `file_get(client, data_map, dest_path)` | Download a private file using a caller-held DataMap |
| `file_put_public(client, path, opts \\ [])` | Upload a file publicly — returns `Antd.FilePutPublicResult` (DataMap stored on-network). `opts`: `payment_mode:`. The result's `sha256` is the plaintext's SHA-256 (hex); requires antd 0.17.0 or later, `nil` on older daemons. |
| `file_get_public(client, address, dest_path)` | Download a public file by address |
| `file_cost(client, path, is_public, opts \\ [])` | Estimate upload cost — returns `Antd.UploadCostEstimate` with size, chunks, gas, payment mode |

The same `sha256` field is on the `Antd.FinalizeUploadResult` that `finalize_upload` and
`finalize_merkle_upload` return: the plaintext's SHA-256 (hex); requires antd 0.17.0 or
later, `nil` on older daemons.

### Pointers

A pointer is a small, owner-signed, mutable reference (needs antd 0.16.0 or
later, the first release with pointers). Its address is derived from its
owner's key and never changes. What it points at (a chunk, such as a public
file's or public data's address, or another pointer) can be changed by the
owner, and the owner can hand the pointer over to another pointer for good.
The daemon holds the owner keys, loaded at startup with
`antd --pointer-keys <file-or-dir>` (files in the format `ant pointer keygen`
writes), so every write names the pointer by its address (`owner`), never by
a key.

**Every write pays** (about the price of one chunk), and every attempt pays
again. The SDK never retries `pointer_create`, `pointer_update`,
`pointer_transfer` or `pointer_finalize`, and you should not retry them
automatically either. Reads are free to retry: a read during an update in
flight or churn can fail with `Antd.CloseGroupShortfallError`.

Counters are integers, parsed strictly from the daemon's decimal strings (a
malformed counter is an `Antd.AntdError`, never a zero); a final state sits at
`Antd.PointerRecord.final_counter()`, 2^64 − 1. Unset values (`counter`,
`state`, `majority`, `transferred_to`) are `nil` on both transports. The
daemon accepts addresses with a `0x` prefix but always returns bare hex, so
normalise before comparing.

| Function | Description |
|----------|-------------|
| `pointer_keys(client)` | Addresses of the pointers this daemon holds keys for, so can write |
| `pointer_create(client, owner, target, opts \\ [])` | Create a pointer, paid by the daemon wallet — returns `Antd.PointerWriteResult` (`address`, `state_id`, `counter`). `Antd.AlreadyExistsError` if it exists, refused before paying. `opts`: `kind: :chunk | :pointer` (default `:chunk`) |
| `pointer_update(client, owner, target, opts \\ [])` | Point a pointer at a new target, paid by the daemon wallet; creates it if needed. `Antd.PointerFinalError` once transferred or frozen. `opts`: `kind:` |
| `pointer_transfer(client, owner, recipient)` | Hand a pointer over for good to the recipient's pointer, which must exist. Irreversible. Returns `Antd.PointerTransferResult` with the close group's `finality` (or `finality_error`) |
| `pointer_get(client, address)` | Read a pointer — returns `Antd.PointerRecord` (`counter`, `target`, `kind`/`kind_tag`, `is_final`, `transferred_to`, the owner's public key). `Antd.NotFoundError` if there is none |
| `pointer_resolve(client, address)` | Follow a chain of pointers to its target — returns `Antd.PointerTarget` |
| `pointer_finality(client, address)` | Ask the whole close group where a pointer stands — returns `Antd.PointerFinality`; `status` is `:open`, `:settling`, `:unconfirmed`, `:final`, `:forked` or `{:unknown, status}`. Only `:final` (`Antd.PointerFinality.final?/1`) means a transfer is beyond dispute |
| `pointer_controller(client, address)` | Follow transfers to the pointer whose owner now decides — returns `Antd.PointerController` |
| `pointer_prepare(client, owner, op, opts \\ [])` | External signer: the daemon signs `op` (`{:create, target}`, `{:update, target}`, either with a kind as a third element, or `{:transfer, recipient}`) and quotes it — returns `Antd.PointerPrepareResult` (wave-batch `payments` for `payForQuotes()`). Needs no daemon wallet. Other writes to the pointer return `Antd.ConflictError` until it is finalized or expires. `opts`: `include_signed_quotes: true` |
| `pointer_finalize(client, upload_id, tx_hashes)` | External signer: store the prepared write once paid — returns `Antd.PointerFinalizeResult`. A write that falls short after payment returns `Antd.CloseGroupShortfallError` with `retryable: true`: repeat the same call (bounded) to store it against the same payment |

`Antd.GrpcClient` has the same functions, each with an extra `opts` keyword
(`:timeout`, plus `:kind` / `:include_signed_quotes` where the REST function
takes them). See [`examples/08_pointers.exs`](examples/08_pointers.exs).

```elixir
{:ok, put} = Antd.Client.data_put_public(client, "version 1")
{:ok, _} = Antd.Client.pointer_create(client, owner, put.address)

case Antd.Client.pointer_update(client, owner, new_address) do
  {:ok, write} -> IO.puts("now at counter #{write.counter}")
  {:error, %Antd.PointerFinalError{}} -> IO.puts("handed over or frozen; nothing can change it")
  {:error, error} -> IO.puts("not retried (it may have paid): #{Exception.message(error)}")
end
```

## Error Handling

All functions return `{:ok, result}` or `{:error, exception}`. Use pattern matching:

```elixir
case Antd.Client.data_get_public(client, address) do
  {:ok, data} ->
    IO.puts("Got data: #{data}")

  {:error, %Antd.NotFoundError{}} ->
    IO.puts("Data not found on network")

  {:error, %Antd.PaymentError{}} ->
    IO.puts("Insufficient funds")

  {:error, error} ->
    IO.puts("Error: #{Exception.message(error)}")
end
```

Bang variants raise exceptions directly:

```elixir
try do
  data = Antd.Client.data_get_public!(client, address)
  IO.puts("Got: #{data}")
rescue
  e in Antd.NotFoundError ->
    IO.puts("Not found: #{e.message}")
end
```

| Error Module | HTTP Status | When |
|-------------|-------------|------|
| `Antd.BadRequestError` | 400 | Invalid parameters |
| `Antd.PaymentError` | 402 | Insufficient funds |
| `Antd.NotFoundError` | 404 | Resource not found |
| `Antd.AlreadyExistsError` | 409 | Resource exists |
| `Antd.ForkError` | 409 (`code: "POINTER_FORKED"`; gRPC `FAILED_PRECONDITION`) | Version conflict: a pointer's owner signed two final states and no majority holds either |
| `Antd.PointerFinalError` | 409 (`code: "POINTER_FINAL"`; gRPC `FAILED_PRECONDITION`) | The pointer is transferred or frozen; nothing can change it |
| `Antd.ConflictError` | 409 (`code: "CONFLICT"`; gRPC `ABORTED`) | A pointer write while a prepared write to it awaits payment (refused before paying), or an update that lost to a newer state (possibly after paying) |
| `Antd.TooLargeError` | 413 | Payload too large |
| `Antd.InternalError` | 500 | Server error |
| `Antd.NetworkError` | 502 | Network unreachable |
| `Antd.ServiceUnavailableError` | 503 | Service unavailable, e.g. wallet not configured |
| `Antd.CloseGroupShortfallError` | 503 (`code: "CLOSE_GROUP_SHORTFALL"`; gRPC `UNAVAILABLE`) | Too few of the close group answered or stored. Reads may retry; `retryable` is `true` only for a pointer finalize that kept the paid state |
| `Antd.PartialUploadError` | 502 (gRPC `ABORTED`) | An upload stored only part of its chunks (`code: "PARTIAL_UPLOAD"`) — carries `chunks_stored`, `chunks_failed`, `total_chunks`, `retryable`, `retention_known`. Not a `NetworkError` / `AntdError`: see [Migrating error handlers](#migrating-error-handlers-partial-uploads) |

### Partial uploads

`finalize_upload/3` and `finalize_merkle_upload/4` (REST and gRPC) can fail
*after* the wallet has paid: some chunks store, others miss quorum after the
daemon's own retries. That comes back as `{:error, %Antd.PartialUploadError{}}`
with the counts and two flags, `retryable` and `retention_known` (`retryable`
implies `retention_known`). Daemon-wallet uploads (`data_put`, `file_put` and
their `_public` variants) can return the same error. The on-chain payment
persists and the stored chunks stay on the network. Recovery has three cases:

- **`retryable: true`** (antd ≥ 0.14.0) — the daemon kept the paid attempt
  under the same `upload_id`. Call the **same** finalize function again with
  the same `upload_id` and payment arguments to store the remainder against
  the same payment — no re-prepare, no second signature, no double payment.
  Bound that loop: a persistent failure returns this error on every call, so
  cap the attempts and treat a `chunks_failed` that stops shrinking as stuck.
- **`retention_known: true, retryable: false`** — the daemon confirmed it kept
  nothing (a daemon-wallet upload, or a merkle finalize with deliberately
  unpaid batches). Re-prepare the same content: already-stored chunks are
  skipped, so the retry pays only for the remainder.
- **`retention_known: false`** — retention is **unknown**. The daemon may
  still hold the paid attempt (it records the resume handle before it returns
  the error). Stop automatic recovery, keep the `upload_id` and the original
  payment arguments (`tx_hashes` / `winner_pool_hash`), and reconcile before
  re-preparing or paying again. Never pay again on this signal alone. Daemons
  older than 0.14.0 never send `retryable`, so their REST partial uploads read
  as unknown.

Over REST the counts come from the structured error body, and
`retention_known` is `true` only when the body's `retryable` is a JSON boolean
(missing, `null` or any other type reads as unknown). Over gRPC (status
`ABORTED` whose message starts with `Partial upload:` — any other `ABORTED`,
including one that only quotes that phrase further into its message, stays a
plain `Antd.AntdError`) they are parsed from the status message,
`Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)`.
`retention_known` is `true` only when the message starts with those counts,
all three parse (each within the daemon's `u64` range), and the message ends
with one of the daemon's two hints. A `(paid attempt retained...)` hint sets
`retryable`. A `(stored chunks persist; re-prepare the same content...)` hint
means the daemon confirmed nothing was retained; daemons older than 0.14.0
write only this one. A message whose counts do not parse reads as zero counts
with retention unknown. Readable counts with a missing, truncated or
unrecognised hint keep the counts, but both flags stay `false`: retention is
unknown (stop and reconcile), not "nothing retained". See
`finalize_with_retry/3` in [`examples/07_external_signer.exs`](examples/07_external_signer.exs)
and [`docs/external-signer-flow.md`](../docs/external-signer-flow.md) §6
("Retry a partial store — same `upload_id`, same payment").

```elixir
case Antd.Client.finalize_upload(client, upload_id, tx_hashes) do
  {:ok, result} ->
    result

  {:error, %Antd.PartialUploadError{retryable: true} = e} ->
    # paid attempt retained: the same call again stores the remainder (bounded)
    IO.puts("#{e.chunks_stored}/#{e.total_chunks} stored, #{e.chunks_failed} to retry")

  {:error, %Antd.PartialUploadError{retention_known: true}} ->
    # the daemon confirmed nothing was retained: re-prepare the same content
    # (already-stored chunks are skipped)
    :re_prepare

  {:error, %Antd.PartialUploadError{retention_known: false} = e} ->
    # retention unknown: the daemon may still hold the paid attempt. Stop,
    # keep upload_id and tx_hashes, and reconcile before re-preparing or paying.
    {:reconcile, upload_id, tx_hashes, e}
end
```

### Migrating error handlers (partial uploads)

This is an intentional error-contract change. A post-payment partial store
used to come back as `%Antd.NetworkError{}` over REST (HTTP 502) and as
`%Antd.AntdError{status_code: 10}` over gRPC (`ABORTED`). It now returns, and
the bang variants raise, `%Antd.PartialUploadError{}` on both transports. That
covers the external-signer finalize functions and every other call, ordinary
daemon-wallet uploads included, because all calls share one error mapping.
`Antd.PartialUploadError` is a separate exception module, not a subtype of
either (Elixir exceptions have no inheritance), so a clause or `rescue` that
names only `Antd.NetworkError` or `Antd.AntdError` no longer catches a partial
store. Other 502s and other `ABORTED` statuses map as before, and a catch-all
`{:error, error}` clause or a bare `rescue e ->` still catches everything.

Tuple matching — add a `PartialUploadError` clause ahead of the old one:

```elixir
# Before: a partial store reached the NetworkError clause
case Antd.Client.data_put_public(client, data) do
  {:ok, result} -> result
  {:error, %Antd.NetworkError{} = e} -> handle_network_error(e)
end

# After
case Antd.Client.data_put_public(client, data) do
  {:ok, result} -> result
  {:error, %Antd.PartialUploadError{} = e} -> handle_partial_upload(e)
  {:error, %Antd.NetworkError{} = e} -> handle_network_error(e)
end
```

Bang functions — rescue both modules:

```elixir
# Before: a partial store was rescued here
try do
  Antd.Client.finalize_upload!(client, upload_id, tx_hashes)
rescue
  e in Antd.NetworkError -> handle_network_error(e)
end

# After
try do
  Antd.Client.finalize_upload!(client, upload_id, tx_hashes)
rescue
  e in [Antd.PartialUploadError, Antd.NetworkError] -> handle_error(e)
end
```

gRPC — the same applies to handlers that caught the `ABORTED` status as
`Antd.AntdError`:

```elixir
case Antd.GrpcClient.finalize_upload(grpc, upload_id, tx_hashes) do
  {:ok, result} -> result
  {:error, %Antd.PartialUploadError{} = e} -> handle_partial_upload(e)
  {:error, %Antd.AntdError{} = e} -> handle_other(e)
end

try do
  Antd.GrpcClient.finalize_upload!(grpc, upload_id, tx_hashes)
rescue
  e in [Antd.PartialUploadError, Antd.AntdError] -> handle_error(e)
end
```

## Manifests

A manifest (ADR-0006) is one `.ant` file, or an `ant://manifest/` link, that
describes a set of files: each entry has an optional path and size and either
an embedded DataMap (the key to a private upload) or a public DataMap address.
The daemon builds and decodes manifests through ant-core, so the SDK never
re-implements the format. Needs antd 0.16.0 or later.

**Nothing is uploaded or paid for.** Building and decoding read the network
only to resolve DataMaps (the embedding policy on build, `resolve: true` on
decode), so a call can time out, and retrying it is safe. Upload the files
first (`data_put_public`, `file_put`, ...) and build the manifest from the
addresses and DataMaps they return.

| Function | Description |
|----------|-------------|
| `build_manifest(client, entries, opts \\ [])` | Build from a list of `Antd.ManifestEntryInput` (exactly one of `data_map` or `address`, optional `path`, `size` and `sha256`) — returns `Antd.BuiltManifest` (`manifest` bytes, `link` or `nil` when it would exceed 1,500 bytes, `entries` sorted by effective name). `opts`: `name:`, `torrent_info_hashes:`, `embed_roots:` (default `true`: embed each shrunk DataMap's resolved root when it is at most 64 KiB; `false` embeds DataMaps as given) |
| `decode_manifest(client, manifest, opts \\ [])` | Decode `.ant` bytes — returns `Antd.DecodedManifest` (`source`, `name`, `torrent_info_hash_v1`/`_v2`, `entries`). `opts`: `resolve: true` fetches each entry's DataMap to report `exact_size` and confirm it is on the network (content chunks are not fetched) |
| `decode_manifest_link(client, link, opts \\ [])` | Decode an `ant://` manifest link, a file link or a bare 64-hex address (a file link reads as one public entry with no path, `source: "file_link"`). `opts`: `resolve:` |

Each entry comes back as an `Antd.ManifestEntryInfo`: `effective_name` (the
path, or the content address when there is none), `path`, `size` (the
creator's claim), `kind` (`"embedded"` or `"public"`), `content_address`,
`data_map` (decode only), `exact_size`, `error` and `sha256`.

`sha256` is the plaintext's SHA-256 (hex). On an `Antd.ManifestEntryInput` it is
optional: give it to record the hash for the entry; it is passed to the daemon as
given, and left out when `nil` or `""`. On an `Antd.ManifestEntryInfo` it is the hash
the manifest records, or `nil` when none. Requires antd 0.17.0 or later.

- **Bytes.** The manifest is always a raw binary in this API. The REST client
  base64-encodes it on the wire; gRPC carries it as raw bytes.
- **Unset values are `nil`** on both transports. A `size` or `exact_size` that
  was never recorded or resolved is `nil`, never `0`; `link`, `path`, `name`,
  `data_map`, `error` and the torrent hashes are `nil` when absent.
- **Errors.** An entry with both or neither of `data_map` and `address` is
  refused before anything is sent, as an `Antd.BadRequestError` with
  `status_code` 400 and the daemon's own message (`2 invalid entries:
  entries[0]: ...; entries[2]: ...`), so it cannot be told from the daemon's
  refusal. The daemon's rejections (an invalid path such as `../x`, a
  malformed DataMap or manifest) are `Antd.BadRequestError` too (400, or gRPC
  `INVALID_ARGUMENT`), carrying the daemon's message, which names
  `entries[i]`. With `resolve: true`, one entry's failure is reported in its
  `error` and the call still succeeds.
- **gRPC.** `Antd.GrpcClient` has the same functions, each also taking a
  `:timeout` option in milliseconds (default 5 minutes). A manifest can be up
  to 64 MiB; grpc-elixir sets no receive limit on the client, so large
  manifests need no extra option.

```elixir
{:ok, one} = Antd.Client.data_put_public(client, "first file")
{:ok, two} = Antd.Client.data_put_public(client, "second file")

{:ok, built} =
  Antd.Client.build_manifest(
    client,
    [
      %Antd.ManifestEntryInput{path: "notes/one.txt", address: one.address},
      %Antd.ManifestEntryInput{path: "notes/two.txt", address: two.address}
    ],
    name: "notes"
  )

# Keep the .ant bytes, or share the link.
File.write!("notes.ant", built.manifest)

{:ok, decoded} = Antd.Client.decode_manifest_link(client, built.link, resolve: true)
for e <- decoded.entries, do: IO.puts("#{e.effective_name}: #{inspect(e.exact_size)} bytes")
```

See [`examples/09_manifests.exs`](examples/09_manifests.exs).

## Examples

See the [examples/](examples/) directory:

- `01_connect.exs` — Health check
- `02_data.exs` — Public data storage and retrieval
- `03_chunks.exs` — Raw chunk operations
- `04_files.exs` — File upload/download (public and private)
- `06_private_data.exs` — Private encrypted data
- `07_external_signer.exs` — External-signer two-phase upload with a bounded partial-upload retry
- `08_pointers.exs` — Create, update, read and check the finality of a pointer (`ANTD_POINTER_OWNER`, optional `ANTD_BASE_URL`)
- `09_manifests.exs` — Build a manifest of two public uploads, then decode its link with exact sizes (optional `ANTD_BASE_URL`)
