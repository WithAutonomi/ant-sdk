defmodule Antd.LiveSha256Test do
  @moduledoc """
  Live check of the `sha256` fields (antd 0.17.0) against a running antd with
  a devnet and a funded wallet behind it. The manifest steps pay for nothing;
  the last step makes one small public data upload per transport.

  Skipped unless `ANTD_TEST_URL` and `ANTD_TEST_SHA_LINK` are set:

    * `ANTD_TEST_URL` — the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
    * `ANTD_TEST_SHA_LINK` — a manifest link with entries `public.txt` and
      `private.txt` (each with a sha256) and `nohash.txt` (none)
    * `ANTD_TEST_SHA_PUBLIC_ADDRESS`, `ANTD_TEST_SHA_PUBLIC_SHA256` — a public
      data upload and its plaintext SHA-256
    * `ANTD_TEST_SHA_DATA_MAP_SHA256` — the SHA-256 of the private upload the
      link's `private.txt` holds
    * `ANTD_TEST_GRPC` (optional) — the daemon's gRPC target, e.g.
      `127.0.0.1:50051`; when set, everything is repeated over gRPC

      source ~/sha-fanout-daemon/fixtures.env
      mix test test/antd/live_sha256_test.exs
  """
  use ExUnit.Case, async: false

  alias Antd.{Client, GrpcClient, ManifestEntryInput}

  @url System.get_env("ANTD_TEST_URL")
  @grpc System.get_env("ANTD_TEST_GRPC")
  @link System.get_env("ANTD_TEST_SHA_LINK")
  @public_address System.get_env("ANTD_TEST_SHA_PUBLIC_ADDRESS")
  @public_sha256 System.get_env("ANTD_TEST_SHA_PUBLIC_SHA256")
  @data_map_sha256 System.get_env("ANTD_TEST_SHA_DATA_MAP_SHA256")

  if is_nil(@url) or is_nil(@link) do
    @moduletag skip: "set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run"
  end

  @moduletag timeout: 600_000

  defp env!(value, name), do: value || flunk("set #{name}")

  defp by_path(entries), do: Map.new(entries, &{&1.path, &1})

  # The same checks through either client: both take the same arguments.
  defp check(mod, client, payload) do
    public_address = env!(@public_address, "ANTD_TEST_SHA_PUBLIC_ADDRESS")
    public_sha256 = env!(@public_sha256, "ANTD_TEST_SHA_PUBLIC_SHA256")
    data_map_sha256 = env!(@data_map_sha256, "ANTD_TEST_SHA_DATA_MAP_SHA256")

    # 1. Decode the fixture link, without resolving.
    decoded = mod.decode_manifest_link!(client, String.trim(@link), resolve: false)
    d = by_path(decoded.entries)
    assert d["public.txt"].sha256 == public_sha256
    assert d["private.txt"].sha256 == data_map_sha256
    assert d["nohash.txt"].sha256 == nil

    # 2. Build a manifest with a hash: the entry carries it back.
    built =
      mod.build_manifest!(client, [
        %ManifestEntryInput{path: "a.txt", address: public_address, sha256: public_sha256}
      ])

    assert [%Antd.ManifestEntryInfo{path: "a.txt", sha256: ^public_sha256}] = built.entries

    # 3. A malformed hash is the daemon's 400.
    assert {:error, %Antd.BadRequestError{status_code: 400, message: message}} =
             mod.build_manifest(client, [
               %ManifestEntryInput{path: "a.txt", address: public_address, sha256: "zz"}
             ])

    assert message =~ "sha256"

    # 4. The one paid call: the result carries the plaintext's SHA-256.
    expected = Base.encode16(:crypto.hash(:sha256, payload), case: :lower)
    result = mod.data_put_public!(client, payload)
    IO.puts("#{inspect(mod)} data_put_public sha256 #{result.sha256} (local #{expected})")
    assert result.sha256 == expected
  end

  defp payload(suffix),
    do: "sha-fanout elixir #{System.os_time(:second)}#{suffix}"

  test "sha256 over REST" do
    check(Client, Client.new(@url, timeout: 300_000), payload(""))
  end

  if is_nil(@grpc), do: @tag(skip: "set ANTD_TEST_GRPC to run the gRPC checks")

  test "sha256 over gRPC" do
    ensure_client_supervisor()
    {:ok, client} = GrpcClient.new(@grpc)
    check(GrpcClient, client, payload(" grpc"))
  end

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
