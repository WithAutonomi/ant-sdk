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
  # Graph
  # ---------------------------------------------------------------------------

  test "graph_entry_put/5 creates a graph entry", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/graph", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["owner_secret_key"] == "sk1"
      assert decoded["parents"] == []
      assert decoded["content"] == "abc"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "500", address: "ge1"}))
    end)

    assert {:ok, %Antd.PutResult{cost: "500", address: "ge1"}} =
             Antd.Client.graph_entry_put(client, "sk1", [], "abc", [])
  end

  test "graph_entry_get/2 retrieves a graph entry", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/graph/ge1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        owner: "owner1",
        parents: [],
        content: "abc",
        descendants: [%{public_key: "pk1", content: "desc1"}]
      }))
    end)

    assert {:ok, %Antd.GraphEntry{owner: "owner1", descendants: [%Antd.GraphDescendant{public_key: "pk1"}]}} =
             Antd.Client.graph_entry_get(client, "ge1")
  end

  test "graph_entry_exists/2 returns true when entry exists", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "HEAD", "/v1/graph/ge1", fn conn ->
      Plug.Conn.resp(conn, 200, "")
    end)

    assert {:ok, true} = Antd.Client.graph_entry_exists(client, "ge1")
  end

  test "graph_entry_exists/2 returns false for 404", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "HEAD", "/v1/graph/missing", fn conn ->
      Plug.Conn.resp(conn, 404, "")
    end)

    assert {:ok, false} = Antd.Client.graph_entry_exists(client, "missing")
  end

  test "graph_entry_cost/2 estimates graph entry cost", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/graph/cost", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "500"}))
    end)

    assert {:ok, "500"} = Antd.Client.graph_entry_cost(client, "pk1")
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

  test "file_cost/4 estimates file upload cost", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "POST", "/v1/cost/file", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{cost: "1000"}))
    end)

    assert {:ok, "1000"} = Antd.Client.file_cost(client, "/tmp/test.txt", true, false)
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
    Bypass.expect_once(bypass, "POST", "/v1/graph", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(409, Jason.encode!(%{error: "already exists"}))
    end)

    assert {:error, %Antd.AlreadyExistsError{status_code: 409}} =
             Antd.Client.graph_entry_put(client, "sk1", [], "abc", [])
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
end
