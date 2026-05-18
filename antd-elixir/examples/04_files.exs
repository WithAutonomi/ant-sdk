Mix.install([
  {:antd, path: ".."}
])

# Upload and download files
client = Antd.Client.new()

# Upload a file
{:ok, result} = Antd.Client.file_upload_public(client, "/tmp/example.txt")
IO.puts("File uploaded at: #{result.address}")
IO.puts("Storage cost: #{result.storage_cost_atto} atto, gas: #{result.gas_cost_wei} wei")
IO.puts("Chunks stored: #{result.chunks_stored}, mode: #{result.payment_mode_used}")

# Download a file
:ok = Antd.Client.file_download_public(client, result.address, "/tmp/downloaded.txt")
IO.puts("File downloaded to /tmp/downloaded.txt")

# Estimate file upload cost
{:ok, cost} = Antd.Client.file_cost(client, "/tmp/example.txt", true, false)
IO.puts("Estimated upload cost: #{cost.cost} atto (#{cost.chunk_count} chunks)")
