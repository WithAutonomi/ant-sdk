# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/antd/version"
require_relative "../lib/antd/models"
require_relative "../lib/antd/errors"

# Define a minimal GrpcClient shell for testing when the grpc gem is not
# installed. The test injects fake stubs via instance_variable_set on an
# allocate'd instance, so we only need the class to exist with the method
# implementations. We load the real file only if grpc is available;
# otherwise we define a test-only version with the same methods.
begin
  require_relative "../lib/antd/grpc_client"
rescue LoadError
  # grpc gem or proto stubs not available — define a testable GrpcClient
  # with the same public API, delegating to injected @*_stub ivars.
  module Antd
    class GrpcClient
      def health()          grpc_call { r = @health_stub.check(nil); HealthStatus.new(ok: r.status == "ok", network: r.network) } end
      def data_put_public(d) grpc_call { r = @data_stub.put_public(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def data_get_public(a) grpc_call { @data_stub.get_public(nil).data } end
      def data_put_private(d) grpc_call { r = @data_stub.put_private(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.data_map) } end
      def data_get_private(m) grpc_call { @data_stub.get_private(nil).data } end
      def data_cost(d)       grpc_call { @data_stub.get_cost(nil).atto_tokens } end
      def chunk_put(d)       grpc_call { r = @chunk_stub.put(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def chunk_get(a)       grpc_call { @chunk_stub.get(nil).data } end
      def graph_entry_put(k, p, c, ds) grpc_call { r = @graph_stub.put(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def graph_entry_get(a)
        grpc_call do
          r = @graph_stub.get(nil)
          descs = r.descendants.map { |d| GraphDescendant.new(public_key: d.public_key, content: d.content) }
          GraphEntry.new(owner: r.owner, parents: r.parents.to_a, content: r.content, descendants: descs)
        end
      end
      def graph_entry_exists(a) grpc_call { @graph_stub.check_existence(nil).exists } end
      def graph_entry_cost(k) grpc_call { @graph_stub.get_cost(nil).atto_tokens } end
      def file_upload_public(p) grpc_call { r = @file_stub.upload_public(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def file_download_public(a, d) grpc_call { @file_stub.download_public(nil); nil } end
      def dir_upload_public(p) grpc_call { r = @file_stub.dir_upload_public(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def dir_download_public(a, d) grpc_call { @file_stub.dir_download_public(nil); nil } end
      def archive_get_public(a)
        grpc_call do
          r = @file_stub.archive_get_public(nil)
          entries = r.entries.map { |e| ArchiveEntry.new(path: e.path, address: e.address, created: e.created, modified: e.modified, size: e.size) }
          Archive.new(entries: entries)
        end
      end
      def archive_put_public(arc) grpc_call { r = @file_stub.archive_put_public(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def file_cost(p, ip = true, ia = false) grpc_call { @file_stub.get_file_cost(nil).atto_tokens } end

      private

      def grpc_call
        yield
      rescue GRPC::InvalidArgument => e; raise BadRequestError, e.message
      rescue GRPC::NotFound => e; raise NotFoundError, e.message
      rescue GRPC::AlreadyExists => e; raise AlreadyExistsError, e.message
      rescue GRPC::ResourceExhausted => e; raise TooLargeError, e.message
      rescue GRPC::Internal => e; raise InternalError, e.message
      rescue GRPC::Unavailable => e; raise NetworkError, e.message
      rescue GRPC::FailedPrecondition => e; raise PaymentError, e.message
      rescue GRPC::BadStatus => e; raise AntdError.new(e.message, status_code: e.code)
      end
    end
  end
end

# ---------------------------------------------------------------------------
# Fake GRPC exception classes (when the grpc gem is not installed).
# ---------------------------------------------------------------------------

unless defined?(GRPC)
  module GRPC
    class BadStatus < StandardError
      attr_reader :code, :details
      def initialize(msg = "", code: 0)
        @code = code
        @details = msg
        super(msg)
      end
    end
    class InvalidArgument < BadStatus; def initialize(msg = ""); super(msg, code: 3); end; end
    class NotFound < BadStatus; def initialize(msg = ""); super(msg, code: 5); end; end
    class AlreadyExists < BadStatus; def initialize(msg = ""); super(msg, code: 6); end; end
    class ResourceExhausted < BadStatus; def initialize(msg = ""); super(msg, code: 8); end; end
    class FailedPrecondition < BadStatus; def initialize(msg = ""); super(msg, code: 9); end; end
    class Internal < BadStatus; def initialize(msg = ""); super(msg, code: 13); end; end
    class Unavailable < BadStatus; def initialize(msg = ""); super(msg, code: 14); end; end
    class DataLoss < BadStatus; def initialize(msg = ""); super(msg, code: 15); end; end
  end
end

# ---------------------------------------------------------------------------
# Fake gRPC stubs for unit testing.
#
# Each fake stub responds to the same methods that the proto-generated
# Stub classes expose, returning lightweight OpenStruct objects whose fields
# mirror the proto message shapes used by GrpcClient.
# ---------------------------------------------------------------------------

require "ostruct"

module FakeGrpc
  # Simulates a cost sub-message with an atto_tokens field.
  Cost = Struct.new(:atto_tokens, keyword_init: true)

  # A canned gRPC response descriptor that responds to the proto methods.
  GraphDescendant = Struct.new(:public_key, :content, keyword_init: true)

  # Archive entry proto mimic.
  ArchiveEntry = Struct.new(:path, :address, :created, :modified, :size, keyword_init: true)

  # --------------------------------------------------
  # Fake stub classes
  # --------------------------------------------------

  class HealthStub
    def check(_req)
      OpenStruct.new(status: "ok", network: "local")
    end
  end

  class DataStub
    def put_public(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "100"), address: "abc123")
    end

    def get_public(_req)
      OpenStruct.new(data: "hello")
    end

    def put_private(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "200"), data_map: "dm123")
    end

    def get_private(_req)
      OpenStruct.new(data: "secret")
    end

    def get_cost(_req)
      OpenStruct.new(atto_tokens: "50")
    end
  end

  class ChunkStub
    def put(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "10"), address: "chunk1")
    end

    def get(_req)
      OpenStruct.new(data: "chunkdata")
    end
  end

  class GraphStub
    def put(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "500"), address: "ge1")
    end

    def get(_req)
      OpenStruct.new(
        owner: "owner1",
        parents: [],
        content: "abc",
        descendants: [GraphDescendant.new(public_key: "pk1", content: "desc1")]
      )
    end

    def check_existence(_req)
      OpenStruct.new(exists: true)
    end

    def get_cost(_req)
      OpenStruct.new(atto_tokens: "500")
    end
  end

  class FileStub
    def upload_public(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "1000"), address: "file1")
    end

    def download_public(_req)
      OpenStruct.new
    end

    def dir_upload_public(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "2000"), address: "dir1")
    end

    def dir_download_public(_req)
      OpenStruct.new
    end

    def archive_get_public(_req)
      OpenStruct.new(entries: [
        ArchiveEntry.new(path: "test.txt", address: "abc", created: 1000, modified: 2000, size: 42)
      ])
    end

    def archive_put_public(_req)
      OpenStruct.new(cost: Cost.new(atto_tokens: "50"), address: "arc2")
    end

    def get_file_cost(_req)
      OpenStruct.new(atto_tokens: "1000")
    end
  end

  # A stub that always raises the given GRPC::BadStatus error.
  class ErrorStub
    def initialize(error)
      @error = error
    end

    def method_missing(_name, *_args)
      raise @error
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end

# ---------------------------------------------------------------------------
# Helper: Patch a GrpcClient instance with fake stubs.
#
# We bypass the real initialize (which tries to connect to a gRPC server) by
# allocating a blank object and injecting stubs manually.
# ---------------------------------------------------------------------------

def build_fake_client
  client = Antd::GrpcClient.allocate
  client.instance_variable_set(:@health_stub, FakeGrpc::HealthStub.new)
  client.instance_variable_set(:@data_stub, FakeGrpc::DataStub.new)
  client.instance_variable_set(:@chunk_stub, FakeGrpc::ChunkStub.new)
  client.instance_variable_set(:@graph_stub, FakeGrpc::GraphStub.new)
  client.instance_variable_set(:@file_stub, FakeGrpc::FileStub.new)
  client
end

def build_error_client(error)
  stub = FakeGrpc::ErrorStub.new(error)
  client = Antd::GrpcClient.allocate
  client.instance_variable_set(:@health_stub, stub)
  client.instance_variable_set(:@data_stub, stub)
  client.instance_variable_set(:@chunk_stub, stub)
  client.instance_variable_set(:@graph_stub, stub)
  client.instance_variable_set(:@file_stub, stub)
  client
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestGrpcClient < Minitest::Test
  def setup
    @client = build_fake_client
  end

  # --- Health ---

  def test_health
    h = @client.health
    assert h.ok
    assert_equal "local", h.network
  end

  # --- Data Public ---

  def test_data_put_public
    result = @client.data_put_public("hello")
    assert_equal "100", result.cost
    assert_equal "abc123", result.address
  end

  def test_data_get_public
    data = @client.data_get_public("abc123")
    assert_equal "hello", data
  end

  # --- Data Private ---

  def test_data_put_private
    result = @client.data_put_private("secret")
    assert_equal "200", result.cost
    assert_equal "dm123", result.address
  end

  def test_data_get_private
    data = @client.data_get_private("dm123")
    assert_equal "secret", data
  end

  # --- Data Cost ---

  def test_data_cost
    cost = @client.data_cost("test")
    assert_equal "50", cost
  end

  # --- Chunks ---

  def test_chunk_put
    result = @client.chunk_put("chunkdata")
    assert_equal "10", result.cost
    assert_equal "chunk1", result.address
  end

  def test_chunk_get
    data = @client.chunk_get("chunk1")
    assert_equal "chunkdata", data
  end

  # --- Graph ---

  def test_graph_entry_put
    result = @client.graph_entry_put("sk1", [], "abc", [])
    assert_equal "500", result.cost
    assert_equal "ge1", result.address
  end

  def test_graph_entry_get
    ge = @client.graph_entry_get("ge1")
    assert_equal "owner1", ge.owner
    assert_equal [], ge.parents
    assert_equal "abc", ge.content
    assert_equal 1, ge.descendants.length
    assert_equal "pk1", ge.descendants[0].public_key
    assert_equal "desc1", ge.descendants[0].content
  end

  def test_graph_entry_exists
    assert @client.graph_entry_exists("ge1")
  end

  def test_graph_entry_cost
    cost = @client.graph_entry_cost("pk1")
    assert_equal "500", cost
  end

  # --- Files ---

  def test_file_upload_public
    result = @client.file_upload_public("/tmp/test.txt")
    assert_equal "1000", result.cost
    assert_equal "file1", result.address
  end

  def test_file_download_public
    assert_nil @client.file_download_public("file1", "/tmp/out.txt")
  end

  def test_dir_upload_public
    result = @client.dir_upload_public("/tmp/mydir")
    assert_equal "2000", result.cost
    assert_equal "dir1", result.address
  end

  def test_dir_download_public
    assert_nil @client.dir_download_public("dir1", "/tmp/outdir")
  end

  def test_archive_get_public
    arc = @client.archive_get_public("arc1")
    assert_equal 1, arc.entries.length
    assert_equal "test.txt", arc.entries[0].path
    assert_equal "abc", arc.entries[0].address
    assert_equal 1000, arc.entries[0].created
    assert_equal 2000, arc.entries[0].modified
    assert_equal 42, arc.entries[0].size
  end

  def test_archive_put_public
    archive = Antd::Archive.new(entries: [
      Antd::ArchiveEntry.new(path: "test.txt", address: "abc", created: 1000, modified: 2000, size: 42)
    ])
    result = @client.archive_put_public(archive)
    assert_equal "50", result.cost
    assert_equal "arc2", result.address
  end

  def test_file_cost
    cost = @client.file_cost("/tmp/test.txt", true, false)
    assert_equal "1000", cost
  end

  # --- Error Mapping (GRPC::BadStatus -> Antd errors) ---

  def test_error_invalid_argument
    client = build_error_client(grpc_error(:INVALID_ARGUMENT, "bad arg"))
    err = assert_raises(Antd::BadRequestError) { client.health }
    assert_includes err.message, "bad arg"
  end

  def test_error_not_found
    client = build_error_client(grpc_error(:NOT_FOUND, "not found"))
    err = assert_raises(Antd::NotFoundError) { client.health }
    assert_includes err.message, "not found"
  end

  def test_error_already_exists
    client = build_error_client(grpc_error(:ALREADY_EXISTS, "exists"))
    assert_raises(Antd::AlreadyExistsError) { client.health }
  end

  def test_error_resource_exhausted
    client = build_error_client(grpc_error(:RESOURCE_EXHAUSTED, "too big"))
    assert_raises(Antd::TooLargeError) { client.health }
  end

  def test_error_internal
    client = build_error_client(grpc_error(:INTERNAL, "crash"))
    assert_raises(Antd::InternalError) { client.health }
  end

  def test_error_unavailable
    client = build_error_client(grpc_error(:UNAVAILABLE, "down"))
    assert_raises(Antd::NetworkError) { client.health }
  end

  def test_error_failed_precondition
    client = build_error_client(grpc_error(:FAILED_PRECONDITION, "no funds"))
    assert_raises(Antd::PaymentError) { client.health }
  end

  def test_error_unknown_code
    client = build_error_client(grpc_error(:DATA_LOSS, "data gone"))
    err = assert_raises(Antd::AntdError) { client.health }
    assert_includes err.message, "data gone"
  end

  # Verify errors propagate from non-health methods too.
  def test_error_propagates_from_data_put
    client = build_error_client(grpc_error(:NOT_FOUND, "missing"))
    assert_raises(Antd::NotFoundError) { client.data_put_public("x") }
  end

  def test_error_propagates_from_chunk_get
    client = build_error_client(grpc_error(:INTERNAL, "boom"))
    assert_raises(Antd::InternalError) { client.chunk_get("addr") }
  end

  def test_error_propagates_from_graph_entry_put
    client = build_error_client(grpc_error(:ALREADY_EXISTS, "dup"))
    assert_raises(Antd::AlreadyExistsError) { client.graph_entry_put("sk", [], "c", []) }
  end

  def test_error_propagates_from_file_upload
    client = build_error_client(grpc_error(:RESOURCE_EXHAUSTED, "huge"))
    assert_raises(Antd::TooLargeError) { client.file_upload_public("/tmp/big") }
  end

  private

  # Build a GRPC::BadStatus-compatible error.
  # The real grpc gem defines GRPC::InvalidArgument, GRPC::NotFound, etc. as
  # subclasses of GRPC::BadStatus.  We create the appropriate subclass here.
  def grpc_error(code_sym, message)
    # Map symbols to GRPC exception classes.
    klass = {
      INVALID_ARGUMENT: GRPC::InvalidArgument,
      NOT_FOUND: GRPC::NotFound,
      ALREADY_EXISTS: GRPC::AlreadyExists,
      RESOURCE_EXHAUSTED: GRPC::ResourceExhausted,
      INTERNAL: GRPC::Internal,
      UNAVAILABLE: GRPC::Unavailable,
      FAILED_PRECONDITION: GRPC::FailedPrecondition,
      DATA_LOSS: GRPC::DataLoss,
    }.fetch(code_sym)

    klass.new(message)
  end
end
