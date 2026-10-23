# frozen_string_literal: true

require_relative "test_helper"
require "json"

# The sha256 fields (antd 0.17.0) over REST against a mocked daemon: the
# upload results read the plaintext's SHA-256 as hex, or nil when the daemon
# sends none; manifest entries send it only when given and read it back.
class TestSha256 < Minitest::Test
  BASE = "http://localhost:8082"
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze
  SHA = "ab" * 32
  ADDR = "42" * 32

  def setup
    @client = Antd::Client.new(base_url: BASE)
  end

  # --- upload results ---

  def test_data_put_reads_sha256_or_nil
    stub_post("/v1/data", { data_map: "dm", chunks_stored: 3, payment_mode_used: "single", sha256: SHA })
    assert_equal SHA, @client.data_put("x").sha256

    stub_post("/v1/data", { data_map: "dm", chunks_stored: 3, payment_mode_used: "single" })
    assert_nil @client.data_put("x").sha256

    stub_post("/v1/data", { data_map: "dm", sha256: "" })
    assert_nil @client.data_put("x").sha256
  end

  def test_data_put_public_reads_sha256_or_nil
    stub_post("/v1/data/public", { address: "a1", chunks_stored: 4, payment_mode_used: "auto", sha256: SHA })
    assert_equal SHA, @client.data_put_public("x").sha256

    stub_post("/v1/data/public", { address: "a1" })
    assert_nil @client.data_put_public("x").sha256
  end

  def test_file_put_reads_sha256_or_nil
    stub_post("/v1/files", { data_map: "dm", storage_cost_atto: "5", gas_cost_wei: "1", chunks_stored: 2,
                             payment_mode_used: "single", sha256: SHA })
    res = @client.file_put("/tmp/f")
    assert_equal [SHA, "dm", 2], [res.sha256, res.data_map, res.chunks_stored]

    stub_post("/v1/files", { data_map: "dm" })
    assert_nil @client.file_put("/tmp/f").sha256
  end

  def test_file_put_public_reads_sha256_or_nil
    stub_post("/v1/files/public", { address: "a1", storage_cost_atto: "5", gas_cost_wei: "1", chunks_stored: 2,
                                    payment_mode_used: "auto", sha256: SHA })
    res = @client.file_put_public("/tmp/f")
    assert_equal [SHA, "a1"], [res.sha256, res.address]

    stub_post("/v1/files/public", { address: "a1" })
    assert_nil @client.file_put_public("/tmp/f").sha256
  end

  def test_finalize_uploads_read_sha256_or_nil
    stub_post("/v1/upload/finalize", { address: "a", chunks_stored: 1, data_map: "ab", sha256: SHA })
    assert_equal SHA, @client.finalize_upload("up", { "q" => "tx" }).sha256
    assert_equal SHA, @client.finalize_merkle_upload("up", "pool").sha256

    stub_post("/v1/upload/finalize", { address: "a", chunks_stored: 1, data_map: "ab" })
    assert_nil @client.finalize_upload("up", { "q" => "tx" }).sha256
    assert_nil @client.finalize_merkle_upload("up", "pool").sha256
  end

  def test_result_structs_default_sha256_to_nil
    assert_nil Antd::DataPutResult.new.sha256
    assert_nil Antd::DataPutPublicResult.new.sha256
    assert_nil Antd::FilePutResult.new.sha256
    assert_nil Antd::FilePutPublicResult.new.sha256
    assert_nil Antd::FinalizeUploadResult.new.sha256
    # Existing construction keeps working.
    assert_equal "dm", Antd::DataPutResult.new(data_map: "dm", chunks_stored: 1, payment_mode_used: "auto").data_map
  end

  # --- manifests ---

  def test_build_manifest_sends_sha256_only_when_set
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        manifest: "wUFOVAE=",
        entries: [
          { effective_name: "a.txt", path: "a.txt", kind: "public", content_address: ADDR, sha256: SHA },
          { effective_name: "b.txt", path: "b.txt", kind: "public", content_address: ADDR }
        ]
      }.to_json)

    res = @client.build_manifest([
      Antd::ManifestEntryInput.new(path: "a.txt", address: ADDR, sha256: SHA),
      { path: "b.txt", address: ADDR },
      { path: "c.txt", address: ADDR, sha256: "" },
      { path: "d.txt", address: ADDR, sha256: nil }
    ])

    assert_equal({ "path" => "a.txt", "address" => ADDR, "sha256" => SHA }, sent["entries"][0])
    assert_equal({ "path" => "b.txt", "address" => ADDR }, sent["entries"][1])
    # Unset or "" is omitted, never sent as null or "".
    assert_equal({ "path" => "c.txt", "address" => ADDR }, sent["entries"][2])
    assert_equal({ "path" => "d.txt", "address" => ADDR }, sent["entries"][3])
    assert_equal [SHA, nil], res.entries.map(&:sha256)
  end

  def test_manifest_entry_input_sha256_is_passed_through_unchecked
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: { manifest: "wUFOVAE=", entries: [] }.to_json)

    @client.build_manifest([{ path: "a.txt", address: ADDR, sha256: "NOT-hex-AT-ALL" }])
    assert_equal "NOT-hex-AT-ALL", sent["entries"][0]["sha256"]
    assert_nil Antd::ManifestEntryInput.new.sha256
  end

  def test_decode_manifest_reads_entry_sha256
    stub_request(:post, "#{BASE}/v1/manifests/decode")
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        source: "manifest",
        entries: [
          { effective_name: "public.txt", path: "public.txt", kind: "public", content_address: ADDR, sha256: SHA },
          { effective_name: "empty.txt", path: "empty.txt", kind: "public", content_address: ADDR, sha256: "" },
          { effective_name: "nohash.txt", path: "nohash.txt", kind: "public", content_address: ADDR }
        ]
      }.to_json)

    res = @client.decode_manifest_link("ant://manifest/x")
    assert_equal [SHA, nil, nil], res.entries.map(&:sha256)
    assert_nil Antd::ManifestEntryInfo.new.sha256
  end

  def test_bad_sha256_is_the_bad_request_error
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .to_return(status: 400, headers: JSON_HEADERS,
                 body: { error: "Bad request: entries[0]: invalid hex sha256: Odd number of digits",
                         code: "BAD_REQUEST" }.to_json)

    err = assert_raises(Antd::BadRequestError) do
      @client.build_manifest([{ path: "a.txt", address: ADDR, sha256: "zz" }])
    end
    assert_equal 400, err.status_code
    assert_includes err.message, "entries[0]: invalid hex sha256"
  end

  private

  def stub_post(path, body)
    stub_request(:post, "#{BASE}#{path}").to_return(status: 200, headers: JSON_HEADERS, body: body.to_json)
  end
end
