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

Generate the Elixir protobuf/gRPC stubs from the proto definitions:

```bash
protoc --elixir_out=plugins=grpc:lib \
  -I../antd/proto \
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

> **Note:** Wallet operations (address, balance, approve) and external-signer
> two-phase upload are available via REST only.

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
| `data_put_public(client, data, opts \\ [])` | Store public data — returns `Antd.DataPutPublicResult` (DataMap stored on-network). `opts`: `payment_mode: :auto | :merkle | :single`. |
| `data_get_public(client, address)` | Retrieve public data by address |
| `data_put(client, data, opts \\ [])` | Store encrypted private data — returns `Antd.DataPutResult` (DataMap returned to caller). `opts`: `payment_mode:`. |
| `data_get(client, data_map)` | Retrieve private data using a caller-held DataMap |
| `data_cost(client, data, opts \\ [])` | Estimate storage cost — returns `Antd.UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks

| Function | Description |
|----------|-------------|
| `chunk_put(client, data)` | Store a raw chunk |
| `chunk_get(client, address)` | Retrieve a chunk |

### Files

| Function | Description |
|----------|-------------|
| `file_put(client, path, opts \\ [])` | Upload a file privately — returns `Antd.FilePutResult` (DataMap returned to caller). `opts`: `payment_mode:`. |
| `file_get(client, data_map, dest_path)` | Download a private file using a caller-held DataMap |
| `file_put_public(client, path, opts \\ [])` | Upload a file publicly — returns `Antd.FilePutPublicResult` (DataMap stored on-network). `opts`: `payment_mode:`. |
| `file_get_public(client, address, dest_path)` | Download a public file by address |
| `file_cost(client, path, is_public, opts \\ [])` | Estimate upload cost — returns `Antd.UploadCostEstimate` with size, chunks, gas, payment mode |

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
- `04_files.exs` — File upload/download (public and private)
- `06_private_data.exs` — Private encrypted data
