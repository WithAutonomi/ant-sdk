Mix.install([
  {:antd, path: ".."}
])

# Upload and download files and directories, with round-trip assertions.
client = Antd.Client.new()

tmp = Path.join(System.tmp_dir!(), "antd-elixir-04-files")
File.rm_rf!(tmp)
File.mkdir_p!(tmp)

file_content = "Hello from a file on Autonomi!"
dir_file_content = "File inside an uploaded directory."

src_file = Path.join(tmp, "hello.txt")
File.write!(src_file, file_content)

src_dir = Path.join(tmp, "mydir")
File.mkdir_p!(src_dir)
File.write!(Path.join(src_dir, "file_in_dir.txt"), dir_file_content)

{:ok, cost} = Antd.Client.file_cost(client, src_file, true, false)
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

{:ok, dir_result} = Antd.Client.dir_upload_public(client, src_dir)
IO.puts("Directory uploaded at: #{dir_result.address}")

dst_dir = Path.join(tmp, "mydir_copy")
:ok = Antd.Client.dir_download_public(client, dir_result.address, dst_dir)
IO.puts("Directory downloaded to #{dst_dir}")

got_dir_file = File.read!(Path.join(dst_dir, "file_in_dir.txt"))

if got_dir_file != dir_file_content do
  File.rm_rf!(tmp)
  IO.puts(:stderr, "directory round-trip mismatch on file_in_dir.txt")
  System.halt(1)
end

File.rm_rf!(tmp)
IO.puts("File and directory upload/download OK!")
