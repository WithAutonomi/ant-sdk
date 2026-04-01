defmodule Antd.Client do
  @moduledoc """
  REST client for the antd daemon.

  All public functions take a `%Antd.Client{}` as the first argument and return
  `{:ok, result}` or `{:error, exception}`. Bang variants (e.g. `health!/1`)
  raise on error.
  """

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
        {:ok, %Antd.HealthStatus{ok: body["status"] == "ok", network: body["network"]}}

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

  @doc "Stores public immutable data on the network."
  @spec data_put_public(t(), binary(), keyword()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def data_put_public(%__MODULE__{} = client, data, opts \\ []) when is_binary(data) do
    payload = %{data: Base.encode64(data)}
    payload = case Keyword.get(opts, :payment_mode) do
      nil -> payload
      mode -> Map.put(payload, :payment_mode, mode)
    end
    case do_json(client, :post, "/v1/data/public", payload) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["address"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `data_put_public/2` but raises on error."
  @spec data_put_public!(t(), binary(), keyword()) :: Antd.PutResult.t()
  def data_put_public!(client, data, opts \\ []), do: unwrap!(data_put_public(client, data, opts))

  @doc "Retrieves public data by address."
  @spec data_get_public(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get_public(%__MODULE__{} = client, address) do
    case do_json(client, :get, "/v1/data/public/#{address}", nil) do
      {:ok, body} -> {:ok, Base.decode64!(body["data"])}
      {:error, _} = err -> err
    end
  end

  @doc "Like `data_get_public/2` but raises on error."
  @spec data_get_public!(t(), String.t()) :: binary()
  def data_get_public!(client, address), do: unwrap!(data_get_public(client, address))

  @doc "Stores private encrypted data on the network."
  @spec data_put_private(t(), binary(), keyword()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def data_put_private(%__MODULE__{} = client, data, opts \\ []) when is_binary(data) do
    payload = %{data: Base.encode64(data)}
    payload = case Keyword.get(opts, :payment_mode) do
      nil -> payload
      mode -> Map.put(payload, :payment_mode, mode)
    end
    case do_json(client, :post, "/v1/data/private", payload) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["data_map"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `data_put_private/2` but raises on error."
  @spec data_put_private!(t(), binary(), keyword()) :: Antd.PutResult.t()
  def data_put_private!(client, data, opts \\ []), do: unwrap!(data_put_private(client, data, opts))

  @doc "Retrieves private data using a data map."
  @spec data_get_private(t(), String.t()) :: {:ok, binary()} | {:error, Exception.t()}
  def data_get_private(%__MODULE__{} = client, data_map) do
    encoded = URI.encode_www_form(data_map)

    case do_json(client, :get, "/v1/data/private?data_map=#{encoded}", nil) do
      {:ok, body} -> {:ok, Base.decode64!(body["data"])}
      {:error, _} = err -> err
    end
  end

  @doc "Like `data_get_private/2` but raises on error."
  @spec data_get_private!(t(), String.t()) :: binary()
  def data_get_private!(client, data_map), do: unwrap!(data_get_private(client, data_map))

  @doc "Estimates the cost of storing data."
  @spec data_cost(t(), binary()) :: {:ok, String.t()} | {:error, Exception.t()}
  def data_cost(%__MODULE__{} = client, data) when is_binary(data) do
    case do_json(client, :post, "/v1/data/cost", %{data: Base.encode64(data)}) do
      {:ok, body} -> {:ok, body["cost"]}
      {:error, _} = err -> err
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

  # ---------------------------------------------------------------------------
  # Files & Directories
  # ---------------------------------------------------------------------------

  @doc "Uploads a local file to the network."
  @spec file_upload_public(t(), String.t(), keyword()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def file_upload_public(%__MODULE__{} = client, path, opts \\ []) do
    payload = %{path: path}
    payload = case Keyword.get(opts, :payment_mode) do
      nil -> payload
      mode -> Map.put(payload, :payment_mode, mode)
    end
    case do_json(client, :post, "/v1/files/upload/public", payload) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["address"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `file_upload_public/2` but raises on error."
  @spec file_upload_public!(t(), String.t(), keyword()) :: Antd.PutResult.t()
  def file_upload_public!(client, path, opts \\ []), do: unwrap!(file_upload_public(client, path, opts))

  @doc "Downloads a file from the network to a local path."
  @spec file_download_public(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def file_download_public(%__MODULE__{} = client, address, dest_path) do
    case do_json(client, :post, "/v1/files/download/public", %{address: address, dest_path: dest_path}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_download_public/3` but raises on error."
  @spec file_download_public!(t(), String.t(), String.t()) :: :ok
  def file_download_public!(client, address, dest_path) do
    unwrap!(file_download_public(client, address, dest_path))
  end

  @doc "Uploads a local directory to the network."
  @spec dir_upload_public(t(), String.t(), keyword()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def dir_upload_public(%__MODULE__{} = client, path, opts \\ []) do
    payload = %{path: path}
    payload = case Keyword.get(opts, :payment_mode) do
      nil -> payload
      mode -> Map.put(payload, :payment_mode, mode)
    end
    case do_json(client, :post, "/v1/dirs/upload/public", payload) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["address"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `dir_upload_public/2` but raises on error."
  @spec dir_upload_public!(t(), String.t(), keyword()) :: Antd.PutResult.t()
  def dir_upload_public!(client, path, opts \\ []), do: unwrap!(dir_upload_public(client, path, opts))

  @doc "Downloads a directory from the network to a local path."
  @spec dir_download_public(t(), String.t(), String.t()) :: :ok | {:error, Exception.t()}
  def dir_download_public(%__MODULE__{} = client, address, dest_path) do
    case do_json(client, :post, "/v1/dirs/download/public", %{address: address, dest_path: dest_path}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Like `dir_download_public/3` but raises on error."
  @spec dir_download_public!(t(), String.t(), String.t()) :: :ok
  def dir_download_public!(client, address, dest_path) do
    unwrap!(dir_download_public(client, address, dest_path))
  end

  @doc "Estimates the cost of uploading a file."
  @spec file_cost(t(), String.t(), boolean()) :: {:ok, String.t()} | {:error, Exception.t()}
  def file_cost(%__MODULE__{} = client, path, is_public) do
    payload = %{path: path, is_public: is_public}

    case do_json(client, :post, "/v1/cost/file", payload) do
      {:ok, body} -> {:ok, body["cost"]}
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_cost/3` but raises on error."
  @spec file_cost!(t(), String.t(), boolean()) :: String.t()
  def file_cost!(client, path, is_public) do
    unwrap!(file_cost(client, path, is_public))
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

  @doc "Prepares a file upload for external signing."
  @spec prepare_upload(t(), String.t()) :: {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_upload(%__MODULE__{} = client, path) do
    case do_json(client, :post, "/v1/upload/prepare", %{path: path}) do
      {:ok, body} ->
        payments =
          (body["payments"] || [])
          |> Enum.map(fn p ->
            %Antd.PaymentInfo{
              quote_hash: p["quote_hash"],
              rewards_address: p["rewards_address"],
              amount: p["amount"]
            }
          end)

        {:ok,
         %Antd.PrepareUploadResult{
           upload_id: body["upload_id"],
           payments: payments,
           total_amount: body["total_amount"],
           data_payments_address: body["data_payments_address"],
           payment_token_address: body["payment_token_address"],
           rpc_url: body["rpc_url"]
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `prepare_upload/2` but raises on error."
  @spec prepare_upload!(t(), String.t()) :: Antd.PrepareUploadResult.t()
  def prepare_upload!(client, path), do: unwrap!(prepare_upload(client, path))

  @doc "Prepares a data upload for external signing."
  @spec prepare_data_upload(t(), binary()) :: {:ok, Antd.PrepareUploadResult.t()} | {:error, Exception.t()}
  def prepare_data_upload(%__MODULE__{} = client, data) when is_binary(data) do
    case do_json(client, :post, "/v1/data/prepare", %{data: Base.encode64(data)}) do
      {:ok, body} ->
        payments =
          (body["payments"] || [])
          |> Enum.map(fn p ->
            %Antd.PaymentInfo{
              quote_hash: p["quote_hash"],
              rewards_address: p["rewards_address"],
              amount: p["amount"]
            }
          end)

        {:ok,
         %Antd.PrepareUploadResult{
           upload_id: body["upload_id"],
           payments: payments,
           total_amount: body["total_amount"],
           data_payments_address: body["data_payments_address"],
           payment_token_address: body["payment_token_address"],
           rpc_url: body["rpc_url"]
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `prepare_data_upload/2` but raises on error."
  @spec prepare_data_upload!(t(), binary()) :: Antd.PrepareUploadResult.t()
  def prepare_data_upload!(client, data), do: unwrap!(prepare_data_upload(client, data))

  @doc "Finalizes an upload after an external signer has submitted payment transactions."
  @spec finalize_upload(t(), String.t(), map()) :: {:ok, Antd.FinalizeUploadResult.t()} | {:error, Exception.t()}
  def finalize_upload(%__MODULE__{} = client, upload_id, tx_hashes) do
    payload = %{upload_id: upload_id, tx_hashes: tx_hashes}

    case do_json(client, :post, "/v1/upload/finalize", payload) do
      {:ok, body} ->
        {:ok,
         %Antd.FinalizeUploadResult{
           address: body["address"],
           chunks_stored: body["chunks_stored"]
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `finalize_upload/3` but raises on error."
  @spec finalize_upload!(t(), String.t(), map()) :: Antd.FinalizeUploadResult.t()
  def finalize_upload!(client, upload_id, tx_hashes) do
    unwrap!(finalize_upload(client, upload_id, tx_hashes))
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

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
        Keyword.merge(req_opts, [
          json: body,
          headers: [{"content-type", "application/json"}]
        ])
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

  defp do_head(%__MODULE__{} = client, path) do
    url = client.base_url <> path

    case Req.request(method: :head, url: url, receive_timeout: client.timeout, retry: false) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, exception} -> {:error, %Antd.AntdError{message: Exception.message(exception), status_code: 0}}
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
