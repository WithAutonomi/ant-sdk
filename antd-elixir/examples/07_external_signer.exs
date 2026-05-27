Mix.install([
  {:antd, path: ".."}
])

# Example 07: External-signer flow — public file + single-chunk publish.
#
# PR #90 added prepare_upload_public / finalize_upload and prepare_chunk_upload
# / finalize_chunk_upload so the wallet key never has to live in the antd
# daemon. This example uses anvil deterministic account #0 as the external
# signer and exercises both round-trips end-to-end.
#
# See docs/external-signer-flow.md for the full reference. Elixir does not
# have a first-party EVM lib that handles EIP-1559 + tuple ABI encoding +
# secp256k1 signing in a way that's both robust against version drift and
# small enough for an example. This example shells out to `cast` (foundry
# CLI) which is already a hard dependency of `ant dev start --enable-evm`.

# Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
# (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
# use this key anywhere except a throw-away local devnet.
anvil_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
max_uint256 = String.duplicate("f", 64)

defmodule ExternalSigner do
  @moduledoc false

  def pay(_rpc_url, _vault_addr, _token_addr, [], _key), do: %{}

  def pay(rpc_url, vault_addr, token_addr, payments, key) do
    # Idempotent unlimited approval so subsequent runs in the same devnet
    # session skip a fresh approve.
    {_, 0} =
      System.cmd("cast", [
        "send", token_addr,
        "approve(address,uint256)",
        vault_addr,
        "0x" <> String.duplicate("f", 64),
        "--rpc-url", rpc_url,
        "--private-key", key,
        "--gas-limit", "500000",
        "--json"
      ])

    tuples =
      payments
      |> Enum.map(fn p ->
        qh = String.replace_prefix(p.quote_hash, "0x", "")
        "(#{p.rewards_address},#{p.amount},0x#{qh})"
      end)
      |> Enum.join(",")

    {pay_json, 0} =
      System.cmd("cast", [
        "send", vault_addr,
        "payForQuotes((address,uint256,bytes32)[])",
        "[#{tuples}]",
        "--rpc-url", rpc_url,
        "--private-key", key,
        "--gas-limit", "1000000",
        "--json"
      ])

    %{"transactionHash" => tx_hash} = Jason.decode!(pay_json)

    # Every quote in this wave was paid in the same call.
    Enum.into(payments, %{}, fn p -> {p.quote_hash, tx_hash} end)
  end
end

client = Antd.Client.new()

tmp = Path.join(System.tmp_dir!(), "antd-elixir-07-extsig-#{:rand.uniform(1_000_000)}")
File.mkdir_p!(tmp)

try do
  # --- 1. file upload via external signer ---------------------------
  src = Path.join(tmp, "file.bin")
  File.write!(src, String.duplicate("hello external signer from elixir (file)\n", 16))

  {:ok, file_prep} = Antd.Client.prepare_upload_public(client, src)

  IO.puts(
    "File prepare: upload_id=#{String.slice(file_prep.upload_id, 0, 16)}..., " <>
      "payment_type=#{file_prep.payment_type}, " <>
      "payments=#{length(file_prep.payments)}, total_amount=#{file_prep.total_amount}"
  )

  file_tx_hashes =
    ExternalSigner.pay(
      file_prep.rpc_url,
      file_prep.payment_vault_address,
      file_prep.payment_token_address,
      file_prep.payments,
      anvil_key
    )

  {:ok, file_fin} = Antd.Client.finalize_upload(client, file_prep.upload_id, file_tx_hashes)

  IO.puts(
    "File finalize: data_map_address=#{file_fin.data_map_address}, " <>
      "chunks_stored=#{file_fin.chunks_stored}"
  )

  dst = src <> ".downloaded"
  :ok = Antd.Client.file_get_public(client, file_fin.data_map_address, dst)

  unless File.read!(dst) == File.read!(src) do
    IO.puts(:stderr, "file round-trip mismatch")
    System.halt(1)
  end

  IO.puts("File round-trip OK!")

  # --- 2. single-chunk publish via external signer ------------------
  chunk_data = String.duplicate("hello external signer from elixir (chunk)\n", 8)
  {:ok, chunk_prep} = Antd.Client.prepare_chunk_upload(client, chunk_data)

  if chunk_prep.already_stored do
    IO.puts("Chunk prepare: already_stored, address=#{chunk_prep.address}")
  else
    IO.puts(
      "Chunk prepare: upload_id=#{String.slice(chunk_prep.upload_id, 0, 16)}..., " <>
        "address=#{chunk_prep.address}, payments=#{length(chunk_prep.payments)}, " <>
        "total_amount=#{chunk_prep.total_amount}"
    )

    chunk_tx_hashes =
      ExternalSigner.pay(
        chunk_prep.rpc_url,
        chunk_prep.payment_vault_address,
        chunk_prep.payment_token_address,
        chunk_prep.payments,
        anvil_key
      )

    {:ok, chunk_addr} =
      Antd.Client.finalize_chunk_upload(client, chunk_prep.upload_id, chunk_tx_hashes)

    IO.puts("Chunk finalize: address=#{chunk_addr}")
  end

  retrieved = Antd.Client.chunk_get!(client, chunk_prep.address)

  unless retrieved == chunk_data do
    IO.puts(:stderr, "chunk round-trip mismatch")
    System.halt(1)
  end

  IO.puts("Chunk round-trip OK!")
  IO.puts("\n07_external_signer OK!\n")
after
  File.rm_rf!(tmp)
end
