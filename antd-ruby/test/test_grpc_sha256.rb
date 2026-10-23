# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/antd/version"
require_relative "../lib/antd/models"
require_relative "../lib/antd/errors"

# These need the real GrpcClient and the generated stubs, so they skip
# without the grpc gem.
begin
  require_relative "../lib/antd/grpc_client"
  require_relative "../lib/antd/grpc_manifests"
rescue LoadError
  # grpc gem not installed
end

# The sha256 fields (antd 0.17.0) over gRPC against fake stubs that answer
# with real proto messages: an upload result reads the field as hex, or nil
# when it is "" (the proto3 zero value); a manifest entry sets it on the
# request only when given, so presence is meaningful.
class TestGrpcSha256 < Minitest::Test
  SHA = "ab" * 32
  ADDR = "42" * 32
  V1 = Antd::V1 if defined?(Antd::V1)

  # Records every call as [rpc, request]; answers with the registered
  # response, raising it if it is an exception.
  class FakeStub
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    %i[put put_public finalize_upload build decode].each do |rpc|
      define_method(rpc) do |req|
        @calls << [rpc, req]
        resp = @responses.fetch(rpc)
        raise resp if resp.is_a?(Exception)

        resp
      end
    end
  end

  def setup
    skip "needs the grpc gem and the generated stubs" unless defined?(Antd::GrpcClient) && defined?(Antd::V1::ManifestService)

    @client = Antd::GrpcClient.allocate
  end

  # --- upload results ---

  def test_data_put_reads_sha256_or_nil
    @client.instance_variable_set(:@data_stub, FakeStub.new(put: V1::PutDataResponse.new(data_map: "dm", sha256: SHA)))
    assert_equal SHA, @client.data_put("x").sha256
    @client.instance_variable_set(:@data_stub, FakeStub.new(put: V1::PutDataResponse.new(data_map: "dm")))
    assert_nil @client.data_put("x").sha256
  end

  def test_data_put_public_reads_sha256_or_nil
    @client.instance_variable_set(:@data_stub, FakeStub.new(put_public: V1::PutPublicDataResponse.new(address: "a", sha256: SHA)))
    assert_equal SHA, @client.data_put_public("x").sha256
    @client.instance_variable_set(:@data_stub, FakeStub.new(put_public: V1::PutPublicDataResponse.new(address: "a", sha256: "")))
    assert_nil @client.data_put_public("x").sha256
  end

  def test_file_put_reads_sha256_or_nil
    @client.instance_variable_set(:@file_stub, FakeStub.new(put: V1::PutFileResponse.new(data_map: "dm", sha256: SHA)))
    assert_equal SHA, @client.file_put("/tmp/f").sha256
    @client.instance_variable_set(:@file_stub, FakeStub.new(put: V1::PutFileResponse.new(data_map: "dm")))
    assert_nil @client.file_put("/tmp/f").sha256
  end

  def test_file_put_public_reads_sha256_or_nil
    @client.instance_variable_set(:@file_stub, FakeStub.new(put_public: V1::PutFilePublicResponse.new(address: "a", sha256: SHA)))
    assert_equal SHA, @client.file_put_public("/tmp/f").sha256
    @client.instance_variable_set(:@file_stub, FakeStub.new(put_public: V1::PutFilePublicResponse.new(address: "a")))
    assert_nil @client.file_put_public("/tmp/f").sha256
  end

  def test_finalize_uploads_read_sha256_or_nil
    @client.instance_variable_set(:@upload_stub,
                                  FakeStub.new(finalize_upload: V1::FinalizeUploadResponse.new(address: "a", sha256: SHA)))
    assert_equal SHA, @client.finalize_upload("up", { "q" => "tx" }).sha256
    assert_equal SHA, @client.finalize_merkle_upload("up", "pool").sha256
    @client.instance_variable_set(:@upload_stub,
                                  FakeStub.new(finalize_upload: V1::FinalizeUploadResponse.new(address: "a", sha256: "")))
    assert_nil @client.finalize_upload("up", { "q" => "tx" }).sha256
    assert_nil @client.finalize_merkle_upload("up", "pool").sha256
  end

  # --- manifests ---

  def test_build_manifest_sets_sha256_presence_only_when_given
    resp = V1::BuildManifestResponse.new(
      manifest: "\xC1ANT\x01".b,
      entries: [
        V1::ManifestEntryInfo.new(effective_name: "a.txt", path: "a.txt", kind: "public", content_address: ADDR, sha256: SHA),
        V1::ManifestEntryInfo.new(effective_name: "b.txt", path: "b.txt", kind: "public", content_address: ADDR, sha256: "")
      ]
    )
    stub = FakeStub.new(build: resp)
    @client.instance_variable_set(:@manifest_stub, stub)

    res = @client.build_manifest([
      Antd::ManifestEntryInput.new(path: "a.txt", address: ADDR, sha256: SHA),
      { path: "b.txt", address: ADDR },
      { path: "c.txt", address: ADDR, sha256: "" }
    ])

    _, req = stub.calls.first
    first, second, third = req.entries.to_a
    assert_equal [true, SHA], [first.has_sha256?, first.sha256]
    refute second.has_sha256?
    refute third.has_sha256?
    # Entry info: "" reads as nil.
    assert_equal [SHA, nil], res.entries.map(&:sha256)
  end

  def test_decode_manifest_reads_entry_sha256
    resp = V1::DecodeManifestResponse.new(
      source: "manifest",
      entries: [
        V1::ManifestEntryInfo.new(effective_name: "p", path: "p", kind: "public", content_address: ADDR, sha256: SHA),
        V1::ManifestEntryInfo.new(effective_name: "n", path: "n", kind: "public", content_address: ADDR)
      ]
    )
    @client.instance_variable_set(:@manifest_stub, FakeStub.new(decode: resp))
    assert_equal [SHA, nil], @client.decode_manifest_link("ant://manifest/x").entries.map(&:sha256)
  end

  def test_bad_sha256_is_the_bad_request_error
    error = GRPC::InvalidArgument.new("entries[0]: sha256 must be 32 bytes, got 1")
    @client.instance_variable_set(:@manifest_stub, FakeStub.new(build: error))
    err = assert_raises(Antd::BadRequestError) do
      @client.build_manifest([{ path: "a.txt", address: ADDR, sha256: "zz" }])
    end
    assert_includes err.message, "entries[0]: sha256 must be 32 bytes, got 1"
  end
end
