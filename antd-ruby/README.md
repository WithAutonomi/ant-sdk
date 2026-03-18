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

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```ruby
# Default: http://localhost:8080, 300 second timeout
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
| `data_put_public(data)` | Store public data |
| `data_get_public(address)` | Retrieve public data |
| `data_put_private(data)` | Store encrypted private data |
| `data_get_private(data_map)` | Retrieve private data |
| `data_cost(data)` | Estimate storage cost |

### Chunks
| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Graph Entries (DAG Nodes)
| Method | Description |
|--------|-------------|
| `graph_entry_put(secret_key, parents, content, descendants)` | Create entry |
| `graph_entry_get(address)` | Read entry |
| `graph_entry_exists(address)` | Check if exists |
| `graph_entry_cost(public_key)` | Estimate creation cost |

### Files & Directories
| Method | Description |
|--------|-------------|
| `file_upload_public(path)` | Upload a file |
| `file_download_public(address, dest_path)` | Download a file |
| `dir_upload_public(path)` | Upload a directory |
| `dir_download_public(address, dest_path)` | Download a directory |
| `archive_get_public(address)` | Get archive manifest |
| `archive_put_public(archive)` | Create archive manifest |
| `file_cost(path, is_public, include_archive)` | Estimate upload cost |

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
- `05_graph.rb` — Graph entry CRUD
- `06_private_data.rb` — Private data put/get
