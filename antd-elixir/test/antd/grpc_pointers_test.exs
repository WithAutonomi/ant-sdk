defmodule Antd.GrpcPointersTest do
  @moduledoc """
  gRPC pointer API against a real grpc-elixir server with a mock
  PointerService, dialled with a real `Antd.GrpcClient`: request and
  response mapping, unset values, counters, and the `x-antd-error-code`
  metadata the daemon tags shared-status errors with.
  """
  use ExUnit.Case, async: false

  alias Antd.GrpcClient

  @owner String.duplicate("a1", 32)
  @recipient String.duplicate("b2", 32)
  @target String.duplicate("c3", 32)
  @max_u64 18_446_744_073_709_551_615

  @retained_hint "(paid attempt retained: call finalize again with the same upload_id to " <>
                   "store it against the same payment)"

  defmodule MockPointerServer do
    use GRPC.Server, service: Antd.V1.PointerService.Service

    @owner String.duplicate("a1", 32)
    @recipient String.duplicate("b2", 32)
    @target String.duplicate("c3", 32)
    @state_id String.duplicate("d4", 32)

    # Fails the call the way the daemon does: the status, plus its error
    # code as metadata. `:trailers_only` is how tonic answers a failed unary
    # call (one HEADERS frame ending the stream); `:headers_first` sends the
    # metadata in response headers ahead of the error trailers.
    defp fail(stream, status, message, tag \\ nil, mode \\ :trailers_only) do
      if tag do
        case mode do
          :trailers_only -> GRPC.Server.set_headers(stream, %{"x-antd-error-code" => tag})
          :headers_first -> GRPC.Server.send_headers(stream, %{"x-antd-error-code" => tag})
        end
      end

      raise GRPC.RPCError, status: status, message: message
    end

    def list_keys(_req, _stream) do
      %Antd.V1.ListPointerKeysResponse{
        keys: [%Antd.V1.PointerKey{address: @owner}, %Antd.V1.PointerKey{address: @recipient}]
      }
    end

    # The owner picks the behaviour.
    def create(req, stream) do
      case req.owner do
        "final" ->
          fail(stream, GRPC.Status.failed_precondition(), "Pointer is final: x", "POINTER_FINAL")

        "final_headers_first" ->
          fail(
            stream,
            GRPC.Status.failed_precondition(),
            "Pointer is final: x",
            "POINTER_FINAL",
            :headers_first
          )

        "forked" ->
          fail(
            stream,
            GRPC.Status.failed_precondition(),
            "Pointer is forked: x",
            "POINTER_FORKED"
          )

        "conflict" ->
          fail(stream, GRPC.Status.aborted(), "Conflict: pending prepare", "CONFLICT")

        "shortfall" ->
          fail(
            stream,
            GRPC.Status.unavailable(),
            "Close group shortfall: 3 of 7",
            "CLOSE_GROUP_SHORTFALL"
          )

        "untagged_precondition" ->
          fail(stream, GRPC.Status.failed_precondition(), "wallet not configured")

        "untagged_unavailable" ->
          fail(stream, GRPC.Status.unavailable(), "network down")

        "exists" ->
          fail(stream, GRPC.Status.already_exists(), "Already exists: pointer")

        # A tag on a status it does not belong to is not trusted.
        "mismatched" ->
          fail(stream, GRPC.Status.unavailable(), "network down", "POINTER_FINAL")

        "unknown_tag" ->
          fail(stream, GRPC.Status.failed_precondition(), "insufficient funds", "SOMETHING_NEW")

        "bad_counter" ->
          %Antd.V1.PointerWriteResponse{address: @owner, state_id: @state_id, counter: "-1"}

        "empty_counter" ->
          %Antd.V1.PointerWriteResponse{address: @owner, state_id: @state_id, counter: ""}

        _ ->
          # Echo the kind into the state id so the test can see it arrived.
          %Antd.V1.PointerWriteResponse{
            address: req.owner,
            state_id: "kind=" <> req.kind <> ";target=" <> req.target,
            counter: "0"
          }
      end
    end

    def update(req, _stream) do
      %Antd.V1.PointerWriteResponse{
        address: req.owner,
        state_id: "kind=" <> req.kind,
        counter: "7"
      }
    end

    def transfer(req, _stream) do
      case req.recipient do
        "unchecked" ->
          %Antd.V1.PointerTransferResponse{
            address: req.owner,
            state_id: @state_id,
            finality_error: "only 3 of 7 answered"
          }

        _ ->
          %Antd.V1.PointerTransferResponse{
            address: req.owner,
            state_id: @state_id,
            finality: %Antd.V1.PointerFinality{
              address: req.owner,
              group: 7,
              answered: 7,
              status: "final",
              state: %Antd.V1.PointerFinalState{
                state_id: @state_id,
                kind: "pointer",
                kind_tag: 1,
                target: req.recipient,
                holders: 7,
                transferred_to: req.recipient
              },
              transferred_to: req.recipient
            }
          }
      end
    end

    def get(req, stream) do
      case req.address do
        "missing" ->
          fail(stream, GRPC.Status.not_found(), "no pointer")

        "open" ->
          %Antd.V1.PointerRecord{
            address: req.address,
            owner: "ab",
            counter: "3",
            kind: "chunk",
            kind_tag: 0,
            target: @target,
            state_id: @state_id
          }

        _ ->
          %Antd.V1.PointerRecord{
            address: req.address,
            owner: "ab",
            counter: "18446744073709551615",
            kind: "pointer",
            kind_tag: 1,
            target: @recipient,
            state_id: @state_id,
            is_final: true,
            transferred_to: @recipient
          }
      end
    end

    def resolve(req, _stream) do
      %Antd.V1.PointerResolved{kind: "chunk", kind_tag: 0, target: "resolved:" <> req.address}
    end

    def finality(req, stream) do
      case req.address do
        "open_unset" ->
          %Antd.V1.PointerFinality{address: req.address, group: 7, answered: 5, status: "open"}

        "open_counter" ->
          %Antd.V1.PointerFinality{
            address: req.address,
            group: 7,
            answered: 7,
            status: "open",
            counter: "1"
          }

        "forked" ->
          s1 = %Antd.V1.PointerFinalState{
            state_id: "aa",
            kind: "chunk",
            target: @target,
            holders: 5
          }

          s2 = %Antd.V1.PointerFinalState{
            state_id: "bb",
            kind: "chunk",
            target: @target,
            holders: 2
          }

          %Antd.V1.PointerFinality{
            address: req.address,
            group: 7,
            answered: 7,
            status: "forked",
            states: [s1, s2],
            majority: s1
          }

        "novel" ->
          %Antd.V1.PointerFinality{
            address: req.address,
            group: 7,
            answered: 7,
            status: "contested"
          }

        "bad_counter" ->
          %Antd.V1.PointerFinality{address: req.address, status: "open", counter: "1 "}

        "shortfall" ->
          fail(
            stream,
            GRPC.Status.unavailable(),
            "Close group shortfall: 3 of 7",
            "CLOSE_GROUP_SHORTFALL"
          )
      end
    end

    def controller(req, _stream) do
      %Antd.V1.PointerController{
        pointer: @recipient,
        transfers: [@recipient, req.address],
        frozen: true
      }
    end

    def prepare(req, _stream) do
      %Antd.V1.PreparePointerResponse{
        upload_id:
          Enum.join([req.op, req.target, req.kind, req.recipient, req.include_signed_quotes], "|"),
        op: req.op,
        address: req.owner,
        state_id: @state_id,
        counter: "1",
        payment_type: "wave_batch",
        payments: [%Antd.V1.PaymentEntry{quote_hash: "0xq", rewards_address: "0xr", amount: "10"}],
        total_amount: "10",
        payment_vault_address: "0xv",
        payment_token_address: "0xt",
        rpc_url: "http://rpc",
        signed_quotes:
          if req.include_signed_quotes do
            [
              %Antd.V1.SignedQuoteEntry{
                quote_hash: "0xq",
                quote: "quote",
                commitment_sidecar: "side"
              },
              %Antd.V1.SignedQuoteEntry{quote_hash: "0xq2", quote: "quote2"}
            ]
          else
            []
          end
      }
    end

    def finalize(req, stream) do
      case req.upload_id do
        "retained" ->
          fail(
            stream,
            GRPC.Status.unavailable(),
            "Close group shortfall: stored on 4 of 7 " <>
              "(paid attempt retained: call finalize again with the same upload_id to " <>
              "store it against the same payment)",
            "CLOSE_GROUP_SHORTFALL"
          )

        "quoted_hint" ->
          fail(
            stream,
            GRPC.Status.unavailable(),
            "Close group shortfall: peer said (paid attempt retained) earlier; 4 of 7",
            "CLOSE_GROUP_SHORTFALL"
          )

        _ ->
          %Antd.V1.FinalizePointerResponse{
            address: @owner,
            state_id:
              Enum.map_join(Enum.sort(req.tx_hashes), ",", fn {k, v} -> k <> "=" <> v end),
            counter: "18446744073709551615",
            finality: %Antd.V1.PointerFinality{
              address: @owner,
              group: 7,
              answered: 7,
              status: "final",
              transferred_to: @recipient
            }
          }
      end
    end
  end

  defmodule TestEndpoint do
    use GRPC.Endpoint
    run(MockPointerServer)
  end

  setup_all do
    # `GRPC.Stub.connect/1` needs the GRPC client supervisor, which
    # grpc-elixir does not start on its own.
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

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------

  test "pointer_keys lists the addresses", %{client: client} do
    assert {:ok, [@owner, @recipient]} = GrpcClient.pointer_keys(client)
  end

  test "pointer_create sends an empty kind by default and parses the write", %{client: client} do
    assert {:ok, %Antd.PointerWriteResult{} = w} =
             GrpcClient.pointer_create(client, @owner, @target)

    assert {w.address, w.state_id, w.counter} == {@owner, "kind=;target=" <> @target, 0}
  end

  test "pointer_update sends the kind", %{client: client} do
    assert {:ok, %Antd.PointerWriteResult{state_id: "kind=pointer", counter: 7}} =
             GrpcClient.pointer_update(client, @owner, @target, kind: :pointer)
  end

  test "pointer_transfer parses the finality", %{client: client} do
    assert {:ok, %Antd.PointerTransferResult{finality: f, finality_error: nil}} =
             GrpcClient.pointer_transfer(client, @owner, @recipient)

    assert %Antd.PointerFinality{status: :final, transferred_to: @recipient, counter: nil} = f
    assert %Antd.PointerFinalState{holders: 7, transferred_to: @recipient} = f.state
    assert {f.states, f.majority} == {[], nil}
  end

  test "pointer_transfer reads an absent finality as nil, with the error", %{client: client} do
    assert {:ok,
            %Antd.PointerTransferResult{finality: nil, finality_error: "only 3 of 7 answered"}} =
             GrpcClient.pointer_transfer(client, @owner, "unchecked")
  end

  test "pointer_get parses a final record at u64::MAX", %{client: client} do
    assert {:ok, %Antd.PointerRecord{} = r} = GrpcClient.pointer_get(client, @owner)
    assert {r.counter, r.is_final, r.transferred_to} == {@max_u64, true, @recipient}
    assert {r.kind, r.kind_tag, r.owner} == {"pointer", 1, "ab"}
  end

  test "pointer_get reads an empty transferred_to as nil", %{client: client} do
    assert {:ok, %Antd.PointerRecord{counter: 3, is_final: false, transferred_to: nil}} =
             GrpcClient.pointer_get(client, "open")
  end

  test "pointer_get maps NOT_FOUND", %{client: client} do
    assert {:error, %Antd.NotFoundError{}} = GrpcClient.pointer_get(client, "missing")
  end

  test "pointer_resolve parses the target", %{client: client} do
    assert {:ok, %Antd.PointerTarget{kind: "chunk", kind_tag: 0, target: "resolved:" <> @owner}} =
             GrpcClient.pointer_resolve(client, @owner)
  end

  test "pointer_finality reads an empty counter and absent states as nil", %{client: client} do
    assert {:ok, %Antd.PointerFinality{} = f} = GrpcClient.pointer_finality(client, "open_unset")

    assert {f.status, f.counter, f.state, f.majority, f.transferred_to, f.answered} ==
             {:open, nil, nil, nil, nil, 5}
  end

  test "pointer_finality parses an open counter", %{client: client} do
    assert {:ok, %Antd.PointerFinality{status: :open, counter: 1}} =
             GrpcClient.pointer_finality(client, "open_counter")
  end

  test "pointer_finality parses a fork", %{client: client} do
    assert {:ok, %Antd.PointerFinality{status: :forked} = f} =
             GrpcClient.pointer_finality(client, "forked")

    assert Enum.map(f.states, &{&1.state_id, &1.holders}) == [{"aa", 5}, {"bb", 2}]
    assert %Antd.PointerFinalState{state_id: "aa", transferred_to: nil} = f.majority
  end

  test "pointer_finality keeps a status this SDK does not know", %{client: client} do
    assert {:ok, %Antd.PointerFinality{status: {:unknown, "contested"}}} =
             GrpcClient.pointer_finality(client, "novel")
  end

  test "pointer_controller parses the transfers", %{client: client} do
    assert {:ok,
            %Antd.PointerController{
              pointer: @recipient,
              transfers: [@recipient, @owner],
              frozen: true
            }} =
             GrpcClient.pointer_controller(client, @owner)
  end

  test "pointer_prepare maps each op onto the request", %{client: client} do
    assert {:ok, %Antd.PointerPrepareResult{} = p} =
             GrpcClient.pointer_prepare(client, @owner, {:create, @target})

    assert p.upload_id == "create|#{@target}|||false"
    assert {p.op, p.address, p.counter, p.payment_type} == {"create", @owner, 1, "wave_batch"}

    assert [%Antd.PaymentInfo{quote_hash: "0xq", rewards_address: "0xr", amount: "10"}] =
             p.payments

    assert {p.total_amount, p.payment_vault_address, p.payment_token_address, p.rpc_url} ==
             {"10", "0xv", "0xt", "http://rpc"}

    assert p.signed_quotes == []

    assert {:ok, %{upload_id: "update|#{@target}|pointer||false"}} =
             GrpcClient.pointer_prepare(client, @owner, {:update, @target, :pointer})

    assert {:ok, %{upload_id: "transfer|||#{@recipient}|false"}} =
             GrpcClient.pointer_prepare(client, @owner, {:transfer, @recipient})
  end

  test "pointer_prepare base64-encodes signed quotes", %{client: client} do
    assert {:ok, %Antd.PointerPrepareResult{signed_quotes: [q1, q2]} = p} =
             GrpcClient.pointer_prepare(client, @owner, {:update, @target},
               include_signed_quotes: true
             )

    assert String.ends_with?(p.upload_id, "|true")

    assert q1 == %Antd.SignedQuoteEntry{
             quote_hash: "0xq",
             quote: Base.encode64("quote"),
             commitment_sidecar: Base.encode64("side")
           }

    assert q2.commitment_sidecar == nil
  end

  test "pointer_finalize sends the hashes and parses the result", %{client: client} do
    assert {:ok, %Antd.PointerFinalizeResult{} = r} =
             GrpcClient.pointer_finalize(client, "up1", %{"0xq" => "0xtx"})

    assert {r.state_id, r.counter} == {"0xq=0xtx", @max_u64}
    assert %Antd.PointerFinality{status: :final, transferred_to: @recipient} = r.finality
  end

  test "bang variants return the value or raise", %{client: client} do
    assert %Antd.PointerController{} = GrpcClient.pointer_controller!(client, @owner)

    assert_raise Antd.PointerFinalError, fn ->
      GrpcClient.pointer_create!(client, "final", @target)
    end
  end

  # ---------------------------------------------------------------------------
  # Counters
  # ---------------------------------------------------------------------------

  test "a malformed write counter is an error, not a number", %{client: client} do
    assert {:error, %Antd.AntdError{status_code: 0, message: m}} =
             GrpcClient.pointer_create(client, "bad_counter", @target)

    assert m =~ "not a decimal u64"
  end

  test "an empty write counter is an error: only finality's counter may be unset",
       %{client: client} do
    assert {:error, %Antd.AntdError{}} =
             GrpcClient.pointer_create(client, "empty_counter", @target)
  end

  test "a malformed finality counter is an error", %{client: client} do
    assert {:error, %Antd.AntdError{}} = GrpcClient.pointer_finality(client, "bad_counter")
  end

  # ---------------------------------------------------------------------------
  # x-antd-error-code
  # ---------------------------------------------------------------------------

  for {owner, module, status_code} <- [
        {"final", Antd.PointerFinalError, 409},
        {"final_headers_first", Antd.PointerFinalError, 409},
        {"forked", Antd.ForkError, 409},
        {"conflict", Antd.ConflictError, 409},
        {"shortfall", Antd.CloseGroupShortfallError, 503},
        {"untagged_precondition", Antd.PaymentError, 402},
        {"untagged_unavailable", Antd.NetworkError, 502},
        {"exists", Antd.AlreadyExistsError, 409},
        {"mismatched", Antd.NetworkError, 502},
        {"unknown_tag", Antd.PaymentError, 402}
      ] do
    test "a #{owner} failure maps to #{inspect(module)}", %{client: client} do
      assert {:error, %unquote(module){status_code: unquote(status_code)}} =
               GrpcClient.pointer_create(client, unquote(owner), @target)
    end
  end

  test "the status message is kept", %{client: client} do
    assert {:error, %Antd.PointerFinalError{message: "Pointer is final: x"}} =
             GrpcClient.pointer_create(client, "final", @target)
  end

  test "a shortfall on a read is not retryable", %{client: client} do
    assert {:error, %Antd.CloseGroupShortfallError{retryable: false}} =
             GrpcClient.pointer_finality(client, "shortfall")
  end

  test "a finalize shortfall closing with the retained hint is retryable", %{client: client} do
    assert {:error, %Antd.CloseGroupShortfallError{retryable: true, message: m}} =
             GrpcClient.pointer_finalize(client, "retained", %{})

    assert String.ends_with?(m, @retained_hint)
  end

  test "a retained hint quoted mid-message does not make a shortfall retryable",
       %{client: client} do
    assert {:error, %Antd.CloseGroupShortfallError{retryable: false}} =
             GrpcClient.pointer_finalize(client, "quoted_hint", %{})
  end

  test "Antd.Errors.grpc_tagged_error/3 trusts a tag only on its own status" do
    assert %Antd.PointerFinalError{} = Antd.Errors.grpc_tagged_error(9, "POINTER_FINAL", "m")
    assert %Antd.ForkError{} = Antd.Errors.grpc_tagged_error(9, "POINTER_FORKED", "m")
    assert %Antd.ConflictError{} = Antd.Errors.grpc_tagged_error(10, "CONFLICT", "m")

    assert %Antd.CloseGroupShortfallError{retryable: false} =
             Antd.Errors.grpc_tagged_error(14, "CLOSE_GROUP_SHORTFALL", "m")

    for {status, tag} <- [
          {10, "POINTER_FINAL"},
          {9, "CONFLICT"},
          {9, "CLOSE_GROUP_SHORTFALL"},
          {14, "POINTER_FORKED"},
          {9, nil},
          {9, "ALREADY_EXISTS"}
        ] do
      assert Antd.Errors.grpc_tagged_error(status, tag, "m") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Antd.GrpcAdapter
  # ---------------------------------------------------------------------------

  test "the adapter returns a failed call's metadata only when asked", %{client: client} do
    req = %Antd.V1.PointerWriteRequest{owner: "final", target: @target}

    assert {:error, %GRPC.RPCError{status: 9}} =
             Antd.V1.PointerService.Stub.create(client.channel, req)

    # Trailers-only, as tonic answers: the status rides in the headers.
    assert {:error, %GRPC.RPCError{status: 9}, %{headers: headers, trailers: trailers}} =
             Antd.V1.PointerService.Stub.create(client.channel, req, return_headers: true)

    assert {headers["x-antd-error-code"], headers["grpc-status"], trailers} ==
             {"POINTER_FINAL", "9", %{}}

    # Response headers first, then the status in the trailers.
    req = %Antd.V1.PointerWriteRequest{owner: "final_headers_first", target: @target}

    assert {:error, %GRPC.RPCError{status: 9}, %{headers: headers, trailers: trailers}} =
             Antd.V1.PointerService.Stub.create(client.channel, req, return_headers: true)

    assert {headers["x-antd-error-code"], trailers["grpc-status"]} == {"POINTER_FINAL", "9"}

    ok_req = %Antd.V1.PointerWriteRequest{owner: @owner, target: @target}

    assert {:ok, %Antd.V1.PointerWriteResponse{}} =
             Antd.V1.PointerService.Stub.create(client.channel, ok_req)

    assert {:ok, %Antd.V1.PointerWriteResponse{}, %{headers: _, trailers: _}} =
             Antd.V1.PointerService.Stub.create(client.channel, ok_req, return_headers: true)
  end

  test "the adapter leaves no messages behind", %{client: client} do
    {:error, _} = GrpcClient.pointer_create(client, "final", @target)
    {:error, _} = GrpcClient.pointer_create(client, "final_headers_first", @target)
    {:ok, _} = GrpcClient.pointer_get(client, @owner)
    {:messages, messages} = Process.info(self(), :messages)

    assert Enum.filter(
             messages,
             &(is_tuple(&1) and elem(&1, 0) in [:gun_response, :gun_data, :gun_trailers])
           ) == []
  end
end
