--- REST client for the antd daemon.
--
-- Naming convention (post v1.0):
--   * Unqualified verb (`data_put`, `data_get`, `file_put`, `file_get`) =
--     private — the DataMap is returned to the caller and NOT stored
--     on-network.
--   * `_public` suffix = public — the DataMap is stored on-network as an
--     extra chunk; the call returns the shareable address.
--
-- @module antd.client

local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local base64 = require("antd.base64")
local errors = require("antd.errors")
local models = require("antd.models")
local discover = require("antd.discover")

local Client = {}
Client.__index = Client

--- Default base URL for the antd daemon.
Client.DEFAULT_BASE_URL = "http://localhost:8082"

--- Default request timeout in seconds.
Client.DEFAULT_TIMEOUT = 300

--- Create a new antd client.
-- @param base_url string base URL (default "http://localhost:8082")
-- @param opts table optional settings: { timeout = number }
-- @return Client
function Client:new(base_url, opts)
    opts = opts or {}
    local o = setmetatable({}, Client)
    o.base_url = (base_url or Client.DEFAULT_BASE_URL):gsub("/+$", "")
    o.timeout = opts.timeout or Client.DEFAULT_TIMEOUT
    return o
end

-- ── internal helpers ──

--- Build full URL.
function Client:_url(path)
    return self.base_url .. path
end

