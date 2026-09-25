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
# A finalize can also fail *after* the payment settled: some chunks store,
# others miss quorum. `finalize_with_retry/3` below shows the bounded
# same-payment retry the daemon's PARTIAL_UPLOAD contract allows.
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

  @max_finalize_attempts 5

  # Finalize with a bounded same-payment retry.
  #
  # A finalize that stored only part of the upload returns
  # `%Antd.PartialUploadError{}`. When the daemon says `retryable: true` it
  # kept the paid attempt under the same upload_id, so the very same call
  # again stores the remainder against the same payment (no re-prepare, no
  # second signature, no double payment). A persistent failure (a chunk whose
  # close group stays unreachable) returns that error on every call, never a
  # different one, so the loop caps the attempts and treats a `chunks_failed`
  # that stops shrinking as stuck. A non-retryable partial upload (older
  # daemon, or a merkle upload with unpaid batches) is returned untouched:
  # the recovery there is to re-prepare the same content, which skips the
  # chunks already stored. (Over gRPC, a non-retryable error with all counts
  # 0 means the message could not be parsed: retention is unconfirmed, so
  # check before paying again.)
  def finalize_with_retry(client, upload_id, tx_hashes, attempt \\ 1, last_failed \\ nil) do
    case Antd.Client.finalize_upload(client, upload_id, tx_hashes) do
      {:ok, _} = ok ->
        # every chunk stored
        ok

      {:error, %Antd.PartialUploadError{retryable: true} = err} ->
        stuck = last_failed != nil and err.chunks_failed >= last_failed

        if attempt >= @max_finalize_attempts or stuck do
          IO.puts(
            :stderr,
            "finalize stuck after #{attempt} attempt(s): " <>
              "#{err.chunks_stored}/#{err.total_chunks} chunks stored, " <>
              "#{err.chunks_failed} still unstored (paid attempt retained under " <>
              "upload_id #{upload_id} — retry later or re-prepare)"
          )

          {:error, err}
        else
          IO.puts(
            "finalize stored #{err.chunks_stored}/#{err.total_chunks} chunks, " <>
              "#{err.chunks_failed} still unstored — retrying against the same payment " <>
              "(attempt #{attempt + 1}/#{@max_finalize_attempts})"
          )

          Process.sleep(attempt * 2_000)
          finalize_with_retry(client, upload_id, tx_hashes, attempt + 1, err.chunks_failed)
        end

      # Non-retryable partial upload or any other error: hand it back as-is.
      {:error, _} = err ->
        err
    end
  end

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

  {:ok, file_fin} =
    ExternalSigner.finalize_with_retry(client, file_prep.upload_id, file_tx_hashes)

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
