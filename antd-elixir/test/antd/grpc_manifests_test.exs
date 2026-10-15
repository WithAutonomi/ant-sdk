defmodule Antd.GrpcManifestsTest do
  @moduledoc """
  gRPC manifest API against a real grpc-elixir server with a mock
  ManifestService, dialled with a real `Antd.GrpcClient`: request fields and
  their proto3 presence, raw bytes both ways, unset sizes, the bad-request
  mapping, the call timeout, and manifests larger than the 4 MiB receive
  default other gRPC clients have.
  """
  use ExUnit.Case, async: false

  alias Antd.{GrpcClient, ManifestEntryInput}

  @address String.duplicate("11", 32)
  @header <<0xC1, "ANT", 0x01>>

  defmodule MockManifestServer do
    use GRPC.Server, service: Antd.V1.ManifestService.Service

    @content String.duplicate("cc", 32)

    # The name picks the behaviour. By default the request is echoed back,
    # encoded, as the manifest bytes, so the test can read the fields (and
    # their presence) exactly as they arrived.
    def build(req, _stream) do
      case req.name do
        "invalid" ->
          raise GRPC.RPCError,
            status: GRPC.Status.invalid_argument(),
            message: ~s(Bad request: entries[1]: invalid path "../x": escapes the root)

        "slow" ->
          Process.sleep(1_000)
          %Antd.V1.BuildManifestResponse{}

        "big" ->
          %Antd.V1.BuildManifestResponse{manifest: big_manifest()}

        _ ->
          %Antd.V1.BuildManifestResponse{
            manifest: Antd.V1.BuildManifestRequest.encode(req),
            link: "ant://manifest/wUFOVAE",
            entries: [
              %Antd.V1.ManifestEntryInfo{
                effective_name: "a.txt",
                path: "a.txt",
                size: 10,
                kind: "embedded",
                content_address: @content,
                exact_size: 10
              },
              # Unset optionals, and a recorded size of 0.
              %Antd.V1.ManifestEntryInfo{
                effective_name: @content,
                kind: "public",
                content_address: @content
              },
              %Antd.V1.ManifestEntryInfo{
                effective_name: "empty",
                path: "empty",
                size: 0,
                kind: "public",
                content_address: @content,
                exact_size: 0
              }
            ]
          }
      end
    end

    def decode(req, _stream) do
      resolved = if req.resolve, do: "resolved", else: ""

      case req.input do
        {:manifest, "big" <> _ = bytes} ->
          # Hex of the bytes: a response twice the request's size.
          %Antd.V1.DecodeManifestResponse{
            source: "manifest",
            entries: [
              %Antd.V1.ManifestEntryInfo{
                effective_name: "big",
                kind: "embedded",
                data_map: Base.encode16(bytes, case: :lower)
              }
            ]
          }

        {:manifest, bytes} ->
          %Antd.V1.DecodeManifestResponse{
            source: "manifest",
            name: "bytes:" <> Base.encode16(bytes),
            torrent_info_hash_v1: resolved,
            entries: [
              %Antd.V1.ManifestEntryInfo{
                effective_name: "a.txt",
                path: "a.txt",
                kind: "embedded",
                content_address: @content,
                data_map: "abcd",
                exact_size: 3
              },
              %Antd.V1.ManifestEntryInfo{
                effective_name: "b",
                path: "b",
                kind: "public",
                content_address: @content,
                error: "Record not found: gone"
              }
            ]
          }

        {:link, "invalid"} ->
          raise GRPC.RPCError,
            status: GRPC.Status.invalid_argument(),
            message: "Bad request: not a manifest link"

        {:link, link} ->
          %Antd.V1.DecodeManifestResponse{
            source: "file_link",
            torrent_info_hash_v1: resolved,
            entries: [
              %Antd.V1.ManifestEntryInfo{
                effective_name: link,
                kind: "public",
                content_address: link
              }
            ]
          }
      end
    end

    # 8 MiB: twice the receive default of grpc-go and most other clients.
    def big_manifest, do: String.duplicate(<<0xC1, "ANT", 0x01, 0xFF, 0x00, 0x80>>, 1_048_576)
  end

  defmodule Endpoint do
    use GRPC.Endpoint
    run(MockManifestServer)
  end

  # `GRPC.Stub.connect/2` needs GRPC.Client.Supervisor, which grpc-elixir
  # does not start. Other modules start it linked to their setup_all
  # process, so one may still be registered while it goes down with that
  # module: wait for it to go, then start one that outlives this module, so
  # the next module does not inherit a dying one either.
  defp ensure_client_supervisor do
    case DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, pid}} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, _, _} -> ensure_client_supervisor()
        after
          100 ->
            Process.demonitor(ref, [:flush])
            :ok
        end
    end
  end

  setup_all do
    ensure_client_supervisor()
    {:ok, _pid, port} = GRPC.Server.start_endpoint(Endpoint, 0)
    on_exit(fn -> :ok = GRPC.Server.stop_endpoint(Endpoint) end)
    {:ok, client} = GrpcClient.new("localhost:#{port}")
    {:ok, client: client}
  end

  # The request the mock server echoed back as the manifest bytes.
  defp echoed(%Antd.BuiltManifest{manifest: bytes}),
    do: Antd.V1.BuildManifestRequest.decode(bytes)

  # ---------------------------------------------------------------------------
  # build_manifest
  # ---------------------------------------------------------------------------

  test "build_manifest/3 sends the entries and options with proto3 presence",
       %{client: client} do
    entries = [
      %ManifestEntryInput{path: "a.txt", size: 10, data_map: "abcd"},
      %ManifestEntryInput{address: @address},
      # A recorded size of 0 is sent as set, not dropped as a default.
      %ManifestEntryInput{path: "", size: 0, address: @address}
    ]

    assert {:ok, built} =
             GrpcClient.build_manifest(client, entries,
               name: "album",
               torrent_info_hashes: ["aa", "bb"],
               embed_roots: false
             )

    req = echoed(built)
    assert {req.name, req.torrent_info_hashes, req.embed_roots} == {"album", ["aa", "bb"], false}
    assert [first, second, third] = req.entries
    assert {first.path, first.size, first.source} == {"a.txt", 10, {:data_map, "abcd"}}
    assert {second.path, second.size, second.source} == {nil, nil, {:address, @address}}
    assert {third.path, third.size} == {nil, 0}

    assert built.link == "ant://manifest/wUFOVAE"
  end

  test "build_manifest/3 sends embed_roots true by default and leaves the name unset",
       %{client: client} do
    assert {:ok, built} =
             GrpcClient.build_manifest(client, [%ManifestEntryInput{address: @address}])

    req = echoed(built)
    assert {req.name, req.torrent_info_hashes, req.embed_roots} == {nil, [], true}

    assert {:ok, built} =
             GrpcClient.build_manifest(client, [%ManifestEntryInput{address: @address}], name: "")

    assert echoed(built).name == nil
  end

  test "unset sizes and strings read as nil, and a recorded 0 as 0", %{client: client} do
    assert {:ok, built} =
             GrpcClient.build_manifest(client, [%ManifestEntryInput{address: @address}])

    assert [embedded, public, empty] = built.entries
    assert {embedded.path, embedded.size, embedded.exact_size} == {"a.txt", 10, 10}
    assert {embedded.kind, embedded.data_map, embedded.error} == {"embedded", nil, nil}
    assert {public.path, public.size, public.exact_size} == {nil, nil, nil}
    assert {public.data_map, public.error} == {nil, nil}
    assert {empty.size, empty.exact_size} == {0, 0}
  end

  test "build_manifest/3 refuses a bad entry before sending anything" do
    # No channel at all: the check must answer before any call is made.
    offline = %GrpcClient{target: "unused", channel: nil}

    for entry <- [
          %ManifestEntryInput{data_map: "abcd", address: @address},
          %ManifestEntryInput{path: "a.txt"},
          %ManifestEntryInput{address: @address, size: -1}
        ] do
      assert {:error, %Antd.BadRequestError{status_code: 0, message: message}} =
               GrpcClient.build_manifest(offline, [%ManifestEntryInput{address: @address}, entry])

      assert message =~ "entries[1]"
    end

    assert {:error, %Antd.BadRequestError{status_code: 0}} =
             GrpcClient.decode_manifest(offline, "")

    assert {:error, %Antd.BadRequestError{status_code: 0}} =
             GrpcClient.decode_manifest_link(offline, "")
  end

  test "INVALID_ARGUMENT is a BadRequestError carrying the daemon's message",
       %{client: client} do
    assert {:error, %Antd.BadRequestError{status_code: 400, message: message}} =
             GrpcClient.build_manifest(client, [%ManifestEntryInput{address: @address}],
               name: "invalid"
             )

    assert message == ~s(Bad request: entries[1]: invalid path "../x": escapes the root)

    assert_raise Antd.BadRequestError, ~r/not a manifest link/, fn ->
      GrpcClient.decode_manifest_link!(client, "invalid")
    end
  end

  test "the :timeout option bounds the call", %{client: client} do
    assert {:error, %Antd.AntdError{status_code: 4}} =
             GrpcClient.build_manifest(client, [%ManifestEntryInput{address: @address}],
               name: "slow",
               timeout: 100
             )
  end

  # ---------------------------------------------------------------------------
  # decode_manifest / decode_manifest_link
  # ---------------------------------------------------------------------------

  test "decode_manifest/3 sends raw bytes and parses the result", %{client: client} do
    assert {:ok, decoded} = GrpcClient.decode_manifest(client, @header, resolve: true)
    assert decoded.source == "manifest"
    # The server saw the five raw bytes, not their base64.
    assert decoded.name == "bytes:C1414E5401"
    assert {decoded.torrent_info_hash_v1, decoded.torrent_info_hash_v2} == {"resolved", nil}

    assert [embedded, failed] = decoded.entries
    assert {embedded.data_map, embedded.exact_size, embedded.error} == {"abcd", 3, nil}
    assert {failed.data_map, failed.exact_size} == {nil, nil}
    assert failed.error == "Record not found: gone"
  end

  test "decode_manifest_link/3 sends the link, without resolving by default",
       %{client: client} do
    assert {:ok, decoded} = GrpcClient.decode_manifest_link(client, @address)
    assert {decoded.source, decoded.name, decoded.torrent_info_hash_v1} == {"file_link", nil, nil}
    assert [%Antd.ManifestEntryInfo{path: nil, content_address: @address}] = decoded.entries
  end

  # ---------------------------------------------------------------------------
  # Message size
  # ---------------------------------------------------------------------------

  test "a manifest over 4 MiB is received whole", %{client: client} do
    assert {:ok, built} =
             GrpcClient.build_manifest(client, [%ManifestEntryInput{address: @address}],
               name: "big"
             )

    assert byte_size(built.manifest) == 8 * 1024 * 1024
    assert built.manifest == MockManifestServer.big_manifest()
  end

  test "a manifest over 4 MiB is sent whole, and a larger response received",
       %{client: client} do
    bytes = "big" <> :binary.copy(<<0xAB>>, 6 * 1024 * 1024)

    assert {:ok, %Antd.DecodedManifest{entries: [entry]}} =
             GrpcClient.decode_manifest(client, bytes)

    assert byte_size(entry.data_map) == 2 * byte_size(bytes)
    assert Base.decode16!(entry.data_map, case: :lower) == bytes
  end
end
