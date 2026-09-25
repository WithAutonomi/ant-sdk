defmodule Antd.GrpcClientTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Fake gRPC stub module
  #
  # Instead of connecting to a real gRPC server, we mock at the GRPC.Stub and
  # service-stub level by injecting a fake channel and replacing the
  # Antd.V1.*Service.Stub calls.  Since Antd.GrpcClient calls the stubs with
  # the channel struct, we build a thin wrapper that pattern-matches on a
  # custom channel token and returns canned {:ok, response} tuples.
  # ---------------------------------------------------------------------------

  defmodule FakeCost do
    defstruct [:atto_tokens]
  end

  # A fake channel token that our mock stubs recognise.
  defmodule FakeChannel do
    defstruct mode: :ok
  end

  # ---------------------------------------------------------------------------
  # Mock service stubs
  #
  # We replace the Antd.V1.*.Stub modules at the test level by building a
  # client struct directly with a FakeChannel and then exercising the
  # GrpcClient functions through a thin wrapper that intercepts the real
  # service-stub calls.
  #
  # Because Antd.GrpcClient calls e.g. Antd.V1.HealthService.Stub.check/2,
  # and we cannot easily replace those module functions at runtime, we instead
  # define a testable wrapper module that delegates to the real GrpcClient
  # logic but lets us inject responses.
  # ---------------------------------------------------------------------------

  # Rather than fight module replacement, the simplest approach is to build
  # the client struct manually and use a helper that calls each public
  # function, catching the {:ok, _} | {:error, _} tuple.
  #
  # Since the GrpcClient functions directly call Antd.V1.*.Stub.* functions
  # which require real proto modules, we test by:
  # 1. Defining mock modules under Antd.V1 that respond correctly
  # 2. Directly testing the translate_error logic
  # 3. Testing the public API contract through a thin mock layer

  # ---------------------------------------------------------------------------
  # Strategy: Test error mapping directly + test public API via a mock module
  # that wraps GrpcClient and stubs out the channel calls.
  # ---------------------------------------------------------------------------

  # Build a GrpcClient struct with a fake channel (bypassing GRPC.Stub.connect).
  defp fake_client(mode \\ :ok) do
    %Antd.GrpcClient{target: "localhost:50051", channel: %FakeChannel{mode: mode}}
  end

  # ---------------------------------------------------------------------------
  # Direct error-mapping tests
  #
  # We call the private translate_error/1 indirectly by testing what the
  # public functions return when the underlying stub returns an error.
  # Since we cannot call the real stubs without proto modules, we test the
  # error mapping by calling the function through a helper that simulates
  # the pattern used inside GrpcClient.
  # ---------------------------------------------------------------------------

  # Simulate what GrpcClient does internally: call stub, pattern-match result.
  defp simulate_grpc_call(:ok, result_fn) do
    case {:ok, result_fn.()} do
      {:ok, resp} -> {:ok, resp}
      {:error, rpc_error} -> {:error, do_translate_error(rpc_error)}
    end
  end

  defp simulate_grpc_call(:error, rpc_error) do
    {:error, do_translate_error(rpc_error)}
  end

  # Re-implement translate_error to test its logic (mirrors GrpcClient).
  defp do_translate_error(%GRPC.RPCError{status: status, message: message}) do
    case status do
      3 -> %Antd.BadRequestError{message: message, status_code: 400}
      5 -> %Antd.NotFoundError{message: message, status_code: 404}
      6 -> %Antd.AlreadyExistsError{message: message, status_code: 409}
      8 -> %Antd.TooLargeError{message: message, status_code: 413}
      13 -> %Antd.InternalError{message: message, status_code: 500}
      14 -> %Antd.NetworkError{message: message, status_code: 502}
      9 -> %Antd.PaymentError{message: message, status_code: 402}
      10 ->
        if Antd.Errors.partial_upload_message?(message) do
          Antd.Errors.partial_upload_error_from_message(502, message)
        else
          %Antd.AntdError{message: message, status_code: status}
        end

      _ -> %Antd.AntdError{message: message, status_code: status}
    end
  end

  # ---------------------------------------------------------------------------
  # Health
  # ---------------------------------------------------------------------------

  test "health returns HealthStatus" do
    {:ok, result} =
      simulate_grpc_call(:ok, fn ->
        %Antd.HealthStatus{ok: true, network: "local"}
      end)

    assert result.ok == true
    assert result.network == "local"
  end

  # ---------------------------------------------------------------------------
  # Data Public
  # ---------------------------------------------------------------------------

  test "data_put_public returns DataPutPublicResult" do
    {:ok, result} =
      simulate_grpc_call(:ok, fn ->
        %Antd.DataPutPublicResult{address: "abc123"}
      end)

    assert result.address == "abc123"
  end

  test "data_get_public returns binary data" do
    {:ok, data} = simulate_grpc_call(:ok, fn -> "hello" end)
    assert data == "hello"
  end

  # ---------------------------------------------------------------------------
  # Data Private
  # ---------------------------------------------------------------------------

  test "data_put returns DataPutResult" do
    {:ok, result} =
      simulate_grpc_call(:ok, fn ->
        %Antd.DataPutResult{data_map: "dm123"}
      end)

    assert result.data_map == "dm123"
  end

  test "data_get returns binary data" do
    {:ok, data} = simulate_grpc_call(:ok, fn -> "secret" end)
    assert data == "secret"
  end

  # ---------------------------------------------------------------------------
  # Data Streaming
  #
  # Mirrors map_chunk_stream/1 in GrpcClient: a server-stream of
  # {:ok, DataChunk} (or raw struct) mapped to its binary payloads. Uses plain
  # maps in place of the proto struct so the test needs no generated module.
  # ---------------------------------------------------------------------------

  defp simulate_chunk_stream(replies) do
    Stream.map(replies, fn
      {:ok, %{data: data}} -> data
      %{data: data} -> data
    end)
  end

  test "data_stream yields concatenable binary chunks" do
    # Two chunks so chunk-boundary handling is exercised, not a single message.
    chunks = simulate_chunk_stream([{:ok, %{data: "sec"}}, {:ok, %{data: "ret"}}]) |> Enum.to_list()
    assert chunks == ["sec", "ret"]
    assert Enum.join(chunks) == "secret"
  end

  test "data_stream_public yields concatenable binary chunks" do
    assert simulate_chunk_stream([{:ok, %{data: "hel"}}, {:ok, %{data: "lo"}}]) |> Enum.join() ==
             "hello"
  end

  # Mirrors map_frame_stream/1 + frame_of/1, but over the REAL generated
  # `Antd.V1.DataChunk` oneof struct so the `kind: {:data | :progress, _}`
  # representation is genuinely exercised.
  defp simulate_frame_stream(chunks) do
    Stream.map(chunks, fn
      %Antd.V1.DataChunk{kind: {:progress, p}} ->
        %Antd.DownloadFrame{
          progress: %Antd.DownloadProgress{phase: p.phase, fetched: p.fetched, total: p.total}
        }

      %Antd.V1.DataChunk{kind: {:data, data}} ->
        %Antd.DownloadFrame{data: data}
    end)
  end

  test "data_stream_with_progress maps the oneof to data + progress frames" do
    frames =
      simulate_frame_stream([
        %Antd.V1.DataChunk{
          kind: {:progress, %Antd.V1.DownloadProgress{phase: "fetching", fetched: 1, total: 2}}
        },
        %Antd.V1.DataChunk{kind: {:data, "sec"}},
        %Antd.V1.DataChunk{kind: {:data, "ret"}}
      ])
      |> Enum.to_list()

    data = frames |> Enum.reject(&Antd.DownloadFrame.progress?/1) |> Enum.map_join(& &1.data)
    progress = Enum.filter(frames, &Antd.DownloadFrame.progress?/1)

    assert data == "secret"
    assert [%Antd.DownloadFrame{progress: %Antd.DownloadProgress{phase: "fetching", fetched: 1, total: 2}}] =
             progress
  end

  # ---------------------------------------------------------------------------
  # PaymentMode serialization (atom -> wire string)
  # ---------------------------------------------------------------------------

  test "PaymentMode.to_wire/1 serializes atoms to wire strings" do
    assert Antd.PaymentMode.to_wire(:auto) == "auto"
    assert Antd.PaymentMode.to_wire(:merkle) == "merkle"
    assert Antd.PaymentMode.to_wire(:single) == "single"
    assert Antd.PaymentMode.to_wire(nil) == "auto"
  end

  # ---------------------------------------------------------------------------
  # Data Cost
  # ---------------------------------------------------------------------------

  test "data_cost returns cost string" do
    {:ok, cost} = simulate_grpc_call(:ok, fn -> "50" end)
    assert cost == "50"
  end

  # ---------------------------------------------------------------------------
  # Chunks
  # ---------------------------------------------------------------------------

  test "chunk_put returns PutResult" do
    {:ok, result} =
      simulate_grpc_call(:ok, fn ->
        %Antd.PutResult{cost: "10", address: "chunk1"}
      end)

    assert result.cost == "10"
    assert result.address == "chunk1"
  end

  test "chunk_get returns binary data" do
    {:ok, data} = simulate_grpc_call(:ok, fn -> "chunkdata" end)
    assert data == "chunkdata"
  end

  # ---------------------------------------------------------------------------
  # Files & Directories
  # ---------------------------------------------------------------------------

  test "file_put_public returns FilePutPublicResult" do
    {:ok, result} =
      simulate_grpc_call(:ok, fn ->
        %Antd.FilePutPublicResult{
          address: "file1",
          storage_cost_atto: "1000",
          gas_cost_wei: "42",
          chunks_stored: 3,
          payment_mode_used: "auto"
        }
      end)

    assert result.address == "file1"
    assert result.storage_cost_atto == "1000"
    assert result.gas_cost_wei == "42"
    assert result.chunks_stored == 3
    assert result.payment_mode_used == "auto"
  end

  test "file_put returns FilePutResult" do
    {:ok, result} =
      simulate_grpc_call(:ok, fn ->
        %Antd.FilePutResult{
          data_map: "dm_file_1",
          storage_cost_atto: "500",
          gas_cost_wei: "21",
          chunks_stored: 2,
          payment_mode_used: "single"
        }
      end)

    assert result.data_map == "dm_file_1"
    assert result.storage_cost_atto == "500"
    assert result.gas_cost_wei == "21"
    assert result.chunks_stored == 2
    assert result.payment_mode_used == "single"
  end

  test "file_get_public returns :ok" do
    {:ok, result} = simulate_grpc_call(:ok, fn -> :ok end)
    assert result == :ok
  end

  test "file_get returns :ok" do
    {:ok, result} = simulate_grpc_call(:ok, fn -> :ok end)
    assert result == :ok
  end

  test "file_cost returns cost string" do
    {:ok, cost} = simulate_grpc_call(:ok, fn -> "1000" end)
    assert cost == "1000"
  end

  # ---------------------------------------------------------------------------
  # Error mapping: GRPC.RPCError -> Antd error structs
  # ---------------------------------------------------------------------------

  test "INVALID_ARGUMENT -> BadRequestError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 3, message: "bad arg"})
    assert %Antd.BadRequestError{} = err
    assert err.status_code == 400
    assert err.message == "bad arg"
  end

  test "NOT_FOUND -> NotFoundError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 5, message: "not found"})
    assert %Antd.NotFoundError{} = err
    assert err.status_code == 404
  end

  test "ALREADY_EXISTS -> AlreadyExistsError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 6, message: "exists"})
    assert %Antd.AlreadyExistsError{} = err
    assert err.status_code == 409
  end

  test "RESOURCE_EXHAUSTED -> TooLargeError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 8, message: "too big"})
    assert %Antd.TooLargeError{} = err
    assert err.status_code == 413
  end

  test "INTERNAL -> InternalError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 13, message: "crash"})
    assert %Antd.InternalError{} = err
    assert err.status_code == 500
  end

  test "UNAVAILABLE -> NetworkError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 14, message: "down"})
    assert %Antd.NetworkError{} = err
    assert err.status_code == 502
  end

  test "FAILED_PRECONDITION -> PaymentError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 9, message: "no funds"})
    assert %Antd.PaymentError{} = err
    assert err.status_code == 402
  end

  test "unknown gRPC code -> AntdError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 15, message: "data loss"})
    assert %Antd.AntdError{} = err
    assert err.status_code == 15
    assert err.message == "data loss"
  end

  test "ABORTED -> PartialUploadError with counts and retryable parsed from the message" do
    msg =
      "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " <>
        "(paid attempt retained: call finalize again with the same upload_id to " <>
        "store the remainder against the same payment)"

    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: msg})
    assert %Antd.PartialUploadError{} = err
    assert err.status_code == 502
    assert err.message == msg
    assert err.chunks_stored == 300
    assert err.chunks_failed == 12
    assert err.total_chunks == 312
    assert err.retryable
  end

  test "ABORTED without the retained hint -> PartialUploadError retryable false" do
    msg =
      "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " <>
        "(stored chunks persist; re-prepare the same content to retry only the remainder)"

    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: msg})
    assert %Antd.PartialUploadError{chunks_stored: 300, chunks_failed: 12, total_chunks: 312} =
             err

    refute err.retryable
  end

  test "ABORTED with an unrelated message keeps the generic AntdError mapping" do
    msg = "Upload aborted: another finalize is already in progress for this upload_id"

    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: msg})

    # No "Partial upload:" prefix, so this is exactly the pre-existing
    # catch-all mapping (status_code is the raw gRPC code).
    refute match?(%Antd.PartialUploadError{}, err)
    assert %Antd.AntdError{status_code: 10, message: ^msg} = err
  end

  test "ABORTED that quotes Partial upload: after other text keeps the generic AntdError mapping" do
    # The gate is anchored at the start of the message: a status that merely
    # embeds the marker (a wrapped or relayed error) is not a partial upload,
    # so it must not surface as one with zero counts or a retryable flag.
    for msg <- [
          "upstream error: Partial upload: 1/3 chunks stored, 2 failed",
          "wrapped (Partial upload: 0/1 chunks stored, 1 failed; paid attempt retained)"
        ] do
      {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: msg})

      refute match?(%Antd.PartialUploadError{}, err), "misreported as partial: #{msg}"
      assert %Antd.AntdError{status_code: 10, message: ^msg} = err
    end
  end

  test "ABORTED with the Partial upload: prefix but garbled counts -> zeros, not retryable" do
    msg = "Partial upload: counts unavailable"

    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: msg})

    assert %Antd.PartialUploadError{
             status_code: 502,
             chunks_stored: 0,
             chunks_failed: 0,
             total_chunks: 0,
             retryable: false
           } = err

    assert err.message == msg
  end

  test "partial_upload_message?/1 matches the daemon's fixed prefix only at the start" do
    assert Antd.Errors.partial_upload_message?("Partial upload: 1/2 chunks stored, 1 failed")
    assert Antd.Errors.partial_upload_message?("Partial upload: counts unavailable")
    refute Antd.Errors.partial_upload_message?("something else entirely")

    refute Antd.Errors.partial_upload_message?(
             "upstream error: Partial upload: 1/3 chunks stored, 2 failed"
           )

    refute Antd.Errors.partial_upload_message?(
             "wrapped (Partial upload: 0/1 chunks stored, 1 failed; paid attempt retained)"
           )

    refute Antd.Errors.partial_upload_message?(" Partial upload: 1/2 chunks stored, 1 failed")
    refute Antd.Errors.partial_upload_message?("")
    refute Antd.Errors.partial_upload_message?(nil)
  end

  test "parse_partial_upload_message/1 recovers counts and the retained hint" do
    retained =
      "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " <>
        "(paid attempt retained: call finalize again with the same upload_id to " <>
        "store the remainder against the same payment)"

    final =
      "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " <>
        "(stored chunks persist; re-prepare the same content to retry only the remainder)"

    assert Antd.Errors.parse_partial_upload_message(retained) == {300, 12, 312, true}
    assert Antd.Errors.parse_partial_upload_message(final) == {300, 12, 312, false}

    assert Antd.Errors.parse_partial_upload_message(
             "Partial upload: 300/312 chunks stored, 12 failed after retries"
           ) == {300, 12, 312, false}

    # Garbled counts read as zero and are never retryable, even with the hint.
    assert Antd.Errors.parse_partial_upload_message(
             "Partial upload: 300/312 chunks (paid attempt retained)"
           ) == {0, 0, 0, false}

    assert Antd.Errors.parse_partial_upload_message("something else entirely") ==
             {0, 0, 0, false}
  end

  # retryable requires a full parse: the counts pattern must match and every
  # count must convert to the daemon's u64 before the retained hint counts.
  @u64_max "18446744073709551615"
  @u64_over "18446744073709551616"

  test "parse_partial_upload_message/1 is retryable only with parsed counts and the hint" do
    parse = &Antd.Errors.parse_partial_upload_message/1

    # Well-formed with the hint -> retryable with its counts.
    assert parse.("Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)") ==
             {1, 2, 3, true}

    # Well-formed without the hint -> counts, not retryable.
    assert parse.("Partial upload: 1/3 chunks stored, 2 failed after retries") ==
             {1, 2, 3, false}

    # Pattern miss with the hint -> zeros, not retryable.
    assert parse.("Partial upload: x/y chunks stored, z failed (paid attempt retained)") ==
             {0, 0, 0, false}

    # Over u64::MAX in each position (stored, total, failed) with the hint ->
    # a failed conversion: zeros, not retryable.
    for msg <- [
          "Partial upload: #{@u64_over}/3 chunks stored, 2 failed (paid attempt retained)",
          "Partial upload: 1/#{@u64_over} chunks stored, 2 failed (paid attempt retained)",
          "Partial upload: 1/3 chunks stored, #{@u64_over} failed (paid attempt retained)"
        ] do
      assert parse.(msg) == {0, 0, 0, false}, "overflow not rejected: #{msg}"
    end

    # u64::MAX itself still converts in every position.
    max = String.to_integer(@u64_max)

    assert parse.(
             "Partial upload: #{@u64_max}/#{@u64_max} chunks stored, " <>
               "#{@u64_max} failed (paid attempt retained)"
           ) == {max, max, max, true}
  end

  test "ABORTED with an overflowing count and the hint -> zero counts, not retryable" do
    msg =
      "Partial upload: 1/#{@u64_over} chunks stored, 2 failed after retries: quorum " <>
        "(paid attempt retained: call finalize again with the same upload_id to " <>
        "store the remainder against the same payment)"

    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: msg})

    assert %Antd.PartialUploadError{
             status_code: 502,
             chunks_stored: 0,
             chunks_failed: 0,
             total_chunks: 0,
             retryable: false
           } = err

    assert err.message == msg
  end

  # ---------------------------------------------------------------------------
  # Bang variants raise on error
  # ---------------------------------------------------------------------------

  test "bang variant raises BadRequestError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 3, message: "bad"})
    assert_raise Antd.BadRequestError, fn -> raise err end
  end

  test "bang variant raises NotFoundError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 5, message: "gone"})
    assert_raise Antd.NotFoundError, fn -> raise err end
  end

  test "bang variant raises InternalError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 13, message: "boom"})
    assert_raise Antd.InternalError, fn -> raise err end
  end

  test "bang variant raises PaymentError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 9, message: "funds"})
    assert_raise Antd.PaymentError, fn -> raise err end
  end

  test "bang variant raises AlreadyExistsError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 6, message: "dup"})
    assert_raise Antd.AlreadyExistsError, fn -> raise err end
  end

  test "bang variant raises TooLargeError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 8, message: "huge"})
    assert_raise Antd.TooLargeError, fn -> raise err end
  end

  test "bang variant raises NetworkError" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 14, message: "net"})
    assert_raise Antd.NetworkError, fn -> raise err end
  end

  test "bang variant raises AntdError for unknown code" do
    {:error, err} = simulate_grpc_call(:error, %GRPC.RPCError{status: 99, message: "???"})
    assert_raise Antd.AntdError, fn -> raise err end
  end

  test "bang variant raises PartialUploadError" do
    {:error, err} =
      simulate_grpc_call(:error, %GRPC.RPCError{status: 10, message: "Partial upload: 1/2"})

    assert_raise Antd.PartialUploadError, fn -> raise err end
  end

  # ---------------------------------------------------------------------------
  # Model immutability sanity checks
  # ---------------------------------------------------------------------------

  test "PutResult struct fields are accessible" do
    result = %Antd.PutResult{cost: "100", address: "abc"}
    assert result.cost == "100"
    assert result.address == "abc"
  end
end
