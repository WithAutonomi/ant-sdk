defmodule Antd.LivePointersTest do
  @moduledoc """
  Live pointer round trip against a running antd with a devnet behind it.

  Skipped unless these are set:

    * `ANTD_TEST_URL` — the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
    * `ANTD_TEST_POINTER_OWNERS` — two comma-separated pointer addresses the
      daemon holds keys for (`antd --pointer-keys`) and that have **never
      been written**. The test creates both, transfers the first to the
      second, and leaves the second with a prepared write awaiting payment,
      so each pair can be used once.
    * `ANTD_TEST_GRPC` (optional) — the daemon's gRPC target, e.g.
      `127.0.0.1:50051`; when set, the gRPC client is exercised too.

  Every write is paid by the daemon's wallet, so run it against a devnet:

      ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \\
      ANTD_TEST_POINTER_OWNERS=<hex>,<hex> mix test test/antd/live_pointers_test.exs
  """
  use ExUnit.Case, async: false

  alias Antd.{Client, GrpcClient}

  @url System.get_env("ANTD_TEST_URL")
  @grpc System.get_env("ANTD_TEST_GRPC")
  @owners System.get_env("ANTD_TEST_POINTER_OWNERS")

  if is_nil(@url) or is_nil(@owners) do
    @moduletag skip: "set ANTD_TEST_URL and ANTD_TEST_POINTER_OWNERS to run"
  end

  @moduletag timeout: 1_800_000

  # The daemon accepts a 0x prefix but always answers bare hex.
  defp norm(address),
    do: address |> String.trim() |> String.replace_prefix("0x", "") |> String.downcase()

  defp owners do
    case String.split(@owners || "", ",") do
      [a, b] when a != "" and b != "" -> {norm(a), norm(b)}
      _ -> flunk("ANTD_TEST_POINTER_OWNERS must be two comma-separated addresses")
    end
  end

  defp grpc_client do
    if @grpc do
      case DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      {:ok, client} = GrpcClient.new(@grpc)
      client
    end
  end

  defp put_public!(rest, text), do: Client.data_put_public!(rest, text).address

  test "pointer round trip: create, update, read, transfer, then prepare up to the quote" do
    {a, b} = owners()
    rest = Client.new(@url, timeout: 600_000)
    grpc = grpc_client()

    # Both owners must be writable through this daemon.
    keys = Enum.map(Client.pointer_keys!(rest), &norm/1)
    assert a in keys and b in keys, "daemon holds no key for one of the owners: #{inspect(keys)}"

    # Real targets, so the chain can be followed back to bytes.
    one = put_public!(rest, "antd-elixir pointer target one")
    two = put_public!(rest, "antd-elixir pointer target two")
    three = put_public!(rest, "antd-elixir recipient target")

    # ── REST: create, read, update ──
    case Client.pointer_get(rest, a) do
      {:error, %Antd.NotFoundError{}} -> :ok
      other -> flunk("owner #{a} has been written before; use a fresh pair: #{inspect(other)}")
    end

    assert {:ok, %Antd.PointerWriteResult{counter: 0}} = Client.pointer_create(rest, a, one)
    assert {:error, %Antd.AlreadyExistsError{}} = Client.pointer_create(rest, a, two)

    r = Client.pointer_get!(rest, a)
    assert {r.counter, r.target, r.is_final, r.kind, r.kind_tag} == {0, one, false, "chunk", 0}
    assert byte_size(r.owner) == 2 * 1952
    assert r.transferred_to == nil

    res = Client.pointer_resolve!(rest, a)
    assert res.target == one
    assert Client.data_get_public!(rest, res.target) == "antd-elixir pointer target one"

    assert {:ok, %Antd.PointerWriteResult{counter: 1}} = Client.pointer_update(rest, a, two)
    assert Client.pointer_resolve!(rest, a).target == two
    assert Client.data_get_public!(rest, two) == "antd-elixir pointer target two"

    f = Client.pointer_finality!(rest, a)
    assert {f.status, f.counter} == {:open, 1}
    assert f.answered == f.group

    # ── the recipient: a gRPC write and read when gRPC is configured ──
    if grpc do
      assert {:ok, %Antd.PointerWriteResult{counter: 0}} =
               GrpcClient.pointer_create(grpc, b, three)

      gr = GrpcClient.pointer_get!(grpc, b)
      assert {gr.counter, gr.target, gr.transferred_to} == {0, three, nil}
    else
      assert {:ok, %Antd.PointerWriteResult{counter: 0}} = Client.pointer_create(rest, b, three)
    end

    # ── transfer a -> b ──
    t = Client.pointer_transfer!(rest, a, b)
    assert match?(%Antd.PointerFinality{}, t.finality), "no finality: #{t.finality_error}"
    assert t.finality.status == :final
    assert norm(t.finality.transferred_to) == b

    r = Client.pointer_get!(rest, a)
    assert r.is_final
    assert r.counter == Antd.PointerRecord.final_counter()
    assert norm(r.transferred_to) == b

    c = Client.pointer_controller!(rest, a)
    assert {norm(c.pointer), Enum.map(c.transfers, &norm/1)} == {b, [b]}

    # a now resolves through b.
    assert Client.pointer_resolve!(rest, a).target == three

    # A final pointer refuses every write, before anything is paid.
    assert {:error, %Antd.PointerFinalError{}} = Client.pointer_update(rest, a, one)
    assert {:error, %Antd.PointerFinalError{}} = Client.pointer_transfer(rest, a, b)

    if grpc do
      assert GrpcClient.pointer_resolve!(grpc, a).target == three
      gf = GrpcClient.pointer_finality!(grpc, a)
      assert Antd.PointerFinality.final?(gf)
      assert norm(gf.transferred_to) == b
      gr = GrpcClient.pointer_get!(grpc, a)
      assert {gr.is_final, gr.counter} == {true, Antd.PointerRecord.final_counter()}
      assert {:error, %Antd.PointerFinalError{}} = GrpcClient.pointer_update(grpc, a, one)
    end

    # ── external signer, up to the quote ──
    # Last: the prepared write blocks b's other writes until it expires.
    p = Client.pointer_prepare!(rest, b, {:update, two})
    assert {p.op, p.counter, p.payment_type} == {"update", 1, "wave_batch"}
    assert p.payments != [] and p.upload_id != ""
    assert {:error, %Antd.ConflictError{}} = Client.pointer_update(rest, b, two)

    if grpc do
      assert {:error, %Antd.ConflictError{}} = GrpcClient.pointer_prepare(grpc, b, {:update, two})
    end

    # A finalize without the payment is refused and keeps the session.
    assert {:error, %Antd.BadRequestError{}} = Client.pointer_finalize(rest, p.upload_id, %{})
    assert {:error, %Antd.ConflictError{}} = Client.pointer_update(rest, b, two)
  end
end
