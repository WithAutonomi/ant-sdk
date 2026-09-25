defmodule Antd.GrpcExternalSignerTest do
  @moduledoc """
  V2-284 wire-mapping tests for `Antd.GrpcClient` external-signer surface.

  Spins up a real grpc-elixir server on a random port with mock service
  implementations, then dials with a real `Antd.GrpcClient`. Mirrors the
  antd-rust / antd-go / antd-py / antd-java / antd-kotlin / antd-csharp /
  antd-ruby / antd-dart / antd-swift / antd-cpp suites — exercises the
  actual proto wire-shape mapping (merkle-only field gating, visibility
  round-trip via `upload_id` encoding, EXISTS short-circuit).
  """
  use ExUnit.Case, async: false

  alias Antd.GrpcClient

  defmodule MockUploadServer do
    use GRPC.Server, service: Antd.V1.UploadService.Service

    @spec prepare_file_upload(Antd.V1.PrepareFileUploadRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.PrepareUploadResponse.t()
    def prepare_file_upload(req, _stream) do
      %Antd.V1.PrepareUploadResponse{
        upload_id: "upid_file_" <> req.visibility,
        payment_type: "wave_batch",
        total_amount: "1",
        payment_vault_address: "0xvault",
        payment_token_address: "0xtoken",
        rpc_url: "http://localhost:8545",
        total_chunks: 3,
        already_stored_count: 1,
        payments: [
          %Antd.V1.PaymentEntry{quote_hash: "0xqa", rewards_address: "0xra", amount: "1"}
        ]
      }
    end

    @spec prepare_data_upload(Antd.V1.PrepareDataUploadRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.PrepareUploadResponse.t()
    def prepare_data_upload(req, _stream) do
      uid = "upid_data_" <> req.visibility

      # Payload starting "MERKLE" triggers the merkle response shape.
      case req.data do
        <<"MERKLE", _::binary>> ->
          %Antd.V1.PrepareUploadResponse{
            upload_id: uid,
            payment_type: "merkle",
            depth: 7,
            merkle_payment_timestamp: 1_700_000_000,
            total_amount: "0",
            payment_vault_address: "0xvault",
            payment_token_address: "0xtoken",
            rpc_url: "http://localhost:8545",
            pool_commitments: [
              %Antd.V1.PoolCommitmentEntry{
                pool_hash: "0xpool",
                candidates: [
                  %Antd.V1.CandidateNodeEntry{rewards_address: "0xc1", amount: "5"}
                ]
              }
            ]
          }

        _ ->
          %Antd.V1.PrepareUploadResponse{
            upload_id: uid,
            payment_type: "wave_batch",
            total_amount: "2",
            payment_vault_address: "0xvault",
            payment_token_address: "0xtoken",
            rpc_url: "http://localhost:8545",
            payments: [
              %Antd.V1.PaymentEntry{quote_hash: "0xqb", rewards_address: "0xrb", amount: "2"}
            ]
          }
      end
    end

    @spec finalize_upload(Antd.V1.FinalizeUploadRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.FinalizeUploadResponse.t()
    def finalize_upload(req, _stream) do
      cond do
        # PARTIAL_UPLOAD after the daemon retained the paid attempt: ABORTED
        # with the counts and the "paid attempt retained" hint in the message.
        req.upload_id == "partial_retained" ->
          raise GRPC.RPCError,
            status: GRPC.Status.aborted(),
            message:
              "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " <>
                "(paid attempt retained: call finalize again with the same upload_id to " <>
                "store the remainder against the same payment)"

        # PARTIAL_UPLOAD with nothing retained (unpaid merkle batches / older
        # daemon): same status, re-prepare hint instead.
        req.upload_id == "partial_final" ->
          raise GRPC.RPCError,
            status: GRPC.Status.aborted(),
            message:
              "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " <>
                "(stored chunks persist; re-prepare the same content to retry only the remainder)"

        # Any other ABORTED (no "Partial upload:" prefix) is not a partial
        # upload and must keep the generic error mapping.
        req.upload_id == "aborted_other" ->
          raise GRPC.RPCError,
            status: GRPC.Status.aborted(),
            message: "Upload aborted: another finalize is already in progress"

        # An ABORTED that only quotes the marker further into its message
        # (a wrapped error) is not a partial upload either.
        req.upload_id == "aborted_embedded" ->
          raise GRPC.RPCError,
            status: GRPC.Status.aborted(),
            message:
              "upstream error: Partial upload: 1/3 chunks stored, 2 failed " <>
                "(paid attempt retained)"

        req.winner_pool_hash != "" ->
          %Antd.V1.FinalizeUploadResponse{
            data_map: "dm_merkle",
            address: if(req.store_data_map, do: "stored_on_network", else: ""),
            chunks_stored: 64
          }

        String.ends_with?(req.upload_id, "public") ->
          %Antd.V1.FinalizeUploadResponse{
            data_map: "dm_wave",
            data_map_address: "addr_public_dm",
            chunks_stored: 3
          }

        true ->
          %Antd.V1.FinalizeUploadResponse{
            data_map: "dm_wave",
            data_map_address: "",
            chunks_stored: 3
          }
      end
    end
  end

  defmodule MockChunkServer do
    use GRPC.Server, service: Antd.V1.ChunkService.Service

    @spec get(Antd.V1.GetChunkRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.GetChunkResponse.t()
    def get(_req, _stream),
      do: raise(GRPC.RPCError, status: GRPC.Status.unimplemented(), message: "not exercised")

    @spec put(Antd.V1.PutChunkRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.PutChunkResponse.t()
    def put(_req, _stream),
      do: raise(GRPC.RPCError, status: GRPC.Status.unimplemented(), message: "not exercised")

    @spec prepare_chunk(Antd.V1.PrepareChunkRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.PrepareChunkResponse.t()
    def prepare_chunk(req, _stream) do
      case req.data do
        <<"EXISTS", _::binary>> ->
          %Antd.V1.PrepareChunkResponse{address: "0xabc", already_stored: true}

        _ ->
          %Antd.V1.PrepareChunkResponse{
            address: "0xnewchunk",
            already_stored: false,
            upload_id: "upid_chunk_42",
            payment_type: "wave_batch",
            total_amount: "100",
            payment_vault_address: "0xvault",
            payment_token_address: "0xtoken",
            rpc_url: "http://localhost:8545",
            payments: [
              %Antd.V1.PaymentEntry{quote_hash: "0xq1", rewards_address: "0xr1", amount: "100"}
            ]
          }
      end
    end

    @spec finalize_chunk(Antd.V1.FinalizeChunkRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.FinalizeChunkResponse.t()
    def finalize_chunk(req, _stream) do
      %Antd.V1.FinalizeChunkResponse{address: "addr_for_" <> req.upload_id}
    end
  end

  defmodule TestEndpoint do
    use GRPC.Endpoint
    run(MockUploadServer)
    run(MockChunkServer)
  end

  setup_all do
    # `Antd.GrpcClient.new/1` calls `GRPC.Stub.connect/1`, which requires
    # the GRPC client supervisor to be running. grpc-elixir does not start
    # it as part of its application supervision tree, so kick it off here
    # for the duration of this suite.
    case DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  setup do
    {:ok, _pid, port} = GRPC.Server.start_endpoint(TestEndpoint, 0)
    on_exit(fn -> :ok = GRPC.Server.stop_endpoint(TestEndpoint) end)
    {:ok, client} = GrpcClient.new("localhost:#{port}")
    {:ok, client: client}
  end

  # --- prepare/finalize uploads ---

  test "prepare_upload omits visibility (sends empty string)", %{client: client} do
    # Empty visibility = proto3 default → mock echoes that into upload_id.
    {:ok, r} = GrpcClient.prepare_upload(client, "/tmp/x.bin")
    assert r.upload_id == "upid_file_"
    assert r.total_chunks == 3
    assert r.already_stored_count == 1
    assert r.payment_type == "wave_batch"
    assert length(r.payments) == 1
    assert hd(r.payments).quote_hash == "0xqa"
    assert r.depth == 0
    assert r.pool_commitments == []
    assert r.merkle_payment_timestamp == 0
  end

  test "prepare_upload forwards visibility=public", %{client: client} do
    {:ok, r} = GrpcClient.prepare_upload(client, "/tmp/x.bin", visibility: "public")
    assert r.upload_id == "upid_file_public"
  end

  test "prepare_upload_public convenience wrapper", %{client: client} do
    {:ok, r} = GrpcClient.prepare_upload_public(client, "/tmp/x.bin")
    assert r.upload_id == "upid_file_public"
  end

  test "prepare_data_upload wave-batch", %{client: client} do
    {:ok, r} = GrpcClient.prepare_data_upload(client, "small")
    assert r.upload_id == "upid_data_"
    assert r.payment_type == "wave_batch"
    assert r.depth == 0
    assert r.pool_commitments == []
    assert r.merkle_payment_timestamp == 0
  end

  test "prepare_data_upload merkle", %{client: client} do
    {:ok, r} = GrpcClient.prepare_data_upload(client, "MERKLE-large-payload")
    assert r.payment_type == "merkle"
    assert r.depth == 7
    assert r.merkle_payment_timestamp == 1_700_000_000
    assert length(r.pool_commitments) == 1
    pc = hd(r.pool_commitments)
    assert pc.pool_hash == "0xpool"
    assert hd(pc.candidates).rewards_address == "0xc1"
  end

  test "finalize_upload wave-batch private omits data_map_address", %{client: client} do
    {:ok, r} = GrpcClient.finalize_upload(client, "upid_file_", %{"0xq1" => "0xtx1"})
    assert r.data_map == "dm_wave"
    assert r.data_map_address == ""
    assert r.chunks_stored == 3
  end

  test "finalize_upload wave-batch public returns data_map_address", %{client: client} do
    {:ok, r} = GrpcClient.finalize_upload(client, "upid_file_public", %{"0xq1" => "0xtx1"})
    assert r.data_map_address == "addr_public_dm"
  end

  test "finalize_merkle_upload store_data_map=true", %{client: client} do
    {:ok, r} =
      GrpcClient.finalize_merkle_upload(client, "upid_data_", "0xwinpool", store_data_map: true)

    assert r.data_map == "dm_merkle"
    assert r.address == "stored_on_network"
    assert r.chunks_stored == 64
  end

  test "finalize_merkle_upload store_data_map default false", %{client: client} do
    {:ok, r} = GrpcClient.finalize_merkle_upload(client, "upid_data_", "0xwinpool")
    assert r.data_map == "dm_merkle"
    assert r.address == ""
  end

  test "finalize_upload ABORTED maps to PartialUploadError with parsed counts",
       %{client: client} do
    {:error, err} = GrpcClient.finalize_upload(client, "partial_retained", %{"0xq1" => "0xtx1"})

    # Counts and the retained hint are parsed from the status message, so
    # the gRPC client matches the REST client's typed error.
    assert %Antd.PartialUploadError{
             status_code: 502,
             chunks_stored: 300,
             chunks_failed: 12,
             total_chunks: 312,
             retryable: true
           } = err

    assert String.starts_with?(err.message, "Partial upload: 300/312 chunks stored")
  end

  test "finalize_merkle_upload ABORTED without the retained hint is not retryable",
       %{client: client} do
    {:error, err} = GrpcClient.finalize_merkle_upload(client, "partial_final", "0xwinpool")

    assert %Antd.PartialUploadError{chunks_stored: 300, chunks_failed: 12, total_chunks: 312} =
             err

    refute err.retryable
  end

  test "finalize_upload ABORTED without the partial-upload prefix stays a generic AntdError",
       %{client: client} do
    {:error, err} = GrpcClient.finalize_upload(client, "aborted_other", %{"0xq1" => "0xtx1"})

    refute match?(%Antd.PartialUploadError{}, err)
    assert %Antd.AntdError{status_code: 10} = err
    assert err.message =~ "another finalize is already in progress"
  end

  test "finalize_upload ABORTED that only quotes the prefix mid-message stays a generic AntdError",
       %{client: client} do
    {:error, err} =
      GrpcClient.finalize_upload(client, "aborted_embedded", %{"0xq1" => "0xtx1"})

    refute match?(%Antd.PartialUploadError{}, err)
    assert %Antd.AntdError{status_code: 10} = err
    assert String.starts_with?(err.message, "upstream error: Partial upload:")
  end

  # --- prepare/finalize chunks ---

  test "prepare_chunk_upload new chunk", %{client: client} do
    {:ok, r} = GrpcClient.prepare_chunk_upload(client, "newchunk")
    refute r.already_stored
    assert r.address == "0xnewchunk"
    assert r.upload_id == "upid_chunk_42"
    assert r.payment_type == "wave_batch"
    assert length(r.payments) == 1
    assert hd(r.payments).quote_hash == "0xq1"
    assert r.total_amount == "100"
    assert r.rpc_url == "http://localhost:8545"
  end

  test "prepare_chunk_upload already-stored short-circuit", %{client: client} do
    {:ok, r} = GrpcClient.prepare_chunk_upload(client, "EXISTS-data")
    assert r.already_stored
    assert r.address == "0xabc"
    assert r.upload_id == ""
    assert r.payments == []
  end

  test "finalize_chunk_upload returns address and forwards body", %{client: client} do
    {:ok, addr} = GrpcClient.finalize_chunk_upload(client, "upid_chunk_42", %{"0xq1" => "0xtxabc"})
    assert addr == "addr_for_upid_chunk_42"
  end
end
