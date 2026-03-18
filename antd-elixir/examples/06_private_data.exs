Mix.install([
  {:antd, path: ".."}
])

# Store and retrieve private (encrypted) data
client = Antd.Client.new()

# Store private data — returns a data_map needed for retrieval
{:ok, result} = Antd.Client.data_put_private(client, "my secret message")
IO.puts("Private data stored")
IO.puts("Cost: #{result.cost} atto")
IO.puts("Data map (save this!): #{result.address}")

# Retrieve private data using the data map
{:ok, data} = Antd.Client.data_get_private(client, result.address)
IO.puts("Retrieved: #{data}")
