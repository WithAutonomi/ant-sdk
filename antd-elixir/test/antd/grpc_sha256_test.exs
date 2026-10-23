defmodule Antd.GrpcSha256Test do
  @moduledoc """
  gRPC `sha256` (antd 0.17.0) against a real grpc-elixir server with mock
  Data, File, Upload and Manifest services, dialled with a real
  `Antd.GrpcClient`: the five upload results read it (and read `nil` for the
  empty string), a manifest entry sets it only when given (proto3 presence),
  entry info reads it, and INVALID_ARGUMENT is a `BadRequestError`.
  """
  use ExUnit.Case, async: false

  alias Antd.{GrpcClient, ManifestEntryInput}

  @hash String.duplicate("ab", 32)
  @address String.duplicate("11", 32)
  @content String.duplicate("cc", 32)

  # In each mock, a payload (or path, or upload id) of "nohash" leaves sha256
  # at the proto3 default "", which is what a daemon older than 0.17.0 sends;
  # anything else carries the hash.
  defmodule MockDataServer do
    use GRPC.Server, service: Antd.V1.DataService.Service

    def put(req, _stream), do: %Antd.V1.PutDataResponse{data_map: "dm", sha256: sha(req.data)}

    def put_public(req, _stream),
      do: %Antd.V1.PutPublicDataResponse{address: "addr", sha256: sha(req.data)}

    defp sha(<<"nohash", _::binary>>), do: ""
    defp sha(_), do: String.duplicate("ab", 32)
  end

  defmodule MockFileServer do
    use GRPC.Server, service: Antd.V1.FileService.Service

    def put(req, _stream),
      do: %Antd.V1.PutFileResponse{data_map: "dm", chunks_stored: 3, sha256: sha(req.path)}

    def put_public(req, _stream),
      do: %Antd.V1.PutFilePublicResponse{address: "addr", chunks_stored: 3, sha256: sha(req.path)}

    defp sha("nohash"), do: ""
    defp sha(_), do: String.duplicate("ab", 32)
  end

  defmodule MockUploadServer do
    use GRPC.Server, service: Antd.V1.UploadService.Service

    def finalize_upload(req, _stream) do
      %Antd.V1.FinalizeUploadResponse{
        address: "addr",
        chunks_stored: 4,
        sha256: if(req.upload_id == "nohash", do: "", else: String.duplicate("ab", 32))
      }
    end
  end

  defmodule MockManifestServer do
    use GRPC.Server, service: Antd.V1.ManifestService.Service

    @content String.duplicate("cc", 32)

    # By default the request is echoed back, encoded, as the manifest bytes,
    # so the test reads the entries (and their presence) as they arrived.
    def build(req, _stream) do
      if Enum.any?(req.entries, &(&1.sha256 == "zz")) do
        raise GRPC.RPCError,
          status: GRPC.Status.invalid_argument(),
          message:
            "Bad request: entries[0]: invalid hex sha256: Invalid character 'z' at position 0"
      end

      %Antd.V1.BuildManifestResponse{
        manifest: Antd.V1.BuildManifestRequest.encode(req),
        entries: info()
      }
    end

    def decode(_req, _stream) do
      %Antd.V1.DecodeManifestResponse{source: "manifest", entries: info()}
    end

    defp info do
      [
        %Antd.V1.ManifestEntryInfo{
          effective_name: "public.txt",
          path: "public.txt",
          kind: "public",
          content_address: @content,
          sha256: String.duplicate("ab", 32)
        },
        # Unset: a plain string, so "" on the wire.
        %Antd.V1.ManifestEntryInfo{
          effective_name: "nohash.txt",
          path: "nohash.txt",
          kind: "public",
          content_address: @content
        }
      ]
    end
  end

  defmodule Endpoint do
    use GRPC.Endpoint
    run([MockDataServer, MockFileServer, MockUploadServer, MockManifestServer])
  end

  # See grpc_manifests_test.exs: `GRPC.Client.Supervisor` may still be going
  # down with the previous module, so wait for it and start one that outlives
  # this module.
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

  # ---------------------------------------------------------------------------
  # Upload results
  # ---------------------------------------------------------------------------

  test "data_put/3 reads sha256, and nil for the empty string", %{client: client} do
    assert {:ok, %Antd.DataPutResult{data_map: "dm", sha256: @hash}} =
             GrpcClient.data_put(client, "hello")

    assert {:ok, %Antd.DataPutResult{sha256: nil}} = GrpcClient.data_put(client, "nohash")
  end

  test "data_put_public/3 reads sha256, and nil for the empty string", %{client: client} do
    assert {:ok, %Antd.DataPutPublicResult{address: "addr", sha256: @hash}} =
             GrpcClient.data_put_public(client, "hello")

    assert {:ok, %Antd.DataPutPublicResult{sha256: nil}} =
             GrpcClient.data_put_public(client, "nohash")
  end

  test "file_put/3 reads sha256, and nil for the empty string", %{client: client} do
    assert {:ok, %Antd.FilePutResult{data_map: "dm", sha256: @hash}} =
             GrpcClient.file_put(client, "/f")

    assert {:ok, %Antd.FilePutResult{sha256: nil}} = GrpcClient.file_put(client, "nohash")
  end

  test "file_put_public/3 reads sha256, and nil for the empty string", %{client: client} do
    assert {:ok, %Antd.FilePutPublicResult{address: "addr", sha256: @hash}} =
             GrpcClient.file_put_public(client, "/f")

    assert {:ok, %Antd.FilePutPublicResult{sha256: nil}} =
             GrpcClient.file_put_public(client, "nohash")
  end

  test "finalize_upload/3 and finalize_merkle_upload/4 read sha256, and nil for the empty string",
       %{client: client} do
    assert {:ok, %Antd.FinalizeUploadResult{address: "addr", sha256: @hash}} =
             GrpcClient.finalize_upload(client, "up1", %{"0xq" => "0xt"})

    assert {:ok, %Antd.FinalizeUploadResult{sha256: @hash}} =
             GrpcClient.finalize_merkle_upload(client, "mb1", "0xw1")

    assert {:ok, %Antd.FinalizeUploadResult{sha256: nil}} =
             GrpcClient.finalize_upload(client, "nohash", %{})

    assert {:ok, %Antd.FinalizeUploadResult{sha256: nil}} =
             GrpcClient.finalize_merkle_upload(client, "nohash", "0xw1")
  end

  # ---------------------------------------------------------------------------
  # Manifest entries
  # ---------------------------------------------------------------------------

  test "build_manifest/3 sets sha256 only on an entry that gives it, and reads entry info",
       %{client: client} do
    entries = [
      %ManifestEntryInput{path: "a.txt", address: @address, sha256: "ABCD"},
      %ManifestEntryInput{path: "b.txt", address: @address},
      %ManifestEntryInput{path: "c.txt", address: @address, sha256: ""}
    ]

    assert {:ok, built} = GrpcClient.build_manifest(client, entries)

    assert [a, b, c] = Antd.V1.BuildManifestRequest.decode(built.manifest).entries
    # Presence, not the zero value: unset and "" stay unset.
    assert {a.sha256, b.sha256, c.sha256} == {"ABCD", nil, nil}

    assert [public, nohash] = built.entries
    assert {public.sha256, nohash.sha256} == {@hash, nil}
    assert nohash.content_address == @content
  end

  test "decode_manifest/3 and decode_manifest_link/3 read entry sha256, and nil for the empty string",
       %{client: client} do
    for decoded <- [
          GrpcClient.decode_manifest(client, <<0xC1, "ANT", 0x01>>),
          GrpcClient.decode_manifest_link(client, "ant://manifest/x")
        ] do
      assert {:ok, %Antd.DecodedManifest{entries: [public, nohash]}} = decoded
      assert {public.sha256, nohash.sha256} == {@hash, nil}
    end
  end

  test "INVALID_ARGUMENT for a bad sha256 is a BadRequestError carrying the daemon's message",
       %{client: client} do
    assert {:error, %Antd.BadRequestError{status_code: 400, message: message}} =
             GrpcClient.build_manifest(client, [
               %ManifestEntryInput{address: @address, sha256: "zz"}
             ])

    assert message ==
             "Bad request: entries[0]: invalid hex sha256: Invalid character 'z' at position 0"
  end
end
