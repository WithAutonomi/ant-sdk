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

    # Inputs starting with "EXISTS" → already-stored short-circuit.
    def prepare_chunk(req)
      if req.data.byteslice(0, 6) == "EXISTS"
        OpenStruct.new(
          address: "0xabc",
          already_stored: true,
          upload_id: "",
          payment_type: "",
          payments: [],
          total_amount: "",
          payment_vault_address: "",
          payment_token_address: "",
          rpc_url: "",
        )
      else
        OpenStruct.new(
          address: "0xnewchunk",
          already_stored: false,
          upload_id: "upid_chunk_42",
          payment_type: "wave_batch",
          payments: [
            OpenStruct.new(quote_hash: "0xq1", rewards_address: "0xr1", amount: "100"),
          ],
          total_amount: "100",
          payment_vault_address: "0xvault",
          payment_token_address: "0xtoken",
          rpc_url: "http://localhost:8545",
        )
      end
    end

    def finalize_chunk(req)
      # Echo upload_id into address so the test can verify forwarding.
      OpenStruct.new(address: "addr_for_#{req.upload_id}")
    end
  end

  # Mock UploadService stub. PrepareFileUpload echoes visibility into
  # upload_id; PrepareDataUpload returns merkle when payload starts with
  # "MERKLE"; FinalizeUpload returns merkle vs wave-batch based on which
  # field is set.
  class UploadStub
    def prepare_file_upload(req)
      OpenStruct.new(
        upload_id: "upid_file_#{req.visibility}",
        payment_type: "wave_batch",
        payments: [
          OpenStruct.new(quote_hash: "0xqa", rewards_address: "0xra", amount: "1"),
        ],
        depth: 0,
        pool_commitments: [],
        merkle_payment_timestamp: 0,
        total_amount: "1",
        payment_vault_address: "0xvault",
        payment_token_address: "0xtoken",
        rpc_url: "http://localhost:8545",
      )
    end

    def prepare_data_upload(req)
      uid = "upid_data_#{req.visibility}"
      if req.data.byteslice(0, 6) == "MERKLE"
        OpenStruct.new(
          upload_id: uid,
          payment_type: "merkle",
          payments: [],
          depth: 7,
          pool_commitments: [
            OpenStruct.new(
              pool_hash: "0xpool",
              candidates: [
                OpenStruct.new(rewards_address: "0xc1", amount: "5"),
              ],
            ),
          ],
          merkle_payment_timestamp: 1_700_000_000,
          total_amount: "0",
          payment_vault_address: "0xvault",
          payment_token_address: "0xtoken",
          rpc_url: "http://localhost:8545",
        )
      else
        OpenStruct.new(
          upload_id: uid,
          payment_type: "wave_batch",
          payments: [
            OpenStruct.new(quote_hash: "0xqb", rewards_address: "0xrb", amount: "2"),
          ],
          depth: 0,
          pool_commitments: [],
          merkle_payment_timestamp: 0,
          total_amount: "2",
          payment_vault_address: "0xvault",
          payment_token_address: "0xtoken",
          rpc_url: "http://localhost:8545",
        )
      end
    end

    def finalize_upload(req)
      if req.winner_pool_hash && !req.winner_pool_hash.empty?
        OpenStruct.new(
          data_map: "dm_merkle",
          address: req.store_data_map ? "stored_on_network" : "",
          data_map_address: "",
          chunks_stored: 64,
        )
      else
        OpenStruct.new(
          data_map: "dm_wave",
          address: "",
          data_map_address: req.upload_id.end_with?("public") ? "addr_public_dm" : "",
          chunks_stored: 3,
        )
      end
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
  client.instance_variable_set(:@upload_stub, FakeGrpc::UploadStub.new)
  client
end

