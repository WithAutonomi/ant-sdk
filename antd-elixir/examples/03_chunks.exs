Mix.install([
  {:antd, path: ".."}
])

# Store and retrieve raw chunks
client = Antd.Client.new()

# Store a chunk
{:ok, result} = Antd.Client.chunk_put(client, "raw chunk data")
IO.puts("Chunk stored at: #{result.address}")
IO.puts("Cost: #{result.cost} atto")

# Retrieve the chunk
{:ok, data} = Antd.Client.chunk_get(client, result.address)
IO.puts("Retrieved chunk: #{data}")
