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

# Store data
{:ok, result} = Antd.Client.data_put_public(client, "Hello, Autonomi!")
IO.puts("Stored at #{result.address} (cost: #{result.cost} atto)")

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

## gRPC Transport

The SDK includes an `Antd.GrpcClient` module that provides the same
functions as the REST `Antd.Client`, but communicates over gRPC.

### Setup

The `grpc` and `protobuf` hex packages are already listed in `mix.exs`. Fetch
them with:

```bash
mix deps.get
```

Generate the Elixir protobuf/gRPC stubs from the proto definitions:

```bash
protoc --elixir_out=plugins=grpc:lib \
  -I../../antd/proto \
  antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
  antd/v1/chunks.proto antd/v1/files.proto
```

The generated modules are expected under `lib/antd/v1/`.

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

> **Note:** Wallet operations (address, balance, approve) and payment_mode are available via REST only.

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

### Data (Immutable)

| Function | Description |
|----------|-------------|
| `data_put_public(client, data)` | Store public data |
| `data_get_public(client, address)` | Retrieve public data |
| `data_put_private(client, data)` | Store encrypted private data |
| `data_get_private(client, data_map)` | Retrieve private data |
| `data_cost(client, data)` | Estimate storage cost — returns `Antd.UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks

| Function | Description |
|----------|-------------|
| `chunk_put(client, data)` | Store a raw chunk |
| `chunk_get(client, address)` | Retrieve a chunk |

### Files & Directories

| Function | Description |
|----------|-------------|
| `file_upload_public(client, path)` | Upload a file |
| `file_download_public(client, address, dest_path)` | Download a file |
| `dir_upload_public(client, path)` | Upload a directory |
| `dir_download_public(client, address, dest_path)` | Download a directory |
| `file_cost(client, path, is_public)` | Estimate upload cost — returns `Antd.UploadCostEstimate` with size, chunks, gas, payment mode |

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
| `Antd.ForkError` | 409 | Version conflict |
| `Antd.TooLargeError` | 413 | Payload too large |
| `Antd.InternalError` | 500 | Server error |
| `Antd.NetworkError` | 502 | Network unreachable |

## Examples

See the [examples/](examples/) directory:

- `01_connect.exs` — Health check
- `02_data.exs` — Public data storage and retrieval
- `03_chunks.exs` — Raw chunk operations
- `04_files.exs` — File and directory upload/download
- `06_private_data.exs` — Private encrypted data