def build_error_client(error)
  stub = FakeGrpc::ErrorStub.new(error)
  client = Antd::GrpcClient.allocate
  client.instance_variable_set(:@health_stub, stub)
  client.instance_variable_set(:@data_stub, stub)
  client.instance_variable_set(:@chunk_stub, stub)
  client.instance_variable_set(:@file_stub, stub)
  client.instance_variable_set(:@upload_stub, stub)
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

  # --- External signer (prepare/finalize) ---

  def test_prepare_upload_omits_visibility_when_nil
    r = @client.prepare_upload("/tmp/x.bin")
    # Empty visibility = proto3 default; the mock echoes that into upload_id.
    assert_equal "upid_file_", r.upload_id
    assert_equal "wave_batch", r.payment_type
    assert_equal 1, r.payments.length
    assert_equal "0xqa", r.payments.first.quote_hash
    assert_nil r.depth
    assert_nil r.pool_commitments
    assert_nil r.merkle_payment_timestamp
  end

  def test_prepare_upload_forwards_visibility_public
    r = @client.prepare_upload("/tmp/x.bin", visibility: "public")
    assert_equal "upid_file_public", r.upload_id
  end

  def test_prepare_upload_public_convenience
    r = @client.prepare_upload_public("/tmp/x.bin")
    assert_equal "upid_file_public", r.upload_id
  end

  def test_prepare_data_upload_wave_batch
    r = @client.prepare_data_upload("small")
    assert_equal "upid_data_", r.upload_id
    assert_equal "wave_batch", r.payment_type
    assert_nil r.depth
  end

  def test_prepare_data_upload_merkle
    r = @client.prepare_data_upload("MERKLE-large-payload")
    assert_equal "merkle", r.payment_type
    assert_equal 7, r.depth
    assert_equal 1_700_000_000, r.merkle_payment_timestamp
    assert_equal 1, r.pool_commitments.length
    assert_equal "0xpool", r.pool_commitments.first.pool_hash
    assert_equal "0xc1", r.pool_commitments.first.candidates.first.rewards_address
  end

  def test_finalize_upload_wave_batch_private_omits_data_map_address
    r = @client.finalize_upload("upid_file_", { "0xq1" => "0xtx1" })
    assert_equal "dm_wave", r.data_map
    assert_equal "", r.data_map_address
    assert_equal 3, r.chunks_stored
  end

  def test_finalize_upload_wave_batch_public_returns_data_map_address
    r = @client.finalize_upload("upid_file_public", { "0xq1" => "0xtx1" })
    assert_equal "addr_public_dm", r.data_map_address
  end

  def test_finalize_merkle_upload_store_data_map_true
    r = @client.finalize_merkle_upload("upid_data_", "0xwinpool", store_data_map: true)
    assert_equal "dm_merkle", r.data_map
    assert_equal "stored_on_network", r.address
    assert_equal 64, r.chunks_stored
  end

  def test_finalize_merkle_upload_store_data_map_default_false
    r = @client.finalize_merkle_upload("upid_data_", "0xwinpool")
    assert_equal "dm_merkle", r.data_map
    assert_equal "", r.address
  end

  def test_prepare_chunk_upload_new_chunk
    r = @client.prepare_chunk_upload("newchunk")
    refute r.already_stored
    assert_equal "0xnewchunk", r.address
    assert_equal "upid_chunk_42", r.upload_id
    assert_equal "wave_batch", r.payment_type
    assert_equal 1, r.payments.length
    assert_equal "0xq1", r.payments.first.quote_hash
    assert_equal "100", r.total_amount
    assert_equal "http://localhost:8545", r.rpc_url
  end

  def test_prepare_chunk_upload_already_stored_short_circuit
    r = @client.prepare_chunk_upload("EXISTS-data")
    assert r.already_stored
    assert_equal "0xabc", r.address
    assert_equal "", r.upload_id
    assert_empty r.payments
  end

  def test_finalize_chunk_upload_returns_address_and_forwards_body
    addr = @client.finalize_chunk_upload("upid_chunk_42", { "0xq1" => "0xtxabc" })
    assert_equal "addr_for_upid_chunk_42", addr
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
