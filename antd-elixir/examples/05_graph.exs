Mix.install([
  {:antd, path: ".."}
])

# Create and query graph entries (DAG nodes)
client = Antd.Client.new()

# Create a graph entry
{:ok, result} =
  Antd.Client.graph_entry_put(client, "secret_key_hex", [], "content_hash", [
    %Antd.GraphDescendant{public_key: "pk_hex", content: "descendant_content"}
  ])

IO.puts("Graph entry created at: #{result.address}")
IO.puts("Cost: #{result.cost} atto")

# Read it back
{:ok, entry} = Antd.Client.graph_entry_get(client, result.address)
IO.puts("Owner: #{entry.owner}")
IO.puts("Content: #{entry.content}")
IO.puts("Parents: #{inspect(entry.parents)}")
IO.puts("Descendants: #{length(entry.descendants)}")

# Check existence
{:ok, exists} = Antd.Client.graph_entry_exists(client, result.address)
IO.puts("Exists: #{exists}")

# Estimate cost
{:ok, cost} = Antd.Client.graph_entry_cost(client, "public_key_hex")
IO.puts("Estimated graph entry cost: #{cost.cost} atto (#{cost.chunk_count} chunks)")
