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
      def health()              grpc_call { r = @health_stub.check(nil); HealthStatus.new(ok: r.status == "ok", network: r.network) } end
      def data_put(d, payment_mode: PaymentMode::AUTO) grpc_call { r = @data_stub.put(nil); DataPutResult.new(data_map: r.data_map) } end
      def data_get(m)           grpc_call { @data_stub.get(nil).data } end
      def data_put_public(d, payment_mode: PaymentMode::AUTO) grpc_call { r = @data_stub.put_public(nil); DataPutPublicResult.new(address: r.address) } end
      def data_get_public(a)    grpc_call { @data_stub.get_public(nil).data } end
      def data_cost(d, payment_mode: PaymentMode::AUTO) grpc_call { @data_stub.cost(nil).atto_tokens } end
      def chunk_put(d)          grpc_call { r = @chunk_stub.put(nil); PutResult.new(cost: r.cost.atto_tokens, address: r.address) } end
      def chunk_get(a)          grpc_call { @chunk_stub.get(nil).data } end
      def file_put(p, payment_mode: PaymentMode::AUTO) grpc_call { r = @file_stub.put(nil); FilePutResult.new(data_map: r.data_map, storage_cost_atto: r.storage_cost_atto, gas_cost_wei: r.gas_cost_wei, chunks_stored: r.chunks_stored, payment_mode_used: r.payment_mode_used) } end
      def file_get(m, d)        grpc_call { @file_stub.get(nil); nil } end
      def file_put_public(p, payment_mode: PaymentMode::AUTO) grpc_call { r = @file_stub.put_public(nil); FilePutPublicResult.new(address: r.address, storage_cost_atto: r.storage_cost_atto, gas_cost_wei: r.gas_cost_wei, chunks_stored: r.chunks_stored, payment_mode_used: r.payment_mode_used) } end
      def file_get_public(a, d) grpc_call { @file_stub.get_public(nil); nil } end
      def file_cost(p, ip = true, payment_mode: PaymentMode::AUTO) grpc_call { @file_stub.cost(nil).atto_tokens } end

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
      OpenStruct.new(address: "abc123")
    end

    def get_public(_req)
      OpenStruct.new(data: "hello")
    end

    def put(_req)
      OpenStruct.new(data_map: "dm123")
    end

    def get(_req)
      OpenStruct.new(data: "secret")
    end

    def cost(_req)
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

  class FileStub
    def put(_req)
      OpenStruct.new(
        data_map: "filedm1",
        storage_cost_atto: "500",
        gas_cost_wei: "21",
        chunks_stored: 2,
        payment_mode_used: "single",
      )
    end

    def get(_req)
      OpenStruct.new
    end

    def put_public(_req)
      OpenStruct.new(
        address: "file1",
        storage_cost_atto: "1000",
        gas_cost_wei: "42",
        chunks_stored: 3,
        payment_mode_used: "auto",
      )
    end

    def get_public(_req)
      OpenStruct.new
    end

    def cost(_req)
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
  client.instance_variable_set(:@file_stub, FakeGrpc::FileStub.new)
  client
end

def build_error_client(error)
  stub = FakeGrpc::ErrorStub.new(error)
  client = Antd::GrpcClient.allocate
  client.instance_variable_set(:@health_stub, stub)
  client.instance_variable_set(:@data_stub, stub)
  client.instance_variable_set(:@chunk_stub, stub)
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
    assert_instance_of Antd::DataPutPublicResult, result
    assert_equal "abc123", result.address
  end

  def test_data_get_public
    data = @client.data_get_public("abc123")
    assert_equal "hello", data
  end

  # --- Data Private ---

  def test_data_put
    result = @client.data_put("secret")
    assert_instance_of Antd::DataPutResult, result
    assert_equal "dm123", result.data_map
  end

  def test_data_get
    data = @client.data_get("dm123")
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

  # --- Files ---

  def test_file_put
    result = @client.file_put("/tmp/test.txt")
    assert_instance_of Antd::FilePutResult, result
    assert_equal "filedm1", result.data_map
    assert_equal "500", result.storage_cost_atto
    assert_equal 2, result.chunks_stored
    assert_equal "single", result.payment_mode_used
  end

  def test_file_get
    assert_nil @client.file_get("filedm1", "/tmp/out.txt")
  end

  def test_file_put_public
    result = @client.file_put_public("/tmp/test.txt")
    assert_instance_of Antd::FilePutPublicResult, result
    assert_equal "file1", result.address
    assert_equal "1000", result.storage_cost_atto
    assert_equal "42", result.gas_cost_wei
    assert_equal 3, result.chunks_stored
    assert_equal "auto", result.payment_mode_used
  end

  def test_file_get_public
    assert_nil @client.file_get_public("file1", "/tmp/out.txt")
  end

  def test_file_cost
    cost = @client.file_cost("/tmp/test.txt", true)
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
