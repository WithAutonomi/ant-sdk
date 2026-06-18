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
    local route = mock_routes[method .. " " .. url]
    if route then return route end

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

        local path = url:match("http://[^/]+(/.*)") or "/"

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
        cjson.encode({
            address = "abc123",
            chunks_stored = 3,
            payment_mode_used = "single",
        }))

    -- Data get public
    register_route("GET", "/v1/data/public/abc123", 200,
        cjson.encode({ data = base64.encode("hello") }))

    -- Data put private (new convention: POST /v1/data)
    register_route("POST", "/v1/data", 200,
        cjson.encode({
            data_map = "dm123",
            chunks_stored = 2,
            payment_mode_used = "merkle",
        }))

    -- Data get private (POST /v1/data/get with data_map in body)
    register_route("POST", "/v1/data/get", 200,
        cjson.encode({ data = base64.encode("secret") }))

    -- Data stream private (POST /v1/data/stream): body is raw decrypted bytes
    register_route("POST", "/v1/data/stream", 200, "streamed-secret-bytes")

    -- Data stream public (GET /v1/data/public/{address}/stream): raw bytes
    register_route("GET", "/v1/data/public/abc123/stream", 200, "streamed-public-bytes")

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

    -- File put public (was /v1/files/upload/public)
    register_route("POST", "/v1/files/public", 200,
        cjson.encode({
            address = "file1",
            storage_cost_atto = "1000",
            gas_cost_wei = "42",
            chunks_stored = 3,
            payment_mode_used = "auto",
        }))

    -- File get public (was /v1/files/download/public)
    register_route("POST", "/v1/files/public/get", 200, "")

    -- File put private (NEW)
    register_route("POST", "/v1/files", 200,
        cjson.encode({
            data_map = "fdm1",
            storage_cost_atto = "900",
            gas_cost_wei = "42",
            chunks_stored = 2,
            payment_mode_used = "merkle",
        }))

    -- File get private (NEW)
    register_route("POST", "/v1/files/get", 200, "")

    -- File cost
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

    describe("PaymentMode", function()
        it("exposes the wire-format string constants", function()
            local models = require("antd.models")
            assert.are.equal("auto", models.PaymentMode.AUTO)
            assert.are.equal("merkle", models.PaymentMode.MERKLE)
            assert.are.equal("single", models.PaymentMode.SINGLE)
        end)
    end)

    describe("data_put_public", function()
        it("returns DataPutPublicResult and forwards default payment_mode=auto", function()
            local result, err = client:data_put_public("hello")
            assert.is_nil(err)
            assert.are.equal("abc123", result.address)
            assert.are.equal(3, result.chunks_stored)
            assert.are.equal("single", result.payment_mode_used)

            local body = captured_body("POST", "/v1/data/public")
            assert.are.equal("auto", body.payment_mode)
        end)

        it("forwards explicit payment_mode", function()
            local _, err = client:data_put_public("hello", { payment_mode = "merkle" })
            assert.is_nil(err)
            local body = captured_body("POST", "/v1/data/public")
            assert.are.equal("merkle", body.payment_mode)
        end)
    end)

    describe("data_get_public", function()
        it("retrieves public data", function()
            local data, err = client:data_get_public("abc123")
            assert.is_nil(err)
            assert.are.equal("hello", data)
        end)
    end)

    describe("data_put", function()
        it("returns DataPutResult and POSTs payment_mode to /v1/data", function()
            local result, err = client:data_put("secret", { payment_mode = "merkle" })
            assert.is_nil(err)
            assert.are.equal("dm123", result.data_map)
            assert.are.equal(2, result.chunks_stored)
            assert.are.equal("merkle", result.payment_mode_used)

            local body = captured_body("POST", "/v1/data")
            assert.are.equal("merkle", body.payment_mode)
        end)
    end)

    describe("data_get", function()
        it("POSTs data_map and returns decoded bytes", function()
            local data, err = client:data_get("dm123")
            assert.is_nil(err)
            assert.are.equal("secret", data)
            local body = captured_body("POST", "/v1/data/get")
            assert.are.equal("dm123", body.data_map)
        end)
    end)

    describe("data_stream", function()
        it("POSTs data_map and forwards raw body chunks to the sink", function()
            local got = {}
            local ok, err = client:data_stream("dm123", function(chunk)
                got[#got + 1] = chunk
            end)
            assert.is_nil(err)
            assert.is_true(ok)
            assert.are.equal("streamed-secret-bytes", table.concat(got))
            local body = captured_body("POST", "/v1/data/stream")
            assert.are.equal("dm123", body.data_map)
        end)

        it("returns a bad_request error when no sink callback is given", function()
            local ok, err = client:data_stream("dm123", nil)
            assert.is_nil(ok)
            assert.is_not_nil(err)
            assert.are.equal("bad_request", err.type)
        end)

        it("maps a non-2xx {\"error\"} body onto an antd error", function()
            register_route("POST", "/v1/data/stream", 404,
                cjson.encode({ error = "data map not found", code = "not_found" }))
            local got = {}
            local ok, err = client:data_stream("missing", function(chunk)
                got[#got + 1] = chunk
            end)
            assert.is_nil(ok)
            assert.is_not_nil(err)
            assert.are.equal("not_found", err.type)
            assert.are.equal("data map not found", err.message)
            -- the error body must NOT be forwarded to the caller's sink
            assert.are.equal(0, #got)
        end)
    end)

    describe("data_stream_public", function()
        it("GETs the /stream path and forwards raw body chunks to the sink", function()
            local got = {}
            local ok, err = client:data_stream_public("abc123", function(chunk)
                got[#got + 1] = chunk
            end)
            assert.is_nil(err)
            assert.is_true(ok)
            assert.are.equal("streamed-public-bytes", table.concat(got))
        end)

        it("maps a non-2xx {\"error\"} body onto an antd error", function()
            register_route("GET", "/v1/data/public/missing/stream", 404,
                cjson.encode({ error = "address not found", code = "not_found" }))
            local got = {}
            local ok, err = client:data_stream_public("missing", function(chunk)
                got[#got + 1] = chunk
            end)
            assert.is_nil(ok)
            assert.is_not_nil(err)
            assert.are.equal("not_found", err.type)
            assert.are.equal("address not found", err.message)
            assert.are.equal(0, #got)
        end)
    end)

    describe("data_cost", function()
        it("returns full breakdown and forwards payment_mode", function()
            local est, err = client:data_cost("test", { payment_mode = "single" })
            assert.is_nil(err)
            assert.are.equal("50", est.cost)
            assert.are.equal(4, est.file_size)
            assert.are.equal(3, est.chunk_count)
            assert.are.equal("150000000000000", est.estimated_gas_cost_wei)
            assert.are.equal("single", est.payment_mode)
            local body = captured_body("POST", "/v1/data/cost")
            assert.are.equal("single", body.payment_mode)
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

    describe("file_put_public", function()
        it("returns FilePutPublicResult and forwards payment_mode", function()
            local result, err = client:file_put_public("/tmp/test.txt")
            assert.is_nil(err)
            assert.are.equal("file1", result.address)
            assert.are.equal("1000", result.storage_cost_atto)
            assert.are.equal("42", result.gas_cost_wei)
            assert.are.equal(3, result.chunks_stored)
            assert.are.equal("auto", result.payment_mode_used)
            local body = captured_body("POST", "/v1/files/public")
            assert.are.equal("auto", body.payment_mode)
        end)
    end)

    describe("file_get_public", function()
        it("POSTs to /v1/files/public/get with address + dest_path", function()
            local _, err = client:file_get_public("file1", "/tmp/out.txt")
            assert.is_nil(err)
            local body = captured_body("POST", "/v1/files/public/get")
            assert.are.equal("file1", body.address)
            assert.are.equal("/tmp/out.txt", body.dest_path)
        end)
    end)

    describe("file_put", function()
        it("returns FilePutResult and POSTs payment_mode to /v1/files", function()
            local result, err = client:file_put("/tmp/secret.txt", { payment_mode = "merkle" })
            assert.is_nil(err)
            assert.are.equal("fdm1", result.data_map)
            assert.are.equal("900", result.storage_cost_atto)
            assert.are.equal(2, result.chunks_stored)
            assert.are.equal("merkle", result.payment_mode_used)
            local body = captured_body("POST", "/v1/files")
            assert.are.equal("merkle", body.payment_mode)
        end)
    end)

    describe("file_get", function()
        it("POSTs data_map + dest_path to /v1/files/get", function()
            local _, err = client:file_get("fdm1", "/tmp/priv-out.txt")
            assert.is_nil(err)
            local body = captured_body("POST", "/v1/files/get")
            assert.are.equal("fdm1", body.data_map)
            assert.are.equal("/tmp/priv-out.txt", body.dest_path)
        end)
    end)

    describe("file_cost", function()
        it("returns full breakdown and forwards payment_mode + is_public", function()
            local est, err = client:file_cost("/tmp/test.txt", true, { payment_mode = "single" })
            assert.is_nil(err)
            assert.are.equal("1000", est.cost)
            assert.are.equal(4096, est.file_size)
            assert.are.equal(3, est.chunk_count)
            assert.are.equal("150000000000000", est.estimated_gas_cost_wei)
            assert.are.equal("auto", est.payment_mode)
            local body = captured_body("POST", "/v1/files/cost")
            assert.are.equal("single", body.payment_mode)
            assert.is_true(body.is_public)
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
                    total_chunks = 128,
                    already_stored_count = 4,
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
            -- already-stored preflight (added in antd 0.10.0)
            assert.are.equal(128, result.total_chunks)
            assert.are.equal(4, result.already_stored_count)
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
            -- preflight fields absent in older-daemon responses default to 0
            assert.are.equal(0, result.total_chunks)
            assert.are.equal(0, result.already_stored_count)
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
                    address = "aa" .. string.rep("00", 31),
                    already_stored = true,
                }))

            local result, err = client:prepare_chunk_upload("already-on-network")
            assert.is_nil(err)
            assert.is_true(result.already_stored)
            assert.are.equal(string.rep("a", 2) .. string.rep("00", 31), result.address)
            assert.are.equal("", result.upload_id)
            assert.are.equal(0, #result.payments)
            assert.are.equal("", result.total_amount)
            assert.are.equal("", result.payment_type)
        end)

        it("parses a wave-batch response into payment intent", function()
            register_route("POST", "/v1/chunks/prepare", 200,
                cjson.encode({
                    address = "bb" .. string.rep("11", 31),
                    already_stored = false,
                    upload_id = "chunk-1",
                    payment_type = "wave_batch",
                    payments = {
                        { quote_hash = "qh1", rewards_address = "ra1", amount = "100" },
                        { quote_hash = "qh2", rewards_address = "ra2", amount = "100" },
                    },
                    total_amount = "200",
                    payment_vault_address = "0xvault",
                    payment_token_address = "0xtoken",
                    rpc_url = "http://localhost:8545",
                }))

            local result, err = client:prepare_chunk_upload("hello")
            assert.is_nil(err)
            assert.is_false(result.already_stored)
            assert.are.equal("chunk-1", result.upload_id)
            assert.are.equal("wave_batch", result.payment_type)
            assert.are.equal(2, #result.payments)
            assert.are.equal("qh1", result.payments[1].quote_hash)
            assert.are.equal("100", result.payments[2].amount)
            assert.are.equal("200", result.total_amount)
            assert.are.equal("0xvault", result.payment_vault_address)
            assert.are.equal("http://localhost:8545", result.rpc_url)

            local body = captured_body("POST", "/v1/chunks/prepare")
            assert.are.equal(base64.encode("hello"), body.data)
        end)
    end)

    describe("finalize_chunk_upload", function()
        it("forwards upload_id + tx_hashes and returns the address", function()
            local addr = "cc" .. string.rep("22", 31)
            register_route("POST", "/v1/chunks/finalize", 200,
                cjson.encode({ address = addr }))

            local got, err = client:finalize_chunk_upload("chunk-1", {
                qh1 = "tx1",
                qh2 = "tx2",
            })
            assert.is_nil(err)
            assert.are.equal(addr, got)
            local body = captured_body("POST", "/v1/chunks/finalize")
            assert.are.equal("chunk-1", body.upload_id)
            assert.are.equal("tx1", body.tx_hashes.qh1)
            assert.are.equal("tx2", body.tx_hashes.qh2)
        end)
    end)
end)
