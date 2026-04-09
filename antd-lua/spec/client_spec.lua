--- Tests for the antd Lua SDK client.
-- Uses busted test framework with mocked HTTP.

-- Mock modules before requiring the client
local cjson = require("cjson")

-- ── Mock HTTP layer ──

local mock_routes = {}
local mock_status = 200

local function reset_mock()
    mock_routes = {}
    mock_status = 200
end

local function register_route(method, path, status, body)
    mock_routes[method .. " " .. path] = { status = status, body = body }
end

-- Find route with prefix matching for paths with query strings
local function find_route(method, url)
    -- Try exact match first
    local route = mock_routes[method .. " " .. url]
    if route then return route end

    -- Try matching without query string
    local path = url:match("^([^?]+)")
    route = mock_routes[method .. " " .. path]
    if route then return route end

    return nil
end

-- Override socket.http.request
local original_http_request
local function install_mock()
    local socket_http = require("socket.http")
    original_http_request = socket_http.request
    socket_http.request = function(params)
        local url = params.url
        local method = params.method or "GET"

        -- Extract path from URL
        local path = url:match("http://[^/]+(/.*)") or "/"

        local route = find_route(method, path)
        if not route then
            route = { status = 404, body = cjson.encode({ error = "not found" }) }
        end

        -- Write response body to sink
        if params.sink and route.body then
            local ltn12 = require("ltn12")
            local source = ltn12.source.string(route.body)
            ltn12.pump.all(source, params.sink)
        end

        return 1, route.status, {}
    end
end

local function uninstall_mock()
    if original_http_request then
        local socket_http = require("socket.http")
        socket_http.request = original_http_request
    end
end

-- Install mock before requiring the client
install_mock()

local antd = require("antd")
local errors = require("antd.errors")
local base64 = require("antd.base64")

-- ── Setup mock daemon routes ──

local function setup_daemon()
    reset_mock()

    -- Health
    register_route("GET", "/health", 200,
        cjson.encode({ status = "ok", network = "local" }))

    -- Data put public
    register_route("POST", "/v1/data/public", 200,
        cjson.encode({ cost = "100", address = "abc123" }))

    -- Data get public
    register_route("GET", "/v1/data/public/abc123", 200,
        cjson.encode({ data = base64.encode("hello") }))

    -- Data put private
    register_route("POST", "/v1/data/private", 200,
        cjson.encode({ cost = "200", data_map = "dm123" }))

    -- Data get private
    register_route("GET", "/v1/data/private", 200,
        cjson.encode({ data = base64.encode("secret") }))

    -- Data cost
    register_route("POST", "/v1/data/cost", 200,
        cjson.encode({ cost = "50" }))

    -- Chunks
    register_route("POST", "/v1/chunks", 200,
        cjson.encode({ cost = "10", address = "chunk1" }))
    register_route("GET", "/v1/chunks/chunk1", 200,
        cjson.encode({ data = base64.encode("chunkdata") }))

    -- Files
    register_route("POST", "/v1/files/upload/public", 200,
        cjson.encode({ cost = "1000", address = "file1" }))
    register_route("POST", "/v1/files/download/public", 200, "")
    register_route("POST", "/v1/dirs/upload/public", 200,
        cjson.encode({ cost = "2000", address = "dir1" }))
    register_route("POST", "/v1/dirs/download/public", 200, "")
    register_route("POST", "/v1/cost/file", 200,
        cjson.encode({ cost = "1000" }))
end

-- ── Tests ──

