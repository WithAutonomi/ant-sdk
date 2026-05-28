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
      merkle_payment_timestamp: merkle_ts
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

end
