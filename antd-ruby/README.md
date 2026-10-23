# antd-ruby

Ruby SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

Add to your Gemfile:

```ruby
gem "antd"
```

Or install directly:

```bash
gem install antd
```

## Compatibility

This gem talks to a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon; it does not join the network itself. Ruby 3.1+. Tested against antd 0.12.x; the pointer methods need antd 0.16.0 or later, the first release with pointers. The REST client has no runtime dependencies; the gRPC transport (`Antd::GrpcClient`) needs the `grpc` gem, which is deliberately not a runtime dependency of this gem — add `gem "grpc"` yourself to use it.

## Quick Start

```ruby
require "antd"

client = Antd::Client.new

# Check daemon health
health = client.health
puts "OK: #{health.ok}, Network: #{health.network}"

# Store data
result = client.data_put_public("Hello, Autonomi!")
puts "Stored at #{result.address} (chunks: #{result.chunks_stored})"

# Retrieve data
data = client.data_get_public(result.address)
puts "Retrieved: #{data}"
```

## gRPC Transport

The SDK includes an `Antd::GrpcClient` class that provides the same methods
as the REST `Antd::Client`, but communicates over gRPC.

### Setup

Install the gRPC gem (listed as an optional development dependency):

```bash
gem install grpc grpc-tools
```

The Ruby protobuf/gRPC stubs in `lib/antd/v1/` are generated from the proto
definitions and committed. After changing the protos, regenerate them and
commit the result (CI fails when they drift):

```bash
gem install grpc-tools -v 1.84.0   # the version the script pins
antd-ruby/scripts/generate-protos.sh
```

### Usage

```ruby
require "antd"
require "antd/grpc_client"

client = Antd::GrpcClient.new  # defaults to localhost:50051

# Or custom target:
# client = Antd::GrpcClient.new(target: "my-host:50051")

health = client.health
puts "OK: #{health.ok}, Network: #{health.network}"

result = client.data_put_public("Hello via gRPC!")
puts "Stored at #{result.address}"

data = client.data_get_public(result.address)
puts "Retrieved: #{data}"
```

