# frozen_string_literal: true

# Live check of the sha256 fields against a running antd 0.17.0 or later.
#
# Skipped unless ANTD_TEST_URL and ANTD_TEST_SHA_LINK are set:
#
# - ANTD_TEST_URL: the daemon's REST base URL
# - ANTD_TEST_SHA_LINK: a manifest link with entries public.txt, private.txt
#   (both with a sha256) and nohash.txt (none)
# - ANTD_TEST_SHA_PUBLIC_ADDRESS, ANTD_TEST_SHA_PUBLIC_SHA256: a public
#   upload and its plaintext SHA-256
# - ANTD_TEST_SHA_DATA_MAP_SHA256: the SHA-256 recorded for private.txt
# - ANTD_TEST_GRPC: optional, the gRPC target, to repeat the checks over gRPC
#
# Everything is free except one small public data upload per transport:
#
#   source ~/sha-fanout-daemon/fixtures.env
#   bundle exec ruby -w -Ilib -Itest test/test_live_sha256.rb -v

require "digest"
require "minitest/autorun"
require_relative "../lib/antd"

class TestLiveSha256 < Minitest::Test
  def setup
    @url = ENV.fetch("ANTD_TEST_URL", "")
    @link = ENV.fetch("ANTD_TEST_SHA_LINK", "").strip
    skip "set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run the live sha256 test" if @url.empty? || @link.empty?

    @address = ENV.fetch("ANTD_TEST_SHA_PUBLIC_ADDRESS", "").strip
    @public_sha = ENV.fetch("ANTD_TEST_SHA_PUBLIC_SHA256", "").strip
    @data_map_sha = ENV.fetch("ANTD_TEST_SHA_DATA_MAP_SHA256", "").strip
    [@address, @public_sha, @data_map_sha].each { |v| refute_empty v, "the ANTD_TEST_SHA_* fixtures are required" }
  end

  def test_live_sha256_rest
    check(Antd::Client.new(base_url: @url))
  end

  def test_live_sha256_grpc
    target = ENV.fetch("ANTD_TEST_GRPC", "")
    skip "set ANTD_TEST_GRPC to run the live sha256 test over gRPC" if target.empty?
    skip "needs the grpc gem" unless defined?(Antd::GrpcClient) && Antd::GrpcClient.method_defined?(:build_manifest)

    check(Antd::GrpcClient.new(target: target))
  end

  private

  def check(client)
    # 1. Decode the fixture link: the recorded hashes, and none where unset.
    by_path = client.decode_manifest_link(@link, resolve: false).entries.to_h { |e| [e.path, e] }
    assert_equal @public_sha, by_path.fetch("public.txt").sha256
    assert_equal @data_map_sha, by_path.fetch("private.txt").sha256
    assert_nil by_path.fetch("nohash.txt").sha256

    # 2. Build with a sha256: the returned entry carries it.
    built = client.build_manifest([{ path: "a.txt", address: @address, sha256: @public_sha }])
    assert_equal [@public_sha], built.entries.map(&:sha256)
    assert_equal [@public_sha], client.decode_manifest(built.manifest).entries.map(&:sha256)

    # 3. A malformed sha256 is the daemon's 400.
    err = assert_raises(Antd::BadRequestError) do
      client.build_manifest([{ path: "a.txt", address: @address, sha256: "zz" }])
    end
    assert_includes err.message, "entries[0]"

    # 4. One paid call: the upload's sha256 is the SHA-256 of the plaintext.
    payload = "sha-fanout ruby #{Time.now.to_i} #{client.class.name}".b
    res = client.data_put_public(payload)
    assert_equal Digest::SHA256.hexdigest(payload), res.sha256
    puts "#{client.class.name}: sha256 #{res.sha256} (address #{res.address})"
  end
end
