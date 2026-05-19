Mix.install([
  {:antd, path: ".."}
])

# Upload and download files and directories, with round-trip assertions.
client = Antd.Client.new()

tmp = Path.join(System.tmp_dir!(), "antd-elixir-04-files")
File.rm_rf!(tmp)
File.mkdir_p!(tmp)

file_content = "Hello from a file on Autonomi!"

src_file = Path.join(tmp, "hello.txt")
File.write!(src_file, file_content)

{:ok, cost} = Antd.Client.file_cost(client, src_file, true)
IO.puts("Estimated upload cost: #{cost.cost} atto (#{cost.chunk_count} chunks)")

{:ok, result} = Antd.Client.file_upload_public(client, src_file)
IO.puts("File uploaded at: #{result.address}")
IO.puts("Storage cost: #{result.storage_cost_atto} atto, gas: #{result.gas_cost_wei} wei")
IO.puts("Chunks stored: #{result.chunks_stored}, mode: #{result.payment_mode_used}")

dst_file = Path.join(tmp, "hello.txt.downloaded")
:ok = Antd.Client.file_download_public(client, result.address, dst_file)
IO.puts("File downloaded to #{dst_file}")

got = File.read!(dst_file)

if got != file_content do
  File.rm_rf!(tmp)
  IO.puts(:stderr, "round-trip mismatch on hello.txt")
  System.halt(1)
end

File.rm_rf!(tmp)
IO.puts("File upload/download OK!")
