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

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```elixir
{:ok, one} = Antd.Client.data_put_public(client, "first file")    # pays
{:ok, two} = Antd.Client.data_put_public(client, "second file")   # pays

{:ok, built} =
  Antd.Client.build_manifest(                                      # free
    client,
    [
      %Antd.ManifestEntryInput{path: "notes/one.txt", address: one.address},
      %Antd.ManifestEntryInput{path: "notes/two.txt", address: two.address}
    ],
    name: "example"
  )
# built.link is nil when over 1,500 bytes: share built.manifest (binary) instead

{:ok, decoded} = Antd.Client.decode_manifest_link(client, built.link, resolve: true)   # free
for e <- decoded.entries, do: IO.puts("#{e.effective_name}: #{inspect(e.exact_size)} bytes")
```

`decode_manifest(client, bytes, resolve: true)` takes raw `.ant` bytes. Set `data_map:` instead of `address:` for an embedded entry, and `embed_roots: false` to keep shrunk DataMaps as given. Every function has a `!` variant, and `Antd.GrpcClient` has the same set.

Runnable example: `antd-elixir/examples/09_manifests.exs`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-elixir/examples
ANTD_BASE_URL=http://localhost:8082 elixir 09_manifests.exs
```

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
