Mix.install([
  {:antd, path: ".."}
])

# Upload and download files and directories
client = Antd.Client.new()

# Upload a file
{:ok, result} = Antd.Client.file_upload_public(client, "/tmp/example.txt")
IO.puts("File uploaded at: #{result.address}")
IO.puts("Cost: #{result.cost} atto")

# Download a file
:ok = Antd.Client.file_download_public(client, result.address, "/tmp/downloaded.txt")
IO.puts("File downloaded to /tmp/downloaded.txt")

# Upload a directory
{:ok, dir_result} = Antd.Client.dir_upload_public(client, "/tmp/mydir")
IO.puts("Directory uploaded at: #{dir_result.address}")

# Download a directory
:ok = Antd.Client.dir_download_public(client, dir_result.address, "/tmp/mydir_copy")
IO.puts("Directory downloaded to /tmp/mydir_copy")

# Estimate file upload cost
{:ok, cost} = Antd.Client.file_cost(client, "/tmp/example.txt", true, false)
IO.puts("Estimated upload cost: #{cost} atto")
