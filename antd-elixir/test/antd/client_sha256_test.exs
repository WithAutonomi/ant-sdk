defmodule Antd.ClientSha256Test do
  @moduledoc """
  REST `sha256` (antd 0.17.0) against a mock daemon (Bypass): the five upload
  results read it (and read `nil` when the key is absent or empty), a manifest
  entry sends it only when given, entry info reads it, and a bad hash is the
  daemon's 400 as a `BadRequestError`.
  """
  use ExUnit.Case, async: true

  alias Antd.{Client, ManifestEntryInput}

  @hash String.duplicate("ab", 32)
  @address String.duplicate("11", 32)
  @content String.duplicate("cc", 32)

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: Client.new("http://localhost:#{bypass.port}")}
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  defp read_json(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  # Replies to `path` with `body` and returns the SDK call's result.
  defp respond(bypass, path, body) do
    Bypass.expect_once(bypass, "POST", path, fn conn -> json(conn, 200, body) end)
  end

  # ---------------------------------------------------------------------------
  # Upload results
  # ---------------------------------------------------------------------------

  test "data_put/3 reads sha256, and nil when absent or empty", %{bypass: bypass, client: client} do
    respond(bypass, "/v1/data", %{data_map: "dm", chunks_stored: 1, sha256: @hash})

    assert {:ok, %Antd.DataPutResult{data_map: "dm", sha256: @hash}} =
             Client.data_put(client, "x")

    respond(bypass, "/v1/data", %{data_map: "dm", chunks_stored: 1})
    assert {:ok, %Antd.DataPutResult{sha256: nil}} = Client.data_put(client, "x")

    respond(bypass, "/v1/data", %{data_map: "dm", chunks_stored: 1, sha256: ""})
    assert {:ok, %Antd.DataPutResult{sha256: nil}} = Client.data_put(client, "x")
  end

  test "data_put_public/3 reads sha256, and nil when absent or empty",
       %{bypass: bypass, client: client} do
    respond(bypass, "/v1/data/public", %{address: @address, chunks_stored: 2, sha256: @hash})

    assert {:ok, %Antd.DataPutPublicResult{address: @address, sha256: @hash}} =
             Client.data_put_public(client, "x")

    respond(bypass, "/v1/data/public", %{address: @address, chunks_stored: 2})
    assert {:ok, %Antd.DataPutPublicResult{sha256: nil}} = Client.data_put_public(client, "x")

    respond(bypass, "/v1/data/public", %{address: @address, sha256: ""})
    assert {:ok, %Antd.DataPutPublicResult{sha256: nil}} = Client.data_put_public(client, "x")
  end

  test "file_put/3 reads sha256, and nil when absent or empty", %{bypass: bypass, client: client} do
    base = %{data_map: "dm", storage_cost_atto: "1", gas_cost_wei: "2", chunks_stored: 3}
    respond(bypass, "/v1/files", Map.put(base, :sha256, @hash))

    assert {:ok, %Antd.FilePutResult{data_map: "dm", sha256: @hash}} =
             Client.file_put(client, "/f")

    respond(bypass, "/v1/files", base)
    assert {:ok, %Antd.FilePutResult{sha256: nil}} = Client.file_put(client, "/f")

    respond(bypass, "/v1/files", Map.put(base, :sha256, ""))
    assert {:ok, %Antd.FilePutResult{sha256: nil}} = Client.file_put(client, "/f")
  end

  test "file_put_public/3 reads sha256, and nil when absent or empty",
       %{bypass: bypass, client: client} do
    base = %{address: @address, storage_cost_atto: "1", gas_cost_wei: "2", chunks_stored: 3}
    respond(bypass, "/v1/files/public", Map.put(base, :sha256, @hash))

    assert {:ok, %Antd.FilePutPublicResult{address: @address, sha256: @hash}} =
             Client.file_put_public(client, "/f")

    respond(bypass, "/v1/files/public", base)
    assert {:ok, %Antd.FilePutPublicResult{sha256: nil}} = Client.file_put_public(client, "/f")

    respond(bypass, "/v1/files/public", Map.put(base, :sha256, ""))
    assert {:ok, %Antd.FilePutPublicResult{sha256: nil}} = Client.file_put_public(client, "/f")
  end

  test "finalize_upload/3 and finalize_merkle_upload/4 read sha256, and nil when absent or empty",
       %{bypass: bypass, client: client} do
    base = %{address: @address, chunks_stored: 4, data_map: "dm"}

    respond(bypass, "/v1/upload/finalize", Map.put(base, :sha256, @hash))

    assert {:ok, %Antd.FinalizeUploadResult{address: @address, sha256: @hash}} =
             Client.finalize_upload(client, "up1", %{"0xq" => "0xt"})

    respond(bypass, "/v1/upload/finalize", Map.put(base, :sha256, @hash))

    assert {:ok, %Antd.FinalizeUploadResult{sha256: @hash}} =
             Client.finalize_merkle_upload(client, "mb1", "0xw1")

    respond(bypass, "/v1/upload/finalize", base)

    assert {:ok, %Antd.FinalizeUploadResult{sha256: nil}} =
             Client.finalize_upload(client, "up1", %{"0xq" => "0xt"})

    respond(bypass, "/v1/upload/finalize", Map.put(base, :sha256, ""))

    assert {:ok, %Antd.FinalizeUploadResult{sha256: nil}} =
             Client.finalize_merkle_upload(client, "mb1", "0xw1")
  end

  # ---------------------------------------------------------------------------
  # Manifest entries
  # ---------------------------------------------------------------------------

  test "build_manifest/3 sends sha256 only on an entry that sets it, as given",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      {body, conn} = read_json(conn)

      assert body["entries"] == [
               # Passed through exactly as given: no lowercasing, no checks.
               %{"address" => @address, "path" => "a.txt", "sha256" => "ABCD"},
               # Unset, nil and "" are all omitted, never null or "".
               %{"address" => @address, "path" => "b.txt"},
               %{"address" => @address, "path" => "c.txt"},
               %{"data_map" => "abcd", "sha256" => @hash}
             ]

      json(conn, 200, %{
        manifest: Base.encode64("m"),
        entries: [
          %{
            effective_name: "a.txt",
            path: "a.txt",
            kind: "public",
            content_address: @content,
            sha256: @hash
          },
          %{effective_name: "b.txt", path: "b.txt", kind: "public", content_address: @content},
          %{
            effective_name: "c.txt",
            path: "c.txt",
            kind: "public",
            content_address: @content,
            sha256: ""
          }
        ]
      })
    end)

    entries = [
      %ManifestEntryInput{path: "a.txt", address: @address, sha256: "ABCD"},
      %ManifestEntryInput{path: "b.txt", address: @address},
      %ManifestEntryInput{path: "c.txt", address: @address, sha256: ""},
      %ManifestEntryInput{data_map: "abcd", sha256: @hash}
    ]

    assert {:ok, %Antd.BuiltManifest{entries: [a, b, c]}} = Client.build_manifest(client, entries)
    assert {a.sha256, b.sha256, c.sha256} == {@hash, nil, nil}
  end

  test "decode_manifest/3 and decode_manifest_link/3 read entry sha256, and nil when absent or empty",
       %{bypass: bypass, client: client} do
    decoded = %{
      source: "manifest",
      entries: [
        %{effective_name: "public.txt", path: "public.txt", kind: "public", sha256: @hash},
        %{effective_name: "nohash.txt", path: "nohash.txt", kind: "public"},
        %{effective_name: "empty.txt", path: "empty.txt", kind: "public", sha256: ""}
      ]
    }

    for decode <- [
          fn -> Client.decode_manifest(client, <<0xC1, "ANT", 0x01>>) end,
          fn -> Client.decode_manifest_link(client, "ant://manifest/x", resolve: false) end
        ] do
      respond(bypass, "/v1/manifests/decode", decoded)
      assert {:ok, %Antd.DecodedManifest{entries: [a, b, c]}} = decode.()
      assert {a.sha256, b.sha256, c.sha256} == {@hash, nil, nil}
    end
  end

  test "a malformed sha256 is a BadRequestError carrying the daemon's message",
       %{bypass: bypass, client: client} do
    message = "entries[0]: invalid hex sha256: Invalid character 'z' at position 0"

    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      {body, conn} = read_json(conn)
      assert [%{"sha256" => "zz"}] = body["entries"]
      json(conn, 400, %{error: message, code: "BAD_REQUEST"})
    end)

    assert {:error, %Antd.BadRequestError{status_code: 400, message: ^message}} =
             Client.build_manifest(client, [%ManifestEntryInput{address: @address, sha256: "zz"}])
  end
end