describe("antd client", function()
    local client

    before_each(function()
        setup_daemon()
        client = antd.new_client("http://localhost:8082")
    end)

    after_each(function()
        reset_mock()
    end)

    -- Teardown mock after all tests
    teardown(function()
        uninstall_mock()
    end)

    describe("health", function()
        it("returns health status", function()
            local h, err = client:health()
            assert.is_nil(err)
            assert.is_true(h.ok)
            assert.are.equal("local", h.network)
        end)
    end)

    describe("data_put_public", function()
        it("stores public data", function()
            local result, err = client:data_put_public("hello")
            assert.is_nil(err)
            assert.are.equal("abc123", result.address)
            assert.are.equal("100", result.cost)
        end)
    end)

    describe("data_get_public", function()
        it("retrieves public data", function()
            local data, err = client:data_get_public("abc123")
            assert.is_nil(err)
            assert.are.equal("hello", data)
        end)
    end)

    describe("data_put_private", function()
        it("stores private data", function()
            local result, err = client:data_put_private("secret")
            assert.is_nil(err)
            assert.are.equal("dm123", result.address)
            assert.are.equal("200", result.cost)
        end)
    end)

    describe("data_get_private", function()
        it("retrieves private data", function()
            local data, err = client:data_get_private("dm123")
            assert.is_nil(err)
            assert.are.equal("secret", data)
        end)
    end)

    describe("data_cost", function()
        it("estimates data cost", function()
            local cost, err = client:data_cost("test")
            assert.is_nil(err)
            assert.are.equal("50", cost)
        end)
    end)

    describe("chunk_put", function()
        it("stores a chunk", function()
            local result, err = client:chunk_put("chunkdata")
            assert.is_nil(err)
            assert.are.equal("chunk1", result.address)
            assert.are.equal("10", result.cost)
        end)
    end)

    describe("chunk_get", function()
        it("retrieves a chunk", function()
            local data, err = client:chunk_get("chunk1")
            assert.is_nil(err)
            assert.are.equal("chunkdata", data)
        end)
    end)

    describe("file_upload_public", function()
        it("uploads a file", function()
            local result, err = client:file_upload_public("/tmp/test.txt")
            assert.is_nil(err)
            assert.are.equal("file1", result.address)
            assert.are.equal("1000", result.cost)
        end)
    end)

    describe("file_download_public", function()
        it("downloads a file", function()
            local _, err = client:file_download_public("file1", "/tmp/out.txt")
            assert.is_nil(err)
        end)
    end)

    describe("dir_upload_public", function()
        it("uploads a directory", function()
            local result, err = client:dir_upload_public("/tmp/mydir")
            assert.is_nil(err)
            assert.are.equal("dir1", result.address)
            assert.are.equal("2000", result.cost)
        end)
    end)

    describe("dir_download_public", function()
        it("downloads a directory", function()
            local _, err = client:dir_download_public("dir1", "/tmp/outdir")
            assert.is_nil(err)
        end)
    end)

    describe("file_cost", function()
        it("estimates file cost", function()
            local cost, err = client:file_cost("/tmp/test.txt", true, false)
            assert.is_nil(err)
            assert.are.equal("1000", cost)
        end)
    end)

    -- ── Merkle Batch Payment ──

    describe("prepare_upload merkle", function()
        it("parses merkle batch response with pool commitments", function()
            register_route("POST", "/v1/upload/prepare", 200,
                cjson.encode({
                    upload_id = "up_merkle_1",
                    payment_type = "merkle_batch",
                    depth = 3,
                    total_amount = "5000",
                    payments = {},
                    payment_vault_address = "0xMERKLE",
                    payment_token_address = "0xTOKEN",
                    rpc_url = "http://localhost:8545",
                    merkle_payment_timestamp = 1700000000,
                    pool_commitments = {
                        {
                            pool_hash = "pool_abc",
                            candidates = {
                                { rewards_address = "0xR1", amount = "2000" },
                                { rewards_address = "0xR2", amount = "3000" },
                            },
                        },
                    },
                }))

            local result, err = client:prepare_upload("/tmp/merkle/file.dat")
            assert.is_nil(err)
            assert.are.equal("up_merkle_1", result.upload_id)
            assert.are.equal("merkle_batch", result.payment_type)
            assert.are.equal(3, result.depth)
            assert.are.equal("5000", result.total_amount)
            assert.are.equal(1700000000, result.merkle_payment_timestamp)
            assert.are.equal("0xMERKLE", result.payment_vault_address)
            assert.are.equal(0, #result.payments)

            assert.are.equal(1, #result.pool_commitments)
            local pc = result.pool_commitments[1]
            assert.are.equal("pool_abc", pc.pool_hash)
            assert.are.equal(2, #pc.candidates)
            assert.are.equal("0xR1", pc.candidates[1].rewards_address)
            assert.are.equal("2000", pc.candidates[1].amount)
            assert.are.equal("0xR2", pc.candidates[2].rewards_address)
            assert.are.equal("3000", pc.candidates[2].amount)
        end)
    end)

    describe("finalize_merkle_upload", function()
        it("finalizes with winner pool hash", function()
            register_route("POST", "/v1/upload/finalize", 200,
                cjson.encode({ address = "0xFINAL", chunks_stored = 42 }))

            local result, err = client:finalize_merkle_upload("up_merkle_1", "pool_abc", true)
            assert.is_nil(err)
            assert.are.equal("0xFINAL", result.address)
            assert.are.equal(42, result.chunks_stored)
        end)
    end)

    describe("prepare_upload backward compat", function()
        it("defaults payment_type to wave_batch when absent", function()
            register_route("POST", "/v1/upload/prepare", 200,
                cjson.encode({
                    upload_id = "up_compat_1",
                    payments = {
                        { quote_hash = "qh1", rewards_address = "0xR1", amount = "100" },
                    },
                    total_amount = "100",
                    payment_vault_address = "0xDATA",
                    payment_token_address = "0xTOKEN",
                    rpc_url = "http://localhost:8545",
                }))

            local result, err = client:prepare_upload("/tmp/compat/file.dat")
            assert.is_nil(err)
            assert.are.equal("up_compat_1", result.upload_id)
            assert.are.equal("wave_batch", result.payment_type)
            assert.are.equal(0, result.depth)
            assert.are.equal(0, #result.pool_commitments)
            assert.are.equal(0, result.merkle_payment_timestamp)

            assert.are.equal(1, #result.payments)
            assert.are.equal("qh1", result.payments[1].quote_hash)
        end)
    end)

    describe("error mapping", function()
        it("maps 404 to not_found error", function()
            register_route("GET", "/health", 404,
                cjson.encode({ error = "not found" }))
            local _, err = client:health()
            assert.is_not_nil(err)
            assert.is_true(errors.is_antd_error(err))
            assert.are.equal("not_found", err.type)
            assert.are.equal(404, err.status_code)
        end)

        it("maps 400 to bad_request error", function()
            register_route("POST", "/v1/data/public", 400,
                cjson.encode({ error = "invalid data" }))
            local _, err = client:data_put_public("bad")
            assert.is_not_nil(err)
            assert.are.equal("bad_request", err.type)
            assert.are.equal(400, err.status_code)
        end)

        it("maps 402 to payment error", function()
            register_route("POST", "/v1/data/public", 402,
                cjson.encode({ error = "insufficient funds" }))
            local _, err = client:data_put_public("data")
            assert.is_not_nil(err)
            assert.are.equal("payment", err.type)
            assert.are.equal(402, err.status_code)
        end)

        it("maps 409 to already_exists error", function()
            register_route("POST", "/v1/data/public", 409,
                cjson.encode({ error = "already exists" }))
            local _, err = client:data_put_public("test")
            assert.is_not_nil(err)
            assert.are.equal("already_exists", err.type)
            assert.are.equal(409, err.status_code)
        end)

        it("maps 413 to too_large error", function()
            register_route("POST", "/v1/data/public", 413,
                cjson.encode({ error = "payload too large" }))
            local _, err = client:data_put_public("huge")
            assert.is_not_nil(err)
            assert.are.equal("too_large", err.type)
            assert.are.equal(413, err.status_code)
        end)

        it("maps 500 to internal error", function()
            register_route("GET", "/health", 500,
                cjson.encode({ error = "server error" }))
            local _, err = client:health()
            assert.is_not_nil(err)
            assert.are.equal("internal", err.type)
            assert.are.equal(500, err.status_code)
        end)

        it("maps 502 to network error", function()
            register_route("GET", "/health", 502,
                cjson.encode({ error = "bad gateway" }))
            local _, err = client:health()
            assert.is_not_nil(err)
            assert.are.equal("network", err.type)
            assert.are.equal(502, err.status_code)
        end)
    end)
end)