--- Perform an HTTP request that sends/receives JSON.
function Client:_do_json(method, path, body)
    local req_body
    local headers = {}

    if body ~= nil then
        req_body = cjson.encode(body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#req_body)
    end

    local resp_parts = {}
    local source = nil
    if req_body then
        source = ltn12.source.string(req_body)
    end

    local _, status, resp_headers = http.request({
        url = self:_url(path),
        method = method,
        headers = headers,
        source = source,
        sink = ltn12.sink.table(resp_parts),
        timeout = self.timeout,
    })

    if not status or type(status) ~= "number" then
        return nil, 0, errors.network(tostring(status or "connection failed"))
    end

    local resp_body = table.concat(resp_parts)

    if status < 200 or status >= 300 then
        local msg = resp_body
        local ok, parsed = pcall(cjson.decode, resp_body)
        if ok and type(parsed) == "table" and parsed.error then
            msg = parsed.error
        end
        return nil, status, errors.error_for_status(status, msg)
    end

    if resp_body == "" or resp_body == nil then
        return nil, status, nil
    end

    local ok, result = pcall(cjson.decode, resp_body)
    if not ok then
        return nil, status, errors.internal("failed to decode JSON response: " .. tostring(result))
    end

    return result, status, nil
end

--- Perform an HTTP HEAD request.
function Client:_do_head(path)
    local resp_parts = {}
    local _, status = http.request({
        url = self:_url(path),
        method = "HEAD",
        sink = ltn12.sink.table(resp_parts),
        timeout = self.timeout,
    })

    if not status or type(status) ~= "number" then
        return 0, errors.network(tostring(status or "connection failed"))
    end

    return status, nil
end

--- Safe string extraction from a table.
local function str(t, key)
    local v = t[key]
    if type(v) == "string" then return v end
    return ""
end

--- Safe number extraction from a table.
local function num(t, key)
    local v = t[key]
    if type(v) == "number" then return v end
    return 0
end

--- Resolve a payment-mode value from an opts table, defaulting to "auto".
local function resolve_payment_mode(opts)
    if opts and opts.payment_mode then
        return opts.payment_mode
    end
    return models.PaymentMode.AUTO
end

--- Build a prepare-upload result table from a parsed JSON response.
local function build_prepare_result(j)
    local payment_type = j.payment_type or "wave_batch"

    local payments = {}
    if j.payments and type(j.payments) == "table" then
        for _, p in ipairs(j.payments) do
            if type(p) == "table" then
                payments[#payments + 1] = {
                    quote_hash = str(p, "quote_hash"),
                    rewards_address = str(p, "rewards_address"),
                    amount = str(p, "amount"),
                }
            end
        end
    end

    local pool_commitments = {}
    if payment_type == "merkle_batch" and j.pool_commitments and type(j.pool_commitments) == "table" then
        for _, pc in ipairs(j.pool_commitments) do
            if type(pc) == "table" then
                local candidates = {}
                if pc.candidates and type(pc.candidates) == "table" then
                    for _, c in ipairs(pc.candidates) do
                        if type(c) == "table" then
                            candidates[#candidates + 1] = {
                                rewards_address = c.rewards_address or "",
                                amount = c.amount or "",
                            }
                        end
                    end
                end
                pool_commitments[#pool_commitments + 1] = {
                    pool_hash = pc.pool_hash or "",
                    candidates = candidates,
                }
            end
        end
    end

    return {
        upload_id = str(j, "upload_id"),
        payments = payments,
        total_amount = str(j, "total_amount"),
        payment_vault_address = str(j, "payment_vault_address"),
        payment_token_address = str(j, "payment_token_address"),
        rpc_url = str(j, "rpc_url"),
        payment_type = payment_type,
        depth = num(j, "depth"),
        pool_commitments = pool_commitments,
        merkle_payment_timestamp = num(j, "merkle_payment_timestamp"),
        -- Already-stored preflight (added in antd 0.10.0). 0 on older daemons.
        total_chunks = num(j, "total_chunks"),
        already_stored_count = num(j, "already_stored_count"),
    }
end

-- ── Health ──

function Client:health()
    local j, _, err = self:_do_json("GET", "/health", nil)
    if err then return nil, err end
    return models.new_health_status(str(j, "status") == "ok", str(j, "network"), {
        version = str(j, "version"),
        evm_network = str(j, "evm_network"),
        uptime_seconds = j.uptime_seconds or 0,
        build_commit = str(j, "build_commit"),
        payment_token_address = str(j, "payment_token_address"),
        payment_vault_address = str(j, "payment_vault_address"),
    }), nil
end

-- ── Data ──

--- Store public immutable data.
-- @param data string raw bytes to store
-- @param opts table optional settings: { payment_mode = "auto"|"merkle"|"single" }
-- @return DataPutPublicResult|nil, error|nil
function Client:data_put_public(data, opts)
    local body = {
        data = base64.encode(data),
        payment_mode = resolve_payment_mode(opts),
    }
    local j, _, err = self:_do_json("POST", "/v1/data/public", body)
    if err then return nil, err end
    return models.new_data_put_public_result(
        str(j, "address"),
        num(j, "chunks_stored"),
        str(j, "payment_mode_used")
    ), nil
end

--- Retrieve public data by address.
function Client:data_get_public(address)
    local j, _, err = self:_do_json("GET", "/v1/data/public/" .. address, nil)
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

--- Store private encrypted data. The returned DataMap is the caller's key to
-- retrieve the data later via :func:`data_get`; it is NOT stored on-network.
-- @param data string raw bytes to store
-- @param opts table optional settings: { payment_mode = "auto"|"merkle"|"single" }
-- @return DataPutResult|nil, error|nil
function Client:data_put(data, opts)
    local body = {
        data = base64.encode(data),
        payment_mode = resolve_payment_mode(opts),
    }
    local j, _, err = self:_do_json("POST", "/v1/data", body)
    if err then return nil, err end
    return models.new_data_put_result(
        str(j, "data_map"),
        num(j, "chunks_stored"),
        str(j, "payment_mode_used")
    ), nil
end

--- Retrieve private data using a caller-held DataMap.
function Client:data_get(data_map)
    local j, _, err = self:_do_json("POST", "/v1/data/get", { data_map = data_map })
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

--- Pre-upload cost breakdown for the given bytes.
-- @param data string raw bytes
-- @param opts table optional settings: { payment_mode = "auto"|"merkle"|"single" }
function Client:data_cost(data, opts)
    local body = {
        data = base64.encode(data),
        payment_mode = resolve_payment_mode(opts),
    }
    local j, _, err = self:_do_json("POST", "/v1/data/cost", body)
    if err then return nil, err end
    return {
        cost = str(j, "cost"),
        file_size = num(j, "file_size"),
        chunk_count = num(j, "chunk_count"),
        estimated_gas_cost_wei = str(j, "estimated_gas_cost_wei"),
        payment_mode = str(j, "payment_mode"),
    }, nil
end

-- ── Chunks ──

function Client:chunk_put(data)
    local j, _, err = self:_do_json("POST", "/v1/chunks", {
        data = base64.encode(data),
    })
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

function Client:chunk_get(address)
    local j, _, err = self:_do_json("GET", "/v1/chunks/" .. address, nil)
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

function Client:prepare_chunk_upload(data)
    local j, _, err = self:_do_json("POST", "/v1/chunks/prepare", {
        data = base64.encode(data),
    })
    if err then return nil, err end

    local payments = {}
    if j.payments and type(j.payments) == "table" then
        for _, p in ipairs(j.payments) do
            if type(p) == "table" then
                payments[#payments + 1] = {
                    quote_hash = str(p, "quote_hash"),
                    rewards_address = str(p, "rewards_address"),
                    amount = str(p, "amount"),
                }
            end
        end
    end

    return models.new_prepare_chunk_result({
        address = str(j, "address"),
        already_stored = j.already_stored == true,
        upload_id = str(j, "upload_id"),
        payment_type = str(j, "payment_type"),
        payments = payments,
        total_amount = str(j, "total_amount"),
        payment_vault_address = str(j, "payment_vault_address"),
        payment_token_address = str(j, "payment_token_address"),
        rpc_url = str(j, "rpc_url"),
    }), nil
end

function Client:finalize_chunk_upload(upload_id, tx_hashes)
    local j, _, err = self:_do_json("POST", "/v1/chunks/finalize", {
        upload_id = upload_id,
        tx_hashes = tx_hashes,
    })
    if err then return nil, err end
    return str(j, "address"), nil
end

-- ── Files ──

--- Upload a file to the network *publicly*.
-- @param path string local file path
-- @param opts table optional settings: { payment_mode = "auto"|"merkle"|"single" }
-- @return FilePutPublicResult|nil, error|nil
function Client:file_put_public(path, opts)
    local body = {
        path = path,
        payment_mode = resolve_payment_mode(opts),
    }
    local j, _, err = self:_do_json("POST", "/v1/files/public", body)
    if err then return nil, err end
    return models.new_file_put_public_result(
        str(j, "address"),
        str(j, "storage_cost_atto"),
        str(j, "gas_cost_wei"),
        num(j, "chunks_stored"),
        str(j, "payment_mode_used")
    ), nil
end

--- Download a public file from an on-network DataMap address.
function Client:file_get_public(address, dest_path)
    local _, _, err = self:_do_json("POST", "/v1/files/public/get", {
        address = address,
        dest_path = dest_path,
    })
    return nil, err
end

--- Upload a file to the network *privately*. The returned DataMap is the
-- caller's key to retrieve the file later via :func:`file_get`.
-- @param path string local file path
-- @param opts table optional settings: { payment_mode = "auto"|"merkle"|"single" }
-- @return FilePutResult|nil, error|nil
function Client:file_put(path, opts)
    local body = {
        path = path,
        payment_mode = resolve_payment_mode(opts),
    }
    local j, _, err = self:_do_json("POST", "/v1/files", body)
    if err then return nil, err end
    return models.new_file_put_result(
        str(j, "data_map"),
        str(j, "storage_cost_atto"),
        str(j, "gas_cost_wei"),
        num(j, "chunks_stored"),
        str(j, "payment_mode_used")
    ), nil
end

--- Download a private file from a caller-held DataMap into `dest_path`.
function Client:file_get(data_map, dest_path)
    local _, _, err = self:_do_json("POST", "/v1/files/get", {
        data_map = data_map,
        dest_path = dest_path,
    })
    return nil, err
end

--- Pre-upload cost breakdown for the file at `path`.
-- @param path string local file path
-- @param is_public boolean whether the file will be public
-- @param opts table optional settings: { payment_mode = "auto"|"merkle"|"single" }
function Client:file_cost(path, is_public, opts)
    local body = {
        path = path,
        is_public = is_public,
        payment_mode = resolve_payment_mode(opts),
    }
    local j, _, err = self:_do_json("POST", "/v1/files/cost", body)
    if err then return nil, err end
    return {
        cost = str(j, "cost"),
        file_size = num(j, "file_size"),
        chunk_count = num(j, "chunk_count"),
        estimated_gas_cost_wei = str(j, "estimated_gas_cost_wei"),
        payment_mode = str(j, "payment_mode"),
    }, nil
end

-- ── Wallet ──

function Client:wallet_address()
    local j, _, err = self:_do_json("GET", "/v1/wallet/address", nil)
    if err then return nil, err end
    return { address = str(j, "address") }, nil
end

function Client:wallet_balance()
    local j, _, err = self:_do_json("GET", "/v1/wallet/balance", nil)
    if err then return nil, err end
    return { balance = str(j, "balance"), gas_balance = str(j, "gas_balance") }, nil
end

function Client:wallet_approve()
    local j, _, err = self:_do_json("POST", "/v1/wallet/approve", {})
    if err then return nil, err end
    return j.approved == true, nil
end

-- ── External Signer (Two-Phase Upload) ──

function Client:prepare_upload(path, visibility)
    local body = { path = path }
    if visibility ~= nil then
        body.visibility = visibility
    end
    local j, _, err = self:_do_json("POST", "/v1/upload/prepare", body)
    if err then return nil, err end
    return build_prepare_result(j), nil
end

function Client:prepare_upload_public(path)
    return self:prepare_upload(path, "public")
end

function Client:prepare_data_upload(data)
    local j, _, err = self:_do_json("POST", "/v1/data/prepare", {
        data = base64.encode(data),
    })
    if err then return nil, err end
    return build_prepare_result(j), nil
end

function Client:finalize_upload(upload_id, tx_hashes)
    local j, _, err = self:_do_json("POST", "/v1/upload/finalize", {
        upload_id = upload_id,
        tx_hashes = tx_hashes,
    })
    if err then return nil, err end
    return models.new_finalize_upload_result({
        address = str(j, "address"),
        chunks_stored = num(j, "chunks_stored"),
        data_map = str(j, "data_map"),
        data_map_address = str(j, "data_map_address"),
    }), nil
end

function Client:finalize_merkle_upload(upload_id, winner_pool_hash, store_data_map)
    local j, _, err = self:_do_json("POST", "/v1/upload/finalize", {
        upload_id = upload_id,
        winner_pool_hash = winner_pool_hash,
        store_data_map = store_data_map or false,
    })
    if err then return nil, err end
    return models.new_finalize_upload_result({
        address = str(j, "address"),
        chunks_stored = num(j, "chunks_stored"),
        data_map = str(j, "data_map"),
        data_map_address = str(j, "data_map_address"),
    }), nil
end

--- Create a client using daemon port discovery.
-- @return Client client, string url
function Client.auto_discover(opts)
    local url = discover.daemon_url()
    if url == "" then
        url = Client.DEFAULT_BASE_URL
    end
    return Client:new(url, opts), url
end

return Client
