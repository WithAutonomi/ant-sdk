--- Tests for the antd Lua SDK client.
-- Uses busted test framework with mocked HTTP.

-- Mock modules before requiring the client
local cjson = require("cjson")

-- ── Mock HTTP layer ──

local mock_routes = {}
local mock_status = 200
-- Captured request bodies keyed by `METHOD PATH` so tests can assert on
-- exactly what the client sent (e.g. visibility forwarding, base64-encoded
-- chunk data, tx_hashes maps).
local captured_bodies = {}
-- Last prepare-upload request body, mirrors the antd-py mock's
-- `_last_prepare_request` pattern. Used by visibility-forwarding tests.
local last_prepare_body = nil

local function reset_mock()
    mock_routes = {}
    mock_status = 200
    captured_bodies = {}
    last_prepare_body = nil
end

local function register_route(method, path, status, body)
    mock_routes[method .. " " .. path] = { status = status, body = body }
end

local function captured_body(method, path)
    return captured_bodies[method .. " " .. path]
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
    local ltn12 = require("ltn12")
    original_http_request = socket_http.request
    socket_http.request = function(params)
        local url = params.url
        local method = params.method or "GET"

        -- Extract path from URL
        local path = url:match("http://[^/]+(/.*)") or "/"

        -- Drain the ltn12 source (if any) so tests can assert what the
        -- client sent. Mirrors the antd-py / antd-go mock-daemon pattern
        -- of stashing `_last_prepare_request` etc.
        if params.source then
            local body_parts = {}
            local sink = ltn12.sink.table(body_parts)
            ltn12.pump.all(params.source, sink)
            local raw = table.concat(body_parts)
            if raw ~= "" then
                local ok, parsed = pcall(cjson.decode, raw)
                local key = method .. " " .. path
                if ok then
                    captured_bodies[key] = parsed
                    if path == "/v1/upload/prepare" or path == "/v1/data/prepare" then
                        last_prepare_body = parsed
                    end
                else
                    captured_bodies[key] = raw
                end
            end
        end

        local route = find_route(method, path)
        if not route then
            route = { status = 404, body = cjson.encode({ error = "not found" }) }
        end

        -- Write response body to sink
        if params.sink and route.body then
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
        cjson.encode({
            status = "ok",
            network = "local",
            version = "0.4.0",
            evm_network = "local",
            uptime_seconds = 42,
            build_commit = "abcdef123456",
            payment_token_address = "0xtoken",
            payment_vault_address = "0xvault",
        }))

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
        cjson.encode({
            cost = "50",
            file_size = 4,
            chunk_count = 3,
            estimated_gas_cost_wei = "150000000000000",
            payment_mode = "single",
        }))

    -- Chunks
    register_route("POST", "/v1/chunks", 200,
        cjson.encode({ cost = "10", address = "chunk1" }))
    register_route("GET", "/v1/chunks/chunk1", 200,
        cjson.encode({ data = base64.encode("chunkdata") }))

    -- Files
    register_route("POST", "/v1/files/upload/public", 200,
        cjson.encode({
            address = "file1",
            storage_cost_atto = "1000",
            gas_cost_wei = "42",
            chunks_stored = 3,
            payment_mode_used = "auto",
        }))
    register_route("POST", "/v1/files/download/public", 200, "")
    register_route("POST", "/v1/files/cost", 200,
        cjson.encode({
            cost = "1000",
            file_size = 4096,
            chunk_count = 3,
            estimated_gas_cost_wei = "150000000000000",
            payment_mode = "auto",
        }))
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
        it("returns health status with all diagnostic fields", function()
            local h, err = client:health()
            assert.is_nil(err)
            assert.is_true(h.ok)
            assert.are.equal("local", h.network)
            assert.are.equal("0.4.0", h.version)
            assert.are.equal("local", h.evm_network)
            assert.are.equal(42, h.uptime_seconds)
            assert.are.equal("abcdef123456", h.build_commit)
            assert.are.equal("0xtoken", h.payment_token_address)
            assert.are.equal("0xvault", h.payment_vault_address)
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
        it("returns full breakdown", function()
            local est, err = client:data_cost("test")
            assert.is_nil(err)
            assert.are.equal("50", est.cost)
            assert.are.equal(4, est.file_size)
            assert.are.equal(3, est.chunk_count)
            assert.are.equal("150000000000000", est.estimated_gas_cost_wei)
            assert.are.equal("single", est.payment_mode)
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
            assert.are.equal("1000", result.storage_cost_atto)
            assert.are.equal("42", result.gas_cost_wei)
            assert.are.equal(3, result.chunks_stored)
            assert.are.equal("auto", result.payment_mode_used)
        end)
    end)

    describe("file_download_public", function()
        it("downloads a file", function()
            local _, err = client:file_download_public("file1", "/tmp/out.txt")
            assert.is_nil(err)
        end)
    end)

    describe("file_cost", function()
        it("returns full breakdown", function()
            local est, err = client:file_cost("/tmp/test.txt", true, false)
            assert.is_nil(err)
            assert.are.equal("1000", est.cost)
            assert.are.equal(4096, est.file_size)
            assert.are.equal(3, est.chunk_count)
            assert.are.equal("150000000000000", est.estimated_gas_cost_wei)
            assert.are.equal("auto", est.payment_mode)
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

    -- ── Public-prepare (visibility forwarding + data_map_address) ──

    describe("prepare_upload visibility", function()
        it("omits visibility from request body when nil", function()
            register_route("POST", "/v1/upload/prepare", 200,
                cjson.encode({
                    upload_id = "up_no_vis_1",
                    payment_type = "wave_batch",
                    payments = {
                        { quote_hash = "qh1", rewards_address = "0xR1", amount = "100" },
                    },
                    total_amount = "100",
                    payment_vault_address = "0xDP",
                    payment_token_address = "0xTK",
                    rpc_url = "http://rpc.local",
                }))

            local result, err = client:prepare_upload("/tmp/no-vis/file.dat")
            assert.is_nil(err)
            assert.are.equal("up_no_vis_1", result.upload_id)
            -- visibility key must NOT appear in the request body when nil
            assert.is_nil(last_prepare_body.visibility)
            assert.are.equal("/tmp/no-vis/file.dat", last_prepare_body.path)
        end)

        it("forwards visibility='private' verbatim when supplied", function()
            register_route("POST", "/v1/upload/prepare", 200,
                cjson.encode({
                    upload_id = "up_priv_1",
                    payment_type = "wave_batch",
                    payments = {},
                    total_amount = "0",
                }))

            local _, err = client:prepare_upload("/tmp/priv/file.dat", "private")
            assert.is_nil(err)
            assert.are.equal("private", last_prepare_body.visibility)
        end)
    end)

    describe("prepare_upload_public", function()
        it("forwards visibility='public' and parses the result", function()
            register_route("POST", "/v1/upload/prepare", 200,
                cjson.encode({
                    upload_id = "up_pub_1",
                    payment_type = "wave_batch",
                    payments = {
                        { quote_hash = "qh1", rewards_address = "0xR1", amount = "100" },
                    },
                    total_amount = "100",
                    payment_vault_address = "0xDP",
                    payment_token_address = "0xTK",
                    rpc_url = "http://rpc.local",
                }))

            local result, err = client:prepare_upload_public("/tmp/pub/file.dat")
            assert.is_nil(err)
            assert.are.equal("up_pub_1", result.upload_id)
            assert.are.equal("public", last_prepare_body.visibility)
            assert.are.equal("/tmp/pub/file.dat", last_prepare_body.path)
        end)
    end)

    describe("finalize_upload data_map_address", function()
        it("surfaces data_map_address + data_map on wave-batch finalize", function()
            register_route("POST", "/v1/upload/finalize", 200,
                cjson.encode({
                    address = "",
                    data_map = "deadbeef",
                    data_map_address = "0xDMAP",
                    chunks_stored = 4,
                }))

            local result, err = client:finalize_upload("up_pub_1", { qh1 = "tx1" })
            assert.is_nil(err)
            assert.are.equal("deadbeef", result.data_map)
            assert.are.equal("0xDMAP", result.data_map_address)
            assert.are.equal(4, result.chunks_stored)
            -- Sent body must contain the tx_hashes map
            local body = captured_body("POST", "/v1/upload/finalize")
            assert.are.equal("up_pub_1", body.upload_id)
            assert.are.equal("tx1", body.tx_hashes.qh1)
        end)

        it("defaults data_map_address to '' when the daemon omits it", function()
            register_route("POST", "/v1/upload/finalize", 200,
                cjson.encode({
                    address = "0xFIN",
                    data_map = "deadbeef",
                    chunks_stored = 2,
                }))

            local result, err = client:finalize_upload("up_priv_1", { qh1 = "tx1" })
            assert.is_nil(err)
            assert.are.equal("", result.data_map_address)
            assert.are.equal("deadbeef", result.data_map)
            assert.are.equal("0xFIN", result.address)
        end)
    end)

    -- ── Single-chunk external-signer (antd >= 0.7.0) ──

    describe("prepare_chunk_upload", function()
        it("parses an already-stored response and omits payment fields", function()
            register_route("POST", "/v1/chunks/prepare", 200,
                cjson.encode({
                    address = "addr_already_stored",
                    already_stored = true,
                }))

            local result, err = client:prepare_chunk_upload("already-on-network")
            assert.is_nil(err)
            assert.are.equal("addr_already_stored", result.address)
            assert.is_true(result.already_stored)
            assert.are.equal("", result.upload_id)
            assert.are.equal(0, #result.payments)
            assert.are.equal("", result.total_amount)
            assert.are.equal("", result.payment_type)
            -- Body must arrive base64-encoded under `data`.
            local body = captured_body("POST", "/v1/chunks/prepare")
            assert.are.equal(base64.encode("already-on-network"), body.data)
        end)

        it("parses a wave-batch payment intent for a new chunk", function()
            register_route("POST", "/v1/chunks/prepare", 200,
                cjson.encode({
                    address = "addr_chunk_new",
                    already_stored = false,
                    upload_id = "chunk_up_1",
                    payment_type = "wave_batch",
                    payments = {
                        { quote_hash = "qhC", rewards_address = "0xRC", amount = "7" },
                    },
                    total_amount = "7",
                    payment_vault_address = "0xVC",
                    payment_token_address = "0xTC",
                    rpc_url = "http://rpc.local",
                }))

            local result, err = client:prepare_chunk_upload("new-chunk-bytes")
            assert.is_nil(err)
            assert.is_false(result.already_stored)
            assert.are.equal("addr_chunk_new", result.address)
            assert.are.equal("chunk_up_1", result.upload_id)
            assert.are.equal("wave_batch", result.payment_type)
            assert.are.equal(1, #result.payments)
            assert.are.equal("qhC", result.payments[1].quote_hash)
            assert.are.equal("0xRC", result.payments[1].rewards_address)
            assert.are.equal("7", result.payments[1].amount)
            assert.are.equal("7", result.total_amount)
            assert.are.equal("0xVC", result.payment_vault_address)
            assert.are.equal("0xTC", result.payment_token_address)
            assert.are.equal("http://rpc.local", result.rpc_url)
        end)
    end)

    describe("finalize_chunk_upload", function()
        it("returns the stored chunk address and forwards tx_hashes", function()
            register_route("POST", "/v1/chunks/finalize", 200,
                cjson.encode({ address = "addr_chunk_new" }))

            local addr, err = client:finalize_chunk_upload("chunk_up_1", {
                qhC = "tx_C",
            })
            assert.is_nil(err)
            assert.are.equal("addr_chunk_new", addr)
            local body = captured_body("POST", "/v1/chunks/finalize")
            assert.are.equal("chunk_up_1", body.upload_id)
            assert.are.equal("tx_C", body.tx_hashes.qhC)
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
