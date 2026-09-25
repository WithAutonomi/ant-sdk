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

This gem talks to a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon; it does not join the network itself. Ruby 3.1+. Tested against antd 0.12.x. The REST client has no runtime dependencies; the gRPC transport (`Antd::GrpcClient`) needs the `grpc` gem, which is deliberately not a runtime dependency of this gem — add `gem "grpc"` yourself to use it.

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

Generate the Ruby protobuf/gRPC stubs from the proto definitions:

```bash
grpc_tools_ruby_protoc \
  -I../../antd/proto \
  --ruby_out=lib --grpc_out=lib \
  antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
  antd/v1/chunks.proto antd/v1/files.proto
```

The generated files are expected under `lib/antd/v1/`.

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
`Antd::PartialUploadError`, with the chunk counts and the `retryable` flag
parsed from that text — see [Partial uploads](#partial-uploads); any other
`ABORTED`, including one that only mentions `Partial upload:` later in its
text, stays a generic `Antd::AntdError`).

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

### Partial uploads

A `finalize_upload` / `finalize_merkle_upload` / `finalize_chunk_upload` call
can fail *after* the external signer has paid: some chunks store, others miss
quorum after the daemon's own retries. The daemon reports this as HTTP `502`
with `code: "PARTIAL_UPLOAD"` (gRPC `ABORTED`), and the SDK raises
`Antd::PartialUploadError` carrying `chunks_stored`, `chunks_failed`,
`total_chunks` and `retryable`. The on-chain payment persists and the stored
chunks stay on the network; what to do next depends on `retryable`:

- **`retryable == true`** (antd >= 0.14.0) — the daemon kept the paid attempt
  under the same `upload_id`. Call the **same finalize method again with the
  same arguments** to store the remainder against the same payment: no
  re-prepare, no second signature, no double payment. Bound the loop — a
  persistent failure raises this error on every call — so cap the attempts
  and treat a `chunks_failed` that stops shrinking as stuck. The retained
  attempt expires with the daemon's pending-upload TTL.
- **`retryable == false`** — nothing was retained (a merkle finalize with
  deliberately unpaid batches, or a daemon older than 0.14.0, which never
  sends the flag). Re-prepare the same content: already-stored chunks are
  skipped, so the retry pays only for the remainder.

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
  raise unless e.retryable                     # not resumable: re-prepare
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

## Examples

See the [examples/](examples/) directory:

- `01_connect.rb` — Health check
- `02_data.rb` — Public data put/get with cost estimate
- `03_chunks.rb` — Chunk put/get
- `04_files.rb` — File upload and download
- `06_private_data.rb` — Private data put/get
- `07_external_signer.rb` — External-signer prepare/pay/finalize with a bounded partial-upload retry
