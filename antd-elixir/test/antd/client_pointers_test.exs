defmodule Antd.ClientPointersTest do
  @moduledoc """
  REST pointer API against a mock daemon (Bypass): request shapes, response
  parsing (counters up to u64::MAX, nulls), and the error codes that share a
  status with older errors.
  """
  use ExUnit.Case, async: true

  alias Antd.Client

  @owner String.duplicate("a1", 32)
  @recipient String.duplicate("b2", 32)
  @target String.duplicate("c3", 32)
  @state_id String.duplicate("d4", 32)
  @max_u64 18_446_744_073_709_551_615

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: Client.new("http://localhost:#{bypass.port}")}
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  defp read_json(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  defp finality_body(overrides) do
    Map.merge(
      %{
        address: @owner,
        group: 7,
        answered: 7,
        status: "open",
        counter: nil,
        state: nil,
        states: [],
        majority: nil,
        transferred_to: nil
      },
      overrides
    )
  end

  defp final_state(id, holders, transferred_to \\ nil) do
    %{
      state_id: id,
      kind: "pointer",
      kind_tag: 1,
      target: @recipient,
      holders: holders,
      transferred_to: transferred_to
    }
  end

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------

  test "pointer_keys/1 lists the addresses", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/keys", fn conn ->
      json(conn, 200, %{keys: [%{address: @owner}, %{address: @recipient}]})
    end)

    assert {:ok, [@owner, @recipient]} = Client.pointer_keys(client)
  end

  test "pointer_create/4 posts owner and target, omitting kind by default",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"owner" => @owner, "target" => @target}
      json(conn, 200, %{address: @owner, state_id: @state_id, counter: "0"})
    end)

    assert {:ok, %Antd.PointerWriteResult{address: @owner, state_id: @state_id, counter: 0}} =
             Client.pointer_create(client, @owner, @target)
  end

  test "pointer_update/4 posts the kind when given", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/update", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"owner" => @owner, "target" => @target, "kind" => "pointer"}
      json(conn, 200, %{address: @owner, state_id: @state_id, counter: "41"})
    end)

    assert {:ok, %Antd.PointerWriteResult{counter: 41}} =
             Client.pointer_update(client, @owner, @target, kind: :pointer)
  end

  test "pointer_transfer/3 parses the close group's finality",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/transfer", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"owner" => @owner, "recipient" => @recipient}

      json(conn, 200, %{
        address: @owner,
        state_id: @state_id,
        finality:
          finality_body(%{
            status: "final",
            state: final_state(@state_id, 7, @recipient),
            transferred_to: @recipient
          })
      })
    end)

    assert {:ok, %Antd.PointerTransferResult{} = r} =
             Client.pointer_transfer(client, @owner, @recipient)

    assert r.address == @owner
    assert r.finality_error == nil
    assert %Antd.PointerFinality{status: :final, transferred_to: @recipient} = r.finality
    assert Antd.PointerFinality.final?(r.finality)

    assert %Antd.PointerFinalState{holders: 7, kind: "pointer", kind_tag: 1} =
             r.finality.state

    assert r.finality.state.transferred_to == @recipient
  end

  test "pointer_transfer/3 keeps a failed finality check as finality_error",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/transfer", fn conn ->
      json(conn, 200, %{
        address: @owner,
        state_id: @state_id,
        finality: nil,
        finality_error: "only 3 of 7 answered"
      })
    end)

    assert {:ok,
            %Antd.PointerTransferResult{finality: nil, finality_error: "only 3 of 7 answered"}} =
             Client.pointer_transfer(client, @owner, @recipient)
  end

  test "pointer_get/2 parses the record, final counter at u64::MAX",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}", fn conn ->
      json(conn, 200, %{
        address: @owner,
        owner: "ab",
        counter: "18446744073709551615",
        kind: "pointer",
        kind_tag: 1,
        target: @recipient,
        state_id: @state_id,
        is_final: true,
        transferred_to: @recipient
      })
    end)

    assert {:ok, %Antd.PointerRecord{} = r} = Client.pointer_get(client, @owner)
    assert r.counter == @max_u64
    assert r.counter == Antd.PointerRecord.final_counter()
    assert r.is_final
    assert r.transferred_to == @recipient
    assert {r.kind, r.kind_tag, r.owner} == {"pointer", 1, "ab"}
  end

  test "pointer_get/2 reads a null transferred_to as nil", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}", fn conn ->
      json(conn, 200, %{
        address: @owner,
        owner: "ab",
        counter: "3",
        kind: "chunk",
        kind_tag: 0,
        target: @target,
        state_id: @state_id,
        is_final: false,
        transferred_to: nil
      })
    end)

    assert {:ok, %Antd.PointerRecord{counter: 3, is_final: false, transferred_to: nil}} =
             Client.pointer_get(client, @owner)
  end

  test "pointer_resolve/2 parses the target", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/resolve", fn conn ->
      json(conn, 200, %{kind: "chunk", kind_tag: 0, target: @target})
    end)

    assert {:ok, %Antd.PointerTarget{kind: "chunk", kind_tag: 0, target: @target}} =
             Client.pointer_resolve(client, @owner)
  end

  test "pointer_finality/2 parses an open pointer's counter",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/finality", fn conn ->
      json(conn, 200, finality_body(%{counter: "1"}))
    end)

    assert {:ok, %Antd.PointerFinality{} = f} = Client.pointer_finality(client, @owner)
    assert {f.status, f.counter, f.group, f.answered} == {:open, 1, 7, 7}
    assert {f.state, f.states, f.majority, f.transferred_to} == {nil, [], nil, nil}
    refute Antd.PointerFinality.final?(f)
  end

  test "pointer_finality/2 reads a null counter as nil", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/finality", fn conn ->
      json(conn, 200, finality_body(%{answered: 5}))
    end)

    assert {:ok, %Antd.PointerFinality{status: :open, counter: nil, answered: 5}} =
             Client.pointer_finality(client, @owner)
  end

  test "pointer_finality/2 parses a fork", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/finality", fn conn ->
      json(
        conn,
        200,
        finality_body(%{
          status: "forked",
          states: [final_state("aa", 5), final_state("bb", 2)],
          majority: final_state("aa", 5)
        })
      )
    end)

    assert {:ok, %Antd.PointerFinality{status: :forked} = f} =
             Client.pointer_finality(client, @owner)

    assert Enum.map(f.states, &{&1.state_id, &1.holders}) == [{"aa", 5}, {"bb", 2}]
    assert %Antd.PointerFinalState{state_id: "aa", transferred_to: nil} = f.majority
  end

  for {wire, status} <- [{"settling", :settling}, {"unconfirmed", :unconfirmed}] do
    test "pointer_finality/2 parses status #{wire}", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/finality", fn conn ->
        json(conn, 200, finality_body(%{status: unquote(wire), state: final_state("aa", 3)}))
      end)

      assert {:ok, %Antd.PointerFinality{status: unquote(status), state: %{holders: 3}}} =
               Client.pointer_finality(client, @owner)
    end
  end

  test "pointer_finality/2 keeps a status this SDK does not know",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/finality", fn conn ->
      json(conn, 200, finality_body(%{status: "contested"}))
    end)

    assert {:ok, %Antd.PointerFinality{status: {:unknown, "contested"}} = f} =
             Client.pointer_finality(client, @owner)

    refute Antd.PointerFinality.final?(f)
  end

  test "pointer_controller/2 parses the transfers", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/controller", fn conn ->
      json(conn, 200, %{pointer: @recipient, transfers: [@recipient], frozen: false})
    end)

    assert {:ok,
            %Antd.PointerController{pointer: @recipient, transfers: [@recipient], frozen: false}} =
             Client.pointer_controller(client, @owner)
  end

  test "pointer_prepare/4 sends a create, update or transfer and parses the quote",
       %{bypass: bypass, client: client} do
    test_pid = self()

    Bypass.expect(bypass, "POST", "/v1/pointers/prepare", fn conn ->
      {body, conn} = read_json(conn)
      send(test_pid, {:body, body})

      json(conn, 200, %{
        upload_id: "up1",
        op: body["op"],
        address: @owner,
        state_id: @state_id,
        counter: "2",
        payment_type: "wave_batch",
        payments: [%{quote_hash: "0xq", rewards_address: "0xr", amount: "10"}],
        total_amount: "10",
        payment_vault_address: "0xv",
        payment_token_address: "0xt",
        rpc_url: "http://rpc"
      })
    end)

    assert {:ok, %Antd.PointerPrepareResult{} = p} =
             Client.pointer_prepare(client, @owner, {:create, @target})

    assert_received {:body, %{"owner" => @owner, "op" => "create", "target" => @target} = b1}
    refute Map.has_key?(b1, "kind")
    refute Map.has_key?(b1, "include_signed_quotes")

    assert {p.upload_id, p.op, p.counter, p.payment_type} == {"up1", "create", 2, "wave_batch"}

    assert [%Antd.PaymentInfo{quote_hash: "0xq", rewards_address: "0xr", amount: "10"}] =
             p.payments

    assert {p.total_amount, p.payment_vault_address, p.payment_token_address, p.rpc_url} ==
             {"10", "0xv", "0xt", "http://rpc"}

    assert p.signed_quotes == []

    {:ok, _} = Client.pointer_prepare(client, @owner, {:update, @target, :chunk})

    assert_received {:body,
                     %{
                       "op" => "update",
                       "target" => @target,
                       "kind" => "chunk",
                       "owner" => @owner
                     }}

    {:ok, _} =
      Client.pointer_prepare(client, @owner, {:transfer, @recipient}, include_signed_quotes: true)

    assert_received {:body, b3}

    assert b3 == %{
             "owner" => @owner,
             "op" => "transfer",
             "recipient" => @recipient,
             "include_signed_quotes" => true
           }
  end

  test "pointer_prepare/4 parses signed quotes", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/prepare", fn conn ->
      json(conn, 200, %{
        upload_id: "up1",
        op: "update",
        address: @owner,
        state_id: @state_id,
        counter: "1",
        payment_type: "wave_batch",
        payments: [],
        signed_quotes: [
          %{quote_hash: "0xq1", quote: "cXVvdGU=", commitment_sidecar: "c2lkZQ=="},
          %{quote_hash: "0xq2", quote: "cXVvdGUy"}
        ]
      })
    end)

    assert {:ok, %Antd.PointerPrepareResult{signed_quotes: [q1, q2]}} =
             Client.pointer_prepare(client, @owner, {:update, @target},
               include_signed_quotes: true
             )

    assert q1 == %Antd.SignedQuoteEntry{
             quote_hash: "0xq1",
             quote: "cXVvdGU=",
             commitment_sidecar: "c2lkZQ=="
           }

    assert q2.commitment_sidecar == nil
  end

  test "pointer_finalize/3 posts the hashes and parses a transfer's finality",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/finalize", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"upload_id" => "up1", "tx_hashes" => %{"0xq" => "0xtx"}}

      json(conn, 200, %{
        address: @owner,
        state_id: @state_id,
        counter: "18446744073709551615",
        finality: finality_body(%{status: "final", transferred_to: @recipient})
      })
    end)

    assert {:ok, %Antd.PointerFinalizeResult{counter: @max_u64} = r} =
             Client.pointer_finalize(client, "up1", %{"0xq" => "0xtx"})

    assert %Antd.PointerFinality{status: :final, transferred_to: @recipient} = r.finality
  end

  test "pointer_finalize/3 leaves finality nil for a create or update",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/finalize", fn conn ->
      json(conn, 200, %{address: @owner, state_id: @state_id, counter: "4"})
    end)

    assert {:ok, %Antd.PointerFinalizeResult{counter: 4, finality: nil}} =
             Client.pointer_finalize(client, "up1", %{})
  end

  test "bang variants return the value or raise the mapped error",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/resolve", fn conn ->
      json(conn, 200, %{kind: "chunk", kind_tag: 0, target: @target})
    end)

    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@recipient}", fn conn ->
      json(conn, 404, %{error: "no pointer", code: "NOT_FOUND"})
    end)

    assert %Antd.PointerTarget{target: @target} = Client.pointer_resolve!(client, @owner)
    assert_raise Antd.NotFoundError, fn -> Client.pointer_get!(client, @recipient) end
  end

  # ---------------------------------------------------------------------------
  # Counters
  # ---------------------------------------------------------------------------

  for {label, counter} <- [
        {"a sign", "+1"},
        {"a minus sign", "-1"},
        {"trailing junk", "12abc"},
        {"whitespace", " 1"},
        {"an empty string", ""},
        {"a decimal point", "1.0"},
        {"u64::MAX + 1", "18446744073709551616"},
        {"a JSON number", 5},
        {"null", nil}
      ] do
    test "a write's counter with #{label} is an error, not a number",
         %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/pointers", fn conn ->
        json(conn, 200, %{address: @owner, state_id: @state_id, counter: unquote(counter)})
      end)

      assert {:error, %Antd.AntdError{message: message, status_code: 0}} =
               Client.pointer_create(client, @owner, @target)

      assert message =~ "not a decimal u64"
    end
  end

  test "a malformed finality counter is an error", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/pointers/#{@owner}/finality", fn conn ->
      json(conn, 200, finality_body(%{counter: "0x10"}))
    end)

    assert {:error, %Antd.AntdError{}} = Client.pointer_finality(client, @owner)
  end

  test "a malformed counter in a transfer's finality is an error",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/transfer", fn conn ->
      json(conn, 200, %{
        address: @owner,
        state_id: @state_id,
        finality: finality_body(%{counter: "-3"})
      })
    end)

    assert {:error, %Antd.AntdError{}} = Client.pointer_transfer(client, @owner, @recipient)
  end

  test "Antd.Pointers.counter/1 reads zero and u64::MAX exactly" do
    assert Antd.Pointers.counter("0") == {:ok, 0}
    assert Antd.Pointers.counter("18446744073709551615") == {:ok, @max_u64}
    assert {:error, _} = Antd.Pointers.counter("18446744073709551616")
    assert Antd.Pointers.optional_counter(nil) == {:ok, nil}
    assert Antd.Pointers.optional_counter("") == {:ok, nil}
  end

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

  for {code, status, module} <- [
        {"POINTER_FINAL", 409, Antd.PointerFinalError},
        {"POINTER_FORKED", 409, Antd.ForkError},
        {"CONFLICT", 409, Antd.ConflictError},
        {"ALREADY_EXISTS", 409, Antd.AlreadyExistsError},
        {"CLOSE_GROUP_SHORTFALL", 503, Antd.CloseGroupShortfallError},
        {"SERVICE_UNAVAILABLE", 503, Antd.ServiceUnavailableError},
        {"NOT_FOUND", 404, Antd.NotFoundError},
        {"BAD_REQUEST", 400, Antd.BadRequestError}
      ] do
    test "#{status} #{code} returns #{inspect(module)}", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/pointers/update", fn conn ->
        json(conn, unquote(status), %{error: "refused", code: unquote(code)})
      end)

      assert {:error, %unquote(module){message: "refused", status_code: unquote(status)}} =
               Client.pointer_update(client, @owner, @target)
    end
  end

  test "a 409 without a code stays AlreadyExistsError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers", fn conn ->
      json(conn, 409, %{error: "exists"})
    end)

    assert {:error, %Antd.AlreadyExistsError{}} = Client.pointer_create(client, @owner, @target)
  end

  for {label, body, retryable} <- [
        {"retryable true", %{retryable: true}, true},
        {"retryable false", %{retryable: false}, false},
        {"no retryable", %{}, false},
        {"a string retryable", %{retryable: "true"}, false}
      ] do
    test "CLOSE_GROUP_SHORTFALL with #{label} reads retryable=#{retryable}",
         %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/pointers/finalize", fn conn ->
        json(
          conn,
          503,
          Map.merge(
            %{error: "stored on 4 of 5", code: "CLOSE_GROUP_SHORTFALL"},
            unquote(Macro.escape(body))
          )
        )
      end)

      assert {:error, %Antd.CloseGroupShortfallError{retryable: unquote(retryable)}} =
               Client.pointer_finalize(client, "up1", %{})
    end
  end

  test "the code mapping applies to every REST call", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/data/public/abc", fn conn ->
      json(conn, 503, %{error: "only 3 answered", code: "CLOSE_GROUP_SHORTFALL"})
    end)

    assert {:error, %Antd.CloseGroupShortfallError{retryable: false}} =
             Client.data_get_public(client, "abc")
  end

  test "pointer_transfer!/3 raises PointerFinalError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/pointers/transfer", fn conn ->
      json(conn, 409, %{error: "Pointer is final: x", code: "POINTER_FINAL"})
    end)

    assert_raise Antd.PointerFinalError, "Pointer is final: x", fn ->
      Client.pointer_transfer!(client, @owner, @recipient)
    end
  end
end
