Mix.install([
  {:antd, path: ".."}
])

# Store and retrieve private (encrypted) data.
#
# Private methods are the unqualified verb: `data_put` / `data_get`. The
# returned DataMap is the caller-held handle (NOT stored on-network).
client = Antd.Client.new()

# Store private data — returns a data_map needed for retrieval.
{:ok, result} = Antd.Client.data_put(client, "my secret message", payment_mode: :auto)
IO.puts("Private data stored")
IO.puts("Data map (save this!): #{result.data_map}")
IO.puts("Chunks stored: #{result.chunks_stored}, mode: #{result.payment_mode_used}")

# Retrieve private data using the data map.
{:ok, data} = Antd.Client.data_get(client, result.data_map)
IO.puts("Retrieved: #{data}")

unless data == "my secret message", do: raise "Round-trip mismatch!"
IO.puts("Private data round-trip OK!")
