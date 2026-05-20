defmodule Antd.Client do
  @moduledoc """
  REST client for the antd daemon.

  All public functions take a `%Antd.Client{}` as the first argument and return
  `{:ok, result}` or `{:error, exception}`. Bang variants (e.g. `health!/1`)
  raise on error.

  ## Naming convention

  Private = unqualified verb (the DataMap is returned to the caller; it is
  NOT stored on the network). Public = `_public` suffix (the DataMap is
  additionally stored on-network and the call returns the resulting address).

  * `data_put` / `data_get`             — private
  * `data_put_public` / `data_get_public` — public
  * `file_put` / `file_get`             — private
  * `file_put_public` / `file_get_public` — public
  * `chunk_put` / `chunk_get`           — no public/private split

  ## Payment mode

  Put and cost methods that touch the network accept an optional
  `:payment_mode` keyword argument — an atom (`:auto`, `:merkle`, `:single`)
  from `Antd.PaymentMode`. The atom is serialized to the wire string at the
  request boundary. `:auto` is the default.
  """

  alias Antd.PaymentMode

  @default_base_url "http://localhost:8082"
  @default_timeout 300_000

  defstruct base_url: @default_base_url, timeout: @default_timeout

  @type t :: %__MODULE__{
          base_url: String.t(),
          timeout: integer()
        }

  @doc """
  Creates a client using port discovery.

  Reads the daemon.port file to find the REST port. Falls back to the
  default base URL if the port file is not found.

  ## Options

    * `:timeout` - HTTP request timeout in milliseconds (default: 300_000)

  ## Examples

      {client, url} = Antd.Client.auto_discover()
      {client, url} = Antd.Client.auto_discover(timeout: 30_000)
  """
  @spec auto_discover(keyword()) :: {t(), String.t()}
  def auto_discover(opts \\ []) do
    url =
      case Antd.Discover.discover_daemon_url() do
        "" -> @default_base_url
        discovered -> discovered
      end

    {new(url, opts), url}
  end

  @doc """
  Creates a new client.

  ## Options

    * `:timeout` - HTTP request timeout in milliseconds (default: 300_000)

  ## Examples

      client = Antd.Client.new()
      client = Antd.Client.new("http://custom-host:9090")
      client = Antd.Client.new("http://localhost:8082", timeout: 30_000)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(base_url \\ @default_base_url, opts \\ []) do
    %__MODULE__{
      base_url: String.trim_trailing(base_url, "/"),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end

  # ---------------------------------------------------------------------------
  # Health
  # ---------------------------------------------------------------------------

  @doc "Checks the antd daemon status."
  @spec health(t()) :: {:ok, Antd.HealthStatus.t()} | {:error, Exception.t()}
  def health(%__MODULE__{} = client) do
    case do_json(client, :get, "/health", nil) do
      {:ok, body} ->
        {:ok,
         %Antd.HealthStatus{
           ok: body["status"] == "ok",
           network: body["network"],
           version: Map.get(body, "version", ""),
           evm_network: Map.get(body, "evm_network", ""),
           uptime_seconds: Map.get(body, "uptime_seconds", 0),
           build_commit: Map.get(body, "build_commit", ""),
           payment_token_address: Map.get(body, "payment_token_address", ""),
           payment_vault_address: Map.get(body, "payment_vault_address", "")
         }}

      {:error, _} = err ->
        err
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

  Returns an `%Antd.DataPutResult{}` whose `:data_map` is the caller-held hex
  DataMap; the DataMap is NOT stored on-network.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_put(t(), binary(), keyword()) ::
          {:ok, Antd.DataPutResult.t()} | {:error, Exception.t()}
  def data_put(%__MODULE__{} = client, data, opts \\ []) when is_binary(data) do
    payload = %{
      data: Base.encode64(data),
      payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
    }

    case do_json(client, :post, "/v1/data", payload) do
      {:ok, body} ->
        {:ok,
         %Antd.DataPutResult{
           data_map: body["data_map"] || "",
           chunks_stored: body["chunks_stored"] || 0,
           payment_mode_used: body["payment_mode_used"] || ""
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `data_put/3` but raises on error."
  @spec data_put!(t(), binary(), keyword()) :: Antd.DataPutResult.t()
  def data_put!(client, data, opts \\ []), do: unwrap!(data_put(client, data, opts))

  @doc "Retrieves private data using a caller-held DataMap (hex)."
  @spec data_get(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get(%__MODULE__{} = client, data_map) when is_binary(data_map) do
    case do_json(client, :post, "/v1/data/get", %{data_map: data_map}) do
      {:ok, body} -> {:ok, Base.decode64!(body["data"] || "")}
      {:error, _} = err -> err
    end
  end

  @doc "Like `data_get/2` but raises on error."
  @spec data_get!(t(), String.t()) :: binary()
  def data_get!(client, data_map), do: unwrap!(data_get(client, data_map))

  @doc """
  Stores public data on the network.

  The DataMap is stored on-network as an extra chunk; the returned
  `:address` is the shareable retrieval handle.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec data_put_public(t(), binary(), keyword()) ::
          {:ok, Antd.DataPutPublicResult.t()} | {:error, Exception.t()}
  def data_put_public(%__MODULE__{} = client, data, opts \\ []) when is_binary(data) do
    payload = %{
      data: Base.encode64(data),
      payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
    }

    case do_json(client, :post, "/v1/data/public", payload) do
      {:ok, body} ->
        {:ok,
         %Antd.DataPutPublicResult{
           address: body["address"] || "",
           chunks_stored: body["chunks_stored"] || 0,
           payment_mode_used: body["payment_mode_used"] || ""
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `data_put_public/3` but raises on error."
  @spec data_put_public!(t(), binary(), keyword()) :: Antd.DataPutPublicResult.t()
  def data_put_public!(client, data, opts \\ []), do: unwrap!(data_put_public(client, data, opts))

  @doc "Retrieves public data by address."
  @spec data_get_public(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get_public(%__MODULE__{} = client, address) do
    case do_json(client, :get, "/v1/data/public/#{address}", nil) do
      {:ok, body} -> {:ok, Base.decode64!(body["data"] || "")}
      {:error, _} = err -> err
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
  def data_cost(%__MODULE__{} = client, data, opts \\ []) when is_binary(data) do
    payload = %{
      data: Base.encode64(data),
      payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
    }

    case do_json(client, :post, "/v1/data/cost", payload) do
      {:ok, body} ->
        {:ok,
         %Antd.UploadCostEstimate{
           cost: body["cost"] || "",
           file_size: body["file_size"] || 0,
           chunk_count: body["chunk_count"] || 0,
           estimated_gas_cost_wei: body["estimated_gas_cost_wei"] || "",
           payment_mode: body["payment_mode"] || ""
         }}

      {:error, _} = err ->
        err
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
  def chunk_put(%__MODULE__{} = client, data) when is_binary(data) do
    case do_json(client, :post, "/v1/chunks", %{data: Base.encode64(data)}) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["address"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `chunk_put/2` but raises on error."
  @spec chunk_put!(t(), binary()) :: Antd.PutResult.t()
  def chunk_put!(client, data), do: unwrap!(chunk_put(client, data))

  @doc "Retrieves a chunk by address."
  @spec chunk_get(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def chunk_get(%__MODULE__{} = client, address) do
    case do_json(client, :get, "/v1/chunks/#{address}", nil) do
      {:ok, body} -> {:ok, Base.decode64!(body["data"])}
      {:error, _} = err -> err
    end
  end

  @doc "Like `chunk_get/2` but raises on error."
  @spec chunk_get!(t(), String.t()) :: binary()
  def chunk_get!(client, address), do: unwrap!(chunk_get(client, address))

  @doc """
  Prepares a single chunk for external-signer publish via
  `POST /v1/chunks/prepare`.

  The daemon quotes the close group, stashes the prepared state under a
  fresh upload id, and returns either:

    * `%Antd.PrepareChunkResult{already_stored: true, address: addr}` —
      the chunk is already on-network; no payment or finalize is needed.
    * `%Antd.PrepareChunkResult{already_stored: false, upload_id: ...,
      payments: [...], ...}` — the wave-batch intent the external signer
      must satisfy before calling `finalize_chunk_upload/3`.

  Unlike `chunk_put/2`, this endpoint does NOT require the daemon to have
  a wallet — all funds flow through the external signer. Requires antd
  >= 0.7.0.
  """
  @spec prepare_chunk_upload(t(), binary()) ::
          {:ok, Antd.PrepareChunkResult.t()} | {:error, Exception.t()}
  def prepare_chunk_upload(%__MODULE__{} = client, data) when is_binary(data) do
    case do_json(client, :post, "/v1/chunks/prepare", %{data: Base.encode64(data)}) do
      {:ok, body} -> {:ok, parse_prepare_chunk_response(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `prepare_chunk_upload/2` but raises on error."
  @spec prepare_chunk_upload!(t(), binary()) :: Antd.PrepareChunkResult.t()
  def prepare_chunk_upload!(client, data), do: unwrap!(prepare_chunk_upload(client, data))

  @doc """
  Submits a prepared chunk to the network after external payment via
  `POST /v1/chunks/finalize`.

  `tx_hashes` maps each non-zero `quote_hash` returned by
  `prepare_chunk_upload/2` to the `tx_hash` of the corresponding
  `payForQuotes()` transaction. Returns the hex-encoded network address of
  the stored chunk (matches `:address` from the prepare result).

  Requires antd >= 0.7.0.
  """
  @spec finalize_chunk_upload(t(), String.t(), map()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def finalize_chunk_upload(%__MODULE__{} = client, upload_id, tx_hashes)
      when is_binary(upload_id) and is_map(tx_hashes) do
    payload = %{upload_id: upload_id, tx_hashes: tx_hashes}

    case do_json(client, :post, "/v1/chunks/finalize", payload) do
      {:ok, body} -> {:ok, body["address"] || ""}
      {:error, _} = err -> err
    end
  end

  @doc "Like `finalize_chunk_upload/3` but raises on error."
  @spec finalize_chunk_upload!(t(), String.t(), map()) :: String.t()
  def finalize_chunk_upload!(client, upload_id, tx_hashes),
    do: unwrap!(finalize_chunk_upload(client, upload_id, tx_hashes))

  # ---------------------------------------------------------------------------
  # Files
  # ---------------------------------------------------------------------------

  @doc """
  Uploads a file privately. Returns the caller-held DataMap (hex) in the
  result — the DataMap is NOT stored on-network.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec file_put(t(), String.t(), keyword()) ::
          {:ok, Antd.FilePutResult.t()} | {:error, Exception.t()}
  def file_put(%__MODULE__{} = client, path, opts \\ []) when is_binary(path) do
    payload = %{
      path: path,
      payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
    }

    case do_json(client, :post, "/v1/files", payload) do
      {:ok, body} -> {:ok, file_put_result_from_body(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_put/3` but raises on error."
  @spec file_put!(t(), String.t(), keyword()) :: Antd.FilePutResult.t()
  def file_put!(client, path, opts \\ []), do: unwrap!(file_put(client, path, opts))

  @doc """
  Downloads a private file from a caller-held DataMap into `dest_path`.

  The response body is empty on success — the file is written to `dest_path`.
  """
  @spec file_get(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def file_get(%__MODULE__{} = client, data_map, dest_path)
      when is_binary(data_map) and is_binary(dest_path) do
    case do_json(client, :post, "/v1/files/get", %{data_map: data_map, dest_path: dest_path}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_get/3` but raises on error."
  @spec file_get!(t(), String.t(), String.t()) :: :ok
  def file_get!(client, data_map, dest_path),
    do: unwrap!(file_get(client, data_map, dest_path))

  @doc """
  Uploads a local file publicly.

  The DataMap is stored on-network as an extra chunk; the returned
  `:address` is the shareable retrieval handle.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec file_put_public(t(), String.t(), keyword()) ::
          {:ok, Antd.FilePutPublicResult.t()} | {:error, Exception.t()}
  def file_put_public(%__MODULE__{} = client, path, opts \\ []) when is_binary(path) do
    payload = %{
      path: path,
      payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
    }

    case do_json(client, :post, "/v1/files/public", payload) do
      {:ok, body} -> {:ok, file_put_public_result_from_body(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_put_public/3` but raises on error."
  @spec file_put_public!(t(), String.t(), keyword()) :: Antd.FilePutPublicResult.t()
  def file_put_public!(client, path, opts \\ []),
    do: unwrap!(file_put_public(client, path, opts))

  @doc "Downloads a public file from the network to a local path."
  @spec file_get_public(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def file_get_public(%__MODULE__{} = client, address, dest_path) do
    case do_json(client, :post, "/v1/files/public/get", %{address: address, dest_path: dest_path}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_get_public/3` but raises on error."
  @spec file_get_public!(t(), String.t(), String.t()) :: :ok
  def file_get_public!(client, address, dest_path) do
    unwrap!(file_get_public(client, address, dest_path))
  end

  defp file_put_result_from_body(body) do
    %Antd.FilePutResult{
      data_map: Map.get(body, "data_map", ""),
      storage_cost_atto: Map.get(body, "storage_cost_atto", ""),
      gas_cost_wei: Map.get(body, "gas_cost_wei", ""),
      chunks_stored: Map.get(body, "chunks_stored", 0),
      payment_mode_used: Map.get(body, "payment_mode_used", "")
    }
  end

  defp file_put_public_result_from_body(body) do
    %Antd.FilePutPublicResult{
      address: Map.get(body, "address", ""),
      storage_cost_atto: Map.get(body, "storage_cost_atto", ""),
      gas_cost_wei: Map.get(body, "gas_cost_wei", ""),
      chunks_stored: Map.get(body, "chunks_stored", 0),
      payment_mode_used: Map.get(body, "payment_mode_used", "")
    }
  end

  @doc """
  Estimates the cost of uploading a file.

  ## Options

    * `:payment_mode` — `Antd.PaymentMode.t()` (default `:auto`).
  """
  @spec file_cost(t(), String.t(), boolean(), keyword()) ::
          {:ok, Antd.UploadCostEstimate.t()} | {:error, Exception.t()}
  def file_cost(%__MODULE__{} = client, path, is_public, opts \\ []) do
    payload = %{
      path: path,
      is_public: is_public,
      payment_mode: PaymentMode.to_wire(Keyword.get(opts, :payment_mode, :auto))
    }

    case do_json(client, :post, "/v1/files/cost", payload) do
      {:ok, body} ->
        {:ok,
         %Antd.UploadCostEstimate{
           cost: body["cost"] || "",
           file_size: body["file_size"] || 0,
           chunk_count: body["chunk_count"] || 0,
           estimated_gas_cost_wei: body["estimated_gas_cost_wei"] || "",
           payment_mode: body["payment_mode"] || ""
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `file_cost/4` but raises on error."
  @spec file_cost!(t(), String.t(), boolean(), keyword()) :: Antd.UploadCostEstimate.t()
  def file_cost!(client, path, is_public, opts \\ []) do
    unwrap!(file_cost(client, path, is_public, opts))
  end

  # ---------------------------------------------------------------------------
  # Wallet
  # ---------------------------------------------------------------------------

  @doc "Returns the wallet address configured on the daemon."
  @spec wallet_address(t()) :: {:ok, Antd.WalletAddress.t()} | {:error, Exception.t()}
  def wallet_address(%__MODULE__{} = client) do
    case do_json(client, :get, "/v1/wallet/address", nil) do
      {:ok, body} ->
        {:ok, %Antd.WalletAddress{address: body["address"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `wallet_address/1` but raises on error."
  @spec wallet_address!(t()) :: Antd.WalletAddress.t()
  def wallet_address!(client), do: unwrap!(wallet_address(client))

  @doc "Returns the wallet balance and gas balance."
  @spec wallet_balance(t()) :: {:ok, Antd.WalletBalance.t()} | {:error, Exception.t()}
  def wallet_balance(%__MODULE__{} = client) do
    case do_json(client, :get, "/v1/wallet/balance", nil) do
      {:ok, body} ->
        {:ok, %Antd.WalletBalance{balance: body["balance"], gas_balance: body["gas_balance"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `wallet_balance/1` but raises on error."
  @spec wallet_balance!(t()) :: Antd.WalletBalance.t()
  def wallet_balance!(client), do: unwrap!(wallet_balance(client))

  @doc "Approves the wallet to spend tokens on payment contracts (one-time operation)."
  @spec wallet_approve(t()) :: {:ok, boolean()} | {:error, Exception.t()}
  def wallet_approve(%__MODULE__{} = client) do
    case do_json(client, :post, "/v1/wallet/approve", %{}) do
      {:ok, body} ->
        {:ok, body["approved"] == true}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `wallet_approve/1` but raises on error."
  @spec wallet_approve!(t()) :: boolean()
  def wallet_approve!(client), do: unwrap!(wallet_approve(client))

  # ---------------------------------------------------------------------------
  # External Signer (Two-Phase Upload)
  # ---------------------------------------------------------------------------

  @doc """
  Prepares a file upload for external signing.

  ## Options

    * `:visibility` — `"public"` bundles the DataMap chunk into the same
      external-signer payment batch so a single EVM transaction covers
      both the data chunks and the DataMap. After `finalize_upload/3`,
      `data_map_address` on the result is the shareable retrieval handle.
      `"private"` (or omitting the option) keeps the existing private-only
      behaviour and the field is sent only when set.
  """
  @spec prepare_upload(t(), String.t(), keyword()) ::
          {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_upload(%__MODULE__{} = client, path, opts \\ []) do
    payload = %{path: path}

    payload =
      case Keyword.get(opts, :visibility) do
        nil -> payload
        visibility -> Map.put(payload, :visibility, visibility)
      end

    case do_json(client, :post, "/v1/upload/prepare", payload) do
      {:ok, body} -> {:ok, parse_prepare_response(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `prepare_upload/3` but raises on error."
  @spec prepare_upload!(t(), String.t(), keyword()) :: Antd.PrepareUploadResult.t()
  def prepare_upload!(client, path, opts \\ []), do: unwrap!(prepare_upload(client, path, opts))

  @doc """
  Convenience wrapper: prepare a *public* file upload for external signing.

  Equivalent to `prepare_upload(client, path, visibility: "public")`.
  Requires antd >= 0.6.1.
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

    * `:visibility` — see `prepare_upload/3`. Note that the daemon currently
      returns 501 for `"public"` on `/v1/data/prepare`; use
      `prepare_upload_public/2` with a file path until upstream ant-client
      exposes `data_prepare_upload_with_visibility`.
  """
  @spec prepare_data_upload(t(), binary(), keyword()) ::
          {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_data_upload(%__MODULE__{} = client, data, opts \\ []) when is_binary(data) do
    payload = %{data: Base.encode64(data)}

    payload =
      case Keyword.get(opts, :visibility) do
        nil -> payload
        visibility -> Map.put(payload, :visibility, visibility)
      end

    case do_json(client, :post, "/v1/data/prepare", payload) do
      {:ok, body} -> {:ok, parse_prepare_response(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `prepare_data_upload/3` but raises on error."
  @spec prepare_data_upload!(t(), binary(), keyword()) :: Antd.PrepareUploadResult.t()
  def prepare_data_upload!(client, data, opts \\ []),
    do: unwrap!(prepare_data_upload(client, data, opts))

  @doc "Finalizes an upload after an external signer has submitted payment transactions."
  @spec finalize_upload(t(), String.t(), map()) ::
          {:ok, Antd.FinalizeUploadResult.t()} | {:error, Exception.t()}
  def finalize_upload(%__MODULE__{} = client, upload_id, tx_hashes) do
    payload = %{upload_id: upload_id, tx_hashes: tx_hashes}

    case do_json(client, :post, "/v1/upload/finalize", payload) do
      {:ok, body} -> {:ok, parse_finalize_response(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `finalize_upload/3` but raises on error."
  @spec finalize_upload!(t(), String.t(), map()) :: Antd.FinalizeUploadResult.t()
  def finalize_upload!(client, upload_id, tx_hashes) do
    unwrap!(finalize_upload(client, upload_id, tx_hashes))
  end

  @doc "Finalizes a merkle-batch upload after selecting a winning pool."
  @spec finalize_merkle_upload(t(), String.t(), String.t(), keyword()) ::
          {:ok, Antd.FinalizeUploadResult.t()} | {:error, Exception.t()}
  def finalize_merkle_upload(%__MODULE__{} = client, upload_id, winner_pool_hash, opts \\ []) do
    payload = %{upload_id: upload_id, winner_pool_hash: winner_pool_hash}

    payload =
      case Keyword.get(opts, :store_data_map) do
        nil -> payload
        val -> Map.put(payload, :store_data_map, val)
      end

    case do_json(client, :post, "/v1/upload/finalize", payload) do
      {:ok, body} -> {:ok, parse_finalize_response(body)}
      {:error, _} = err -> err
    end
  end

  @doc "Like `finalize_merkle_upload/4` but raises on error."
  @spec finalize_merkle_upload!(t(), String.t(), String.t(), keyword()) ::
          Antd.FinalizeUploadResult.t()
  def finalize_merkle_upload!(client, upload_id, winner_pool_hash, opts \\ []) do
    unwrap!(finalize_merkle_upload(client, upload_id, winner_pool_hash, opts))
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp parse_prepare_response(body) do
    payment_type = body["payment_type"] || "wave_batch"

    payments =
      (body["payments"] || [])
      |> Enum.map(fn p ->
        %Antd.PaymentInfo{
          quote_hash: p["quote_hash"],
          rewards_address: p["rewards_address"],
          amount: p["amount"]
        }
      end)

    pool_commitments =
      if payment_type == "merkle_batch" do
        (body["pool_commitments"] || [])
        |> Enum.map(fn pc ->
          candidates =
            (pc["candidates"] || [])
            |> Enum.map(fn c ->
              %Antd.CandidateNodeEntry{
                rewards_address: c["rewards_address"] || "",
                amount: c["amount"] || ""
              }
            end)

          %Antd.PoolCommitmentEntry{
            pool_hash: pc["pool_hash"] || "",
            candidates: candidates
          }
        end)
      else
        []
      end

    %Antd.PrepareUploadResult{
      upload_id: body["upload_id"] || "",
      payments: payments,
      total_amount: body["total_amount"] || "",
      payment_vault_address: body["payment_vault_address"] || "",
      payment_token_address: body["payment_token_address"] || "",
      rpc_url: body["rpc_url"] || "",
      payment_type: payment_type,
      depth: body["depth"] || 0,
      pool_commitments: pool_commitments,
      merkle_payment_timestamp: body["merkle_payment_timestamp"] || 0
    }
  end

  defp parse_prepare_chunk_response(body) do
    payments =
      (body["payments"] || [])
      |> Enum.map(fn p ->
        %Antd.PaymentInfo{
          quote_hash: p["quote_hash"],
          rewards_address: p["rewards_address"],
          amount: p["amount"]
        }
      end)

    %Antd.PrepareChunkResult{
      address: body["address"] || "",
      already_stored: body["already_stored"] == true,
      upload_id: body["upload_id"] || "",
      payment_type: body["payment_type"] || "",
      payments: payments,
      total_amount: body["total_amount"] || "",
      payment_vault_address: body["payment_vault_address"] || "",
      payment_token_address: body["payment_token_address"] || "",
      rpc_url: body["rpc_url"] || ""
    }
  end

  defp parse_finalize_response(body) do
    %Antd.FinalizeUploadResult{
      address: body["address"] || "",
      chunks_stored: body["chunks_stored"] || 0,
      data_map: body["data_map"] || "",
      data_map_address: body["data_map_address"] || ""
    }
  end

  defp unwrap!({:ok, result}), do: result
  defp unwrap!(:ok), do: :ok
  defp unwrap!({:error, exception}), do: raise(exception)

  defp do_json(%__MODULE__{} = client, method, path, body) do
    url = client.base_url <> path

    req_opts = [
      method: method,
      url: url,
      receive_timeout: client.timeout,
      retry: false
    ]

    req_opts =
      if body do
        Keyword.merge(req_opts,
          json: body,
          headers: [{"content-type", "application/json"}]
        )
      else
        req_opts
      end

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status >= 200 and status < 300 ->
        parsed =
          case resp_body do
            body when is_map(body) -> body
            body when is_binary(body) and byte_size(body) > 0 -> Jason.decode!(body)
            _ -> %{}
          end

        {:ok, parsed}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        message = extract_error_message(resp_body)
        {:error, Antd.Errors.error_for_status(status, message)}

      {:error, exception} ->
        {:error, %Antd.AntdError{message: Exception.message(exception), status_code: 0}}
    end
  end

  defp extract_error_message(body) when is_map(body) do
    Map.get(body, "error", Jason.encode!(body))
  end

  defp extract_error_message(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => msg}} -> msg
      _ -> body
    end
  end

  defp extract_error_message(_), do: "unknown error"
end
