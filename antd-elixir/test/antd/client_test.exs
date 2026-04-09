defmodule Antd.ClientTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    client = Antd.Client.new("http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, client: client}
  end

  # ---------------------------------------------------------------------------
  # Health
  # ---------------------------------------------------------------------------

  test "health/1 returns health status", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/health", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok", network: "local"}))
    end)

    assert {:ok, %Antd.HealthStatus{ok: true, network: "local"}} = Antd.Client.health(client)
  end

  # ---------------------------------------------------------------------------
  # Data
  # ---------------------------------------------------------------------------

  test "data_put_public/2 stores public data", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/public", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["data"] == Base.encode64("hello")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "100", address: "abc123"}))
    end)

    assert {:ok, %Antd.PutResult{cost: "100", address: "abc123"}} =
             Antd.Client.data_put_public(client, "hello")
  end

  test "data_get_public/2 retrieves public data", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/data/public/abc123", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{data: Base.encode64("hello")}))
    end)

    assert {:ok, "hello"} = Antd.Client.data_get_public(client, "abc123")
  end

  test "data_put_private/2 stores private data", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/private", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "200", data_map: "dm123"}))
    end)

    assert {:ok, %Antd.PutResult{cost: "200", address: "dm123"}} =
             Antd.Client.data_put_private(client, "secret")
  end

  test "data_get_private/2 retrieves private data", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/data/private", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{data: Base.encode64("secret")}))
    end)

    assert {:ok, "secret"} = Antd.Client.data_get_private(client, "dm123")
  end

  test "data_cost/2 estimates storage cost", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/cost", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "50"}))
    end)

    assert {:ok, "50"} = Antd.Client.data_cost(client, "test")
  end

  # ---------------------------------------------------------------------------
  # Chunks
  # ---------------------------------------------------------------------------

  test "chunk_put/2 stores a chunk", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/chunks", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "10", address: "chunk1"}))
    end)

    assert {:ok, %Antd.PutResult{cost: "10", address: "chunk1"}} =
             Antd.Client.chunk_put(client, "chunkdata")
  end

  test "chunk_get/2 retrieves a chunk", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/chunks/chunk1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{data: Base.encode64("chunkdata")}))
    end)

    assert {:ok, "chunkdata"} = Antd.Client.chunk_get(client, "chunk1")
  end

  # ---------------------------------------------------------------------------
  # Files & Directories
  # ---------------------------------------------------------------------------

  test "file_upload_public/2 uploads a file", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/files/upload/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "1000", address: "file1"}))
    end)

    assert {:ok, %Antd.PutResult{cost: "1000", address: "file1"}} =
             Antd.Client.file_upload_public(client, "/tmp/test.txt")
  end

  test "file_download_public/3 downloads a file", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/files/download/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{}))
    end)

    assert :ok = Antd.Client.file_download_public(client, "file1", "/tmp/out.txt")
  end

  test "dir_upload_public/2 uploads a directory", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/dirs/upload/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "2000", address: "dir1"}))
    end)

    assert {:ok, %Antd.PutResult{cost: "2000", address: "dir1"}} =
             Antd.Client.dir_upload_public(client, "/tmp/mydir")
  end

  test "dir_download_public/3 downloads a directory", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/dirs/download/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{}))
    end)

    assert :ok = Antd.Client.dir_download_public(client, "dir1", "/tmp/outdir")
  end

  test "file_cost/3 estimates file upload cost", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/cost/file", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "1000"}))
    end)

    assert {:ok, "1000"} = Antd.Client.file_cost(client, "/tmp/test.txt", true)
  end

  # ---------------------------------------------------------------------------
  # Error mapping
  # ---------------------------------------------------------------------------

  test "404 returns NotFoundError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/health", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(404, Jason.encode!(%{error: "not found"}))
    end)

    assert {:error, %Antd.NotFoundError{status_code: 404, message: "not found"}} =
             Antd.Client.health(client)
  end

  test "400 returns BadRequestError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(400, Jason.encode!(%{error: "bad request"}))
    end)

    assert {:error, %Antd.BadRequestError{status_code: 400}} =
             Antd.Client.data_put_public(client, "test")
  end

  test "402 returns PaymentError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(402, Jason.encode!(%{error: "insufficient funds"}))
    end)

    assert {:error, %Antd.PaymentError{status_code: 402}} =
             Antd.Client.data_put_public(client, "test")
  end

  test "409 returns AlreadyExistsError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(409, Jason.encode!(%{error: "already exists"}))
    end)

    assert {:error, %Antd.AlreadyExistsError{status_code: 409}} =
             Antd.Client.data_put_public(client, "test")
  end

  test "413 returns TooLargeError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/public", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(413, Jason.encode!(%{error: "payload too large"}))
    end)

    assert {:error, %Antd.TooLargeError{status_code: 413}} =
             Antd.Client.data_put_public(client, "test")
  end

  test "500 returns InternalError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/health", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(500, Jason.encode!(%{error: "server error"}))
    end)

    assert {:error, %Antd.InternalError{status_code: 500}} =
             Antd.Client.health(client)
  end

  test "502 returns NetworkError", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/health", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(502, Jason.encode!(%{error: "network unreachable"}))
    end)

    assert {:error, %Antd.NetworkError{status_code: 502}} =
             Antd.Client.health(client)
  end

  # ---------------------------------------------------------------------------
  # Bang variants
  # ---------------------------------------------------------------------------

  test "health!/1 raises on error", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/health", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(500, Jason.encode!(%{error: "server error"}))
    end)

    assert_raise Antd.InternalError, fn ->
      Antd.Client.health!(client)
    end
  end

  # ---------------------------------------------------------------------------
  # External Signer (Two-Phase Upload)
  # ---------------------------------------------------------------------------

  test "prepare_upload/2 parses wave_batch response", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/upload/prepare", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        upload_id: "up1",
        payments: [%{quote_hash: "qh1", rewards_address: "ra1", amount: "100"}],
        total_amount: "100",
        payment_vault_address: "pva1",
        payment_token_address: "pta1",
        rpc_url: "http://rpc",
        payment_type: "wave_batch"
      }))
    end)

    assert {:ok, result} = Antd.Client.prepare_upload(client, "/tmp/file.txt")
    assert result.upload_id == "up1"
    assert result.payment_type == "wave_batch"
    assert length(result.payments) == 1
    assert hd(result.payments).quote_hash == "qh1"
    assert result.pool_commitments == []
  end

  test "prepare_upload/2 defaults payment_type to wave_batch", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/upload/prepare", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        upload_id: "up2",
        payments: [],
        total_amount: "0",
        payment_vault_address: "pva2",
        payment_token_address: "pta2",
        rpc_url: "http://rpc"
      }))
    end)

    assert {:ok, result} = Antd.Client.prepare_upload(client, "/tmp/file.txt")
    assert result.payment_type == "wave_batch"
  end

  test "prepare_upload/2 parses merkle_batch response with pool_commitments", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/upload/prepare", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        upload_id: "up3",
        payments: [],
        total_amount: "500",
        payment_vault_address: "pva3",
        payment_token_address: "pta3",
        rpc_url: "http://rpc",
        payment_type: "merkle_batch",
        depth: 4,
        merkle_payment_timestamp: 1234567890,
        pool_commitments: [
          %{
            pool_hash: "ph1",
            candidates: [
              %{rewards_address: "ra1", amount: "100"},
              %{rewards_address: "ra2", amount: "200"}
            ]
          },
          %{
            pool_hash: "ph2",
            candidates: [
              %{rewards_address: "ra3", amount: "300"}
            ]
          }
        ]
      }))
    end)

    assert {:ok, result} = Antd.Client.prepare_upload(client, "/tmp/file.txt")
    assert result.payment_type == "merkle_batch"
    assert result.depth == 4
    assert result.merkle_payment_timestamp == 1234567890
    assert length(result.pool_commitments) == 2

    [pool1, pool2] = result.pool_commitments
    assert pool1.pool_hash == "ph1"
    assert length(pool1.candidates) == 2
    assert hd(pool1.candidates).rewards_address == "ra1"
    assert hd(pool1.candidates).amount == "100"
    assert pool2.pool_hash == "ph2"
    assert length(pool2.candidates) == 1
  end

  test "prepare_data_upload/2 uses shared parser", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/data/prepare", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["data"] == Base.encode64("test data")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        upload_id: "up4",
        payments: [%{quote_hash: "qh2", rewards_address: "ra2", amount: "50"}],
        total_amount: "50",
        payment_vault_address: "pva4",
        payment_token_address: "pta4",
        rpc_url: "http://rpc",
        payment_type: "wave_batch"
      }))
    end)

    assert {:ok, result} = Antd.Client.prepare_data_upload(client, "test data")
    assert result.upload_id == "up4"
    assert result.payment_type == "wave_batch"
    assert length(result.payments) == 1
  end

  test "finalize_upload/3 finalizes wave_batch upload", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/upload/finalize", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["upload_id"] == "up1"
      assert decoded["tx_hashes"]["qh1"] == "tx1"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{address: "addr1", chunks_stored: 5}))
    end)

    assert {:ok, result} = Antd.Client.finalize_upload(client, "up1", %{"qh1" => "tx1"})
    assert result.address == "addr1"
    assert result.chunks_stored == 5
  end

  test "finalize_merkle_upload/4 sends winner_pool_hash", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/upload/finalize", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["upload_id"] == "up3"
      assert decoded["winner_pool_hash"] == "ph1"
      refute Map.has_key?(decoded, "store_data_map")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{address: "addr2", chunks_stored: 10}))
    end)

    assert {:ok, result} = Antd.Client.finalize_merkle_upload(client, "up3", "ph1")
    assert result.address == "addr2"
    assert result.chunks_stored == 10
  end

  test "finalize_merkle_upload/4 passes store_data_map option", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/upload/finalize", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["upload_id"] == "up3"
      assert decoded["winner_pool_hash"] == "ph1"
      assert decoded["store_data_map"] == true

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{address: "addr3", chunks_stored: 8}))
    end)

    assert {:ok, result} = Antd.Client.finalize_merkle_upload(client, "up3", "ph1", store_data_map: true)
    assert result.address == "addr3"
    assert result.chunks_stored == 8
  end
end
