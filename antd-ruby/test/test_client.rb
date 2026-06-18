# frozen_string_literal: true

require_relative "test_helper"
require "base64"

class TestClient < Minitest::Test
  BASE = "http://localhost:8082"

  def setup
    @client = Antd::Client.new(base_url: BASE)
  end

  # --- Health ---

  def test_health
    body = {
      status: "ok", network: "local",
      version: "0.4.0", evm_network: "local", uptime_seconds: 42,
      build_commit: "abcdef123456",
      payment_token_address: "0xtoken", payment_vault_address: "0xvault"
    }.to_json
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 200, body: body,
                 headers: { "Content-Type" => "application/json" })

    h = @client.health
    assert h.ok
    assert_equal "local", h.network
    assert_equal "0.4.0", h.version
    assert_equal "local", h.evm_network
    assert_equal 42, h.uptime_seconds
    assert_equal "abcdef123456", h.build_commit
    assert_equal "0xtoken", h.payment_token_address
    assert_equal "0xvault", h.payment_vault_address
  end

  # Pre-0.4.0 daemons reply with just status + network — verify the
  # diagnostic fields default to empty / 0 rather than NPE-ing.
  def test_health_pre_0_4_0_daemon
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 200, body: '{"status":"ok","network":"default"}',
                 headers: { "Content-Type" => "application/json" })

    h = @client.health
    assert h.ok
    assert_equal "default", h.network
    assert_equal "", h.version
    assert_equal "", h.evm_network
    assert_equal 0, h.uptime_seconds
  end

  # --- Data Public ---

  def test_data_put_public
    stub_request(:post, "#{BASE}/v1/data/public")
      .with(body: hash_including("payment_mode" => "auto"))
      .to_return(status: 200, body: '{"address":"abc123","chunks_stored":3,"payment_mode_used":"auto"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.data_put_public("hello")
    assert_instance_of Antd::DataPutPublicResult, result
    assert_equal "abc123", result.address
    assert_equal 3, result.chunks_stored
    assert_equal "auto", result.payment_mode_used
  end

  def test_data_get_public
    encoded = Base64.strict_encode64("hello")
    stub_request(:get, "#{BASE}/v1/data/public/abc123")
      .to_return(status: 200, body: %({"data":"#{encoded}"}),
                 headers: { "Content-Type" => "application/json" })

    data = @client.data_get_public("abc123")
    assert_equal "hello", data
  end

  # --- Data Public Streaming ---

  def test_data_stream_public_with_block
    stub_request(:get, "#{BASE}/v1/data/public/abc123/stream")
      .to_return(status: 200, body: "hello world",
                 headers: { "Content-Type" => "application/octet-stream" })

    chunks = []
    result = @client.data_stream_public("abc123") { |c| chunks << c }
    assert_nil result
    assert_equal "hello world", chunks.join
  end

  def test_data_stream_public_returns_enumerator
    stub_request(:get, "#{BASE}/v1/data/public/abc123/stream")
      .to_return(status: 200, body: "enum bytes",
                 headers: { "Content-Type" => "application/octet-stream" })

    enum = @client.data_stream_public("abc123")
    assert_instance_of Enumerator, enum
    assert_equal "enum bytes", enum.to_a.join
  end

  def test_data_stream_public_error
    stub_request(:get, "#{BASE}/v1/data/public/missing/stream")
      .to_return(status: 404, body: '{"error":"not found","code":"NOT_FOUND"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::NotFoundError) do
      @client.data_stream_public("missing") { |_c| }
    end
    assert_equal 404, err.status_code
    assert_includes err.message, "not found"
  end

  # --- Data Private ---

  def test_data_put
    stub_request(:post, "#{BASE}/v1/data")
      .with(body: hash_including("payment_mode" => "merkle"))
      .to_return(status: 200, body: '{"data_map":"dm123","chunks_stored":2,"payment_mode_used":"merkle"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.data_put("secret", payment_mode: Antd::PaymentMode::MERKLE)
    assert_instance_of Antd::DataPutResult, result
    assert_equal "dm123", result.data_map
    assert_equal 2, result.chunks_stored
    assert_equal "merkle", result.payment_mode_used
  end

  def test_data_get
    encoded = Base64.strict_encode64("secret")
    stub_request(:post, "#{BASE}/v1/data/get")
      .with(body: hash_including("data_map" => "dm123"))
      .to_return(status: 200, body: %({"data":"#{encoded}"}),
                 headers: { "Content-Type" => "application/json" })

    data = @client.data_get("dm123")
    assert_equal "secret", data
  end

  # --- Data Private Streaming ---

  def test_data_stream_with_block
    stub_request(:post, "#{BASE}/v1/data/stream")
      .with(body: hash_including("data_map" => "dm123"))
      .to_return(status: 200, body: "secret bytes",
                 headers: { "Content-Type" => "application/octet-stream" })

    chunks = []
    result = @client.data_stream("dm123") { |c| chunks << c }
    assert_nil result
    assert_equal "secret bytes", chunks.join
  end

  def test_data_stream_returns_enumerator
    stub_request(:post, "#{BASE}/v1/data/stream")
      .with(body: hash_including("data_map" => "dm123"))
      .to_return(status: 200, body: "lazy secret",
                 headers: { "Content-Type" => "application/octet-stream" })

    enum = @client.data_stream("dm123")
    assert_instance_of Enumerator, enum
    assert_equal "lazy secret", enum.to_a.join
  end

  def test_data_stream_error
    stub_request(:post, "#{BASE}/v1/data/stream")
      .to_return(status: 500, body: '{"error":"decrypt failed","code":"INTERNAL"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::InternalError) do
      @client.data_stream("dmX") { |_c| }
    end
    assert_equal 500, err.status_code
    assert_includes err.message, "decrypt failed"
  end

  # --- Data Streaming with Progress (NDJSON) ---

  # NDJSON body: leading meta (byte total) + interleaved progress/data frames.
  # base64 payloads are carried under the "chunk" key (matches the daemon).
  def test_data_stream_with_progress
    ndjson = [
      { type: "meta", total_size: 6 },
      { type: "progress", phase: "fetching", fetched: 1, total: 2 },
      { type: "data", chunk: Base64.strict_encode64("sec") },
      { type: "progress", phase: "fetching", fetched: 2, total: 2 },
      { type: "data", chunk: Base64.strict_encode64("ret") }
    ].map(&:to_json).join("\n") + "\n"

    stub_request(:post, "#{BASE}/v1/data/stream")
      .with(headers: { "Accept" => "application/x-ndjson" })
      .to_return(status: 200, body: ndjson,
                 headers: { "Content-Type" => "application/x-ndjson" })

    data = +""
    progress = []
    meta = nil
    first_frame = nil
    @client.data_stream_with_progress("dm123") do |frame|
      first_frame ||= frame
      if frame.meta?
        meta = frame.meta
      elsif frame.progress?
        progress << frame.progress
      else
        data << frame.data
      end
    end

    # The byte-total meta frame surfaces first, before any data/progress.
    assert(first_frame.meta?)
    assert_equal 6, meta
    assert_equal "secret", data
    assert_equal 2, progress.length
    assert_equal "fetching", progress[0].phase
    assert_equal 1, progress[0].fetched
    assert_equal 2, progress[1].fetched
    assert_equal 2, progress[1].total
  end

  def test_data_stream_public_with_progress
    ndjson = [
      { type: "meta", total_size: 5 },
      { type: "progress", phase: "fetching", fetched: 1, total: 1 },
      { type: "data", chunk: Base64.strict_encode64("hello") }
    ].map(&:to_json).join("\n") + "\n"

    stub_request(:get, "#{BASE}/v1/data/public/abc123/stream")
      .with(headers: { "Accept" => "application/x-ndjson" })
      .to_return(status: 200, body: ndjson,
                 headers: { "Content-Type" => "application/x-ndjson" })

    frames = @client.data_stream_public_with_progress("abc123").to_a
    assert_instance_of Enumerator, @client.data_stream_public_with_progress("abc123")
    data = frames.select { |f| !f.meta? && !f.progress? }.map(&:data).join
    assert_equal "hello", data
    assert(frames.any?(&:progress?))
    # The leading meta frame carries the byte total and comes first.
    assert(frames.first.meta?)
    assert_equal 5, frames.first.meta
  end

  # A terminal error frame must surface mid-stream as the mapped SDK error —
  # a raw octet-stream download cannot signal a failure after the body starts.
  def test_data_stream_with_progress_error_frame_raises
    ndjson = [
      { type: "meta", total_size: 0 },
      { type: "error", message: "decrypt failed" }
    ].map(&:to_json).join("\n") + "\n"

    stub_request(:post, "#{BASE}/v1/data/stream")
      .to_return(status: 200, body: ndjson,
                 headers: { "Content-Type" => "application/x-ndjson" })

    err = assert_raises(Antd::InternalError) do
      @client.data_stream_with_progress("dm123") { |_f| }
    end
    assert_includes err.message, "decrypt failed"
  end

  # --- Data Cost ---

  def test_data_cost
    stub_request(:post, "#{BASE}/v1/data/cost")
      .with(body: hash_including("payment_mode" => "single"))
      .to_return(status: 200,
                 body: '{"cost":"50","file_size":4,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"single"}',
                 headers: { "Content-Type" => "application/json" })

    est = @client.data_cost("test", payment_mode: Antd::PaymentMode::SINGLE)
    assert_equal "50", est.cost
    assert_equal 4, est.file_size
    assert_equal 3, est.chunk_count
    assert_equal "150000000000000", est.estimated_gas_cost_wei
    assert_equal "single", est.payment_mode
  end

  # --- Chunks ---

  def test_chunk_put
    stub_request(:post, "#{BASE}/v1/chunks")
      .to_return(status: 200, body: '{"cost":"10","address":"chunk1"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.chunk_put("chunkdata")
    assert_equal "10", result.cost
    assert_equal "chunk1", result.address
  end

  def test_chunk_get
    encoded = Base64.strict_encode64("chunkdata")
    stub_request(:get, "#{BASE}/v1/chunks/chunk1")
      .to_return(status: 200, body: %({"data":"#{encoded}"}),
                 headers: { "Content-Type" => "application/json" })

    data = @client.chunk_get("chunk1")
    assert_equal "chunkdata", data
  end

  # --- Files ---

  def test_file_put
    stub_request(:post, "#{BASE}/v1/files")
      .with(body: hash_including("payment_mode" => "single"))
      .to_return(status: 200,
                 body: '{"data_map":"filedm1","storage_cost_atto":"500","gas_cost_wei":"21","chunks_stored":2,"payment_mode_used":"single"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.file_put("/tmp/test.txt", payment_mode: Antd::PaymentMode::SINGLE)
    assert_instance_of Antd::FilePutResult, result
    assert_equal "filedm1", result.data_map
    assert_equal "500", result.storage_cost_atto
    assert_equal 2, result.chunks_stored
    assert_equal "single", result.payment_mode_used
  end

  def test_file_get
    stub_request(:post, "#{BASE}/v1/files/get")
      .with(body: hash_including("data_map" => "filedm1", "dest_path" => "/tmp/out.txt"))
      .to_return(status: 200, body: "",
                 headers: { "Content-Type" => "application/json" })

    assert_nil @client.file_get("filedm1", "/tmp/out.txt")
  end

  def test_file_put_public
    stub_request(:post, "#{BASE}/v1/files/public")
      .with(body: hash_including("payment_mode" => "auto"))
      .to_return(status: 200,
                 body: '{"address":"file1","storage_cost_atto":"1000","gas_cost_wei":"42","chunks_stored":3,"payment_mode_used":"auto"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.file_put_public("/tmp/test.txt")
    assert_instance_of Antd::FilePutPublicResult, result
    assert_equal "file1", result.address
    assert_equal "1000", result.storage_cost_atto
    assert_equal "42", result.gas_cost_wei
    assert_equal 3, result.chunks_stored
    assert_equal "auto", result.payment_mode_used
  end

  def test_file_get_public
    stub_request(:post, "#{BASE}/v1/files/public/get")
      .to_return(status: 200, body: "",
                 headers: { "Content-Type" => "application/json" })

    assert_nil @client.file_get_public("file1", "/tmp/out.txt")
  end

  def test_file_cost
    stub_request(:post, "#{BASE}/v1/files/cost")
      .with(body: hash_including("payment_mode" => "auto"))
      .to_return(status: 200,
                 body: '{"cost":"1000","file_size":4096,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"auto"}',
                 headers: { "Content-Type" => "application/json" })

    est = @client.file_cost("/tmp/test.txt", true)
    assert_equal "1000", est.cost
    assert_equal 4096, est.file_size
    assert_equal 3, est.chunk_count
    assert_equal "150000000000000", est.estimated_gas_cost_wei
    assert_equal "auto", est.payment_mode
  end

  # --- Merkle Batch Payment ---

  def test_prepare_upload_merkle
    response_body = {
      upload_id: "up_merkle_1",
      payment_type: "merkle_batch",
      depth: 3,
      total_amount: "5000",
      payments: [],
      payment_vault_address: "0xMERKLE",
      payment_token_address: "0xTOKEN",
      rpc_url: "http://localhost:8545",
      merkle_payment_timestamp: 1700000000,
      total_chunks: 128,
      already_stored_count: 4,
      pool_commitments: [
        {
          pool_hash: "pool_abc",
          candidates: [
            { rewards_address: "0xR1", amount: "2000" },
            { rewards_address: "0xR2", amount: "3000" }
          ]
        }
      ]
    }.to_json

    stub_request(:post, "#{BASE}/v1/upload/prepare")
      .to_return(status: 200, body: response_body,
                 headers: { "Content-Type" => "application/json" })

    result = @client.prepare_upload("/tmp/merkle/file.dat")
    assert_instance_of Antd::PrepareUploadResult, result
    assert_equal "up_merkle_1", result.upload_id
    assert_equal "merkle_batch", result.payment_type
    assert_equal 3, result.depth
    assert_equal "5000", result.total_amount
    assert_equal 1700000000, result.merkle_payment_timestamp
    assert_equal "0xMERKLE", result.payment_vault_address
    assert_equal [], result.payments

    assert_equal 1, result.pool_commitments.length
    pc = result.pool_commitments[0]
    assert_instance_of Antd::PoolCommitmentEntry, pc
    assert_equal "pool_abc", pc.pool_hash
    assert_equal 2, pc.candidates.length
    assert_instance_of Antd::CandidateNodeEntry, pc.candidates[0]
    assert_equal "0xR1", pc.candidates[0].rewards_address
    assert_equal "2000", pc.candidates[0].amount
    assert_equal "0xR2", pc.candidates[1].rewards_address
    assert_equal "3000", pc.candidates[1].amount
    # already-stored preflight (added in antd 0.10.0)
    assert_equal 128, result.total_chunks
    assert_equal 4, result.already_stored_count
  end

  def test_finalize_merkle_upload
    stub_request(:post, "#{BASE}/v1/upload/finalize")
      .to_return(status: 200, body: '{"address":"0xFINAL","chunks_stored":42}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.finalize_merkle_upload("up_merkle_1", "pool_abc", store_data_map: true)
    assert_instance_of Antd::FinalizeUploadResult, result
    assert_equal "0xFINAL", result.address
    assert_equal 42, result.chunks_stored
  end

  def test_prepare_upload_backward_compat
    response_body = {
      upload_id: "up_compat_1",
      payments: [
        { quote_hash: "qh1", rewards_address: "0xR1", amount: "100" }
      ],
      total_amount: "100",
      payment_vault_address: "0xDATA",
      payment_token_address: "0xTOKEN",
      rpc_url: "http://localhost:8545"
    }.to_json

    stub_request(:post, "#{BASE}/v1/upload/prepare")
      .to_return(status: 200, body: response_body,
                 headers: { "Content-Type" => "application/json" })

    result = @client.prepare_upload("/tmp/compat/file.dat")
    assert_instance_of Antd::PrepareUploadResult, result
    assert_equal "up_compat_1", result.upload_id
    assert_equal "wave_batch", result.payment_type
    assert_equal 0, result.depth
    assert_equal [], result.pool_commitments
    assert_equal 0, result.merkle_payment_timestamp
    assert_equal "0xDATA", result.payment_vault_address

    assert_equal 1, result.payments.length
    assert_equal "qh1", result.payments[0].quote_hash
    # preflight fields absent in older-daemon responses default to 0
    assert_equal 0, result.total_chunks
    assert_equal 0, result.already_stored_count
  end

  # --- Public Prepare: visibility forwarding + data_map_address surfacing ---

  # `prepare_upload_public` must POST visibility:"public" in the JSON body
  # (sentinel for the daemon to bundle the DataMap chunk into the same
  # external-signer batch). Verify via WebMock's request matcher.
  def test_prepare_upload_public_forwards_visibility
    response_body = {
      upload_id: "up_public_1",
      payment_type: "wave_batch",
      payments: [{ quote_hash: "qh1", rewards_address: "0xR1", amount: "100" }],
      total_amount: "100",
      payment_vault_address: "0xDP",
      payment_token_address: "0xTK",
      rpc_url: "http://rpc.local"
    }.to_json

    stub_request(:post, "#{BASE}/v1/upload/prepare")
      .with(body: hash_including("path" => "/tmp/wave/file.dat", "visibility" => "public"))
      .to_return(status: 200, body: response_body,
                 headers: { "Content-Type" => "application/json" })

    result = @client.prepare_upload_public("/tmp/wave/file.dat")
    assert_instance_of Antd::PrepareUploadResult, result
    assert_equal "up_public_1", result.upload_id
  end

  # `prepare_upload` without a visibility kwarg must NOT include the
  # visibility key — preserves the pre-public daemon wire shape.
  def test_prepare_upload_omits_visibility_by_default
    stub_request(:post, "#{BASE}/v1/upload/prepare")
      .to_return(status: 200, body: '{"upload_id":"x","total_amount":"0","payments":[]}',
                 headers: { "Content-Type" => "application/json" })

    @client.prepare_upload("/tmp/file.dat")

    assert_requested(:post, "#{BASE}/v1/upload/prepare") do |req|
      body = JSON.parse(req.body)
      !body.key?("visibility")
    end
  end

  # Finalize: when the daemon bundled the DataMap into the external-signer
  # batch (visibility="public" prepare), it returns a `data_map_address`
  # alongside the hex DataMap blob. Verify both surface on the result Struct.
  def test_finalize_upload_surfaces_data_map_address
    stub_request(:post, "#{BASE}/v1/upload/finalize")
      .to_return(status: 200,
                 body: '{"address":"0xFINAL","chunks_stored":42,"data_map":"deadbeef","data_map_address":"0xDMAP"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.finalize_upload("up_public_1", { "qh1" => "tx1" })
    assert_instance_of Antd::FinalizeUploadResult, result
    assert_equal "0xFINAL", result.address
    assert_equal 42, result.chunks_stored
    assert_equal "deadbeef", result.data_map
    assert_equal "0xDMAP", result.data_map_address
  end

  # Private upload finalize: data_map_address absent from daemon JSON →
  # defaults to "" rather than nil (Struct convenience).
  def test_finalize_upload_omits_data_map_address_for_private
    stub_request(:post, "#{BASE}/v1/upload/finalize")
      .to_return(status: 200, body: '{"address":"0xFINAL","chunks_stored":1,"data_map":"ab"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.finalize_upload("up_x", { "qh1" => "tx1" })
    assert_equal "", result.data_map_address
    assert_equal "ab", result.data_map
  end

  # --- Chunks: external-signer prepare/finalize ---

  # Already-stored branch: daemon returns address + already_stored:true and no
  # payment fields. The client must surface that flag and leave the payment
  # fields at their defaults.
  def test_prepare_chunk_upload_already_stored
    stub_request(:post, "#{BASE}/v1/chunks/prepare")
      .with(body: hash_including("data" => Base64.strict_encode64("already_chunk_data")))
      .to_return(status: 200,
                 body: '{"address":"addr_already_stored","already_stored":true}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.prepare_chunk_upload("already_chunk_data")
    assert_instance_of Antd::PrepareChunkResult, result
    assert_equal "addr_already_stored", result.address
    assert_equal true, result.already_stored
    assert_equal "", result.upload_id
    assert_equal [], result.payments
    assert_equal "", result.total_amount
  end

  # New-chunk branch: daemon returns the full wave-batch shape. Verify all
  # payment fields parse onto the Struct.
  def test_prepare_chunk_upload_new_chunk
    response_body = {
      address: "addr_chunk_new",
      already_stored: false,
      upload_id: "chunk_up_1",
      payment_type: "wave_batch",
      payments: [
        { quote_hash: "qhC", rewards_address: "0xRC", amount: "7" }
      ],
      total_amount: "7",
      payment_vault_address: "0xVC",
      payment_token_address: "0xTC",
      rpc_url: "http://rpc.local"
    }.to_json

    stub_request(:post, "#{BASE}/v1/chunks/prepare")
      .to_return(status: 200, body: response_body,
                 headers: { "Content-Type" => "application/json" })

    result = @client.prepare_chunk_upload("new_chunk_data")
    assert_equal false, result.already_stored
    assert_equal "addr_chunk_new", result.address
    assert_equal "chunk_up_1", result.upload_id
    assert_equal "wave_batch", result.payment_type
    assert_equal 1, result.payments.length
    assert_equal "qhC", result.payments[0].quote_hash
    assert_equal "0xRC", result.payments[0].rewards_address
    assert_equal "7", result.payments[0].amount
    assert_equal "7", result.total_amount
    assert_equal "0xVC", result.payment_vault_address
    assert_equal "0xTC", result.payment_token_address
    assert_equal "http://rpc.local", result.rpc_url
  end

  # Finalize: forwards upload_id + tx_hashes and returns the address as a
  # plain string (mirrors Go's FinalizeChunkUpload signature).
  def test_finalize_chunk_upload
    stub_request(:post, "#{BASE}/v1/chunks/finalize")
      .with(body: hash_including(
        "upload_id" => "chunk_up_1",
        "tx_hashes" => { "qhC" => "tx_C" }
      ))
      .to_return(status: 200, body: '{"address":"addr_chunk_new"}',
                 headers: { "Content-Type" => "application/json" })

    addr = @client.finalize_chunk_upload("chunk_up_1", { "qhC" => "tx_C" })
    assert_equal "addr_chunk_new", addr
  end

  # --- Error Mapping ---

  def test_error_404
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 404, body: '{"error":"not found"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::NotFoundError) { @client.health }
    assert_equal 404, err.status_code
    assert_includes err.message, "not found"
  end

  def test_error_400
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 400, body: '{"error":"bad request"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::BadRequestError) { @client.health }
    assert_equal 400, err.status_code
  end

  def test_error_402
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 402, body: '{"error":"payment required"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::PaymentError) { @client.health }
    assert_equal 402, err.status_code
  end

  def test_error_409
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 409, body: '{"error":"already exists"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::AlreadyExistsError) { @client.health }
    assert_equal 409, err.status_code
  end

  def test_error_413
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 413, body: '{"error":"too large"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::TooLargeError) { @client.health }
    assert_equal 413, err.status_code
  end

  def test_error_500
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 500, body: '{"error":"internal error"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::InternalError) { @client.health }
    assert_equal 500, err.status_code
  end

  def test_error_502
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 502, body: '{"error":"network error"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::NetworkError) { @client.health }
    assert_equal 502, err.status_code
  end

  def test_error_unknown_status
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 503, body: '{"error":"unavailable"}',
                 headers: { "Content-Type" => "application/json" })

    err = assert_raises(Antd::AntdError) { @client.health }
    assert_equal 503, err.status_code
  end
end
