defmodule Antd.GrpcWalletTest do
  @moduledoc """
  V2-286 wire-mapping tests for `Antd.GrpcClient` wallet surface. Spins up a
  real grpc-elixir server on a random port with a mock WalletService, then
  dials with a real `Antd.GrpcClient`. Mirrors the antd-rust / antd-go /
  antd-py / antd-java / antd-kotlin / antd-csharp / antd-ruby / antd-dart /
  antd-swift / antd-cpp suites.
  """
  use ExUnit.Case, async: false

  alias Antd.GrpcClient

  defmodule MockWalletServer do
    use GRPC.Server, service: Antd.V1.WalletService.Service

    @spec get_address(Antd.V1.GetWalletAddressRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.GetWalletAddressResponse.t()
    def get_address(_req, _stream) do
      %Antd.V1.GetWalletAddressResponse{address: "0xabc1234567890abcdef1234567890abcdef123456"}
    end

    @spec get_balance(Antd.V1.GetWalletBalanceRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.GetWalletBalanceResponse.t()
    def get_balance(_req, _stream) do
      %Antd.V1.GetWalletBalanceResponse{
        balance: "1000000000000000000",
        gas_balance: "500000000000000000"
      }
    end

    @spec approve(Antd.V1.WalletApproveRequest.t(), GRPC.Server.Stream.t()) ::
            Antd.V1.WalletApproveResponse.t()
    def approve(_req, _stream) do
      %Antd.V1.WalletApproveResponse{approved: true}
    end
  end

  # Daemon emits gRPC FailedPrecondition for "wallet not configured"; the
  # established translate_error/1 mapping surfaces it as PaymentError.
  # (Semantic a bit off vs REST's 503 but matches every SDK.)
  defmodule UnconfiguredWalletServer do
    use GRPC.Server, service: Antd.V1.WalletService.Service

    def get_address(_req, _stream),
      do:
        raise(GRPC.RPCError,
          status: GRPC.Status.failed_precondition(),
          message: "wallet not configured — set AUTONOMI_WALLET_KEY"
        )

    def get_balance(_req, _stream),
      do:
        raise(GRPC.RPCError,
          status: GRPC.Status.failed_precondition(),
          message: "wallet not configured — set AUTONOMI_WALLET_KEY"
        )

    def approve(_req, _stream),
      do:
        raise(GRPC.RPCError,
          status: GRPC.Status.failed_precondition(),
          message: "wallet not configured — set AUTONOMI_WALLET_KEY"
        )
  end

  defmodule HappyEndpoint do
    use GRPC.Endpoint
    run(MockWalletServer)
  end

  defmodule UnconfiguredEndpoint do
    use GRPC.Endpoint
    run(UnconfiguredWalletServer)
  end

  setup_all do
    case DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  defp start_client(endpoint) do
    {:ok, _pid, port} = GRPC.Server.start_endpoint(endpoint, 0)
    on_exit_stop = fn -> :ok = GRPC.Server.stop_endpoint(endpoint) end
    {:ok, client} = GrpcClient.new("localhost:#{port}")
    {client, on_exit_stop}
  end

  describe "happy path" do
    setup do
      {client, stop} = start_client(HappyEndpoint)
      on_exit(stop)
      {:ok, client: client}
    end

    test "wallet_address returns address", %{client: client} do
      {:ok, r} = GrpcClient.wallet_address(client)
      assert r.address == "0xabc1234567890abcdef1234567890abcdef123456"
    end

    test "wallet_balance returns balances", %{client: client} do
      {:ok, r} = GrpcClient.wallet_balance(client)
      assert r.balance == "1000000000000000000"
      assert r.gas_balance == "500000000000000000"
    end

    test "wallet_approve returns true", %{client: client} do
      {:ok, true} = GrpcClient.wallet_approve(client)
    end
  end

  describe "unconfigured wallet" do
    setup do
      {client, stop} = start_client(UnconfiguredEndpoint)
      on_exit(stop)
      {:ok, client: client}
    end

    test "wallet_address returns PaymentError", %{client: client} do
      {:error, err} = GrpcClient.wallet_address(client)
      assert %Antd.PaymentError{} = err
      assert err.message =~ "wallet not configured"
    end
  end
end
