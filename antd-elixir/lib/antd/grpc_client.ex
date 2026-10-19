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

  The generated modules under `lib/antd/v1/` are committed; regenerate them
  with `scripts/generate-protos.sh`, which pins protoc-gen-elixir and lists
  the protos this SDK ships stubs for.

  ## Pointers

  The `pointer_*` functions mirror `Antd.Client`'s, each with a `:timeout`
  option (milliseconds, default 5 minutes). Every write pays, and every
  attempt pays again, so they never retry and callers should not either.
  Errors that share a gRPC status with older ones are told apart by the
  daemon's `x-antd-error-code` metadata, trusted only when it agrees with the
  status code.
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
    # Antd.GrpcAdapter is grpc's Gun adapter, except that it keeps a failed
    # unary call's metadata when asked to (the pointer functions read the
    # daemon's x-antd-error-code from it). Every other call behaves as with
    # the default adapter.
    case GRPC.Stub.connect(target, adapter: Antd.GrpcAdapter) do
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
    req = %Antd.V1.HealthCheckRequest{}

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
      %Antd.V1.PutDataRequest{
        data: data,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      }

    case Antd.V1.DataService.Stub.put(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.DataPutResult{data_map: resp.data_map, chunks_stored: resp.chunks_stored, payment_mode_used: resp.payment_mode_used}}

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
    req = %Antd.V1.GetDataRequest{data_map: data_map}

    case Antd.V1.DataService.Stub.get(channel, req) do
      {:ok, resp} -> {:ok, resp.data}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_get/2` but raises on error."
  @spec data_get!(t(), String.t()) :: binary()
  def data_get!(client, data_map), do: unwrap!(data_get(client, data_map))

  @doc """
  Streams private data from a caller-held DataMap, one decrypt batch at a time,
  instead of buffering the whole object. The gRPC counterpart to `data_get/2`
  and mirror of the REST client's `data_stream/2`.

  On success returns `{:ok, enumerable}` where enumerating yields binary chunks;
  concatenate or write them as they arrive, e.g.

      {:ok, stream} = Antd.GrpcClient.data_stream(client, data_map)
      Enum.into(stream, File.stream!("out.bin"))

  A mid-stream gRPC error is raised as the translated exception while the
  enumerable is consumed.
  """
  @spec data_stream(t(), String.t()) :: {:ok, Enumerable.t()} | {:error, Exception.t()}
  def data_stream(%__MODULE__{channel: channel}, data_map) when is_binary(data_map) do
    req = %Antd.V1.StreamDataRequest{data_map: data_map}

    case Antd.V1.DataService.Stub.stream(channel, req) do
      {:ok, reply_enum} -> {:ok, map_chunk_stream(reply_enum)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_stream/2` but raises on error."
  @spec data_stream!(t(), String.t()) :: Enumerable.t()
  def data_stream!(client, data_map), do: unwrap!(data_stream(client, data_map))

  @doc """
  `data_stream/2` with interleaved fetch-progress frames so the caller can drive
  a *determinate* download progress bar. Sets the request's `include_progress`
  flag; enumerating the returned stream yields `Antd.DownloadFrame` structs —
  each a plaintext chunk (`:data`) or a `Antd.DownloadProgress` update
  (`:progress`). The byte denominator arrives separately as the
  `x-content-length` response header.

      {:ok, frames} = Antd.GrpcClient.data_stream_with_progress(client, data_map)
      Enum.each(frames, fn
        %Antd.DownloadFrame{progress: %{} = p} -> render_bar(p.fetched, p.total)
        %Antd.DownloadFrame{data: bytes} -> IO.binwrite(bytes)
      end)
  """
  @spec data_stream_with_progress(t(), String.t()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def data_stream_with_progress(%__MODULE__{channel: channel}, data_map)
      when is_binary(data_map) do
    req = %Antd.V1.StreamDataRequest{data_map: data_map, include_progress: true}

    case Antd.V1.DataService.Stub.stream(channel, req, return_headers: true) do
      {:ok, reply_enum, %{headers: headers}} ->
        {:ok, prepend_meta(headers, map_frame_stream(reply_enum))}

      {:ok, reply_enum} ->
        {:ok, map_frame_stream(reply_enum)}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_stream_with_progress/2` but raises on error."
  @spec data_stream_with_progress!(t(), String.t()) :: Enumerable.t()
  def data_stream_with_progress!(client, data_map),
    do: unwrap!(data_stream_with_progress(client, data_map))

  @doc """
  Stores public data on the network.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_put_public(t(), binary(), keyword()) ::
          {:ok, Antd.DataPutPublicResult.t()} | {:error, Exception.t()}
  def data_put_public(%__MODULE__{channel: channel}, data, opts \\ []) when is_binary(data) do
    req =
      %Antd.V1.PutPublicDataRequest{
        data: data,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      }

    case Antd.V1.DataService.Stub.put_public(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.DataPutPublicResult{address: resp.address, chunks_stored: resp.chunks_stored, payment_mode_used: resp.payment_mode_used}}

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
    req = %Antd.V1.GetPublicDataRequest{address: address}

    case Antd.V1.DataService.Stub.get_public(channel, req) do
      {:ok, resp} -> {:ok, resp.data}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_get_public/2` but raises on error."
  @spec data_get_public!(t(), String.t()) :: binary()
  def data_get_public!(client, address), do: unwrap!(data_get_public(client, address))

  @doc """
  Streams public data by address — the gRPC counterpart to `data_get_public/2`.
  Same `{:ok, enumerable}` of binary chunks contract as `data_stream/2`.
  """
  @spec data_stream_public(t(), String.t()) :: {:ok, Enumerable.t()} | {:error, Exception.t()}
  def data_stream_public(%__MODULE__{channel: channel}, address) when is_binary(address) do
    req = %Antd.V1.StreamPublicDataRequest{address: address}

    case Antd.V1.DataService.Stub.stream_public(channel, req) do
      {:ok, reply_enum} -> {:ok, map_chunk_stream(reply_enum)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_stream_public/2` but raises on error."
  @spec data_stream_public!(t(), String.t()) :: Enumerable.t()
  def data_stream_public!(client, address), do: unwrap!(data_stream_public(client, address))

  @doc """
  `data_stream_public/2` with interleaved fetch-progress frames. See
  `data_stream_with_progress/2`.
  """
  @spec data_stream_public_with_progress(t(), String.t()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def data_stream_public_with_progress(%__MODULE__{channel: channel}, address)
      when is_binary(address) do
    req = %Antd.V1.StreamPublicDataRequest{address: address, include_progress: true}

    case Antd.V1.DataService.Stub.stream_public(channel, req, return_headers: true) do
      {:ok, reply_enum, %{headers: headers}} ->
        {:ok, prepend_meta(headers, map_frame_stream(reply_enum))}

      {:ok, reply_enum} ->
        {:ok, map_frame_stream(reply_enum)}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `data_stream_public_with_progress/2` but raises on error."
  @spec data_stream_public_with_progress!(t(), String.t()) :: Enumerable.t()
  def data_stream_public_with_progress!(client, address),
    do: unwrap!(data_stream_public_with_progress(client, address))

  # Maps a server-stream of DataChunk results into a lazy stream of raw binary
  # chunk payloads. A mid-stream {:error, _} is raised as the translated
  # exception during consumption (the head-of-call error is handled by the
  # caller's case on the Stub return).
  defp map_chunk_stream(reply_enum) do
    # `DataChunk` is a oneof `kind {data | progress}`. The plain stream leaves
    # `include_progress` false, so only `{:data, _}` arms arrive; any stray
    # progress / unset frame is dropped so the byte stream stays pure.
    Stream.flat_map(reply_enum, fn
      {:ok, %Antd.V1.DataChunk{kind: {:data, data}}} -> [data]
      %Antd.V1.DataChunk{kind: {:data, data}} -> [data]
      {:ok, %Antd.V1.DataChunk{}} -> []
      %Antd.V1.DataChunk{} -> []
      {:error, rpc_error} -> raise translate_error(rpc_error)
    end)
  end

  # Maps a server-stream of DataChunk results into a lazy stream of
  # `Antd.DownloadFrame` structs — either a plaintext chunk or a
  # `Antd.DownloadProgress` update. A mid-stream {:error, _} is raised as the
  # translated exception during consumption. `return_headers: true` appends a
  # `{:trailers, _}` (and may yield `{:headers, _}`) item — drop those.
  defp map_frame_stream(reply_enum) do
    reply_enum
    |> Stream.reject(&match?({:trailers, _}, &1))
    |> Stream.reject(&match?({:headers, _}, &1))
    |> Stream.map(fn
      {:ok, %Antd.V1.DataChunk{} = chunk} -> frame_of(chunk)
      %Antd.V1.DataChunk{} = chunk -> frame_of(chunk)
      {:error, rpc_error} -> raise translate_error(rpc_error)
    end)
  end

  # Prepend a byte-total `Antd.DownloadFrame` (`:meta`) read from the gRPC
  # `x-content-length` response header, when present, ahead of the frame stream.
  defp prepend_meta(headers, frame_stream) do
    case meta_from_headers(headers) do
      nil -> frame_stream
      frame -> Stream.concat([frame], frame_stream)
    end
  end

  defp meta_from_headers(headers) when is_map(headers) do
    case Map.get(headers, "x-content-length") do
      nil ->
        nil

      value ->
        case Integer.parse(to_string(value)) do
          {n, _} -> %Antd.DownloadFrame{meta: n}
          :error -> nil
        end
    end
  end

  defp meta_from_headers(_), do: nil

  defp frame_of(%Antd.V1.DataChunk{kind: {:progress, p}}) do
    %Antd.DownloadFrame{
      progress: %Antd.DownloadProgress{phase: p.phase, fetched: p.fetched, total: p.total}
    }
  end

  defp frame_of(%Antd.V1.DataChunk{kind: {:data, data}}), do: %Antd.DownloadFrame{data: data}
  defp frame_of(%Antd.V1.DataChunk{}), do: %Antd.DownloadFrame{data: ""}

  @doc """
  Pre-upload cost breakdown for the given bytes.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_cost(t(), binary(), keyword()) ::
          {:ok, Antd.UploadCostEstimate.t()} | {:error, Exception.t()}
  def data_cost(%__MODULE__{channel: channel}, data, opts \\ []) when is_binary(data) do
    req =
      %Antd.V1.DataCostRequest{
        data: data,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      }

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
    req = %Antd.V1.PutChunkRequest{data: data}

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
    req = %Antd.V1.GetChunkRequest{address: address}

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
      %Antd.V1.PutFileRequest{
        path: path,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      }

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
    req = %Antd.V1.GetFileRequest{data_map: data_map, dest_path: dest_path}

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
      %Antd.V1.PutFileRequest{
        path: path,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      }

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
    req = %Antd.V1.GetFilePublicRequest{address: address, dest_path: dest_path}

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
      %Antd.V1.FileCostRequest{
        path: path,
        is_public: is_public,
        payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
      }

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
  # External signer (two-phase upload)
  # ---------------------------------------------------------------------------

  @doc """
  Prepares a file upload for external signing.

  ## Options

    * `:visibility` — `"public"` bundles the DataMap chunk into the same
      external-signer payment batch so finalize returns its on-network
      address via `:data_map_address`. Omitting the option leaves the
      proto3 default of `""`, preserving the wire shape for daemons
      predating the public-prepare addition.
  """
  @spec prepare_upload(t(), String.t(), keyword()) ::
          {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_upload(%__MODULE__{channel: channel}, path, opts \\ []) do
    req =
      %Antd.V1.PrepareFileUploadRequest{
        path: path,
        visibility: Keyword.get(opts, :visibility, "")
      }

    case Antd.V1.UploadService.Stub.prepare_file_upload(channel, req) do
      {:ok, resp} -> {:ok, prepare_response_from_proto(resp)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `prepare_upload/3` but raises on error."
  @spec prepare_upload!(t(), String.t(), keyword()) :: Antd.PrepareUploadResult.t()
  def prepare_upload!(client, path, opts \\ []), do: unwrap!(prepare_upload(client, path, opts))

  @doc """
  Convenience wrapper: prepare a *public* file upload for external signing.
  Equivalent to `prepare_upload(client, path, visibility: "public")`.
  """
  @spec prepare_upload_public(t(), String.t()) ::
          {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_upload_public(%__MODULE__{} = client, path),
    do: prepare_upload(client, path, visibility: "public")

  @doc "Like `prepare_upload_public/2` but raises on error."
  @spec prepare_upload_public!(t(), String.t()) :: Antd.PrepareUploadResult.t()
  def prepare_upload_public!(client, path), do: unwrap!(prepare_upload_public(client, path))

  @doc """
  Prepares an in-memory data upload for external signing.

  ## Options

    * `:visibility` — see `prepare_upload/3`.
  """
  @spec prepare_data_upload(t(), binary(), keyword()) ::
          {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_data_upload(%__MODULE__{channel: channel}, data, opts \\ [])
      when is_binary(data) do
    req =
      %Antd.V1.PrepareDataUploadRequest{
        data: data,
        visibility: Keyword.get(opts, :visibility, "")
      }

    case Antd.V1.UploadService.Stub.prepare_data_upload(channel, req) do
      {:ok, resp} -> {:ok, prepare_response_from_proto(resp)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `prepare_data_upload/3` but raises on error."
  @spec prepare_data_upload!(t(), binary(), keyword()) :: Antd.PrepareUploadResult.t()
  def prepare_data_upload!(client, data, opts \\ []),
    do: unwrap!(prepare_data_upload(client, data, opts))

  @doc """
  Finalizes a wave-batch upload after an external signer has submitted
  the `payForQuotes()` transactions. `tx_hashes` maps each `quote_hash`
  from the prepare result to its on-chain `tx_hash`.

  A finalize that stored only part of the upload returns
  `{:error, %Antd.PartialUploadError{}}` (gRPC `ABORTED` whose message
  starts with `Partial upload:`; this used to be a plain `Antd.AntdError`,
  as any other `ABORTED` still is) carrying `chunks_stored`, `chunks_failed`,
  `total_chunks`, `retryable` and `retention_known`, parsed from the status
  message: `retention_known` is `true` only when the counts parse and the
  message ends with one of the daemon's two closing hints, which then
  decides `retryable` ("paid attempt retained" sets it; "stored chunks
  persist; re-prepare the same content" means nothing was retained).
  Readable counts with a missing, truncated or unrecognised hint keep the
  counts but read as retention unknown. The payment persists and the stored
  chunks stay on the network. Recovery has three cases:

    * `retryable: true` (antd >= 0.14.0) — the daemon kept the paid attempt
      under the same `upload_id`: call this function again with the same
      arguments to store the remainder against the same payment. Bound that
      loop (cap the attempts; a `chunks_failed` that stops shrinking means
      stuck).
    * `retention_known: true, retryable: false` — the daemon confirmed it
      kept nothing: re-prepare the same content (already-stored chunks are
      skipped, so the retry pays only for the remainder).
    * `retention_known: false` — the status message's counts or closing
      hint could not be read, so retention is unknown and the daemon may
      still hold the paid attempt. Stop automatic recovery, keep `upload_id`
      and `tx_hashes`, and reconcile before re-preparing or paying again.

  See `Antd.PartialUploadError`, `docs/external-signer-flow.md` §6 and
  `examples/07_external_signer.exs`.
  """
  @spec finalize_upload(t(), String.t(), map()) ::
          {:ok, Antd.FinalizeUploadResult.t()} | {:error, Exception.t()}
  def finalize_upload(%__MODULE__{channel: channel}, upload_id, tx_hashes) do
    req =
      %Antd.V1.FinalizeUploadRequest{
        upload_id: upload_id,
        tx_hashes: tx_hashes
      }

    case Antd.V1.UploadService.Stub.finalize_upload(channel, req) do
      {:ok, resp} -> {:ok, finalize_response_from_proto(resp)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `finalize_upload/3` but raises on error."
  @spec finalize_upload!(t(), String.t(), map()) :: Antd.FinalizeUploadResult.t()
  def finalize_upload!(client, upload_id, tx_hashes),
    do: unwrap!(finalize_upload(client, upload_id, tx_hashes))

  @doc """
  Finalizes a merkle-batch upload after the external signer has submitted
  the `payForMerkleTree2()` transaction. `winner_pool_hash` is the
  bytes32 from the `MerklePaymentMade` event (hex with `0x` prefix).

  A partial store surfaces as `{:error, %Antd.PartialUploadError{}}` exactly
  as for `finalize_upload/3`, with the same three cases: retry the same call
  (bounded) while `retryable` is `true`; re-prepare the same content only
  when `retention_known` is `true` and `retryable` is `false` (for example a
  merkle finalize with deliberately unpaid batches); and when
  `retention_known` is `false`, stop, keep `upload_id` and
  `winner_pool_hash`, and reconcile before re-preparing or paying again.

  ## Options

    * `:store_data_map` — legacy daemon-wallet path; when `true`, the
      daemon stores the DataMap on-network and returns its address.
      Prefer `:visibility => "public"` on prepare for the public-DataMap
      case. Omitting the option leaves the proto3 default of `false`.
  """
  @spec finalize_merkle_upload(t(), String.t(), String.t(), keyword()) ::
          {:ok, Antd.FinalizeUploadResult.t()} | {:error, Exception.t()}
  def finalize_merkle_upload(%__MODULE__{channel: channel}, upload_id, winner_pool_hash,
                             opts \\ []) do
    req =
      %Antd.V1.FinalizeUploadRequest{
        upload_id: upload_id,
        winner_pool_hash: winner_pool_hash,
        store_data_map: Keyword.get(opts, :store_data_map, false)
      }

    case Antd.V1.UploadService.Stub.finalize_upload(channel, req) do
      {:ok, resp} -> {:ok, finalize_response_from_proto(resp)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `finalize_merkle_upload/4` but raises on error."
  @spec finalize_merkle_upload!(t(), String.t(), String.t(), keyword()) ::
          Antd.FinalizeUploadResult.t()
  def finalize_merkle_upload!(client, upload_id, winner_pool_hash, opts \\ []),
    do: unwrap!(finalize_merkle_upload(client, upload_id, winner_pool_hash, opts))

  @doc """
  Prepares a single-chunk publish for external signing.

  Returns either `already_stored: true` (no payment needed, no finalize
  call required) or a wave-batch payment intent the external signer must
  execute before calling `finalize_chunk_upload/3`.
  """
  @spec prepare_chunk_upload(t(), binary()) ::
          {:ok, Antd.PrepareChunkResult.t()} | {:error, Exception.t()}
  def prepare_chunk_upload(%__MODULE__{channel: channel}, data) when is_binary(data) do
    req = %Antd.V1.PrepareChunkRequest{data: data}

    case Antd.V1.ChunkService.Stub.prepare_chunk(channel, req) do
      {:ok, resp} -> {:ok, prepare_chunk_response_from_proto(resp)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `prepare_chunk_upload/2` but raises on error."
  @spec prepare_chunk_upload!(t(), binary()) :: Antd.PrepareChunkResult.t()
  def prepare_chunk_upload!(client, data), do: unwrap!(prepare_chunk_upload(client, data))

  @doc """
  Submits a prepared chunk after external payment. Returns the on-network
  address of the stored chunk (matches `PrepareChunkResult.address`).
  """
  @spec finalize_chunk_upload(t(), String.t(), map()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def finalize_chunk_upload(%__MODULE__{channel: channel}, upload_id, tx_hashes) do
    req = %Antd.V1.FinalizeChunkRequest{upload_id: upload_id, tx_hashes: tx_hashes}

    case Antd.V1.ChunkService.Stub.finalize_chunk(channel, req) do
      {:ok, resp} -> {:ok, resp.address}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `finalize_chunk_upload/3` but raises on error."
  @spec finalize_chunk_upload!(t(), String.t(), map()) :: String.t()
  def finalize_chunk_upload!(client, upload_id, tx_hashes),
    do: unwrap!(finalize_chunk_upload(client, upload_id, tx_hashes))

  # ---------------------------------------------------------------------------
  # Pointers
  # ---------------------------------------------------------------------------
  #
  # PointerService: the same functions, results and errors as the REST
  # client's pointer functions (see `Antd.Client`). Every write pays, and
  # every attempt pays again: none of these functions retries, and callers
  # must not retry pointer_create, pointer_update, pointer_transfer or
  # pointer_finalize automatically. Reads are free to retry.
  #
  # Each call keeps the response metadata (`return_headers: true`, which
  # Antd.GrpcAdapter extends to failed calls), because the daemon sends its
  # error code there (x-antd-error-code) for the errors that share a gRPC
  # status with older ones: POINTER_FINAL and POINTER_FORKED
  # (FAILED_PRECONDITION, otherwise a PaymentError), CONFLICT (ABORTED) and
  # CLOSE_GROUP_SHORTFALL (UNAVAILABLE, otherwise a NetworkError). The tag is
  # trusted only when it agrees with the status (`Antd.Errors.grpc_tagged_error/3`).
  #
  # Every pointer function takes a `:timeout` option in milliseconds. It
  # defaults to 5 minutes, the REST client's default, rather than grpc's
  # 10 seconds, since a write quotes, pays and stores before it answers.

  @pointer_timeout 300_000
  @error_code_key "x-antd-error-code"

  @doc """
  Lists the pointers this daemon holds owner keys for, as their addresses.
  Mirrors `Antd.Client.pointer_keys/1`.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_keys(t(), keyword()) :: {:ok, [String.t()]} | {:error, Exception.t()}
  def pointer_keys(%__MODULE__{channel: channel}, opts \\ []) do
    req = %Antd.V1.ListPointerKeysRequest{}

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.list_keys/3, channel, req, opts) do
      {:ok, Enum.map(resp.keys, & &1.address)}
    end
  end

  @doc "Like `pointer_keys/2` but raises on error."
  @spec pointer_keys!(t(), keyword()) :: [String.t()]
  def pointer_keys!(client, opts \\ []), do: unwrap!(pointer_keys(client, opts))

  @doc """
  Creates the pointer at `owner`, pointing at `target`, paid by the daemon
  wallet. Mirrors `Antd.Client.pointer_create/4`: `Antd.AlreadyExistsError`
  if it exists, refused before paying. **Each call pays**: do not retry it
  automatically.

  ## Options

    * `:kind` — `t:Antd.PointerKind.t/0` (`:chunk`, the daemon's default, or
      `:pointer`).
    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_create(t(), String.t(), String.t(), keyword()) ::
          {:ok, Antd.PointerWriteResult.t()} | {:error, Exception.t()}
  def pointer_create(%__MODULE__{channel: channel}, owner, target, opts \\ [])
      when is_binary(owner) and is_binary(target) do
    pointer_write(&Antd.V1.PointerService.Stub.create/3, channel, owner, target, opts)
  end

  @doc "Like `pointer_create/4` but raises on error."
  @spec pointer_create!(t(), String.t(), String.t(), keyword()) :: Antd.PointerWriteResult.t()
  def pointer_create!(client, owner, target, opts \\ []),
    do: unwrap!(pointer_create(client, owner, target, opts))

  @doc """
  Points the pointer at `owner` at `target`, paid by the daemon wallet,
  creating it if it does not exist. Mirrors `Antd.Client.pointer_update/4`:
  `Antd.PointerFinalError` once it was transferred or frozen (usually refused
  before paying), and `Antd.ConflictError` if a prepared write awaits payment
  (refused before paying) or the update lost to a newer state (possibly after
  paying). **Each call pays**: do not retry it automatically. Takes the same
  options as `pointer_create/4`.
  """
  @spec pointer_update(t(), String.t(), String.t(), keyword()) ::
          {:ok, Antd.PointerWriteResult.t()} | {:error, Exception.t()}
  def pointer_update(%__MODULE__{channel: channel}, owner, target, opts \\ [])
      when is_binary(owner) and is_binary(target) do
    pointer_write(&Antd.V1.PointerService.Stub.update/3, channel, owner, target, opts)
  end

  @doc "Like `pointer_update/4` but raises on error."
  @spec pointer_update!(t(), String.t(), String.t(), keyword()) :: Antd.PointerWriteResult.t()
  def pointer_update!(client, owner, target, opts \\ []),
    do: unwrap!(pointer_update(client, owner, target, opts))

  defp pointer_write(rpc, channel, owner, target, opts) do
    kind =
      case Keyword.get(opts, :kind) do
        nil -> ""
        kind -> Antd.PointerKind.to_wire(kind)
      end

    req = %Antd.V1.PointerWriteRequest{owner: owner, target: target, kind: kind}

    with {:ok, resp} <- pointer_call(rpc, channel, req, opts) do
      Antd.Pointers.write_from_proto(resp)
    end
  end

  @doc """
  Hands the pointer at `owner` over to the pointer at `recipient`, for good,
  paid by the daemon wallet. Mirrors `Antd.Client.pointer_transfer/3`.
  Irreversible once stored. **Each call pays**: do not retry it
  automatically.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_transfer(t(), String.t(), String.t(), keyword()) ::
          {:ok, Antd.PointerTransferResult.t()} | {:error, Exception.t()}
  def pointer_transfer(%__MODULE__{channel: channel}, owner, recipient, opts \\ [])
      when is_binary(owner) and is_binary(recipient) do
    req = %Antd.V1.PointerTransferRequest{owner: owner, recipient: recipient}

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.transfer/3, channel, req, opts) do
      Antd.Pointers.transfer_from_proto(resp)
    end
  end

  @doc "Like `pointer_transfer/4` but raises on error."
  @spec pointer_transfer!(t(), String.t(), String.t(), keyword()) ::
          Antd.PointerTransferResult.t()
  def pointer_transfer!(client, owner, recipient, opts \\ []),
    do: unwrap!(pointer_transfer(client, owner, recipient, opts))

  @doc """
  Reads the pointer at `address`. Mirrors `Antd.Client.pointer_get/2`:
  `Antd.NotFoundError` if there is none.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_get(t(), String.t(), keyword()) ::
          {:ok, Antd.PointerRecord.t()} | {:error, Exception.t()}
  def pointer_get(%__MODULE__{channel: channel}, address, opts \\ []) when is_binary(address) do
    req = %Antd.V1.GetPointerRequest{address: address}

    with {:ok, resp} <- pointer_call(&Antd.V1.PointerService.Stub.get/3, channel, req, opts) do
      Antd.Pointers.record_from_proto(resp)
    end
  end

  @doc "Like `pointer_get/3` but raises on error."
  @spec pointer_get!(t(), String.t(), keyword()) :: Antd.PointerRecord.t()
  def pointer_get!(client, address, opts \\ []), do: unwrap!(pointer_get(client, address, opts))

  @doc """
  Follows a chain of pointers from `address` to the target at its end.
  Mirrors `Antd.Client.pointer_resolve/2`.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_resolve(t(), String.t(), keyword()) ::
          {:ok, Antd.PointerTarget.t()} | {:error, Exception.t()}
  def pointer_resolve(%__MODULE__{channel: channel}, address, opts \\ [])
      when is_binary(address) do
    req = %Antd.V1.ResolvePointerRequest{address: address}

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.resolve/3, channel, req, opts) do
      {:ok, Antd.Pointers.target_from_proto(resp)}
    end
  end

  @doc "Like `pointer_resolve/3` but raises on error."
  @spec pointer_resolve!(t(), String.t(), keyword()) :: Antd.PointerTarget.t()
  def pointer_resolve!(client, address, opts \\ []),
    do: unwrap!(pointer_resolve(client, address, opts))

  @doc """
  Asks the whole close group where the pointer at `address` stands. Mirrors
  `Antd.Client.pointer_finality/2`; an unset counter, state or majority (an
  empty string or absent message on the wire) reads as `nil`.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_finality(t(), String.t(), keyword()) ::
          {:ok, Antd.PointerFinality.t()} | {:error, Exception.t()}
  def pointer_finality(%__MODULE__{channel: channel}, address, opts \\ [])
      when is_binary(address) do
    req = %Antd.V1.PointerFinalityRequest{address: address}

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.finality/3, channel, req, opts) do
      Antd.Pointers.finality_from_proto(resp)
    end
  end

  @doc "Like `pointer_finality/3` but raises on error."
  @spec pointer_finality!(t(), String.t(), keyword()) :: Antd.PointerFinality.t()
  def pointer_finality!(client, address, opts \\ []),
    do: unwrap!(pointer_finality(client, address, opts))

  @doc """
  Follows the transfers of the pointer at `address` to the pointer whose
  owner now decides what it resolves to. Mirrors
  `Antd.Client.pointer_controller/2`.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_controller(t(), String.t(), keyword()) ::
          {:ok, Antd.PointerController.t()} | {:error, Exception.t()}
  def pointer_controller(%__MODULE__{channel: channel}, address, opts \\ [])
      when is_binary(address) do
    req = %Antd.V1.PointerControllerRequest{address: address}

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.controller/3, channel, req, opts) do
      {:ok, Antd.Pointers.controller_from_proto(resp)}
    end
  end

  @doc "Like `pointer_controller/3` but raises on error."
  @spec pointer_controller!(t(), String.t(), keyword()) :: Antd.PointerController.t()
  def pointer_controller!(client, address, opts \\ []),
    do: unwrap!(pointer_controller(client, address, opts))

  @doc """
  Has the daemon sign `op` on the pointer at `owner` and quote it for an
  external signer. Mirrors `Antd.Client.pointer_prepare/4`; `op` is an
  `t:Antd.PointerOp.t/0`.

  ## Options

    * `:include_signed_quotes` — when `true`, the result's `signed_quotes`
      carries each quote in full signed form (base64, as over REST).
    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_prepare(t(), String.t(), Antd.PointerOp.t(), keyword()) ::
          {:ok, Antd.PointerPrepareResult.t()} | {:error, Exception.t()}
  def pointer_prepare(%__MODULE__{channel: channel}, owner, op, opts \\ [])
      when is_binary(owner) do
    fields = Antd.PointerOp.to_fields(op)

    req = %Antd.V1.PreparePointerRequest{
      owner: owner,
      op: fields.op,
      target: Map.get(fields, :target, ""),
      kind: Map.get(fields, :kind, ""),
      recipient: Map.get(fields, :recipient, ""),
      include_signed_quotes: Keyword.get(opts, :include_signed_quotes, false) == true
    }

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.prepare/3, channel, req, opts) do
      Antd.Pointers.prepare_from_proto(resp)
    end
  end

  @doc "Like `pointer_prepare/4` but raises on error."
  @spec pointer_prepare!(t(), String.t(), Antd.PointerOp.t(), keyword()) ::
          Antd.PointerPrepareResult.t()
  def pointer_prepare!(client, owner, op, opts \\ []),
    do: unwrap!(pointer_prepare(client, owner, op, opts))

  @doc """
  Stores a prepared pointer write once its external signer has paid.
  Mirrors `Antd.Client.pointer_finalize/3`: an
  `Antd.CloseGroupShortfallError` with `retryable: true` (read from the
  message's closing `(paid attempt retained...)` hint) means the daemon kept
  the paid state; repeat the call with the same `upload_id`, bounded. This
  function never retries by itself.

  ## Options

    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec pointer_finalize(t(), String.t(), map(), keyword()) ::
          {:ok, Antd.PointerFinalizeResult.t()} | {:error, Exception.t()}
  def pointer_finalize(%__MODULE__{channel: channel}, upload_id, tx_hashes, opts \\ [])
      when is_binary(upload_id) and is_map(tx_hashes) do
    req = %Antd.V1.FinalizePointerRequest{upload_id: upload_id, tx_hashes: tx_hashes}

    with {:ok, resp} <-
           pointer_call(&Antd.V1.PointerService.Stub.finalize/3, channel, req, opts) do
      Antd.Pointers.finalize_from_proto(resp)
    end
  end

  @doc "Like `pointer_finalize/4` but raises on error."
  @spec pointer_finalize!(t(), String.t(), map(), keyword()) :: Antd.PointerFinalizeResult.t()
  def pointer_finalize!(client, upload_id, tx_hashes, opts \\ []),
    do: unwrap!(pointer_finalize(client, upload_id, tx_hashes, opts))

  # Runs one PointerService RPC with the response metadata kept, and maps a
  # failure by the daemon's x-antd-error-code where it agrees with the status.
  # A channel opened without Antd.GrpcAdapter returns a failure without
  # metadata, which keeps the status mapping.
  defp pointer_call(rpc, channel, req, opts) do
    call_opts = [timeout: Keyword.get(opts, :timeout, @pointer_timeout), return_headers: true]

    case rpc.(channel, req, call_opts) do
      {:ok, resp, _metadata} -> {:ok, resp}
      {:ok, resp} -> {:ok, resp}
      {:error, rpc_error, metadata} -> {:error, translate_pointer_error(rpc_error, metadata)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  defp translate_pointer_error(%GRPC.RPCError{status: status, message: message} = error, md) do
    Antd.Errors.grpc_tagged_error(status, error_code(md), message) || translate_error(error)
  end

  defp translate_pointer_error(error, _metadata), do: translate_error(error)

  # A trailers-only response (how the daemon answers a failed unary call)
  # carries the code in its headers; a full response in its trailers.
  defp error_code(metadata) when is_map(metadata) do
    Enum.find_value([:trailers, :headers], fn key ->
      case Map.get(metadata, key) do
        %{@error_code_key => code} -> code
        _ -> nil
      end
    end)
  end

  defp error_code(_), do: nil

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp unwrap!({:ok, result}), do: result
  defp unwrap!(:ok), do: :ok
  defp unwrap!({:error, exception}), do: raise(exception)

  # Merkle-only fields (`depth`, `pool_commitments`, `merkle_payment_timestamp`)
  # are gated on `payment_type == "merkle"` — proto3 scalar defaults are not
  # enough because REST omits these fields entirely on wave-batch and the
  # model layer expects them empty/zero there.
  defp prepare_response_from_proto(resp) do
    payment_type = if resp.payment_type == "", do: "wave_batch", else: resp.payment_type

    payments =
      Enum.map(resp.payments, fn p ->
        %Antd.PaymentInfo{
          quote_hash: p.quote_hash,
          rewards_address: p.rewards_address,
          amount: p.amount
        }
      end)

    {depth, pool_commitments, merkle_ts} =
      if payment_type == "merkle" do
        pcs =
          Enum.map(resp.pool_commitments, fn pc ->
            cands =
              Enum.map(pc.candidates, fn c ->
                %Antd.CandidateNodeEntry{
                  rewards_address: c.rewards_address,
                  amount: c.amount
                }
              end)

            %Antd.PoolCommitmentEntry{pool_hash: pc.pool_hash, candidates: cands}
          end)

        {resp.depth, pcs, resp.merkle_payment_timestamp}
      else
        {0, [], 0}
      end

    %Antd.PrepareUploadResult{
      upload_id: resp.upload_id,
      payments: payments,
      total_amount: resp.total_amount,
      payment_vault_address: resp.payment_vault_address,
      payment_token_address: resp.payment_token_address,
      rpc_url: resp.rpc_url,
      payment_type: payment_type,
      depth: depth,
      pool_commitments: pool_commitments,
      merkle_payment_timestamp: merkle_ts,
      # Already-stored preflight (parity with REST): the external signer
      # pays for total_chunks - already_stored_count chunks.
      total_chunks: resp.total_chunks,
      already_stored_count: resp.already_stored_count
    }
  end

  defp finalize_response_from_proto(resp) do
    %Antd.FinalizeUploadResult{
      data_map: resp.data_map,
      address: resp.address,
      data_map_address: resp.data_map_address,
      chunks_stored: resp.chunks_stored
    }
  end

  defp prepare_chunk_response_from_proto(resp) do
    if resp.already_stored do
      %Antd.PrepareChunkResult{
        address: resp.address,
        already_stored: true
      }
    else
      payments =
        Enum.map(resp.payments, fn p ->
          %Antd.PaymentInfo{
            quote_hash: p.quote_hash,
            rewards_address: p.rewards_address,
            amount: p.amount
          }
        end)

      %Antd.PrepareChunkResult{
        address: resp.address,
        already_stored: false,
        upload_id: resp.upload_id,
        payment_type: resp.payment_type,
        payments: payments,
        total_amount: resp.total_amount,
        payment_vault_address: resp.payment_vault_address,
        payment_token_address: resp.payment_token_address,
        rpc_url: resp.rpc_url
      }
    end
  end

  defp translate_error(%GRPC.RPCError{status: status, message: message}) do
    case status do
      3 -> %Antd.BadRequestError{message: message, status_code: 400}
      5 -> %Antd.NotFoundError{message: message, status_code: 404}
      6 -> %Antd.AlreadyExistsError{message: message, status_code: 409}
      8 -> %Antd.TooLargeError{message: message, status_code: 413}
      9 -> %Antd.PaymentError{message: message, status_code: 402}
      # ABORTED carries PARTIAL_UPLOAD: some chunks stored, some still
      # unstored after retries. Every such message opens with the daemon's
      # fixed "Partial upload:" prefix, so gate on the message starting with
      # it (anchored, not containment: an ABORTED that merely quotes the
      # phrase further in is not a partial upload). The counts and the
      # daemon's closing retention hint ride the message text (no structured
      # detail over gRPC yet) and are parsed to match the REST client's typed
      # error; retention is known only when both read. This applies to every
      # RPC through this translator (ordinary uploads included) and replaces
      # the generic Antd.AntdError these statuses used to map to; any other
      # ABORTED keeps that generic mapping.
      10 ->
        if Antd.Errors.partial_upload_message?(message) do
          Antd.Errors.partial_upload_error_from_message(502, message)
        else
          %Antd.AntdError{message: message, status_code: status}
        end

      13 -> %Antd.InternalError{message: message, status_code: 500}
      14 -> %Antd.NetworkError{message: message, status_code: 502}
      _ -> %Antd.AntdError{message: message, status_code: status}
    end
  end

  defp translate_error(other) do
    %Antd.AntdError{message: inspect(other), status_code: 0}
  end
  # ---------------------------------------------------------------------------
  # Wallet (V2-286)
  # ---------------------------------------------------------------------------
  #
  # A missing daemon wallet emits gRPC `FailedPrecondition`, which
  # translate_error/1 surfaces as `PaymentError` (established
  # FailedPrecondition->Payment convention across all SDKs).

  @doc "Returns the wallet's on-chain address."
  @spec wallet_address(t()) :: {:ok, Antd.WalletAddress.t()} | {:error, Exception.t()}
  def wallet_address(%__MODULE__{channel: channel}) do
    req = %Antd.V1.GetWalletAddressRequest{}

    case Antd.V1.WalletService.Stub.get_address(channel, req) do
      {:ok, resp} -> {:ok, %Antd.WalletAddress{address: resp.address}}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `wallet_address/1` but raises on error."
  @spec wallet_address!(t()) :: Antd.WalletAddress.t()
  def wallet_address!(client), do: unwrap!(wallet_address(client))

  @doc "Returns the wallet's token + gas balances."
  @spec wallet_balance(t()) :: {:ok, Antd.WalletBalance.t()} | {:error, Exception.t()}
  def wallet_balance(%__MODULE__{channel: channel}) do
    req = %Antd.V1.GetWalletBalanceRequest{}

    case Antd.V1.WalletService.Stub.get_balance(channel, req) do
      {:ok, resp} ->
        {:ok, %Antd.WalletBalance{balance: resp.balance, gas_balance: resp.gas_balance}}

      {:error, rpc_error} ->
        {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `wallet_balance/1` but raises on error."
  @spec wallet_balance!(t()) :: Antd.WalletBalance.t()
  def wallet_balance!(client), do: unwrap!(wallet_balance(client))

  @doc """
  Approves the wallet to spend tokens on the payment vault contract.
  One-time operation; idempotent at the contract level.
  """
  @spec wallet_approve(t()) :: {:ok, boolean()} | {:error, Exception.t()}
  def wallet_approve(%__MODULE__{channel: channel}) do
    req = %Antd.V1.WalletApproveRequest{}

    case Antd.V1.WalletService.Stub.approve(channel, req) do
      {:ok, resp} -> {:ok, resp.approved}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  @doc "Like `wallet_approve/1` but raises on error."
  @spec wallet_approve!(t()) :: boolean()
  def wallet_approve!(client), do: unwrap!(wallet_approve(client))

  # ---------------------------------------------------------------------------
  # Manifests
  # ---------------------------------------------------------------------------
  #
  # ManifestService: the same functions, results and errors as the REST
  # client's manifest functions (see `Antd.Client.build_manifest/3`). Nothing
  # is uploaded or paid for; the embedding policy and `resolve` read the
  # network, so a call can time out and is safe to retry. Manifest bytes
  # travel as raw protobuf `bytes`.
  #
  # Message size: a manifest can be 64 MiB, and a Build or Decode response
  # carries it, so antd-go raises its client's 4 MiB receive default per
  # call. grpc-elixir 0.11 has no receive limit to raise: its Gun adapter
  # reads a unary response whole, whatever its size; GRPC.Stub.connect has no
  # option for one, and a call rejects any option it does not know; and
  # sends are capped only by GRPC.Message's 2 GiB default. So no limit is
  # passed here (revisit if a later grpc-elixir adds one).
  # test/antd/grpc_manifests_test.exs round-trips a manifest over 4 MiB both
  # ways to hold that.
  #
  # Each function takes a `:timeout` option in milliseconds. It defaults to
  # 5 minutes, the REST client's default, rather than grpc's 10 seconds.

  @manifest_timeout 300_000

  @doc """
  Builds a `.ant` manifest from DataMaps and public addresses already in
  hand. Mirrors `Antd.Client.build_manifest/3`, including its entry check
  before sending; an entry the daemon rejects (`INVALID_ARGUMENT`) is an
  `Antd.BadRequestError` whose message names `entries[i]`. Nothing is
  uploaded or paid for.

  ## Options

    * `:name`, `:torrent_info_hashes`, `:embed_roots` (default `true`) — as
      for `Antd.Client.build_manifest/3`.
    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec build_manifest(t(), [Antd.ManifestEntryInput.t()], keyword()) ::
          {:ok, Antd.BuiltManifest.t()} | {:error, Exception.t()}
  def build_manifest(%__MODULE__{channel: channel}, entries, opts \\ []) when is_list(entries) do
    with :ok <- Antd.Manifests.check_entries(entries) do
      req = Antd.Manifests.build_request(entries, opts)

      case Antd.V1.ManifestService.Stub.build(channel, req, manifest_call_opts(opts)) do
        {:ok, resp} -> {:ok, Antd.Manifests.built_from_proto(resp)}
        {:error, rpc_error} -> {:error, translate_error(rpc_error)}
      end
    end
  end

  @doc "Like `build_manifest/3` but raises on error."
  @spec build_manifest!(t(), [Antd.ManifestEntryInput.t()], keyword()) :: Antd.BuiltManifest.t()
  def build_manifest!(client, entries, opts \\ []),
    do: unwrap!(build_manifest(client, entries, opts))

  @doc """
  Decodes `.ant` bytes (a raw binary). Mirrors
  `Antd.Client.decode_manifest/3`.

  ## Options

    * `:resolve` — as for `Antd.Client.decode_manifest/3` (default `false`).
    * `:timeout` — call timeout in milliseconds (default 300_000).
  """
  @spec decode_manifest(t(), binary(), keyword()) ::
          {:ok, Antd.DecodedManifest.t()} | {:error, Exception.t()}
  def decode_manifest(%__MODULE__{} = client, manifest, opts \\ []) when is_binary(manifest) do
    with :ok <- Antd.Manifests.check_input(manifest) do
      decode_manifest_call(client, {:manifest, manifest}, opts)
    end
  end

  @doc "Like `decode_manifest/3` but raises on error."
  @spec decode_manifest!(t(), binary(), keyword()) :: Antd.DecodedManifest.t()
  def decode_manifest!(client, manifest, opts \\ []),
    do: unwrap!(decode_manifest(client, manifest, opts))

  @doc """
  Decodes an `ant://` manifest link, a file link or a bare 64-hex address.
  Mirrors `Antd.Client.decode_manifest_link/3`; takes the same options as
  `decode_manifest/3`.
  """
  @spec decode_manifest_link(t(), String.t(), keyword()) ::
          {:ok, Antd.DecodedManifest.t()} | {:error, Exception.t()}
  def decode_manifest_link(%__MODULE__{} = client, link, opts \\ []) when is_binary(link) do
    with :ok <- Antd.Manifests.check_input(link) do
      decode_manifest_call(client, {:link, link}, opts)
    end
  end

  @doc "Like `decode_manifest_link/3` but raises on error."
  @spec decode_manifest_link!(t(), String.t(), keyword()) :: Antd.DecodedManifest.t()
  def decode_manifest_link!(client, link, opts \\ []),
    do: unwrap!(decode_manifest_link(client, link, opts))

  defp decode_manifest_call(%__MODULE__{channel: channel}, input, opts) do
    req = Antd.Manifests.decode_request(input, opts)

    case Antd.V1.ManifestService.Stub.decode(channel, req, manifest_call_opts(opts)) do
      {:ok, resp} -> {:ok, Antd.Manifests.decoded_from_proto(resp)}
      {:error, rpc_error} -> {:error, translate_error(rpc_error)}
    end
  end

  defp manifest_call_opts(opts), do: [timeout: Keyword.get(opts, :timeout, @manifest_timeout)]

end
