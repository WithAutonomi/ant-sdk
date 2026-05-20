defmodule Antd.GrpcClient do
  @moduledoc """
  gRPC client for the antd daemon.

  Provides the same functions as `Antd.Client` (REST), but communicates over
  gRPC using the proto-generated modules from `antd/v1/*.proto`.

  All public functions return `{:ok, result}` or `{:error, exception}`.
  Bang variants (e.g. `health!/1`) raise on error.

  ## Naming convention

  Private = unqualified verb. Public = `_public` suffix. See `Antd.Client`
  for full details.

  ## Proto compilation

  Run `protoc` with the Elixir gRPC plugin to generate stubs:

      protoc --elixir_out=plugins=grpc:lib \\
        -I../antd/proto \\
        antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \\
        antd/v1/chunks.proto antd/v1/files.proto

  The generated modules are expected under `lib/antd/v1/`.
  """

  alias Antd.PaymentMode

  @default_target "localhost:50051"

  defstruct target: @default_target, channel: nil

  @type t :: %__MODULE__{
          target: String.t(),
          channel: GRPC.Channel.t() | nil
        }

  @doc """
  Creates a gRPC client using port discovery.

  Reads the daemon.port file to find the gRPC port. Falls back to the
  default target if the port file is not found.

  ## Examples

      {:ok, client, target} = Antd.GrpcClient.auto_discover()
  """
  @spec auto_discover() :: {:ok, t(), String.t()} | {:error, Exception.t()}
  def auto_discover do
    target =
      case Antd.Discover.discover_grpc_target() do
        "" -> @default_target
        discovered -> discovered
      end

    case new(target) do
      {:ok, client} -> {:ok, client, target}
      {:error, _} = err -> err
    end
  end

  @doc """
  Creates a new gRPC client and opens a channel to the daemon.

  ## Examples

      {:ok, client} = Antd.GrpcClient.new()
      {:ok, client} = Antd.GrpcClient.new("localhost:50051")
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(target \\ @default_target) do
    case GRPC.Stub.connect(target) do
      {:ok, channel} ->
        {:ok, %__MODULE__{target: target, channel: channel}}

      {:error, reason} ->
        {:error,
         %Antd.AntdError{message: "failed to connect: #{inspect(reason)}", status_code: 0}}
    end
  end

  @doc "Like `new/1` but raises on error."
  @spec new!(String.t()) :: t()
  def new!(target \\ @default_target) do
    case new(target) do
      {:ok, client} -> client
      {:error, exception} -> raise exception
    end
  end

  # ---------------------------------------------------------------------------
  # Health
  # ---------------------------------------------------------------------------

  @doc "Checks the antd daemon status."
  @spec health(t()) :: {:ok, Antd.HealthStatus.t()} | {:error, Exception.t()}
  def health(%__MODULE__{channel: channel}) do
    req = Antd.V1.HealthCheckRequest.new()

    case Antd.V1.HealthService.Stub.check(channel, req) do
      {:ok, resp} ->
        {:ok,
         %Antd.HealthStatus{
           ok: resp.status == "ok",
           network: resp.network,
           version: resp.version,
           evm_network: resp.evm_network,
           uptime_seconds: resp.uptime_seconds,
           build_commit: resp.build_commit,
           payment_token_address: resp.payment_token_address,
           payment_vault_address: resp.payment_vault_address
         }}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `health/1` but raises on error."
  @spec health!(t()) :: Antd.HealthStatus.t()
  def health!(client), do: unwrap!(health(client))

  # ---------------------------------------------------------------------------
  # Data
  # ---------------------------------------------------------------------------

  @doc """
  Stores private encrypted data on the network.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_put(t(), binary(), keyword()) ::
          {:ok, Antd.DataPutResult.t()} | {:error, Exception.t()}
  def data_put(%__MODULE__{channel: channel}, data, opts \\ []) when is_binary(data) do
    req =
      Antd.V1.PutDataRequest.new(
        data: data,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      )

    case Antd.V1.DataService.Stub.put(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.DataPutResult{data_map: resp.data_map}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_put/3` but raises on error."
  @spec data_put!(t(), binary(), keyword()) :: Antd.DataPutResult.t()
  def data_put!(client, data, opts \\ []), do: unwrap!(data_put(client, data, opts))

  @doc "Retrieves private data using a caller-held DataMap."
  @spec data_get(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get(%__MODULE__{channel: channel}, data_map) do
    req = Antd.V1.GetDataRequest.new(data_map: data_map)

    case Antd.V1.DataService.Stub.get(channel, req) do
      {:ok, resp} -> {:ok, resp.data}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_get/2` but raises on error."
  @spec data_get!(t(), String.t()) :: binary()
  def data_get!(client, data_map), do: unwrap!(data_get(client, data_map))

  @doc """
  Stores public data on the network.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_put_public(t(), binary(), keyword()) ::
          {:ok, Antd.DataPutPublicResult.t()} | {:error, Exception.t()}
  def data_put_public(%__MODULE__{channel: channel}, data, opts \\ []) when is_binary(data) do
    req =
      Antd.V1.PutPublicDataRequest.new(
        data: data,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      )

    case Antd.V1.DataService.Stub.put_public(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.DataPutPublicResult{address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_put_public/3` but raises on error."
  @spec data_put_public!(t(), binary(), keyword()) :: Antd.DataPutPublicResult.t()
  def data_put_public!(client, data, opts \\ []),
    do: unwrap!(data_put_public(client, data, opts))

  @doc "Retrieves public data by address."
  @spec data_get_public(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get_public(%__MODULE__{channel: channel}, address) do
    req = Antd.V1.GetPublicDataRequest.new(address: address)

    case Antd.V1.DataService.Stub.get_public(channel, req) do
      {:ok, resp} -> {:ok, resp.data}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_get_public/2` but raises on error."
  @spec data_get_public!(t(), String.t()) :: binary()
  def data_get_public!(client, address), do: unwrap!(data_get_public(client, address))

  @doc """
  Pre-upload cost breakdown for the given bytes.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_cost(t(), binary(), keyword()) ::
          {:ok, Antd.UploadCostEstimate.t()} | {:error, Exception.t()}
  def data_cost(%__MODULE__{channel: channel}, data, opts \\ []) when is_binary(data) do
    req =
      Antd.V1.DataCostRequest.new(
        data: data,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      )

    case Antd.V1.DataService.Stub.cost(channel, req) do
      {:ok, resp} ->
        {:ok,
         %Antd.UploadCostEstimate{
           cost: resp.atto_tokens,
           file_size: resp.file_size,
           chunk_count: resp.chunk_count,
           estimated_gas_cost_wei: resp.estimated_gas_cost_wei,
           payment_mode: resp.payment_mode
         }}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_cost/3` but raises on error."
  @spec data_cost!(t(), binary(), keyword()) :: Antd.UploadCostEstimate.t()
  def data_cost!(client, data, opts \\ []), do: unwrap!(data_cost(client, data, opts))

  # ---------------------------------------------------------------------------
  # Chunks
  # ---------------------------------------------------------------------------

  @doc "Stores a raw chunk on the network."
  @spec chunk_put(t(), binary()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def chunk_put(%__MODULE__{channel: channel}, data) when is_binary(data) do
    req = Antd.V1.PutChunkRequest.new(data: data)

    case Antd.V1.ChunkService.Stub.put(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `chunk_put/2` but raises on error."
  @spec chunk_put!(t(), binary()) :: Antd.PutResult.t()
  def chunk_put!(client, data), do: unwrap!(chunk_put(client, data))

  @doc "Retrieves a chunk by address."
  @spec chunk_get(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def chunk_get(%__MODULE__{channel: channel}, address) do
    req = Antd.V1.GetChunkRequest.new(address: address)

    case Antd.V1.ChunkService.Stub.get(channel, req) do
      {:ok, resp} -> {:ok, resp.data}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `chunk_get/2` but raises on error."
  @spec chunk_get!(t(), String.t()) :: binary()
  def chunk_get!(client, address), do: unwrap!(chunk_get(client, address))

  # ---------------------------------------------------------------------------
  # Files
  # ---------------------------------------------------------------------------

  @doc """
  Uploads a local file privately.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec file_put(t(), String.t(), keyword()) ::
          {:ok, Antd.FilePutResult.t()} | {:error, Exception.t()}
  def file_put(%__MODULE__{channel: channel}, path, opts \\ []) when is_binary(path) do
    req =
      Antd.V1.PutFileRequest.new(
        path: path,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      )

    case Antd.V1.FileService.Stub.put(channel, req) do
      {:ok, resp} ->
        {:ok, file_put_result_from_resp(resp)}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_put/3` but raises on error."
  @spec file_put!(t(), String.t(), keyword()) :: Antd.FilePutResult.t()
  def file_put!(client, path, opts \\ []), do: unwrap!(file_put(client, path, opts))

  @doc "Downloads a private file from a caller-held DataMap into `dest_path`."
  @spec file_get(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def file_get(%__MODULE__{channel: channel}, data_map, dest_path) do
    req = Antd.V1.GetFileRequest.new(data_map: data_map, dest_path: dest_path)

    case Antd.V1.FileService.Stub.get(channel, req) do
      {:ok, _resp} -> :ok
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_get/3` but raises on error."
  @spec file_get!(t(), String.t(), String.t()) :: :ok
  def file_get!(client, data_map, dest_path) do
    unwrap!(file_get(client, data_map, dest_path))
  end

  @doc """
  Uploads a local file publicly.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec file_put_public(t(), String.t(), keyword()) ::
          {:ok, Antd.FilePutPublicResult.t()} | {:error, Exception.t()}
  def file_put_public(%__MODULE__{channel: channel}, path, opts \\ []) when is_binary(path) do
    req =
      Antd.V1.PutFileRequest.new(
        path: path,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      )

    case Antd.V1.FileService.Stub.put_public(channel, req) do
      {:ok, resp} ->
        {:ok, file_put_public_result_from_resp(resp)}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_put_public/3` but raises on error."
  @spec file_put_public!(t(), String.t(), keyword()) :: Antd.FilePutPublicResult.t()
  def file_put_public!(client, path, opts \\ []),
    do: unwrap!(file_put_public(client, path, opts))

  @doc "Downloads a public file from the network to a local path."
  @spec file_get_public(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def file_get_public(%__MODULE__{channel: channel}, address, dest_path) do
    req = Antd.V1.GetFilePublicRequest.new(address: address, dest_path: dest_path)

    case Antd.V1.FileService.Stub.get_public(channel, req) do
      {:ok, _resp} -> :ok
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_get_public/3` but raises on error."
  @spec file_get_public!(t(), String.t(), String.t()) :: :ok
  def file_get_public!(client, address, dest_path) do
    unwrap!(file_get_public(client, address, dest_path))
  end

  defp file_put_result_from_resp(resp) do
    %Antd.FilePutResult{
      data_map: resp.data_map,
      storage_cost_atto: resp.storage_cost_atto,
      gas_cost_wei: resp.gas_cost_wei,
      chunks_stored: resp.chunks_stored,
      payment_mode_used: resp.payment_mode_used
    }
  end

  defp file_put_public_result_from_resp(resp) do
    %Antd.FilePutPublicResult{
      address: resp.address,
      storage_cost_atto: resp.storage_cost_atto,
      gas_cost_wei: resp.gas_cost_wei,
      chunks_stored: resp.chunks_stored,
      payment_mode_used: resp.payment_mode_used
    }
  end

  @doc """
  Pre-upload cost breakdown for the file at `path`.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec file_cost(t(), String.t(), boolean(), keyword()) ::
          {:ok, Antd.UploadCostEstimate.t()} | {:error, Exception.t()}
  def file_cost(%__MODULE__{channel: channel}, path, is_public, opts \\ []) do
    req =
      Antd.V1.FileCostRequest.new(
        path: path,
        is_public: is_public,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      )

    case Antd.V1.FileService.Stub.cost(channel, req) do
      {:ok, resp} ->
        {:ok,
         %Antd.UploadCostEstimate{
           cost: resp.atto_tokens,
           file_size: resp.file_size,
           chunk_count: resp.chunk_count,
           estimated_gas_cost_wei: resp.estimated_gas_cost_wei,
           payment_mode: resp.payment_mode
         }}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_cost/4` but raises on error."
  @spec file_cost!(t(), String.t(), boolean(), keyword()) :: Antd.UploadCostEstimate.t()
  def file_cost!(client, path, is_public, opts \\ []) do
    unwrap!(file_cost(client, path, is_public, opts))
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp unwrap!({:ok, result}), do: result
  defp unwrap!(:ok), do: :ok
  defp unwrap!({:error, exception}), do: raise(exception)

  defp translate_error(%GRPC.RPCError{status: status, message: message}) do
    case status do
      3 -> %Antd.BadRequestError{message: message, status_code: 400}
      5 -> %Antd.NotFoundError{message: message, status_code: 404}
      6 -> %Antd.AlreadyExistsError{message: message, status_code: 409}
      8 -> %Antd.TooLargeError{message: message, status_code: 413}
      9 -> %Antd.PaymentError{message: message, status_code: 402}
      13 -> %Antd.InternalError{message: message, status_code: 500}
      14 -> %Antd.NetworkError{message: message, status_code: 502}
      _ -> %Antd.AntdError{message: message, status_code: status}
    end
  end

  defp translate_error(other) do
    %Antd.AntdError{message: inspect(other), status_code: 0}
  end
end
