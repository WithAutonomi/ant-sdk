defmodule Antd.GrpcClient do
  @moduledoc """
  gRPC client for the antd daemon.

  Provides the same functions as `Antd.Client` (REST), but communicates over
  gRPC using the proto-generated modules from `antd/v1/*.proto`.

  All public functions return `{:ok, result}` or `{:error, exception}`.
  Bang variants (e.g. `health!/1`) raise on error.

  ## Proto compilation

  Run `protoc` with the Elixir gRPC plugin to generate stubs:

      protoc --elixir_out=plugins=grpc:lib \\
        -I../../antd/proto \\
        antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \\
        antd/v1/chunks.proto antd/v1/files.proto

  The generated modules are expected under `lib/antd/v1/`.
  """

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
        {:error, %Antd.AntdError{message: "failed to connect: #{inspect(reason)}", status_code: 0}}
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

  @doc "Stores public immutable data on the network."
  @spec data_put_public(t(), binary()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def data_put_public(%__MODULE__{channel: channel}, data) when is_binary(data) do
    req = Antd.V1.PutPublicDataRequest.new(data: data)

    case Antd.V1.DataService.Stub.put_public(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_put_public/2` but raises on error."
  @spec data_put_public!(t(), binary()) :: Antd.PutResult.t()
  def data_put_public!(client, data), do: unwrap!(data_put_public(client, data))

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

  @doc "Stores private encrypted data on the network."
  @spec data_put_private(t(), binary()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def data_put_private(%__MODULE__{channel: channel}, data) when is_binary(data) do
    req = Antd.V1.PutPrivateDataRequest.new(data: data)

    case Antd.V1.DataService.Stub.put_private(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.data_map}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_put_private/2` but raises on error."
  @spec data_put_private!(t(), binary()) :: Antd.PutResult.t()
  def data_put_private!(client, data), do: unwrap!(data_put_private(client, data))

  @doc "Retrieves private data using a data map."
  @spec data_get_private(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get_private(%__MODULE__{channel: channel}, data_map) do
    req = Antd.V1.GetPrivateDataRequest.new(data_map: data_map)

    case Antd.V1.DataService.Stub.get_private(channel, req) do
      {:ok, resp} -> {:ok, resp.data}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_get_private/2` but raises on error."
  @spec data_get_private!(t(), String.t()) :: binary()
  def data_get_private!(client, data_map), do: unwrap!(data_get_private(client, data_map))

  @doc "Pre-upload cost breakdown for the given bytes."
  @spec data_cost(t(), binary()) :: {:ok, Antd.UploadCostEstimate.t()} | {:error, Exception.t()}
  def data_cost(%__MODULE__{channel: channel}, data) when is_binary(data) do
    req = Antd.V1.DataCostRequest.new(data: data)

    case Antd.V1.DataService.Stub.get_cost(channel, req) do
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

  @doc "Like `data_cost/2` but raises on error."
  @spec data_cost!(t(), binary()) :: Antd.UploadCostEstimate.t()
  def data_cost!(client, data), do: unwrap!(data_cost(client, data))

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
  # Files & Directories
  # ---------------------------------------------------------------------------

  @doc "Uploads a local file to the network."
  @spec file_upload_public(t(), String.t()) :: {:ok, Antd.FileUploadResult.t()} | {:error, Exception.t()}
  def file_upload_public(%__MODULE__{channel: channel}, path) do
    req = Antd.V1.UploadFileRequest.new(path: path)

    case Antd.V1.FileService.Stub.upload_public(channel, req) do
      {:ok, resp} ->
        {:ok, file_upload_result_from_resp(resp)}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_upload_public/2` but raises on error."
  @spec file_upload_public!(t(), String.t()) :: Antd.FileUploadResult.t()
  def file_upload_public!(client, path), do: unwrap!(file_upload_public(client, path))

  @doc "Downloads a file from the network to a local path."
  @spec file_download_public(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def file_download_public(%__MODULE__{channel: channel}, address, dest_path) do
    req = Antd.V1.DownloadPublicRequest.new(address: address, dest_path: dest_path)

    case Antd.V1.FileService.Stub.download_public(channel, req) do
      {:ok, _resp} -> :ok
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_download_public/3` but raises on error."
  @spec file_download_public!(t(), String.t(), String.t()) :: :ok
  def file_download_public!(client, address, dest_path) do
    unwrap!(file_download_public(client, address, dest_path))
  end

  defp file_upload_result_from_resp(resp) do
    %Antd.FileUploadResult{
      address: resp.address,
      storage_cost_atto: resp.storage_cost_atto,
      gas_cost_wei: resp.gas_cost_wei,
      chunks_stored: resp.chunks_stored,
      payment_mode_used: resp.payment_mode_used
    }
  end

  @doc "Pre-upload cost breakdown for the file at `path`."
  @spec file_cost(t(), String.t(), boolean()) ::
          {:ok, Antd.UploadCostEstimate.t()} | {:error, Exception.t()}
  def file_cost(%__MODULE__{channel: channel}, path, is_public) do
    req =
      Antd.V1.FileCostRequest.new(
        path: path,
        is_public: is_public
      )

    case Antd.V1.FileService.Stub.get_file_cost(channel, req) do
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

  @doc "Like `file_cost/3` but raises on error."
  @spec file_cost!(t(), String.t(), boolean()) :: Antd.UploadCostEstimate.t()
  def file_cost!(client, path, is_public) do
    unwrap!(file_cost(client, path, is_public))
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
