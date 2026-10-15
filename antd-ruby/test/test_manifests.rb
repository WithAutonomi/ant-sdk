# frozen_string_literal: true

require_relative "test_helper"
require "json"

# Manifest API over REST against a mocked daemon: the request shapes, the
# base64 `.ant` bytes on the wire (raw bytes in the API), unset sizes as
# nil, the entry check before sending, and a 400 as BadRequestError.
class TestManifests < Minitest::Test
  BASE = "http://localhost:8082"
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze
  # The five-byte `.ant` header; "wUFOVAE=" is its base64.
  HEADER = "\xC1ANT\x01".b
  HEADER_B64 = "wUFOVAE="
  LINK = "ant://manifest/wUFOVAE"
  ADDR = "42" * 32

  def setup
    @client = Antd::Client.new(base_url: BASE)
  end

  # --- build ---

  def test_build_manifest_sends_entries_and_options
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        manifest: HEADER_B64,
        link: LINK,
        entries: [
          { effective_name: "a.txt", path: "a.txt", size: 10, kind: "embedded", content_address: "cc", exact_size: 10 },
          { effective_name: "11", kind: "public", content_address: "11" }
        ]
      }.to_json)

    res = @client.build_manifest(
      [Antd::ManifestEntryInput.new(path: "a.txt", size: 10, data_map: "abcd"), { address: "11" }],
      name: "album", torrent_info_hashes: ["aa" * 20], embed_roots: false
    )

    assert_equal "album", sent["name"]
    assert_equal false, sent["embed_roots"]
    assert_equal ["aa" * 20], sent["torrent_info_hashes"]
    assert_equal({ "path" => "a.txt", "size" => 10, "data_map" => "abcd" }, sent["entries"][0])
    # An unset path or size is omitted, not sent as null or 0.
    assert_equal({ "address" => "11" }, sent["entries"][1])

    assert_instance_of Antd::BuiltManifest, res
    assert_equal HEADER, res.manifest
    assert_equal Encoding::BINARY, res.manifest.encoding
    assert_equal LINK, res.link
    a, p = res.entries
    assert_instance_of Antd::ManifestEntryInfo, a
    assert_equal ["a.txt", "a.txt", 10, Antd::ManifestEntryKind::EMBEDDED, "cc", 10],
                 [a.effective_name, a.path, a.size, a.kind, a.content_address, a.exact_size]
    assert_equal ["11", Antd::ManifestEntryKind::PUBLIC, "11"], [p.effective_name, p.kind, p.content_address]
    # Unset reads as nil, never 0 or "".
    assert_nil p.path
    assert_nil p.size
    assert_nil p.exact_size
    assert_nil p.data_map
    assert_nil p.error
  end

  def test_build_manifest_embeds_roots_by_default_and_omits_empty_options
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: { manifest: HEADER_B64, entries: [] }.to_json)

    res = @client.build_manifest([{ address: ADDR }], name: "", torrent_info_hashes: [])

    assert_equal({ "entries" => [{ "address" => ADDR }], "embed_roots" => true }, sent)
    # The link is omitted when it would not fit 1,500 bytes.
    assert_nil res.link
    assert_equal [], res.entries
  end

  def test_build_manifest_records_a_zero_size
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        manifest: HEADER_B64,
        entries: [{ effective_name: "e", path: "e", size: 0, kind: "public", content_address: ADDR }]
      }.to_json)

    res = @client.build_manifest([{ path: "e", size: 0, address: ADDR }])
    assert_equal 0, sent["entries"][0]["size"]
    assert_equal 0, res.entries[0].size
  end

  def test_build_manifest_rejects_both_or_neither_before_sending
    both = "entries[1]: give data_map or address, not both"
    neither = "entries[1]: needs a data_map or an address"
    {
      {} => neither,
      { path: "x" } => neither,
      { data_map: "", address: "" } => neither,
      { data_map: "aa", address: "bb" } => both,
      Antd::ManifestEntryInput.new(data_map: "aa", address: "bb") => both
    }.each do |entry, expected|
      err = assert_raises(Antd::BadRequestError) { @client.build_manifest([{ address: ADDR }, entry]) }
      assert_equal 400, err.status_code
      assert_equal "antd error 400: 1 invalid entries: #{expected}", err.message
    end
    assert_not_requested :post, "#{BASE}/v1/manifests/build"
  end

  def test_build_manifest_reports_every_bad_entry
    err = assert_raises(Antd::BadRequestError) do
      @client.build_manifest([{ data_map: "a", address: "b" }, { address: ADDR }, {}])
    end
    assert_equal "antd error 400: 2 invalid entries: entries[0]: give data_map or address, not both; " \
                 "entries[2]: needs a data_map or an address", err.message

    err = assert_raises(Antd::BadRequestError) { @client.build_manifest(Array.new(23) { {} }) }
    expected = (0...20).map { |i| "entries[#{i}]: needs a data_map or an address" }.join("; ")
    assert_equal "antd error 400: 23 invalid entries: #{expected}; and 3 more", err.message
    assert_not_requested :post, "#{BASE}/v1/manifests/build"
  end

  def test_build_manifest_rejects_bad_sizes_and_shapes_before_sending
    [
      [{ address: ADDR, size: -1 }, "entries[0]: size must be a non-negative Integer or nil"],
      [{ address: ADDR, size: "10" }, "entries[0]: size must be a non-negative Integer or nil"],
      [{ address: ADDR, sise: 10 }, "entries[0]: unknown field (expected path, size, data_map, address)"],
      [ADDR, "entries[0]: must be a ManifestEntryInput or Hash"]
    ].each do |entry, expected|
      err = assert_raises(Antd::BadRequestError) { @client.build_manifest([entry]) }
      assert_equal [400, "antd error 400: 1 invalid entries: #{expected}"], [err.status_code, err.message]
    end
    assert_raises(Antd::BadRequestError) { @client.build_manifest({ address: ADDR }) }
    assert_not_requested :post, "#{BASE}/v1/manifests/build"
  end

  def test_build_manifest_bad_request_keeps_the_daemon_message
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .to_return(status: 400, headers: JSON_HEADERS,
                 body: { error: "Bad request: entries[0]: invalid path: ../x", code: "BAD_REQUEST" }.to_json)

    err = assert_raises(Antd::BadRequestError) { @client.build_manifest([{ path: "../x", address: ADDR }]) }
    assert_equal 400, err.status_code
    assert_includes err.message, "entries[0]: invalid path: ../x"
  end

  def test_build_manifest_invalid_base64_is_an_internal_error
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .to_return(status: 200, headers: JSON_HEADERS, body: { manifest: "not base64!", entries: [] }.to_json)

    assert_raises(Antd::InternalError) { @client.build_manifest([{ address: ADDR }]) }
  end

  # --- decode ---

  def test_decode_manifest_sends_base64_and_reads_entries
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/decode")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        source: "manifest", name: "album", torrent_info_hash_v2: "bb" * 32,
        entries: [
          { effective_name: "a.txt", path: "a.txt", kind: "embedded", content_address: "cc",
            data_map: "abcd", exact_size: 3 },
          { effective_name: "b", path: "b", size: 7, kind: "public", content_address: "dd",
            error: "Record not found: gone" }
        ]
      }.to_json)

    res = @client.decode_manifest(HEADER, resolve: true)

    assert_equal({ "manifest" => HEADER_B64, "resolve" => true }, sent)
    assert_instance_of Antd::DecodedManifest, res
    assert_equal [Antd::ManifestSource::MANIFEST, "album", nil, "bb" * 32],
                 [res.source, res.name, res.torrent_info_hash_v1, res.torrent_info_hash_v2]
    a, b = res.entries
    assert_equal ["abcd", 3, nil, nil], [a.data_map, a.exact_size, a.size, a.error]
    # A failed resolve is the entry's error, not a failed call; its sizes
    # stay as the manifest has them.
    assert_equal ["Record not found: gone", 7, nil, nil], [b.error, b.size, b.exact_size, b.data_map]
  end

  def test_decode_manifest_link
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/decode")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        source: "file_link",
        entries: [{ effective_name: ADDR, kind: "public", content_address: ADDR }]
      }.to_json)

    res = @client.decode_manifest_link(ADDR)

    assert_equal({ "link" => ADDR, "resolve" => false }, sent)
    assert_equal Antd::ManifestSource::FILE_LINK, res.source
    assert_nil res.name
    assert_nil res.torrent_info_hash_v1
    assert_nil res.torrent_info_hash_v2
    assert_equal [ADDR, nil], [res.entries[0].content_address, res.entries[0].path]
  end

  def test_decode_base64_round_trip_of_arbitrary_bytes
    bytes = (0..255).map(&:chr).join.b * 3
    sent = nil
    stub_request(:post, "#{BASE}/v1/manifests/decode")
      .with { |req| sent = JSON.parse(req.body) }
      .to_return(status: 200, headers: JSON_HEADERS, body: { source: "manifest", entries: [] }.to_json)
    stub_request(:post, "#{BASE}/v1/manifests/build")
      .to_return(status: 200, headers: JSON_HEADERS,
                 body: { manifest: Base64.strict_encode64(bytes), entries: [] }.to_json)

    built = @client.build_manifest([{ address: ADDR }])
    assert_equal bytes, built.manifest
    @client.decode_manifest(built.manifest)
    assert_equal bytes, Base64.strict_decode64(sent["manifest"])
  end

  def test_decode_rejects_empty_input_before_sending
    [-> { @client.decode_manifest("") }, -> { @client.decode_manifest(nil) },
     -> { @client.decode_manifest_link("") }, -> { @client.decode_manifest_link(nil) }].each do |call|
      err = assert_raises(Antd::BadRequestError, &call)
      assert_equal [400, "antd error 400: needs a manifest (base64 .ant bytes) or a link"],
                   [err.status_code, err.message]
    end
    assert_not_requested :post, "#{BASE}/v1/manifests/decode"
  end

  def test_decode_bad_request_is_typed
    stub_request(:post, "#{BASE}/v1/manifests/decode")
      .to_return(status: 400, headers: JSON_HEADERS,
                 body: { error: "Bad request: not a manifest: missing or invalid header", code: "BAD_REQUEST" }.to_json)

    err = assert_raises(Antd::BadRequestError) { @client.decode_manifest("nope") }
    assert_includes err.message, "not a manifest"
  end
end
