defmodule Antd.ClientManifestsTest do
  @moduledoc """
  REST manifest API against a mock daemon (Bypass): request shapes, the
  base64 wire form of the `.ant` bytes, unset sizes, the entry check made
  before sending, and the bad-request mapping.
  """
  use ExUnit.Case, async: true

  alias Antd.{Client, ManifestEntryInput}

  @address String.duplicate("11", 32)
  @other String.duplicate("22", 32)
  @content String.duplicate("cc", 32)
  @v1 String.duplicate("a1", 20)
  @v2 String.duplicate("b2", 32)

  # The five-byte `.ant` header; "wUFOVAE=" is its base64.
  @header <<0xC1, "ANT", 0x01>>
  # Every byte value, so the base64 round trip covers non-UTF-8 input.
  @all_bytes :binary.list_to_bin(Enum.to_list(0..255))

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

  # ---------------------------------------------------------------------------
  # build_manifest
  # ---------------------------------------------------------------------------

  test "build_manifest/3 sends the entries and options, and returns raw bytes",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      {body, conn} = read_json(conn)

      assert body == %{
               "name" => "album",
               "torrent_info_hashes" => [@v1, @v2],
               "embed_roots" => false,
               "entries" => [
                 # Embedded: no address. Public: no path or size.
                 %{"path" => "a.txt", "size" => 10, "data_map" => "abcd"},
                 %{"address" => @address}
               ]
             }

      json(conn, 200, %{
        manifest: Base.encode64(@all_bytes),
        link: "ant://manifest/wUFOVAE",
        entries: [
          %{
            effective_name: "a.txt",
            path: "a.txt",
            size: 10,
            kind: "embedded",
            content_address: @content,
            exact_size: 10
          },
          %{effective_name: @address, kind: "public", content_address: @address}
        ]
      })
    end)

    entries = [
      %ManifestEntryInput{path: "a.txt", size: 10, data_map: "abcd"},
      %ManifestEntryInput{address: @address}
    ]

    assert {:ok, built} =
             Client.build_manifest(client, entries,
               name: "album",
               torrent_info_hashes: [@v1, @v2],
               embed_roots: false
             )

    assert built.manifest == @all_bytes
    assert built.link == "ant://manifest/wUFOVAE"

    assert [embedded, public] = built.entries

    assert embedded == %Antd.ManifestEntryInfo{
             effective_name: "a.txt",
             path: "a.txt",
             size: 10,
             kind: "embedded",
             content_address: @content,
             data_map: nil,
             exact_size: 10,
             error: nil
           }

    assert public == %Antd.ManifestEntryInfo{
             effective_name: @address,
             path: nil,
             size: nil,
             kind: "public",
             content_address: @address,
             data_map: nil,
             exact_size: nil,
             error: nil
           }
  end

  test "build_manifest/3 embeds roots by default and omits unset options",
       %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "POST", "/v1/manifests/build", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"entries" => [%{"address" => @address}], "embed_roots" => true}
      # No link: the daemon omits it when it would not fit 1,500 bytes.
      json(conn, 200, %{manifest: "wUFOVAE=", entries: []})
    end)

    entry = %ManifestEntryInput{address: @address}

    assert {:ok, %Antd.BuiltManifest{manifest: @header, link: nil, entries: []}} =
             Client.build_manifest(client, [entry])

    # An empty name or hash list, an explicit nil and an empty path are unset too.
    assert {:ok, _} =
             Client.build_manifest(client, [%{entry | path: ""}],
               name: "",
               torrent_info_hashes: [],
               embed_roots: nil
             )
  end

  test "an unset size or exact_size reads as nil, and a recorded 0 as 0",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      json(conn, 200, %{
        manifest: "",
        entries: [
          %{effective_name: "empty", path: "empty", size: 0, kind: "embedded", exact_size: 0},
          %{effective_name: "unset", path: "unset", kind: "public"},
          %{effective_name: "null", path: "null", size: nil, kind: "public", exact_size: nil}
        ]
      })
    end)

    assert {:ok, built} = Client.build_manifest(client, [%ManifestEntryInput{address: @address}])
    assert built.manifest == ""

    assert Enum.map(built.entries, &{&1.effective_name, &1.size, &1.exact_size}) == [
             {"empty", 0, 0},
             {"unset", nil, nil},
             {"null", nil, nil}
           ]
  end

  test "build_manifest/3 refuses a bad entry before sending anything, as the daemon would",
       %{client: client} do
    # The Bypass server expects no request, so any request fails the test.
    good = %ManifestEntryInput{address: @address}
    both = "give data_map or address, not both"
    neither = "needs a data_map or an address"
    size = "size must be nil or an integer from 0 to 2^64-1"

    bad = [
      {%ManifestEntryInput{data_map: "abcd", address: @address}, both},
      {%ManifestEntryInput{path: "a.txt"}, neither},
      {%ManifestEntryInput{data_map: "", address: ""}, neither},
      {%ManifestEntryInput{address: @address, size: -1}, size},
      {%ManifestEntryInput{address: @address, size: 18_446_744_073_709_551_616}, size},
      {%ManifestEntryInput{address: @address, size: 1.5}, size},
      {%ManifestEntryInput{address: @address, path: :a}, "path must be a string"},
      {%ManifestEntryInput{address: 42}, "address must be a hex string"},
      {%{address: @address},
       "expected an %Antd.ManifestEntryInput{}, got: %{address: \"#{@address}\"}"}
    ]

    for {entry, reason} <- bad do
      assert {:error, %Antd.BadRequestError{status_code: 400, message: message}} =
               Client.build_manifest(client, [good, entry])

      assert message == "1 invalid entries: entries[1]: #{reason}"
    end

    assert_raise Antd.BadRequestError, "1 invalid entries: entries[0]: #{neither}", fn ->
      Client.build_manifest!(client, [%ManifestEntryInput{}])
    end
  end

  test "every bad entry is reported, at most 20, in the daemon's wording",
       %{client: client} do
    both = %ManifestEntryInput{data_map: "abcd", address: @address}
    neither = %ManifestEntryInput{path: "a.txt"}
    good = %ManifestEntryInput{address: @address}

    assert {:error, %Antd.BadRequestError{status_code: 400, message: message}} =
             Client.build_manifest(client, [both, good, neither])

    assert message ==
             "2 invalid entries: entries[0]: give data_map or address, not both; " <>
               "entries[2]: needs a data_map or an address"

    assert {:error, %Antd.BadRequestError{status_code: 400, message: many}} =
             Client.build_manifest(client, List.duplicate(neither, 23))

    shown = Enum.map_join(0..19, "; ", &"entries[#{&1}]: needs a data_map or an address")
    assert many == "23 invalid entries: #{shown}; and 3 more"
  end

  test "an empty string counts as unset, so the other source is the entry's",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      {body, conn} = read_json(conn)
      assert body["entries"] == [%{"data_map" => "abcd"}, %{"address" => @address}]
      json(conn, 200, %{manifest: "", entries: []})
    end)

    assert {:ok, _} =
             Client.build_manifest(client, [
               %ManifestEntryInput{data_map: "abcd", address: ""},
               %ManifestEntryInput{data_map: "", address: @address}
             ])
  end

  test "a build response whose manifest is not base64 is an error",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      json(conn, 200, %{manifest: "not base64!", entries: []})
    end)

    assert {:error, %Antd.AntdError{status_code: 0, message: message}} =
             Client.build_manifest(client, [%ManifestEntryInput{address: @address}])

    assert message =~ "base64"
  end

  test "a rejected entry is a BadRequestError carrying the daemon's message",
       %{bypass: bypass, client: client} do
    message = ~s(Bad request: entries[0]: invalid path "../x": escapes the root)

    Bypass.expect_once(bypass, "POST", "/v1/manifests/build", fn conn ->
      json(conn, 400, %{error: message, code: "BAD_REQUEST"})
    end)

    assert {:error, %Antd.BadRequestError{status_code: 400, message: ^message}} =
             Client.build_manifest(client, [%ManifestEntryInput{path: "../x", address: @address}])
  end

  # ---------------------------------------------------------------------------
  # decode_manifest / decode_manifest_link
  # ---------------------------------------------------------------------------

  test "decode_manifest/3 sends the bytes as base64 and parses the result",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/decode", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"manifest" => Base.encode64(@all_bytes), "resolve" => true}

      json(conn, 200, %{
        source: "manifest",
        name: "album",
        torrent_info_hash_v2: @v2,
        entries: [
          %{
            effective_name: "a.txt",
            path: "a.txt",
            kind: "embedded",
            content_address: @content,
            data_map: "abcd",
            exact_size: 3
          },
          %{
            effective_name: "b",
            path: "b",
            kind: "public",
            content_address: @other,
            error: "Record not found: gone"
          }
        ]
      })
    end)

    assert {:ok, decoded} = Client.decode_manifest(client, @all_bytes, resolve: true)
    assert {decoded.source, decoded.name} == {"manifest", "album"}
    assert {decoded.torrent_info_hash_v1, decoded.torrent_info_hash_v2} == {nil, @v2}

    assert [embedded, failed] = decoded.entries
    assert {embedded.data_map, embedded.exact_size, embedded.error} == {"abcd", 3, nil}
    assert {embedded.size, embedded.kind} == {nil, "embedded"}

    # One entry's resolve failure is in its error, not a failed call.
    assert {failed.kind, failed.data_map, failed.exact_size} == {"public", nil, nil}
    assert failed.error == "Record not found: gone"
  end

  test "decode_manifest_link/3 sends the link and no bytes, without resolving by default",
       %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/manifests/decode", fn conn ->
      {body, conn} = read_json(conn)
      assert body == %{"link" => @address, "resolve" => false}

      json(conn, 200, %{
        source: "file_link",
        entries: [%{effective_name: @address, kind: "public", content_address: @address}]
      })
    end)

    assert {:ok, decoded} = Antd.decode_manifest_link(client, @address)
    assert {decoded.source, decoded.name} == {"file_link", nil}
    assert [%Antd.ManifestEntryInfo{path: nil, content_address: @address}] = decoded.entries
  end

  test "a malformed manifest is a BadRequestError carrying the daemon's message",
       %{bypass: bypass, client: client} do
    message = "Bad request: not a manifest: missing or invalid header"

    Bypass.expect_once(bypass, "POST", "/v1/manifests/decode", fn conn ->
      json(conn, 400, %{error: message, code: "BAD_REQUEST"})
    end)

    assert {:error, %Antd.BadRequestError{status_code: 400, message: ^message}} =
             Client.decode_manifest(client, "nope")
  end

  test "an empty decode input is refused before sending", %{client: client} do
    message = "needs a manifest (base64 .ant bytes) or a link"

    assert {:error, %Antd.BadRequestError{status_code: 400, message: ^message}} =
             Client.decode_manifest(client, "")

    assert {:error, %Antd.BadRequestError{status_code: 400, message: ^message}} =
             Client.decode_manifest_link(client, "")
  end
end
