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
      .to_return(status: 200, body: '{"cost":"100","address":"abc123"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.data_put_public("hello")
    assert_equal "100", result.cost
    assert_equal "abc123", result.address
  end

  def test_data_get_public
    encoded = Base64.strict_encode64("hello")
    stub_request(:get, "#{BASE}/v1/data/public/abc123")
      .to_return(status: 200, body: %({"data":"#{encoded}"}),
                 headers: { "Content-Type" => "application/json" })

    data = @client.data_get_public("abc123")
    assert_equal "hello", data
  end

  # --- Data Private ---

  def test_data_put_private
    stub_request(:post, "#{BASE}/v1/data/private")
      .to_return(status: 200, body: '{"cost":"200","data_map":"dm123"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.data_put_private("secret")
    assert_equal "200", result.cost
    assert_equal "dm123", result.address
  end

  def test_data_get_private
    encoded = Base64.strict_encode64("secret")
    stub_request(:get, %r{#{BASE}/v1/data/private\?data_map=})
      .to_return(status: 200, body: %({"data":"#{encoded}"}),
                 headers: { "Content-Type" => "application/json" })

    data = @client.data_get_private("dm123")
    assert_equal "secret", data
  end

  # --- Data Cost ---

  def test_data_cost
    stub_request(:post, "#{BASE}/v1/data/cost")
      .to_return(status: 200,
                 body: '{"cost":"50","file_size":4,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"single"}',
                 headers: { "Content-Type" => "application/json" })

    est = @client.data_cost("test")
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

  def test_file_upload_public
    stub_request(:post, "#{BASE}/v1/files/upload/public")
      .to_return(status: 200,
                 body: '{"address":"file1","storage_cost_atto":"1000","gas_cost_wei":"42","chunks_stored":3,"payment_mode_used":"auto"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.file_upload_public("/tmp/test.txt")
    assert_equal "file1", result.address
    assert_equal "1000", result.storage_cost_atto
    assert_equal "42", result.gas_cost_wei
    assert_equal 3, result.chunks_stored
    assert_equal "auto", result.payment_mode_used
  end

  def test_file_download_public
    stub_request(:post, "#{BASE}/v1/files/download/public")
      .to_return(status: 200, body: "",
                 headers: { "Content-Type" => "application/json" })

    assert_nil @client.file_download_public("file1", "/tmp/out.txt")
  end

  def test_dir_upload_public
    stub_request(:post, "#{BASE}/v1/dirs/upload/public")
      .to_return(status: 200,
                 body: '{"address":"dir1","storage_cost_atto":"2000","gas_cost_wei":"100","chunks_stored":5,"payment_mode_used":"merkle"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.dir_upload_public("/tmp/mydir")
    assert_equal "dir1", result.address
    assert_equal "2000", result.storage_cost_atto
    assert_equal "100", result.gas_cost_wei
    assert_equal 5, result.chunks_stored
    assert_equal "merkle", result.payment_mode_used
  end

  def test_dir_download_public
    stub_request(:post, "#{BASE}/v1/dirs/download/public")
      .to_return(status: 200, body: "",
                 headers: { "Content-Type" => "application/json" })

    assert_nil @client.dir_download_public("dir1", "/tmp/outdir")
  end

  def test_file_cost
    stub_request(:post, "#{BASE}/v1/files/cost")
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
