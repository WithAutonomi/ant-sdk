Mix.install([
  {:antd, path: ".."}
])

# Example 02: Store and retrieve public data, with cost estimation.
#
# Prerequisite: antd daemon running on local testnet.

client = Antd.Client.new()

payload = "Hello, Autonomi!"

# Estimate cost before storing (payment_mode defaults to :auto).
{:ok, est} = Antd.Client.data_cost(client, payload)
IO.puts(
  "Estimate: #{est.file_size} bytes in #{est.chunk_count} chunks, " <>
  "storage #{est.cost} atto, gas #{est.estimated_gas_cost_wei} wei, " <>
  "mode #{est.payment_mode}"
)

# Store public data — public methods KEEP the `_public` suffix.
{:ok, result} = Antd.Client.data_put_public(client, payload, payment_mode: :auto)
IO.puts("Stored at address: #{result.address}")
IO.puts("Chunks stored: #{result.chunks_stored}, mode: #{result.payment_mode_used}")

# Retrieve it back
{:ok, data} = Antd.Client.data_get_public(client, result.address)
IO.puts("Retrieved: #{data}")

unless data == payload, do: raise "Round-trip mismatch!"
IO.puts("Public data round-trip OK!")
