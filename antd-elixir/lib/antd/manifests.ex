defmodule Antd.Manifests do
  @moduledoc false

  # Request building and response parsing shared by the REST (`Antd.Client`)
  # and gRPC (`Antd.GrpcClient`) manifest functions: ADR-0006 `.ant` files
  # and `ant://` links (V2-1580). The daemon builds and decodes them through
  # ant-core, so nothing here re-implements the format.
  #
  # The `.ant` bytes are base64 in REST JSON (`manifest` in the build
  # response and the decode request) and raw `bytes` over gRPC. Callers only
  # ever see raw binaries.
  #
  # Sizes are plain integers, and `nil` when unset, never 0: REST omits an
  # unset `size` or `exact_size`, and gRPC marks both proto3 `optional`,
  # which protobuf-elixir reads as `nil` when absent. Every other absent
  # value is `nil` on both transports too: REST omits it, and gRPC sends its
  # plain strings (`link`, `data_map`, `error`, the torrent hashes) as `""`.

  @max_u64 18_446_744_073_709_551_615

  # ---------------------------------------------------------------------------
  # Checks made before anything is sent
  # ---------------------------------------------------------------------------

  @doc """
  Checks each entry the way the daemon would before it is sent: an
  `Antd.ManifestEntryInput` with exactly one of `data_map` or `address`
  (an empty string counts as unset, as it does for the daemon), string
  fields, and a size that is `nil` or a u64. The first problem is an
  `Antd.BadRequestError` naming `entries[i]`, with `status_code` 0 since the
  daemon never saw it.
  """
  @spec check_entries([term()]) :: :ok | {:error, Antd.BadRequestError.t()}
  def check_entries(entries) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {entry, i} ->
      case entry_problem(entry) do
        nil -> nil
        problem -> {:error, bad_request("antd: manifest entries[#{i}]: #{problem}")}
      end
    end)
  end

  defp entry_problem(%Antd.ManifestEntryInput{} = e) do
    cond do
      not optional_string?(e.data_map) -> "data_map must be a hex string"
      not optional_string?(e.address) -> "address must be a hex string"
      not optional_string?(e.path) -> "path must be a string"
      given?(e.data_map) == given?(e.address) -> "set exactly one of data_map or address"
      not size?(e.size) -> "size must be nil or an integer from 0 to 2^64-1"
      true -> nil
    end
  end

  defp entry_problem(other),
    do: "expected an %Antd.ManifestEntryInput{}, got: #{inspect(other)}"

  @doc """
  Refuses an empty decode input before it is sent; `label` names it, e.g.
  `"decode_manifest: manifest"`.
  """
  @spec check_input(String.t(), binary()) :: :ok | {:error, Antd.BadRequestError.t()}
  def check_input(_label, input) when is_binary(input) and input != "", do: :ok
  def check_input(label, _input), do: {:error, bad_request("antd: #{label} is empty")}

  defp bad_request(message), do: %Antd.BadRequestError{message: message, status_code: 0}

  # ---------------------------------------------------------------------------
  # Options
  # ---------------------------------------------------------------------------

  # Roots are embedded unless the caller says `embed_roots: false`. The value
  # is always sent, so the default is this SDK's whatever a daemon's is.
  defp embed_roots?(opts), do: Keyword.get(opts, :embed_roots, true) != false
  defp resolve?(opts), do: Keyword.get(opts, :resolve, false) == true
  defp name(opts), do: presence(Keyword.get(opts, :name))
  defp torrent_info_hashes(opts), do: Keyword.get(opts, :torrent_info_hashes) || []

  # ---------------------------------------------------------------------------
  # REST (JSON bodies)
  # ---------------------------------------------------------------------------

  @doc "The `POST /v1/manifests/build` body."
  @spec build_payload([Antd.ManifestEntryInput.t()], keyword()) :: map()
  def build_payload(entries, opts) do
    %{entries: Enum.map(entries, &entry_json/1), embed_roots: embed_roots?(opts)}
    |> put_given(:name, name(opts))
    |> put_given(:torrent_info_hashes, torrent_info_hashes(opts))
  end

  defp entry_json(%Antd.ManifestEntryInput{} = e) do
    if(given?(e.data_map), do: %{data_map: e.data_map}, else: %{address: e.address})
    |> put_given(:path, presence(e.path))
    |> put_given(:size, e.size)
  end

  defp put_given(map, _key, nil), do: map
  defp put_given(map, _key, []), do: map
  defp put_given(map, key, value), do: Map.put(map, key, value)

  @doc "The `POST /v1/manifests/decode` body for `.ant` bytes, sent as base64."
  @spec decode_bytes_payload(binary(), keyword()) :: map()
  def decode_bytes_payload(manifest, opts),
    do: %{manifest: Base.encode64(manifest), resolve: resolve?(opts)}

  @doc "The `POST /v1/manifests/decode` body for a link or bare address."
  @spec decode_link_payload(String.t(), keyword()) :: map()
  def decode_link_payload(link, opts), do: %{link: link, resolve: resolve?(opts)}

  @doc "Parses a build response, decoding its base64 `manifest` to raw bytes."
  @spec built_from_json(map()) :: {:ok, Antd.BuiltManifest.t()} | {:error, Antd.AntdError.t()}
  def built_from_json(body) do
    case Base.decode64(str(body["manifest"])) do
      {:ok, manifest} ->
        {:ok,
         %Antd.BuiltManifest{
           manifest: manifest,
           link: presence(body["link"]),
           entries: entries_from_json(body["entries"])
         }}

      :error ->
        {:error,
         %Antd.AntdError{
           message: "antd: build_manifest: the daemon's manifest is not valid base64",
           status_code: 0
         }}
    end
  end

  @doc "Parses a decode response."
  @spec decoded_from_json(map()) :: Antd.DecodedManifest.t()
  def decoded_from_json(body) do
    %Antd.DecodedManifest{
      source: str(body["source"]),
      name: presence(body["name"]),
      torrent_info_hash_v1: presence(body["torrent_info_hash_v1"]),
      torrent_info_hash_v2: presence(body["torrent_info_hash_v2"]),
      entries: entries_from_json(body["entries"])
    }
  end

  defp entries_from_json(entries) when is_list(entries),
    do: for(e <- entries, is_map(e), do: entry_from_json(e))

  defp entries_from_json(_), do: []

  defp entry_from_json(e) do
    %Antd.ManifestEntryInfo{
      effective_name: str(e["effective_name"]),
      path: presence(e["path"]),
      size: json_size(e["size"]),
      kind: str(e["kind"]),
      content_address: str(e["content_address"]),
      data_map: presence(e["data_map"]),
      exact_size: json_size(e["exact_size"]),
      error: presence(e["error"])
    }
  end

  # Absent (omitted) or anything but a non-negative integer reads as unset.
  defp json_size(n) when is_integer(n) and n >= 0, do: n
  defp json_size(_), do: nil

  # ---------------------------------------------------------------------------
  # gRPC (ManifestService messages)
  # ---------------------------------------------------------------------------

  @doc "The `ManifestService.Build` request."
  @spec build_request([Antd.ManifestEntryInput.t()], keyword()) ::
          Antd.V1.BuildManifestRequest.t()
  def build_request(entries, opts) do
    %Antd.V1.BuildManifestRequest{
      name: name(opts),
      torrent_info_hashes: torrent_info_hashes(opts),
      embed_roots: embed_roots?(opts),
      entries: Enum.map(entries, &entry_proto/1)
    }
  end

  # `path` and `size` are proto3 `optional`: `nil` leaves them unset.
  defp entry_proto(%Antd.ManifestEntryInput{} = e) do
    %Antd.V1.ManifestEntryInput{
      path: presence(e.path),
      size: e.size,
      source: if(given?(e.data_map), do: {:data_map, e.data_map}, else: {:address, e.address})
    }
  end

  @doc """
  The `ManifestService.Decode` request: `{:manifest, bytes}` (raw, not
  base64) or `{:link, link}`.
  """
  @spec decode_request({:manifest, binary()} | {:link, String.t()}, keyword()) ::
          Antd.V1.DecodeManifestRequest.t()
  def decode_request(input, opts),
    do: %Antd.V1.DecodeManifestRequest{input: input, resolve: resolve?(opts)}

  @doc "Maps a `BuildManifestResponse`."
  @spec built_from_proto(Antd.V1.BuildManifestResponse.t()) :: Antd.BuiltManifest.t()
  def built_from_proto(resp) do
    %Antd.BuiltManifest{
      manifest: resp.manifest,
      link: presence(resp.link),
      entries: Enum.map(resp.entries, &entry_from_proto/1)
    }
  end

  @doc "Maps a `DecodeManifestResponse`."
  @spec decoded_from_proto(Antd.V1.DecodeManifestResponse.t()) :: Antd.DecodedManifest.t()
  def decoded_from_proto(resp) do
    %Antd.DecodedManifest{
      source: resp.source,
      name: presence(resp.name),
      torrent_info_hash_v1: presence(resp.torrent_info_hash_v1),
      torrent_info_hash_v2: presence(resp.torrent_info_hash_v2),
      entries: Enum.map(resp.entries, &entry_from_proto/1)
    }
  end

  # `size` and `exact_size` are `nil` when the daemon left them unset, so a
  # recorded 0 stays 0 and an unset size never reads as one.
  defp entry_from_proto(e) do
    %Antd.ManifestEntryInfo{
      effective_name: e.effective_name,
      path: presence(e.path),
      size: e.size,
      kind: e.kind,
      content_address: e.content_address,
      data_map: presence(e.data_map),
      exact_size: e.exact_size,
      error: presence(e.error)
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp given?(value), do: is_binary(value) and value != ""

  defp optional_string?(value), do: is_nil(value) or is_binary(value)

  defp size?(nil), do: true
  defp size?(n), do: is_integer(n) and n >= 0 and n <= @max_u64

  defp str(value) when is_binary(value), do: value
  defp str(_), do: ""

  # A string, or `nil` for one that is absent or empty.
  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_), do: nil
end
