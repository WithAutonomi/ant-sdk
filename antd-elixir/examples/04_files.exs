Mix.install([
  {:antd, path: ".."}
])

# Upload and download files, with round-trip assertions.
#
# Public file methods keep the `_public` suffix; private file methods are
# the unqualified `file_put` / `file_get`.
client = Antd.Client.new()

tmp = Path.join(System.tmp_dir!(), "antd-elixir-04-files")
File.rm_rf!(tmp)
File.mkdir_p!(tmp)

file_content = "Hello from a file on Autonomi!"

src_file = Path.join(tmp, "hello.txt")
File.write!(src_file, file_content)

# ---- Public upload/download ----

{:ok, cost} = Antd.Client.file_cost(client, src_file, true)
IO.puts("Estimated upload cost: #{cost.cost} atto (#{cost.chunk_count} chunks)")

{:ok, result} = Antd.Client.file_put_public(client, src_file, payment_mode: :auto)
IO.puts("File uploaded at: #{result.address}")
IO.puts("Storage cost: #{result.storage_cost_atto} atto, gas: #{result.gas_cost_wei} wei")
IO.puts("Chunks stored: #{result.chunks_stored}, mode: #{result.payment_mode_used}")

dst_file = Path.join(tmp, "hello.txt.downloaded")
:ok = Antd.Client.file_get_public(client, result.address, dst_file)
IO.puts("File downloaded to #{dst_file}")

got = File.read!(dst_file)

if got != file_content do
  File.rm_rf!(tmp)
  IO.puts(:stderr, "round-trip mismatch on hello.txt")
  System.halt(1)
end

# ---- Private upload/download ----

src_priv = Path.join(tmp, "secret.txt")
File.write!(src_priv, file_content)

{:ok, priv_result} = Antd.Client.file_put(client, src_priv, payment_mode: :auto)
IO.puts("Private file uploaded — keep this data_map: #{priv_result.data_map}")
IO.puts("Chunks stored: #{priv_result.chunks_stored}, mode: #{priv_result.payment_mode_used}")

priv_dst = Path.join(tmp, "secret.txt.downloaded")
:ok = Antd.Client.file_get(client, priv_result.data_map, priv_dst)

got_priv = File.read!(priv_dst)

if got_priv != file_content do
  File.rm_rf!(tmp)
  IO.puts(:stderr, "round-trip mismatch on secret.txt")
  System.halt(1)
end

File.rm_rf!(tmp)
IO.puts("File upload/download OK!")
