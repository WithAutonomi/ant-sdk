# Ruby Quickstart

A comprehensive guide to using the Autonomi network with the Ruby SDK.

## Setup

```bash
# Install the gem
gem install antd

# Or add to your Gemfile
# gem 'antd'

# Start local testnet
ant dev start
```

## Connecting

```ruby
require 'antd'

# REST transport (default)
client = Antd::Client.new

# Custom endpoint
client = Antd::Client.new(transport: :rest, base_url: "http://localhost:8082")

# gRPC transport
client = Antd::Client.new(transport: :grpc, target: "localhost:50051")
```

## Health Check

```ruby
status = client.health
puts "Healthy: #{status.ok}"
puts "Network: #{status.network}"  # "local", "default", or "alpha"
```

## Public Data

Store and retrieve arbitrary bytes on the network.

```ruby
# Store
result = client.data_put_public("Hello, Autonomi!")
puts "Address: #{result.address}"
puts "Cost: #{result.cost} atto tokens"

# Retrieve
data = client.data_get_public(result.address)
puts data  # "Hello, Autonomi!"

# Cost estimation
cost = client.data_cost("some data")
puts "Would cost: #{cost} atto tokens"
```

## Private Data

Encrypted data -- only accessible with the data map.

```ruby
# Store (self-encrypting)
result = client.data_put_private("secret message")
data_map = result.address  # Keep this secret!

# Retrieve (decrypt)
data = client.data_get_private(data_map)
puts data
```

## Files

```ruby
# Upload a file
result = client.file_upload_public("/path/to/file.txt")
puts "File address: #{result.address}"

# Download a file
client.file_download_public(result.address, "/path/to/output.txt")

# Upload a directory
result = client.dir_upload_public("/path/to/directory")

# Download a directory
client.dir_download_public(result.address, "/path/to/output_dir")

# Cost estimation
cost = client.file_cost("/path/to/file.txt")
```

## Graph Entries (DAG Nodes)

```ruby
require 'securerandom'

key = SecureRandom.hex(32)
content = SecureRandom.hex(32)

# Create a root node
result = client.graph_entry_put(
  key,
  parents: [],
  content: content,
  descendants: [],
)
puts "Graph entry: #{result.address}"

# Read
entry = client.graph_entry_get(result.address)
puts "Owner: #{entry.owner}"
puts "Content: #{entry.content}"
puts "Parents: #{entry.parents}"
puts "Descendants: #{entry.descendants}"

# Check existence
exists = client.graph_entry_exists(result.address)
```

## Error Handling

The Ruby SDK raises exceptions on errors.

```ruby
begin
  client.data_get_public("nonexistent")
rescue Antd::NotFoundError
  puts "Not found"
rescue Antd::PaymentError
  puts "Payment issue"
rescue Antd::NetworkError
  puts "Network unreachable"
rescue Antd::AntdError => e
  puts "Error (#{e.status_code}): #{e.message}"
end
```

Exception hierarchy:

| Exception | HTTP Code | When |
|-----------|-----------|------|
| `Antd::BadRequestError` | 400 | Invalid parameters |
| `Antd::PaymentError` | 402 | Insufficient funds |
| `Antd::NotFoundError` | 404 | Resource not found |
| `Antd::AlreadyExistsError` | 409 | Duplicate creation |
| `Antd::ForkError` | 409 | Version conflict |
| `Antd::TooLargeError` | 413 | Payload too large |
| `Antd::InternalError` | 500 | Server error |
| `Antd::NetworkError` | 502 | Network unreachable |

## Examples

```bash
# Run individual examples
ant dev example connect -l ruby
ant dev example data -l ruby
ant dev example all -l ruby

# Or directly
ruby antd-ruby/examples/01_connect.rb
ruby antd-ruby/examples/02_data.rb
```

See `antd-ruby/examples/` for the complete set of examples.
