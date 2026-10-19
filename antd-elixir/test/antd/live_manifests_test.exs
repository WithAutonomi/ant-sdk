defmodule Antd.LiveManifestsTest do
  @moduledoc """
  Live manifest round trip against a running antd with a devnet behind it.
  It builds and decodes manifests of files that are already uploaded, so it
  pays for nothing and needs no wallet.

  Skipped unless `ANTD_TEST_URL` and `ANTD_TEST_MANIFEST_ADDRESSES` are set:

    * `ANTD_TEST_URL` — the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
    * `ANTD_TEST_MANIFEST_ADDRESSES` — two comma-separated addresses of
      public data uploads
    * `ANTD_TEST_MANIFEST_SIZES` — their exact plaintext sizes, comma-separated
    * `ANTD_TEST_MANIFEST_DATA_MAP` — the hex DataMap of a private data upload
    * `ANTD_TEST_MANIFEST_DATA_MAP_SIZE` — its exact plaintext size
    * `ANTD_TEST_MANIFEST_LINK` (optional) — an `ant://manifest/` link built
      from those three files, decoded as given
    * `ANTD_TEST_GRPC` (optional) — the daemon's gRPC target, e.g.
      `127.0.0.1:50051`; when set, everything is repeated over gRPC

      ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> \\
      ANTD_TEST_MANIFEST_SIZES=<n>,<n> ANTD_TEST_MANIFEST_DATA_MAP=<hex> \\
      ANTD_TEST_MANIFEST_DATA_MAP_SIZE=<n> mix test test/antd/live_manifests_test.exs
  """
  use ExUnit.Case, async: false

  alias Antd.{Client, GrpcClient, ManifestEntryInput}

  @url System.get_env("ANTD_TEST_URL")
  @grpc System.get_env("ANTD_TEST_GRPC")
  @addresses System.get_env("ANTD_TEST_MANIFEST_ADDRESSES")
  @sizes System.get_env("ANTD_TEST_MANIFEST_SIZES")
  @data_map System.get_env("ANTD_TEST_MANIFEST_DATA_MAP")
  @data_map_size System.get_env("ANTD_TEST_MANIFEST_DATA_MAP_SIZE")
  @link System.get_env("ANTD_TEST_MANIFEST_LINK")

  if is_nil(@url) or is_nil(@addresses) do
    @moduletag skip: "set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run"
  end

  @moduletag timeout: 600_000

  defp pair(value, name) do
    case String.split(value || "", ",") do
      [a, b] when a != "" and b != "" -> {String.trim(a), String.trim(b)}
      _ -> flunk("#{name} must be two comma-separated values")
    end
  end

  defp size(value, name) do
    case Integer.parse(String.trim(value || "")) do
      {n, ""} -> n
      _ -> flunk("#{name} must be an integer")
    end
  end

  defp fixtures do
    {a1, a2} = pair(@addresses, "ANTD_TEST_MANIFEST_ADDRESSES")
    {s1, s2} = pair(@sizes, "ANTD_TEST_MANIFEST_SIZES")
    data_map = @data_map || flunk("set ANTD_TEST_MANIFEST_DATA_MAP")

    %{
      a1: a1,
      a2: a2,
      s1: size(s1, "ANTD_TEST_MANIFEST_SIZES"),
      s2: size(s2, "ANTD_TEST_MANIFEST_SIZES"),
      data_map: data_map,
      data_map_size: size(@data_map_size, "ANTD_TEST_MANIFEST_DATA_MAP_SIZE")
    }
  end

  defp by_name(entries), do: Map.new(entries, &{&1.effective_name, &1})

  # The same round trip through either client: both take the same arguments.
  defp round_trip(mod, client) do
    f = fixtures()

    entries = [
      %ManifestEntryInput{path: "public/one.txt", size: f.s1, address: f.a1},
      %ManifestEntryInput{path: "public/two.txt", address: f.a2},
      %ManifestEntryInput{path: "private/three.txt", data_map: f.data_map}
    ]

    # ── build ──
    built = mod.build_manifest!(client, entries, name: "antd-elixir-live")
    assert binary_part(built.manifest, 0, 5) == <<0xC1, "ANT", 0x01>>
    assert is_binary(built.link) and String.starts_with?(built.link, "ant://manifest/")

    names = Enum.map(built.entries, & &1.effective_name)
    assert names == ["private/three.txt", "public/one.txt", "public/two.txt"]

    b = by_name(built.entries)
    assert {b["public/one.txt"].kind, b["public/one.txt"].content_address} == {"public", f.a1}
    assert {b["public/two.txt"].kind, b["public/two.txt"].content_address} == {"public", f.a2}
    assert b["private/three.txt"].kind == "embedded"
    # The recorded size is the one given; none was given for the others.
    assert b["public/one.txt"].size == f.s1
    assert b["public/two.txt"].size == nil
    assert b["private/three.txt"].size == nil

    # ── decode the bytes and the link, resolving ──
    for decoded <- [
          mod.decode_manifest!(client, built.manifest, resolve: true),
          mod.decode_manifest_link!(client, built.link, resolve: true)
        ] do
      assert {decoded.source, decoded.name} == {"manifest", "antd-elixir-live"}
      d = by_name(decoded.entries)
      assert Map.keys(d) == names
      assert Enum.all?(decoded.entries, &is_nil(&1.error)), inspect(decoded.entries)

      assert d["public/one.txt"].exact_size == f.s1
      assert d["public/two.txt"].exact_size == f.s2
      assert d["private/three.txt"].exact_size == f.data_map_size

      embedded = d["private/three.txt"]
      assert embedded.kind == "embedded"
      assert is_binary(embedded.data_map) and embedded.data_map != ""
      assert d["public/one.txt"].data_map == nil
      assert {d["public/one.txt"].size, d["public/two.txt"].size} == {f.s1, nil}
    end

    # Without resolving, a public entry's exact size is unknown: nil, not 0.
    plain = by_name(mod.decode_manifest!(client, built.manifest).entries)
    assert plain["public/two.txt"].exact_size == nil
    assert plain["private/three.txt"].exact_size == f.data_map_size

    # A bare address reads as one public entry.
    file = mod.decode_manifest_link!(client, f.a1, resolve: true)
    assert file.source == "file_link"
    assert [%Antd.ManifestEntryInfo{path: nil, kind: "public"} = only] = file.entries
    assert {only.content_address, only.exact_size} == {f.a1, f.s1}

    # ── the fixture link ──
    if @link do
      fixture = mod.decode_manifest_link!(client, String.trim(@link), resolve: true)
      assert fixture.source == "manifest"
      assert length(fixture.entries) == 3

      assert Enum.all?(fixture.entries, &is_nil(&1.error)), inspect(fixture.entries)

      sizes =
        Map.new(fixture.entries, fn
          %Antd.ManifestEntryInfo{kind: "embedded"} = e -> {:embedded, e.exact_size}
          e -> {e.content_address, e.exact_size}
        end)

      assert sizes == %{f.a1 => f.s1, f.a2 => f.s2, :embedded => f.data_map_size}
    end

    # ── bad entries ──
    both = %ManifestEntryInput{data_map: f.data_map, address: f.a1}

    # The client-side refusals carry the daemon's status and wording. Send
    # the same bad requests past the check, straight to the daemon, and the
    # answers, minus REST's \"Bad request: \" prefix, must equal the client's message.
    for {entry, reason} <- [
          {both, "give data_map or address, not both"},
          {%ManifestEntryInput{}, "needs a data_map or an address"}
        ] do
      assert {:error, %Antd.BadRequestError{status_code: 400, message: local}} =
               mod.build_manifest(client, [entry])

      assert local == "1 invalid entries: entries[0]: #{reason}"
      # REST's error field is AntdError's Display, "Bad request: <text>"; gRPC
      # sends the bare text. The client's message is the bare text.
      remote =
        entry
        |> then(&daemon_message(mod, client, &1))
        |> String.replace_prefix("Bad request: ", "")

      assert remote == local, "daemon said #{inspect(remote)}, client #{inspect(local)}"
    end

    assert {:error, %Antd.BadRequestError{status_code: 400, message: empty}} =
             mod.decode_manifest(client, "")

    assert empty == "needs a manifest (base64 .ant bytes) or a link"

    escaping = %ManifestEntryInput{path: "../x", address: f.a1}

    assert {:error, %Antd.BadRequestError{status_code: 400, message: message}} =
             mod.build_manifest(client, [hd(entries), escaping])

    assert message =~ "entries[1]"

    assert {:error, %Antd.BadRequestError{status_code: 400}} =
             mod.decode_manifest(client, "not a manifest")
  end

  test "manifest round trip over REST" do
    round_trip(Client, Client.new(@url, timeout: 300_000))
  end

  if is_nil(@grpc), do: @tag(skip: "set ANTD_TEST_GRPC to run the gRPC round trip")

  test "manifest round trip over gRPC" do
    ensure_client_supervisor()
    {:ok, client} = GrpcClient.new(@grpc)
    round_trip(GrpcClient, client)
  end

  # What the daemon itself answers to a build with this one entry. Over gRPC
  # the oneof can hold one source, so only an entry with neither is sendable.
  defp daemon_message(Client, client, entry) do
    wire = for {k, v} <- [data_map: entry.data_map, address: entry.address], v, do: {k, v}
    payload = %{entries: [Map.new(wire)], embed_roots: true}

    case Req.post(client.base_url <> "/v1/manifests/build", json: payload, retry: false) do
      {:ok, %Req.Response{status: 400, body: %{"error" => message}}} -> message
      other -> flunk("expected a 400 from the daemon, got #{inspect(other)}")
    end
  end

  defp daemon_message(GrpcClient, client, %{data_map: nil, address: nil}) do
    req = %Antd.V1.BuildManifestRequest{entries: [%Antd.V1.ManifestEntryInput{}]}

    case Antd.V1.ManifestService.Stub.build(client.channel, req) do
      {:error, %GRPC.RPCError{status: 3, message: message}} -> message
      other -> flunk("expected INVALID_ARGUMENT from the daemon, got #{inspect(other)}")
    end
  end

  # No way to send both sources over gRPC: the REST wording is the same code.
  defp daemon_message(GrpcClient, _client, _entry),
    do: "1 invalid entries: entries[0]: give data_map or address, not both"

  # As in Antd.GrpcManifestsTest: wait out a GRPC.Client.Supervisor that is
  # going down with another module, then start one that outlives this test.
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
end
