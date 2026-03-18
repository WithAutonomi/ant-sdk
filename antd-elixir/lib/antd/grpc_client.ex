defmodule Antd.GrpcClient do
  @moduledoc """
  gRPC client for the antd daemon.

  Provides the same 19 functions as `Antd.Client` (REST), but communicates over
  gRPC using the proto-generated modules from `antd/v1/*.proto`.

  All public functions return `{:ok, result}` or `{:error, exception}`.
  Bang variants (e.g. `health!/1`) raise on error.

  ## Proto compilation

  Run `protoc` with the Elixir gRPC plugin to generate stubs:

      protoc --elixir_out=plugins=grpc:lib \\
        -I../../antd/proto \\
        antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \\
        antd/v1/chunks.proto antd/v1/graph.proto antd/v1/files.proto

  The generated modules are expected under `lib/antd/v1/`.
  """

  @default_target "localhost:50051"

  defstruct target: @default_target, channel: nil

  @type t :: %__MODULE__{
          target: String.t(),
          channel: GRPC.Channel.t() | nil
        }

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
        {:ok, %Antd.HealthStatus{ok: resp.status == "ok", network: resp.network}}

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

  @doc "Estimates the cost of storing data."
  @spec data_cost(t(), binary()) :: {:ok, String.t()} | {:error, Exception.t()}
  def data_cost(%__MODULE__{channel: channel}, data) when is_binary(data) do
    req = Antd.V1.DataCostRequest.new(data: data)

    case Antd.V1.DataService.Stub.get_cost(channel, req) do
      {:ok, resp} -> {:ok, resp.atto_tokens}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_cost/2` but raises on error."
  @spec data_cost!(t(), binary()) :: String.t()
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
  # Graph
  # ---------------------------------------------------------------------------

  @doc "Creates a new graph entry (DAG node)."
  @spec graph_entry_put(t(), String.t(), [String.t()], String.t(), [Antd.GraphDescendant.t()]) ::
          {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def graph_entry_put(%__MODULE__{channel: channel}, owner_secret_key, parents, content, descendants) do
    descs =
      Enum.map(descendants, fn d ->
        Antd.V1.GraphDescendant.new(public_key: d.public_key, content: d.content)
      end)

    req =
      Antd.V1.PutGraphEntryRequest.new(
        owner_secret_key: owner_secret_key,
        parents: parents,
        content: content,
        descendants: descs
      )

    case Antd.V1.GraphService.Stub.put(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `graph_entry_put/5` but raises on error."
  @spec graph_entry_put!(t(), String.t(), [String.t()], String.t(), [Antd.GraphDescendant.t()]) ::
          Antd.PutResult.t()
  def graph_entry_put!(client, owner_secret_key, parents, content, descendants) do
    unwrap!(graph_entry_put(client, owner_secret_key, parents, content, descendants))
  end

  @doc "Retrieves a graph entry by address."
  @spec graph_entry_get(t(), String.t()) :: {:ok, Antd.GraphEntry.t()} | {:error, Exception.t()}
  def graph_entry_get(%__MODULE__{channel: channel}, address) do
    req = Antd.V1.GetGraphEntryRequest.new(address: address)

    case Antd.V1.GraphService.Stub.get(channel, req) do
      {:ok, resp} ->
        descendants =
          Enum.map(resp.descendants, fn d ->
            %Antd.GraphDescendant{public_key: d.public_key, content: d.content}
          end)

        {:ok,
         %Antd.GraphEntry{
           owner: resp.owner,
           parents: Enum.to_list(resp.parents),
           content: resp.content,
           descendants: descendants
         }}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `graph_entry_get/2` but raises on error."
  @spec graph_entry_get!(t(), String.t()) :: Antd.GraphEntry.t()
  def graph_entry_get!(client, address), do: unwrap!(graph_entry_get(client, address))

  @doc "Checks if a graph entry exists at the given address."
  @spec graph_entry_exists(t(), String.t()) :: {:ok, boolean()} | {:error, Exception.t()}
  def graph_entry_exists(%__MODULE__{channel: channel}, address) do
    req = Antd.V1.CheckGraphEntryRequest.new(address: address)

    case Antd.V1.GraphService.Stub.check_existence(channel, req) do
      {:ok, resp} -> {:ok, resp.exists}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `graph_entry_exists/2` but raises on error."
  @spec graph_entry_exists!(t(), String.t()) :: boolean()
  def graph_entry_exists!(client, address), do: unwrap!(graph_entry_exists(client, address))

  @doc "Estimates the cost of creating a graph entry."
  @spec graph_entry_cost(t(), String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def graph_entry_cost(%__MODULE__{channel: channel}, public_key) do
    req = Antd.V1.GraphEntryCostRequest.new(public_key: public_key)

    case Antd.V1.GraphService.Stub.get_cost(channel, req) do
      {:ok, resp} -> {:ok, resp.atto_tokens}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `graph_entry_cost/2` but raises on error."
  @spec graph_entry_cost!(t(), String.t()) :: String.t()
  def graph_entry_cost!(client, public_key), do: unwrap!(graph_entry_cost(client, public_key))

  # ---------------------------------------------------------------------------
  # Files & Directories
  # ---------------------------------------------------------------------------

  @doc "Uploads a local file to the network."
  @spec file_upload_public(t(), String.t()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def file_upload_public(%__MODULE__{channel: channel}, path) do
    req = Antd.V1.UploadFileRequest.new(path: path)

    case Antd.V1.FileService.Stub.upload_public(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_upload_public/2` but raises on error."
  @spec file_upload_public!(t(), String.t()) :: Antd.PutResult.t()
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

  @doc "Uploads a local directory to the network."
  @spec dir_upload_public(t(), String.t()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def dir_upload_public(%__MODULE__{channel: channel}, path) do
    req = Antd.V1.UploadFileRequest.new(path: path)

    case Antd.V1.FileService.Stub.dir_upload_public(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `dir_upload_public/2` but raises on error."
  @spec dir_upload_public!(t(), String.t()) :: Antd.PutResult.t()
  def dir_upload_public!(client, path), do: unwrap!(dir_upload_public(client, path))

  @doc "Downloads a directory from the network to a local path."
  @spec dir_download_public(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def dir_download_public(%__MODULE__{channel: channel}, address, dest_path) do
    req = Antd.V1.DownloadPublicRequest.new(address: address, dest_path: dest_path)

    case Antd.V1.FileService.Stub.dir_download_public(channel, req) do
      {:ok, _resp} -> :ok
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `dir_download_public/3` but raises on error."
  @spec dir_download_public!(t(), String.t(), String.t()) :: :ok
  def dir_download_public!(client, address, dest_path) do
    unwrap!(dir_download_public(client, address, dest_path))
  end

  @doc "Retrieves an archive manifest by address."
  @spec archive_get_public(t(), String.t()) :: {:ok, Antd.Archive.t()} | {:error, Exception.t()}
  def archive_get_public(%__MODULE__{channel: channel}, address) do
    req = Antd.V1.ArchiveGetRequest.new(address: address)

    case Antd.V1.FileService.Stub.archive_get_public(channel, req) do
      {:ok, resp} ->
        entries =
          Enum.map(resp.entries, fn e ->
            %Antd.ArchiveEntry{
              path: e.path,
              address: e.address,
              created: e.created,
              modified: e.modified,
              size: e.size
            }
          end)

        {:ok, %Antd.Archive{entries: entries}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `archive_get_public/2` but raises on error."
  @spec archive_get_public!(t(), String.t()) :: Antd.Archive.t()
  def archive_get_public!(client, address), do: unwrap!(archive_get_public(client, address))

  @doc "Creates an archive manifest on the network."
  @spec archive_put_public(t(), Antd.Archive.t()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def archive_put_public(%__MODULE__{channel: channel}, %Antd.Archive{} = archive) do
    entries =
      Enum.map(archive.entries, fn e ->
        Antd.V1.ArchiveEntry.new(
          path: e.path,
          address: e.address,
          created: e.created,
          modified: e.modified,
          size: e.size
        )
      end)

    req = Antd.V1.ArchivePutRequest.new(entries: entries)

    case Antd.V1.FileService.Stub.archive_put_public(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.PutResult{cost: resp.cost.atto_tokens, address: resp.address}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `archive_put_public/2` but raises on error."
  @spec archive_put_public!(t(), Antd.Archive.t()) :: Antd.PutResult.t()
  def archive_put_public!(client, archive), do: unwrap!(archive_put_public(client, archive))

  @doc "Estimates the cost of uploading a file."
  @spec file_cost(t(), String.t(), boolean(), boolean()) :: {:ok, String.t()} | {:error, Exception.t()}
  def file_cost(%__MODULE__{channel: channel}, path, is_public, include_archive) do
    req =
      Antd.V1.FileCostRequest.new(
        path: path,
        is_public: is_public,
        include_archive: include_archive
      )

    case Antd.V1.FileService.Stub.get_file_cost(channel, req) do
      {:ok, resp} -> {:ok, resp.atto_tokens}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `file_cost/4` but raises on error."
  @spec file_cost!(t(), String.t(), boolean(), boolean()) :: String.t()
  def file_cost!(client, path, is_public, include_archive) do
    unwrap!(file_cost(client, path, is_public, include_archive))
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp unwrap!({:ok, result}), do: result
  defp unwrap!(:ok), do: :ok
  defp unwrap!({:error, exception}), do: raise(exception)

  defp translate_error(%GRPC.RPCError{status: status, message: message}) do
    case status do
      GRPC.Status.invalid_argument() ->
        %Antd.BadRequestError{message: message, status_code: 400}

      GRPC.Status.not_found() ->
        %Antd.NotFoundError{message: message, status_code: 404}

      GRPC.Status.already_exists() ->
        %Antd.AlreadyExistsError{message: message, status_code: 409}

      GRPC.Status.resource_exhausted() ->
        %Antd.TooLargeError{message: message, status_code: 413}

      GRPC.Status.internal() ->
        %Antd.InternalError{message: message, status_code: 500}

      GRPC.Status.unavailable() ->
        %Antd.NetworkError{message: message, status_code: 502}

      GRPC.Status.failed_precondition() ->
        %Antd.PaymentError{message: message, status_code: 402}

      _ ->
        %Antd.AntdError{message: message, status_code: status}
    end
  end

  defp translate_error(other) do
    %Antd.AntdError{message: inspect(other), status_code: 0}
  end
end
