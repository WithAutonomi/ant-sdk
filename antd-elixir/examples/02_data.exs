Mix.install([
  {:antd, path: ".."}
])

# Store and retrieve public immutable data
client = Antd.Client.new()

# Store data
{:ok, result} = Antd.Client.data_put_public(client, "Hello, Autonomi!")
IO.puts("Stored at: #{result.address}")
IO.puts("Cost: #{result.cost} atto")

# Retrieve data
{:ok, data} = Antd.Client.data_get_public(client, result.address)
IO.puts("Retrieved: #{data}")

# Estimate cost before storing
{:ok, cost} = Antd.Client.data_cost(client, "Some data to estimate")
IO.puts("Estimated cost: #{cost} atto")
