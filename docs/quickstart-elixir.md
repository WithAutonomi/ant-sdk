# Elixir Quickstart

A comprehensive guide to using the Autonomi network with the Elixir SDK.

## Setup

```elixir
# Add to mix.exs dependencies
defp deps do
  [
    {:antd, "~> 0.1"}
  ]
end
```

```bash
# Fetch dependencies
mix deps.get

# Start local testnet
ant dev start
```

## Connecting

```elixir
# REST transport (default)
{:ok, client} = Antd.Client.new()

# Custom endpoint
{:ok, client} = Antd.Client.new(transport: :rest, base_url: "http://localhost:8082")

# gRPC transport
{:ok, client} = Antd.Client.new(transport: :grpc, target: "localhost:50051")

# Bang variant (raises on error)
client = Antd.Client.new!()
```

## Health Check

```elixir
{:ok, status} = Antd.Client.health(client)
IO.puts("Healthy: #{status.ok}")
IO.puts("Network: #{status.network}")  # "local", "default", or "alpha"

# Bang variant
status = Antd.Client.health!(client)
```

## Public Data

Store and retrieve arbitrary bytes on the network.

```elixir
# Store
{:ok, result} = Antd.Client.data_put_public(client, "Hello, Autonomi!")
IO.puts("Address: #{result.address}")
IO.puts("Cost: #{result.cost} atto tokens")

# Retrieve
{:ok, data} = Antd.Client.data_get_public(client, result.address)
IO.puts(data)  # "Hello, Autonomi!"

# Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
{:ok, est} = Antd.Client.data_cost(client, "some data")
IO.puts("Estimate: #{est.file_size} bytes in #{est.chunk_count} chunks, #{est.cost} atto, gas #{est.estimated_gas_cost_wei} wei, mode #{est.payment_mode}")

# Bang variants
result = Antd.Client.data_put_public!(client, "Hello, Autonomi!")
data = Antd.Client.data_get_public!(client, result.address)
```

## Private Data

Encrypted data -- only accessible with the data map.

```elixir
# Store (self-encrypting)
{:ok, result} = Antd.Client.data_put_private(client, "secret message")
data_map = result.address  # Keep this secret!

# Retrieve (decrypt)
{:ok, data} = Antd.Client.data_get_private(client, data_map)
IO.puts(data)
```

## Files

```elixir
# Upload a file
{:ok, result} = Antd.Client.file_upload_public(client, "/path/to/file.txt")
IO.puts("File address: #{result.address}")

# Download a file
:ok = Antd.Client.file_download_public(client, result.address, "/path/to/output.txt")

# Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
{:ok, est} = Antd.Client.file_cost(client, "/path/to/file.txt")
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```elixir
{:ok, [owner | _]} = Antd.Client.pointer_keys(client)   # a pointer antd can write

{:ok, v1} = Antd.Client.data_put_public(client, "version 1")
{:ok, v2} = Antd.Client.data_put_public(client, "version 2")

{:ok, _} = Antd.Client.pointer_create(client, owner, v1.address)   # pays; counter 0
{:ok, _} = Antd.Client.pointer_update(client, owner, v2.address)   # pays again; counter 1
{:ok, target} = Antd.Client.pointer_resolve(client, owner)         # target.target == v2.address (free)

{:ok, finality} = Antd.Client.pointer_finality(client, owner)      # free
IO.inspect(finality.status)                                        # :open
```

Counters are integers. Every function has a `!` variant, and `Antd.GrpcClient` has the same set. `pointer_transfer`, `pointer_get`, `pointer_controller`, `pointer_prepare` and `pointer_finalize` complete it.

Runnable example: `antd-elixir/examples/08_pointers.exs`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-elixir/examples
ANTD_POINTER_OWNER=<address> elixir 08_pointers.exs
```

## Error Handling

The Elixir SDK returns `{:ok, result}` or `{:error, reason}` tuples. Bang variants (e.g., `health!`) raise an `Antd.Error` exception on failure.

```elixir
case Antd.Client.data_get_public(client, "nonexistent") do
  {:ok, data} ->
    IO.puts("Got data")

  {:error, %Antd.Error{code: :not_found}} ->
    IO.puts("Not found")

  {:error, %Antd.Error{code: :payment}} ->
    IO.puts("Payment issue")

  {:error, %Antd.Error{code: :network}} ->
    IO.puts("Network unreachable")

  {:error, %Antd.Error{code: code, message: message}} ->
    IO.puts("Error (#{code}): #{message}")
end
```

```elixir
# Bang variant raises on error
try do
  Antd.Client.data_get_public!(client, "nonexistent")
rescue
  e in Antd.Error ->
    IO.puts("Error (#{e.code}): #{e.message}")
end
```

Error codes:

| Code Atom | HTTP Code | When |
|-----------|-----------|------|
| `:bad_request` | 400 | Invalid parameters |
| `:payment` | 402 | Insufficient funds |
| `:not_found` | 404 | Resource not found |
| `:already_exists` | 409 | Duplicate creation |
| `:fork` | 409 | Version conflict |
| `:too_large` | 413 | Payload too large |
| `:internal` | 500 | Server error |
| `:network` | 502 | Network unreachable |

## Examples

```bash
# Run individual examples
ant dev example connect -l elixir
ant dev example data -l elixir
ant dev example all -l elixir

# Or directly
mix run antd-elixir/examples/01_connect.exs
mix run antd-elixir/examples/02_data.exs
```

See `antd-elixir/examples/` for the complete set of examples.
