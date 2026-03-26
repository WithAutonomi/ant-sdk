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
  # Graph
  # ---------------------------------------------------------------------------

  @doc "Creates a new graph entry (DAG node)."
  @spec graph_entry_put(t(), String.t(), [String.t()], String.t(), [Antd.GraphDescendant.t()]) ::
          {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def graph_entry_put(%__MODULE__{} = client, owner_secret_key, parents, content, descendants) do
    descs =
      Enum.map(descendants, fn d ->
        %{public_key: d.public_key, content: d.content}
      end)

    payload = %{
      owner_secret_key: owner_secret_key,
      parents: parents,
      content: content,
      descendants: descs
    }

    case do_json(client, :post, "/v1/graph", payload) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["address"]}}

      {:error, _} = err ->
        err
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
  def graph_entry_get(%__MODULE__{} = client, address) do
    case do_json(client, :get, "/v1/graph/#{address}", nil) do
      {:ok, body} ->
        descendants =
          (body["descendants"] || [])
          |> Enum.map(fn d ->
            %Antd.GraphDescendant{public_key: d["public_key"], content: d["content"]}
          end)

        {:ok,
         %Antd.GraphEntry{
           owner: body["owner"],
           parents: body["parents"] || [],
           content: body["content"],
           descendants: descendants
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `graph_entry_get/2` but raises on error."
  @spec graph_entry_get!(t(), String.t()) :: Antd.GraphEntry.t()
  def graph_entry_get!(client, address), do: unwrap!(graph_entry_get(client, address))

  @doc "Checks if a graph entry exists at the given address."
  @spec graph_entry_exists(t(), String.t()) :: {:ok, boolean()} | {:error, Exception.t()}
  def graph_entry_exists(%__MODULE__{} = client, address) do
    case do_head(client, "/v1/graph/#{address}") do
      {:ok, status} when status >= 200 and status < 300 -> {:ok, true}
      {:ok, 404} -> {:ok, false}
      {:ok, status} -> {:error, Antd.Errors.error_for_status(status, "graph entry exists check failed")}
      {:error, _} = err -> err
    end
  end

  @doc "Like `graph_entry_exists/2` but raises on error."
  @spec graph_entry_exists!(t(), String.t()) :: boolean()
  def graph_entry_exists!(client, address), do: unwrap!(graph_entry_exists(client, address))

  @doc "Estimates the cost of creating a graph entry."
  @spec graph_entry_cost(t(), String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def graph_entry_cost(%__MODULE__{} = client, public_key) do
    case do_json(client, :post, "/v1/graph/cost", %{public_key: public_key}) do
      {:ok, body} -> {:ok, body["cost"]}
      {:error, _} = err -> err
    end
  end

  @doc "Like `graph_entry_cost/2` but raises on error."
  @spec graph_entry_cost!(t(), String.t()) :: String.t()
  def graph_entry_cost!(client, public_key), do: unwrap!(graph_entry_cost(client, public_key))

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

  @doc "Retrieves an archive manifest by address."
  @spec archive_get_public(t(), String.t()) :: {:ok, Antd.Archive.t()} | {:error, Exception.t()}
  def archive_get_public(%__MODULE__{} = client, address) do
    case do_json(client, :get, "/v1/archives/public/#{address}", nil) do
      {:ok, body} ->
        entries =
          (body["entries"] || [])
          |> Enum.map(fn e ->
            %Antd.ArchiveEntry{
              path: e["path"],
              address: e["address"],
              created: e["created"],
              modified: e["modified"],
              size: e["size"]
            }
          end)

        {:ok, %Antd.Archive{entries: entries}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `archive_get_public/2` but raises on error."
  @spec archive_get_public!(t(), String.t()) :: Antd.Archive.t()
  def archive_get_public!(client, address), do: unwrap!(archive_get_public(client, address))

  @doc "Creates an archive manifest on the network."
  @spec archive_put_public(t(), Antd.Archive.t()) :: {:ok, Antd.PutResult.t()} | {:error, Exception.t()}
  def archive_put_public(%__MODULE__{} = client, %Antd.Archive{} = archive) do
    entries =
      Enum.map(archive.entries, fn e ->
        %{
          path: e.path,
          address: e.address,
          created: e.created,
          modified: e.modified,
          size: e.size
        }
      end)

    case do_json(client, :post, "/v1/archives/public", %{entries: entries}) do
      {:ok, body} ->
        {:ok, %Antd.PutResult{cost: body["cost"], address: body["address"]}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Like `archive_put_public/2` but raises on error."
  @spec archive_put_public!(t(), Antd.Archive.t()) :: Antd.PutResult.t()
  def archive_put_public!(client, archive), do: unwrap!(archive_put_public(client, archive))

  @doc "Estimates the cost of uploading a file."
  @spec file_cost(t(), String.t(), boolean(), boolean()) :: {:ok, String.t()} | {:error, Exception.t()}
  def file_cost(%__MODULE__{} = client, path, is_public, include_archive) do
    payload = %{path: path, is_public: is_public, include_archive: include_archive}

    case do_json(client, :post, "/v1/cost/file", payload) do
      {:ok, body} -> {:ok, body["cost"]}
      {:error, _} = err -> err
    end
  end

  @doc "Like `file_cost/4` but raises on error."
  @spec file_cost!(t(), String.t(), boolean(), boolean()) :: String.t()
  def file_cost!(client, path, is_public, include_archive) do
    unwrap!(file_cost(client, path, is_public, include_archive))
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
