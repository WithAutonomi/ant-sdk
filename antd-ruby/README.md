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

## Quick Start

```ruby
require "antd"

client = Antd::Client.new

# Check daemon health
health = client.health
puts "OK: #{health.ok}, Network: #{health.network}"

# Store data
result = client.data_put_public("Hello, Autonomi!")
puts "Stored at #{result.address} (cost: #{result.cost} atto)"

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
client, translating gRPC status codes to the appropriate error subclass.

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
| `data_put(data, payment_mode: PaymentMode::AUTO)` | Store encrypted private data; returns caller-held DataMap |
| `data_get(data_map)` | Retrieve private data from a caller-held DataMap |
| `data_put_public(data, payment_mode: PaymentMode::AUTO)` | Store public data; returns on-network DataMap address |
| `data_get_public(address)` | Retrieve public data by address |
| `data_cost(data, payment_mode: PaymentMode::AUTO)` | Estimate storage cost — returns `UploadCostEstimate` |

`Antd::PaymentMode` exposes `AUTO`, `MERKLE`, `SINGLE` string constants. Private uploads use the unqualified verb (`data_put` / `data_get`); the `_public` suffix marks the public variant.

### Chunks
| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Files
| Method | Description |
|--------|-------------|
| `file_put(path, payment_mode: PaymentMode::AUTO)` | Upload a file privately; returns caller-held DataMap |
| `file_get(data_map, dest_path)` | Download a private file from a caller-held DataMap |
| `file_put_public(path, payment_mode: PaymentMode::AUTO)` | Upload a file publicly; returns on-network DataMap address |
| `file_get_public(address, dest_path)` | Download a public file by address |
| `file_cost(path, is_public, payment_mode: PaymentMode::AUTO)` | Estimate upload cost — returns `UploadCostEstimate` |

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

## Examples

See the [examples/](examples/) directory:

- `01_connect.rb` — Health check
- `02_data.rb` — Public data put/get with cost estimate
- `03_chunks.rb` — Chunk put/get
- `04_files.rb` — File upload and download
- `06_private_data.rb` — Private data put/get
