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
    stub_request(:get, "#{BASE}/health")
      .to_return(status: 200, body: '{"status":"ok","network":"local"}',
                 headers: { "Content-Type" => "application/json" })

    h = @client.health
    assert h.ok
    assert_equal "local", h.network
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
      .to_return(status: 200, body: '{"cost":"50"}',
                 headers: { "Content-Type" => "application/json" })

    cost = @client.data_cost("test")
    assert_equal "50", cost
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

  # --- Graph ---

  def test_graph_entry_put
    stub_request(:post, "#{BASE}/v1/graph")
      .to_return(status: 200, body: '{"cost":"500","address":"ge1"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.graph_entry_put("sk1", [], "abc", [])
    assert_equal "500", result.cost
    assert_equal "ge1", result.address
  end

  def test_graph_entry_get
    body = {
      owner: "owner1", parents: [], content: "abc",
      descendants: [{ public_key: "pk1", content: "desc1" }]
    }.to_json
    stub_request(:get, "#{BASE}/v1/graph/ge1")
      .to_return(status: 200, body: body,
                 headers: { "Content-Type" => "application/json" })

    ge = @client.graph_entry_get("ge1")
    assert_equal "owner1", ge.owner
    assert_equal 1, ge.descendants.length
    assert_equal "pk1", ge.descendants[0].public_key
    assert_equal "desc1", ge.descendants[0].content
  end

  def test_graph_entry_exists
    stub_request(:head, "#{BASE}/v1/graph/ge1")
      .to_return(status: 200)

    assert @client.graph_entry_exists("ge1")
  end

  def test_graph_entry_exists_not_found
    stub_request(:head, "#{BASE}/v1/graph/missing")
      .to_return(status: 404)

    refute @client.graph_entry_exists("missing")
  end

  def test_graph_entry_cost
    stub_request(:post, "#{BASE}/v1/graph/cost")
      .to_return(status: 200, body: '{"cost":"500"}',
                 headers: { "Content-Type" => "application/json" })

    cost = @client.graph_entry_cost("pk1")
    assert_equal "500", cost
  end

  # --- Files ---

  def test_file_upload_public
    stub_request(:post, "#{BASE}/v1/files/upload/public")
      .to_return(status: 200, body: '{"cost":"1000","address":"file1"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.file_upload_public("/tmp/test.txt")
    assert_equal "1000", result.cost
    assert_equal "file1", result.address
  end

  def test_file_download_public
    stub_request(:post, "#{BASE}/v1/files/download/public")
      .to_return(status: 200, body: "",
                 headers: { "Content-Type" => "application/json" })

    assert_nil @client.file_download_public("file1", "/tmp/out.txt")
  end

  def test_dir_upload_public
    stub_request(:post, "#{BASE}/v1/dirs/upload/public")
      .to_return(status: 200, body: '{"cost":"2000","address":"dir1"}',
                 headers: { "Content-Type" => "application/json" })

    result = @client.dir_upload_public("/tmp/mydir")
    assert_equal "2000", result.cost
    assert_equal "dir1", result.address
  end

  def test_dir_download_public
    stub_request(:post, "#{BASE}/v1/dirs/download/public")
      .to_return(status: 200, body: "",
                 headers: { "Content-Type" => "application/json" })

    assert_nil @client.dir_download_public("dir1", "/tmp/outdir")
  end

  def test_archive_get_public
    body = {
      entries: [{ path: "test.txt", address: "abc", created: 1000, modified: 2000, size: 42 }]
    }.to_json
    stub_request(:get, "#{BASE}/v1/archives/public/arc1")
      .to_return(status: 200, body: body,
                 headers: { "Content-Type" => "application/json" })

    arc = @client.archive_get_public("arc1")
    assert_equal 1, arc.entries.length
    assert_equal "test.txt", arc.entries[0].path
    assert_equal 42, arc.entries[0].size
  end

  def test_archive_put_public
    stub_request(:post, "#{BASE}/v1/archives/public")
      .to_return(status: 200, body: '{"cost":"50","address":"arc2"}',
                 headers: { "Content-Type" => "application/json" })

    archive = Antd::Archive.new(entries: [
      Antd::ArchiveEntry.new(path: "test.txt", address: "abc", created: 1000, modified: 2000, size: 42)
    ])
    result = @client.archive_put_public(archive)
    assert_equal "50", result.cost
    assert_equal "arc2", result.address
  end

  def test_file_cost
    stub_request(:post, "#{BASE}/v1/cost/file")
      .to_return(status: 200, body: '{"cost":"1000"}',
                 headers: { "Content-Type" => "application/json" })

    cost = @client.file_cost("/tmp/test.txt", true, false)
    assert_equal "1000", cost
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