The `GrpcClient` raises the same `Antd::AntdError` hierarchy as the REST
client, translating gRPC status codes to the appropriate error subclass
(an `ABORTED` whose status details — `GRPC::BadStatus#details`, the text
the daemon sent — start with `Partial upload:` becomes
`Antd::PartialUploadError`, with the chunk counts, `retryable` and
`retention_known` parsed from that text — see
[Partial uploads](#partial-uploads); any other
`ABORTED`, including one that only mentions `Partial upload:` later in its
text, stays a generic `Antd::AntdError`).

The pointer and close-group errors share gRPC status codes with older ones, so
the daemon names them in an `x-antd-error-code` trailer
(`GRPC::BadStatus#metadata`). The client reads it on every call and, when it
agrees with the status code, raises the same typed error as REST:
`FAILED_PRECONDITION` + `POINTER_FINAL` → `PointerFinalError`, + `POINTER_FORKED`
→ `PointerForkedError`, `ABORTED` + `CONFLICT` → `ConflictError`, and
`UNAVAILABLE` + `CLOSE_GROUP_SHORTFALL` → `CloseGroupShortfallError` (`retryable`
when the details close with `(paid attempt retained...)`). Without the trailer,
`FAILED_PRECONDITION` stays a `PaymentError` and `UNAVAILABLE` a `NetworkError`.

> **Note:** Wallet operations (address, balance, approve) and payment_mode are available via REST only.

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```ruby
# Default: http://localhost:8082, 300 second timeout
client = Antd::Client.new

# Custom URL
client = Antd::Client.new(base_url: "http://custom-host:9090")

# Custom timeout (seconds)
client = Antd::Client.new(timeout: 30)

# Both
client = Antd::Client.new(base_url: "http://custom-host:9090", timeout: 30)
```

## API Reference

### Health
| Method | Description |
|--------|-------------|
| `health` | Check daemon status |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `data_put_public(data, payment_mode: :auto)` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `data_get_public(address)` | Retrieve public data by address |
| `data_put(data, payment_mode: :auto)` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `data_get(data_map)` | Retrieve private data using a caller-held DataMap |
| `data_cost(data, payment_mode: :auto)` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks
| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Files
| Method | Description |
|--------|-------------|
| `file_put(path, payment_mode: :auto)` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `file_get(data_map, dest_path)` | Download a private file using a caller-held DataMap |
| `file_put_public(path, payment_mode: :auto)` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `file_get_public(address, dest_path)` | Download a public file by address |
| `file_cost(path, is_public, payment_mode: :auto)` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

**`sha256` on upload results.** `DataPutResult`, `DataPutPublicResult`,
`FilePutResult`, `FilePutPublicResult` and `FinalizeUploadResult` (from
`finalize_upload` and `finalize_merkle_upload`) have a `sha256` field: the
plaintext's SHA-256 (hex); requires antd 0.17.0 or later, none on older
daemons (`nil`, over REST and gRPC alike).

### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived
from the owner's key and never changes; what it points at (a chunk, such as a
public file's data map, or another pointer) can be changed by the owner, and
the owner can hand it over to another pointer for good. The daemon holds the
owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (files
in the format `ant pointer keygen` writes), so every write names the pointer by
its address (`owner`), never by a key. An address the daemon holds no key for
is a `BadRequestError`.

**Every write pays** (about the price of one chunk), and every attempt pays
again. The SDK never retries a request, and you should not retry
`pointer_create`, `pointer_update`, `pointer_transfer` or `pointer_finalize`
automatically either. Reads are free to retry; one during an update or churn
can fail with `CloseGroupShortfallError`.

Both `Antd::Client` and `Antd::GrpcClient` have these methods:

| Method | Description |
|--------|-------------|
| `pointer_keys` | Addresses of the pointers this daemon holds keys for, so can write — `Array<String>` |
| `pointer_create(owner, target, kind: nil)` | Create a pointer, paid by the daemon wallet — returns `PointerWriteResult` (`address`, `state_id`, `counter`). `AlreadyExistsError`, before paying, if it exists. `kind` is `PointerKind::CHUNK` (the default) or `PointerKind::POINTER` |
| `pointer_update(owner, target, kind: nil)` | Point a pointer at a new target, creating it if needed — `PointerWriteResult`. `PointerFinalError`, usually before paying, once it was handed over or frozen |
| `pointer_transfer(owner, recipient)` | Hand a pointer over for good to the recipient's pointer, which must exist. Irreversible. Returns `PointerTransferResult` with the close group's `finality` (nil, with `finality_error`, if that check failed; the transfer stands) |
| `pointer_get(address)` | Read a pointer — `PointerRecord` (`counter`, `target`, `kind`/`kind_tag`, `is_final` / `final?`, `transferred_to`, the owner's public key). `NotFoundError` if there is none |
| `pointer_resolve(address)` | Follow a chain of pointers to the target at its end — `PointerTarget` (`kind`, `kind_tag`, `target`) |
| `pointer_finality(address)` | Ask the whole close group where a pointer stands — `PointerFinality`. Check `final?` before relying on a transfer |
| `pointer_controller(address)` | Follow transfers to the pointer whose owner now decides — `PointerController` (`pointer`, `transfers`, `frozen`) |
| `pointer_prepare(owner, op, target: nil, kind: nil, recipient: nil, include_signed_quotes: false)` | External signer: the daemon signs a `PointerOp::CREATE`, `UPDATE` or `TRANSFER` and quotes it — `PointerPrepareResult` (wave-batch `payments` for `payForQuotes()`; `signed_quotes` when asked). Needs no daemon wallet. Other writes to the pointer raise `ConflictError` until it is finalized or expires (one hour) |
| `pointer_finalize(upload_id, tx_hashes)` | External signer: store the prepared write once paid — `PointerFinalizeResult`. A write that falls short after payment raises `CloseGroupShortfallError` with `retryable`: repeat the same call to store it against the same payment |

Counters are `Integer`s. The daemon sends them as decimal strings, because a
final state (a transfer or a freeze) sits at `Antd::POINTER_FINAL_COUNTER`
(2^64 − 1), past what a JSON number keeps exactly in many languages. A counter
that is not a decimal u64 raises `InternalError`; it never reads as 0.

`PointerFinality#status` is one of the `Antd::PointerFinalityStatus` strings:
`OPEN` (with the corroborated `counter`, or nil), `SETTLING`, `UNCONFIRMED` and
`FINAL` (with the one final `state`), or `FORKED` (with every final state in
`states` and the `majority`). Only `FINAL` means a transfer is beyond dispute.
A status a newer daemon adds is kept verbatim (`status_known?` is false), so
give a `case` over it an `else` branch. Unset fields read as `nil` on both
transports: REST sends `null`, gRPC an empty string or no message.

The daemon accepts addresses with a `0x` prefix but always returns bare hex;
normalise before comparing.

```ruby
owner = client.pointer_keys.first
client.pointer_create(owner, client.data_put_public("v1").address)  # pays
client.pointer_update(owner, client.data_put_public("v2").address)  # pays again
puts client.data_get_public(client.pointer_resolve(owner).target)   # "v2"
puts client.pointer_finality(owner).status                          # "open"
```

## Error Handling

All errors inherit from `Antd::AntdError` and can be caught by type:

```ruby
begin
  data = client.data_get_public(address)
rescue Antd::NotFoundError => e
  puts "Data not found on network"
rescue Antd::PaymentError => e
  puts "Insufficient funds"
rescue Antd::AntdError => e
  puts "Error #{e.status_code}: #{e.message}"
end
```

| Error Type | HTTP Status | When |
|-----------|-------------|------|
| `BadRequestError` | 400 | Invalid parameters |
| `PaymentError` | 402 | Insufficient funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource exists |
| `ForkError` | 409 | Version conflict |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |
| `PartialUploadError` | 502 (`code: "PARTIAL_UPLOAD"`) | Finalize stored some chunks but not all — subclass of `NetworkError` |
| `ServiceUnavailableError` | 503 | Wallet not configured |
| `PointerFinalError` | 409 (`code: "POINTER_FINAL"`) / gRPC `FAILED_PRECONDITION` | The pointer is transferred or frozen; nothing can change it |
| `PointerForkedError` | 409 (`code: "POINTER_FORKED"`) / gRPC `FAILED_PRECONDITION` | The owner signed two final states and no majority holds either — subclass of `ForkError` |
| `ConflictError` | 409 (`code: "CONFLICT"`) / gRPC `ABORTED` | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state |
| `CloseGroupShortfallError` | 503 (`code: "CLOSE_GROUP_SHORTFALL"`) / gRPC `UNAVAILABLE` | Too few of the close group answered or stored; `retryable` is true only for a pointer finalize that kept the paid state |

The pointer errors are read from the error body's `code` (gRPC: the
`x-antd-error-code` trailer), so a 409 with one of those codes is not an
`AlreadyExistsError`. `CloseGroupShortfallError` is not only for pointers: a
daemon with the pointer API reports a close group that fell short on any call
(a chunk store, say) this way, where older daemons sent a 500
(`InternalError`). It is not a `ServiceUnavailableError`, so rescue it by name.

### Partial uploads

A `finalize_upload` / `finalize_merkle_upload` / `finalize_chunk_upload` call
can fail *after* the external signer has paid: some chunks store, others miss
quorum after the daemon's own retries. The daemon reports this as HTTP `502`
with `code: "PARTIAL_UPLOAD"` (gRPC `ABORTED`), and the SDK raises
`Antd::PartialUploadError` carrying `chunks_stored`, `chunks_failed`,
`total_chunks`, `retryable` and `retention_known`. The on-chain payment
persists and the stored chunks stay on the network; what to do next depends
on what the daemon said about the paid attempt:

- **`retryable`** (antd >= 0.14.0; implies `retention_known`) — the daemon
  kept the paid attempt under the same `upload_id`. Call the **same finalize
  method again with the same `upload_id` and payment artefacts** to store the
  remainder against the same payment: no re-prepare, no second signature, no
  double payment. Bound the loop — a persistent failure raises this error on
  every call — so cap the attempts and treat a `chunks_failed` that stops
  shrinking as stuck. The retained attempt expires with the daemon's
  pending-upload TTL.
- **`retention_known && !retryable`** — the daemon confirmed nothing was
  retained (a merkle finalize with deliberately unpaid batches). Re-prepare
  the same content: already-stored chunks are skipped, so the retry pays only
  for the remainder.
- **`!retention_known`** — retention is unknown: the error did not say, in a
  form the SDK could read, whether the paid attempt was kept. The daemon may
  still hold it (it records the resume handle before it returns the error).
  Stop automatic recovery, keep the `upload_id` and the original payment
  artefacts (tx hashes, or the merkle winner pool hash), and reconcile before
  re-preparing or paying again. **Never pay again on this signal alone.**
  Daemons older than 0.14.0 never send `retryable`, so their REST partial
  uploads read as unknown.

Over REST, `retention_known` is true only when the body's `retryable` is a
JSON boolean (`true` or `false`); absent, `null` or any other type reads as
unknown. Over gRPC there is no structured body, so the counts and flags are
parsed from the status text,
`Partial upload: <stored>/<total> chunks stored, <failed> failed after retries: <reason> (<hint>)`.
`retention_known` is true only when the text starts with that counts
pattern, all three counts parse (each within the daemon's u64 range), and the
text ends with one of the daemon's two hints: `(paid attempt retained...)`
sets `retryable`, and `(stored chunks persist; re-prepare the same content...)`
means the daemon confirmed nothing was retained (daemons older than 0.14.0
write only this one). If the counts cannot be read, all three are `0` and
both flags are `false`. Readable counts with a missing, truncated or
unrecognised hint keep the counts, but both flags stay `false`: retention is
unknown, so stop and reconcile rather than re-prepare.

`PartialUploadError` subclasses `NetworkError` (the 502 mapping), so existing
`rescue Antd::NetworkError` blocks keep catching it; rescue the subclass first
to handle it specifically.

```ruby
MAX_ATTEMPTS = 5
last_failed = nil
attempt = 0
begin
  attempt += 1
  result = client.finalize_upload(prep.upload_id, tx_hashes)
rescue Antd::PartialUploadError => e
  # Not resumable. With retention_known, nothing was retained: re-prepare.
  # Without it, retention is unknown: stop, keep upload_id + tx_hashes and
  # reconcile before re-preparing or paying again.
  raise unless e.retryable
  stuck = !last_failed.nil? && e.chunks_failed >= last_failed
  raise if attempt >= MAX_ATTEMPTS || stuck    # bounded: same payment, same upload_id
  last_failed = e.chunks_failed
  sleep(2 * attempt)
  retry
end
```

See [`docs/external-signer-flow.md` section 6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment)
for the daemon contract and `examples/07_external_signer.rb` for a
`finalize_with_retry` helper.

## Manifests

A manifest (ADR-0006) describes a set of files in one `.ant` file or
`ant://` link: each entry has an optional path and size, and either an
embedded DataMap (from a private upload; the manifest is then the key to the
file) or a public file's DataMap address. The daemon builds and decodes
manifests, so the SDK never handles the format itself. These methods need
antd 0.16.0 or later.

**Nothing is uploaded or paid for.** Building one from DataMaps and addresses
you already hold is free. Embedding roots (on build) and `resolve` (on
decode) read from the network, so either can time out; retrying is safe.

Both `Antd::Client` and `Antd::GrpcClient` have these methods:

| Method | Description |
|--------|-------------|
| `build_manifest(entries, name: nil, torrent_info_hashes: nil, embed_roots: true)` | Build a manifest — returns `BuiltManifest` (`manifest`, the raw `.ant` bytes; `link`, or nil when it would exceed 1,500 bytes; `entries`, sorted by effective name). Each entry is a `ManifestEntryInput` or a Hash with `path`, `size`, and exactly one of `data_map` (hex) or `address` (hex); both or neither raises `BadRequestError` (400, the daemon's wording) before anything is sent. By default the daemon resolves each shrunk DataMap and embeds its root when it is at most 64 KiB; `embed_roots: false` embeds them as given |
| `decode_manifest(manifest, resolve: false)` | Decode `.ant` bytes — returns `DecodedManifest` (`source`, `name`, `torrent_info_hash_v1`/`_v2`, `entries`) |
| `decode_manifest_link(link, resolve: false)` | Decode an `ant://manifest/` link, a file link or a bare 64-hex address (a `ManifestSource::FILE_LINK`: one public entry, no path) |

Each entry comes back as a `ManifestEntryInfo`: `effective_name` (the path,
or the content address when there is none), `path`, `size` (what the
manifest records: the creator's claim), `kind` (`ManifestEntryKind::EMBEDDED`
or `PUBLIC`), `content_address`, `data_map` (decode only, embedded entries
only, in the hex form `data_get` and `file_get` take), `exact_size`, and
`error`. With `resolve: true` the daemon fetches each DataMap (not the
content) to fill in `exact_size`; an entry that fails gets an `error` instead
of failing the call.

An entry can record the file's plaintext SHA-256: give `sha256` (hex) on a
`ManifestEntryInput` or Hash entry, and read it back as `sha256` on the
`ManifestEntryInfo`, from both build and decode. Both require antd 0.17.0 or
later. The SDK sends `sha256` only when it is set and non-empty, and passes it
through unchecked: the daemon validates it (upper or lower case is accepted,
lowercase comes back) and a bad one raises `BadRequestError`. An entry with no
recorded hash reads `nil`.

`manifest` is always raw bytes: the SDK base64-encodes it for REST and sends
it as-is over gRPC. Sizes are `Integer`s, and anything a manifest leaves unset
is `nil` on both transports, so a missing `size` or `exact_size` is `nil`,
never `0`. An entry the daemon rejects (a bad path such as `../x`, a malformed
DataMap or address) raises `BadRequestError` (gRPC `INVALID_ARGUMENT`) with
the daemon's message, which names `entries[i]`. The SDK's own checks (both or
neither of `data_map` and `address`, an empty manifest or link) raise the same
error with the daemon's exact text, so the two cannot be told apart.

Over gRPC, a manifest can be up to 64 MiB, past gRPC's 4 MiB default, so the
client talks to ManifestService on a channel of its own with the send and
receive limits raised to `Antd::MANIFEST_GRPC_MAX_MESSAGE` (256 MiB). The
other services keep the defaults.

```ruby
a = client.data_put_public("one").address        # pays
b = client.data_put_public("two").address        # pays
built = client.build_manifest(
  [{ path: "notes/one.txt", address: a }, { path: "notes/two.txt", address: b }],
  name: "notes"
)                                                # free
File.binwrite("notes.ant", built.manifest)
client.decode_manifest_link(built.link, resolve: true).entries.each do |e|
  puts "#{e.effective_name}: #{e.exact_size} bytes"
end
```

## Examples

See the [examples/](examples/) directory:

- `01_connect.rb` — Health check
- `02_data.rb` — Public data put/get with cost estimate
- `03_chunks.rb` — Chunk put/get
- `04_files.rb` — File upload and download
- `06_private_data.rb` — Private data put/get
- `07_external_signer.rb` — External-signer prepare/pay/finalize with a bounded partial-upload retry
- `08_pointers.rb` — Create a pointer, update it, resolve it and check its finality. Run with `ANTD_POINTER_OWNER=<address>` (one of `pointer_keys`); `ANTD_BASE_URL` overrides the daemon URL. Each write pays
- `09_manifests.rb` — Store two pieces of public data, build a manifest of them, print its link and entries, and decode the link with `resolve`. `ANTD_BASE_URL` overrides the daemon URL. The two uploads pay; the manifest calls do not
