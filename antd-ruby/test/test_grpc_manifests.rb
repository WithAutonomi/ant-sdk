# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require_relative "../lib/antd/version"
require_relative "../lib/antd/models"
require_relative "../lib/antd/errors"

# The manifest methods need the real GrpcClient and the generated
# ManifestService stubs, so these tests skip without the grpc gem.
begin
  require_relative "../lib/antd/grpc_manifests"
rescue LoadError
  # grpc gem not installed
end

# Manifest API over gRPC against a fake ManifestService stub that records
# each request and answers with real proto messages, so unset proto3
# optionals read exactly as they do off the wire. The last two tests check
# the raised message limit: the channel arguments the manifest stub is built
# with, and a real in-process server sending a manifest over 4 MiB.
class TestGrpcManifests < Minitest::Test
  HEADER = "\xC1ANT\x01".b
  LINK = "ant://manifest/wUFOVAE"
  ADDR = "42" * 32
  V1 = Antd::V1 if defined?(Antd::V1)

  # Records every call as [rpc, request]; answers with the response
  # registered for the rpc, raising it if it is an exception.
  class ManifestStub
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    %i[build decode].each do |rpc|
      define_method(rpc) do |req|
        @calls << [rpc, req]
        resp = @responses.fetch(rpc)
        raise resp if resp.is_a?(Exception)

        resp
      end
    end
  end

  def setup
    skip "needs the grpc gem and the generated ManifestService stubs" unless defined?(Antd::V1::ManifestService)
  end

  def test_build_manifest_sends_presence_and_raw_bytes_back
    resp = V1::BuildManifestResponse.new(
      manifest: HEADER, link: LINK,
      entries: [
        V1::ManifestEntryInfo.new(effective_name: "a.txt", path: "a.txt", size: 10, kind: "embedded",
                                  content_address: "cc", exact_size: 10),
        V1::ManifestEntryInfo.new(effective_name: "11", kind: "public", content_address: "11")
      ]
    )
    client, stub = client_with(build: resp)

    res = client.build_manifest(
      [Antd::ManifestEntryInput.new(path: "a.txt", size: 10, data_map: "abcd"), { address: "11" }],
      name: "album", torrent_info_hashes: ["aa" * 20]
    )

    rpc, req = stub.calls.first
    assert_equal :build, rpc
    assert req.has_name?
    assert_equal "album", req.name
    assert_equal ["aa" * 20], req.torrent_info_hashes.to_a
    # Default: embed roots, sent explicitly.
    assert req.has_embed_roots?
    assert_equal true, req.embed_roots
    first, second = req.entries.to_a
    assert_equal [true, "a.txt", true, 10, :data_map, "abcd"],
                 [first.has_path?, first.path, first.has_size?, first.size, first.source, first.data_map]
    # An unset path or size has no presence on the wire (not "" or 0).
    assert_equal [false, false, :address, "11"], [second.has_path?, second.has_size?, second.source, second.address]

    assert_equal HEADER, res.manifest
    assert_equal Encoding::BINARY, res.manifest.encoding
    assert_equal LINK, res.link
    a, p = res.entries
    assert_equal ["a.txt", 10, 10, Antd::ManifestEntryKind::EMBEDDED], [a.path, a.size, a.exact_size, a.kind]
    # Unset proto3 optionals read as nil, never 0; empty strings as nil.
    assert_equal ["11", nil, nil, nil, nil, nil], [p.effective_name, p.path, p.size, p.exact_size, p.data_map, p.error]
  end

  def test_build_manifest_keep_shrunk_and_no_name
    client, stub = client_with(build: V1::BuildManifestResponse.new(manifest: HEADER))
    res = client.build_manifest([{ address: ADDR }], name: "", embed_roots: false)
    _, req = stub.calls.first
    refute req.has_name?
    assert req.has_embed_roots?
    assert_equal false, req.embed_roots
    assert_empty req.torrent_info_hashes.to_a
    assert_nil res.link
  end

  def test_zero_sizes_are_kept
    resp = V1::BuildManifestResponse.new(
      manifest: HEADER,
      entries: [V1::ManifestEntryInfo.new(effective_name: "e", path: "e", size: 0, exact_size: 0, kind: "public")]
    )
    client, stub = client_with(build: resp)
    res = client.build_manifest([{ path: "e", size: 0, address: ADDR }])
    entry = stub.calls.first[1].entries.first
    assert_equal [true, 0], [entry.has_size?, entry.size]
    assert_equal [0, 0], [res.entries[0].size, res.entries[0].exact_size]
  end

  def test_build_manifest_rejects_both_or_neither_before_sending
    client, stub = client_with(build: V1::BuildManifestResponse.new)
    err = assert_raises(Antd::BadRequestError) { client.build_manifest([{}]) }
    assert_equal [400, "antd error 400: 1 invalid entries: entries[0]: needs a data_map or an address"],
                 [err.status_code, err.message]
    err = assert_raises(Antd::BadRequestError) do
      client.build_manifest([{ data_map: "aa", address: "bb" }, { address: ADDR }, {}])
    end
    assert_equal "antd error 400: 2 invalid entries: entries[0]: give data_map or address, not both; " \
                 "entries[2]: needs a data_map or an address", err.message
    assert_empty stub.calls
  end

  def test_decode_manifest_sends_raw_bytes
    resp = V1::DecodeManifestResponse.new(
      source: "manifest", name: "album", torrent_info_hash_v1: "aa" * 20,
      entries: [
        V1::ManifestEntryInfo.new(effective_name: "a.txt", path: "a.txt", kind: "embedded",
                                  content_address: "cc", data_map: "abcd", exact_size: 3),
        V1::ManifestEntryInfo.new(effective_name: "b", path: "b", kind: "public", content_address: "dd",
                                  error: "Record not found: gone")
      ]
    )
    client, stub = client_with(decode: resp)

    res = client.decode_manifest(HEADER, resolve: true)

    _, req = stub.calls.first
    assert_equal :manifest, req.input
    assert_equal HEADER, req.manifest
    assert_equal true, req.resolve
    assert_equal [Antd::ManifestSource::MANIFEST, "album", "aa" * 20, nil],
                 [res.source, res.name, res.torrent_info_hash_v1, res.torrent_info_hash_v2]
    a, b = res.entries
    assert_equal ["abcd", 3, nil], [a.data_map, a.exact_size, a.error]
    assert_equal ["Record not found: gone", nil, nil], [b.error, b.exact_size, b.data_map]
  end

  def test_decode_manifest_link
    resp = V1::DecodeManifestResponse.new(
      source: "file_link",
      entries: [V1::ManifestEntryInfo.new(effective_name: ADDR, kind: "public", content_address: ADDR)]
    )
    client, stub = client_with(decode: resp)

    res = client.decode_manifest_link(ADDR)

    _, req = stub.calls.first
    assert_equal [:link, ADDR, false], [req.input, req.link, req.resolve]
    assert_equal [Antd::ManifestSource::FILE_LINK, nil], [res.source, res.name]
    assert_equal [ADDR, nil], [res.entries[0].content_address, res.entries[0].path]
  end

  def test_decode_rejects_empty_input_before_sending
    client, stub = client_with(decode: V1::DecodeManifestResponse.new)
    [-> { client.decode_manifest("") }, -> { client.decode_manifest_link("") }].each do |call|
      err = assert_raises(Antd::BadRequestError, &call)
      assert_equal [400, "antd error 400: needs a manifest (base64 .ant bytes) or a link"],
                   [err.status_code, err.message]
    end
    assert_empty stub.calls
  end

  def test_invalid_argument_is_bad_request
    error = GRPC::InvalidArgument.new("entries[0]: invalid path: ../x")
    client, = client_with(build: error, decode: error)
    err = assert_raises(Antd::BadRequestError) { client.build_manifest([{ path: "../x", address: ADDR }]) }
    assert_includes err.message, "entries[0]: invalid path: ../x"
    assert_raises(Antd::BadRequestError) { client.decode_manifest("nope") }
  end

  # grpc-ruby has no per-call message limit: the manifest stub gets a channel
  # of its own, built with both limits raised.
  def test_manifest_stub_raises_message_limits
    assert_equal 256 * 1024 * 1024, Antd::MANIFEST_GRPC_MAX_MESSAGE
    built = nil
    fake = ManifestStub.new(decode: V1::DecodeManifestResponse.new(source: "manifest"))
    capture = lambda do |*args, **kwargs|
      built = [args, kwargs]
      fake
    end
    client = Antd::GrpcClient.allocate
    client.instance_variable_set(:@target, "example.invalid:50051")
    Antd::V1::ManifestService::Stub.stub(:new, capture) { client.decode_manifest_link(ADDR) }

    args, kwargs = built
    assert_equal ["example.invalid:50051", :this_channel_is_insecure], args
    assert_equal Antd::MANIFEST_GRPC_MAX_MESSAGE, kwargs[:channel_args]["grpc.max_receive_message_length"]
    assert_equal Antd::MANIFEST_GRPC_MAX_MESSAGE, kwargs[:channel_args]["grpc.max_send_message_length"]
  end

  # A real server sends a 5 MiB manifest: over gRPC's 4 MiB default, which
  # a plain stub refuses and the client's manifest stub takes.
  def test_manifest_over_4_mib_is_received
    big = Random.new(7).bytes(5 * 1024 * 1024)
    service = Class.new(Antd::V1::ManifestService::Service) do
      define_method(:build) { |_req, _call| Antd::V1::BuildManifestResponse.new(manifest: big) }
      define_method(:decode) do |req, _call|
        Antd::V1::DecodeManifestResponse.new(source: "manifest", name: req.manifest.bytesize.to_s)
      end
    end
    # The server's own receive limit is 4 MiB too; raise it for the decode.
    server = GRPC::RpcServer.new(pool_size: 2, server_args: Antd::MANIFEST_GRPC_CHANNEL_ARGS)
    port = server.add_http2_port("127.0.0.1:0", :this_port_is_insecure)
    server.handle(service)
    thread = Thread.new { server.run }
    server.wait_till_running(10)
    target = "127.0.0.1:#{port}"

    plain = Antd::V1::ManifestService::Stub.new(target, :this_channel_is_insecure)
    assert_raises(GRPC::ResourceExhausted) { plain.build(Antd::V1::BuildManifestRequest.new) }

    client = Antd::GrpcClient.new(target: target)
    built = client.build_manifest([{ address: ADDR }])
    assert_equal big.bytesize, built.manifest.bytesize
    assert_equal big, built.manifest
    # And back: the 5 MiB manifest goes out as a decode request.
    assert_equal big.bytesize.to_s, client.decode_manifest(built.manifest).name
  ensure
    server&.stop
    thread&.join(10)
  end

  private

  def client_with(responses)
    stub = ManifestStub.new(responses)
    client = Antd::GrpcClient.allocate
    client.instance_variable_set(:@manifest_stub, stub)
    [client, stub]
  end
end
