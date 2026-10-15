# frozen_string_literal: true

# Live manifest round trip against a running antd with a network behind it.
#
# Skipped unless ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES are set:
#
# - ANTD_TEST_URL: the daemon's REST base URL, e.g. http://127.0.0.1:8082
# - ANTD_TEST_MANIFEST_ADDRESSES: two comma-separated addresses of public
#   data already uploaded
# - ANTD_TEST_MANIFEST_SIZES: their exact plaintext sizes, comma-separated
# - ANTD_TEST_MANIFEST_DATA_MAP: the hex DataMap of a private upload
# - ANTD_TEST_MANIFEST_DATA_MAP_SIZE: its exact plaintext size
# - ANTD_TEST_MANIFEST_LINK: optional, an ant://manifest/ link to decode
# - ANTD_TEST_GRPC: optional, the gRPC target, e.g. 127.0.0.1:50051, to run
#   the same checks over gRPC
#
# It only builds and decodes manifests of data already on the network, so
# nothing is paid for:
#
#   ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
#   ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> ANTD_TEST_MANIFEST_SIZES=<n>,<n> \
#   ANTD_TEST_MANIFEST_DATA_MAP=<hex> ANTD_TEST_MANIFEST_DATA_MAP_SIZE=<n> \
#   bundle exec ruby -Ilib -Itest test/test_live_manifests.rb

require "minitest/autorun"
require_relative "../lib/antd"

class TestLiveManifests < Minitest::Test
  def setup
    @url = ENV.fetch("ANTD_TEST_URL", "")
    @addresses = ENV.fetch("ANTD_TEST_MANIFEST_ADDRESSES", "").split(",").map(&:strip)
    if @url.empty? || @addresses.length != 2 || @addresses.any?(&:empty?)
      skip "set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run the live manifest test"
    end

    @sizes = ENV.fetch("ANTD_TEST_MANIFEST_SIZES", "").split(",").map { |s| Integer(s.strip, 10) }
    @data_map = ENV.fetch("ANTD_TEST_MANIFEST_DATA_MAP", "").strip
    data_map_size = ENV.fetch("ANTD_TEST_MANIFEST_DATA_MAP_SIZE", "").strip
    @link = ENV.fetch("ANTD_TEST_MANIFEST_LINK", "").strip
    assert_equal 2, @sizes.length, "ANTD_TEST_MANIFEST_SIZES needs two sizes"
    refute_empty @data_map, "ANTD_TEST_MANIFEST_DATA_MAP is required"
    refute_empty data_map_size, "ANTD_TEST_MANIFEST_DATA_MAP_SIZE is required"
    @data_map_size = Integer(data_map_size, 10)
  end

  def test_live_manifests_rest
    round_trip(Antd::Client.new(base_url: @url))
  end

  def test_live_manifests_grpc
    target = ENV.fetch("ANTD_TEST_GRPC", "")
    skip "set ANTD_TEST_GRPC to run the live manifest test over gRPC" if target.empty?
    skip "needs the grpc gem" unless defined?(Antd::GrpcClient) && Antd::GrpcClient.method_defined?(:build_manifest)

    round_trip(Antd::GrpcClient.new(target: target))
  end

  private

  def round_trip(client)
    one, two = @addresses
    # One size given, so the manifest records it; the others stay unset.
    built = client.build_manifest(
      [
        { path: "live/one.txt", size: @sizes[0], address: one },
        { path: "live/two.txt", address: two },
        { path: "live/private.txt", data_map: @data_map }
      ],
      name: "antd-ruby-live"
    )

    refute_empty built.manifest
    assert_equal Encoding::BINARY, built.manifest.encoding
    refute_nil built.link
    assert built.link.start_with?("ant://manifest/"), built.link
    # Encoded order: sorted by effective name.
    assert_equal %w[live/one.txt live/private.txt live/two.txt], built.entries.map(&:effective_name)
    e1, ep, e2 = built.entries
    assert_equal [Antd::ManifestEntryKind::PUBLIC, one, @sizes[0]], [e1.kind, e1.content_address, e1.size]
    assert_equal [Antd::ManifestEntryKind::PUBLIC, two, nil], [e2.kind, e2.content_address, e2.size]
    assert_equal Antd::ManifestEntryKind::EMBEDDED, ep.kind
    assert_nil ep.size
    assert_match(/\A\h{64}\z/, ep.content_address)

    # The bytes and the link decode to the same manifest; resolve fills in
    # every exact size.
    [client.decode_manifest(built.manifest, resolve: true),
     client.decode_manifest_link(built.link, resolve: true)].each do |d|
      assert_equal [Antd::ManifestSource::MANIFEST, "antd-ruby-live"], [d.source, d.name]
      assert_nil d.torrent_info_hash_v1
      by_name = d.entries.to_h { |e| [e.effective_name, e] }
      assert_equal built.entries.map(&:effective_name), d.entries.map(&:effective_name)
      [["live/one.txt", @sizes[0]], ["live/two.txt", @sizes[1]], ["live/private.txt", @data_map_size]].each do |name, size|
        assert_nil by_name[name].error, "#{name}: #{by_name[name].error}"
        assert_equal size, by_name[name].exact_size, name
      end
      assert_equal [@sizes[0], nil], [by_name["live/one.txt"].size, by_name["live/two.txt"].size]
      priv = by_name["live/private.txt"]
      assert_equal Antd::ManifestEntryKind::EMBEDDED, priv.kind
      refute_nil priv.data_map
      refute_empty priv.data_map
      assert_nil by_name["live/one.txt"].data_map
    end

    # Without resolve, a public entry's exact size is unknown: nil, not 0.
    plain = client.decode_manifest(built.manifest)
    assert_nil plain.entries.find { |e| e.effective_name == "live/two.txt" }.exact_size

    # A bare address is a file link: one public entry with no path.
    file = client.decode_manifest_link(one, resolve: true)
    assert_equal Antd::ManifestSource::FILE_LINK, file.source
    assert_equal [[one, nil, @sizes[0]]], file.entries.map { |e| [e.content_address, e.path, e.exact_size] }

    unless @link.empty?
      fixture = client.decode_manifest_link(@link, resolve: true)
      assert_equal Antd::ManifestSource::MANIFEST, fixture.source
      assert_equal 3, fixture.entries.length
      assert_equal @addresses.sort, fixture.entries.select { |e| e.kind == Antd::ManifestEntryKind::PUBLIC }
                                                  .map(&:content_address).sort
      assert(fixture.entries.all? { |e| e.error.nil? && !e.exact_size.nil? })
    end

    # Bad input: an invalid path is the daemon's 400 naming the entry; both
    # data_map and address is refused before sending.
    err = assert_raises(Antd::BadRequestError) do
      client.build_manifest([{ path: "ok.txt", address: one }, { path: "../x", address: two }])
    end
    assert_includes err.message, "entries[1]"
    assert_raises(ArgumentError) { client.build_manifest([{ data_map: @data_map, address: one }]) }
    assert_raises(Antd::BadRequestError) { client.decode_manifest("not a manifest") }
  end
end
