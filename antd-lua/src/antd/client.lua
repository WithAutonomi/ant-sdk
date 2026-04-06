--- REST client for the antd daemon.
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

--- URL-encode a string.
local function url_encode(str)
    return str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

--- Build full URL.
function Client:_url(path)
    return self.base_url .. path
end

--- Perform an HTTP request that sends/receives JSON.
-- @return table|nil parsed JSON body (may be nil for empty responses)
-- @return number HTTP status code
-- @return table|nil error
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
-- @return number HTTP status code
-- @return table|nil error
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

--- Build a prepare-upload result table from a parsed JSON response.
-- Extracts legacy wave_batch fields and new merkle batch fields.
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
        data_payments_address = str(j, "data_payments_address"),
        payment_token_address = str(j, "payment_token_address"),
        rpc_url = str(j, "rpc_url"),
        payment_type = payment_type,
        depth = num(j, "depth"),
        pool_commitments = pool_commitments,
        merkle_payment_timestamp = num(j, "merkle_payment_timestamp"),
        merkle_payments_address = str(j, "merkle_payments_address"),
    }
end

-- ── Health ──

--- Check daemon health.
-- @return HealthStatus|nil, error|nil
function Client:health()
    local j, _, err = self:_do_json("GET", "/health", nil)
    if err then return nil, err end
    return models.new_health_status(str(j, "status") == "ok", str(j, "network")), nil
end

-- ── Data ──

--- Store public immutable data.
-- @param data string raw bytes to store
-- @param opts table optional settings: { payment_mode = string }
-- @return PutResult|nil, error|nil
function Client:data_put_public(data, opts)
    local body = {
        data = base64.encode(data),
    }
    if opts and opts.payment_mode then
        body.payment_mode = opts.payment_mode
    end
    local j, _, err = self:_do_json("POST", "/v1/data/public", body)
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

--- Retrieve public data by address.
-- @param address string hex address
-- @return string|nil raw bytes, error|nil
function Client:data_get_public(address)
    local j, _, err = self:_do_json("GET", "/v1/data/public/" .. address, nil)
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

--- Store private encrypted data.
-- @param data string raw bytes to store
-- @param opts table optional settings: { payment_mode = string }
-- @return PutResult|nil, error|nil
function Client:data_put_private(data, opts)
    local body = {
        data = base64.encode(data),
    }
    if opts and opts.payment_mode then
        body.payment_mode = opts.payment_mode
    end
    local j, _, err = self:_do_json("POST", "/v1/data/private", body)
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "data_map")), nil
end

--- Retrieve private data using a data map.
-- @param data_map string data map identifier
-- @return string|nil raw bytes, error|nil
function Client:data_get_private(data_map)
    local j, _, err = self:_do_json("GET", "/v1/data/private?data_map=" .. url_encode(data_map), nil)
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

--- Estimate cost of storing data.
-- @param data string raw bytes
-- @return string|nil cost in atto tokens, error|nil
function Client:data_cost(data)
    local j, _, err = self:_do_json("POST", "/v1/data/cost", {
        data = base64.encode(data),
    })
    if err then return nil, err end
    return str(j, "cost"), nil
end

-- ── Chunks ──

--- Store a raw chunk.
-- @param data string raw bytes
-- @return PutResult|nil, error|nil
function Client:chunk_put(data)
    local j, _, err = self:_do_json("POST", "/v1/chunks", {
        data = base64.encode(data),
    })
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

--- Retrieve a chunk by address.
-- @param address string hex address
-- @return string|nil raw bytes, error|nil
function Client:chunk_get(address)
    local j, _, err = self:_do_json("GET", "/v1/chunks/" .. address, nil)
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

-- ── Files ──

--- Upload a file to the network.
-- @param path string local file path
-- @param opts table optional settings: { payment_mode = string }
-- @return PutResult|nil, error|nil
function Client:file_upload_public(path, opts)
    local body = {
        path = path,
    }
    if opts and opts.payment_mode then
        body.payment_mode = opts.payment_mode
    end
    local j, _, err = self:_do_json("POST", "/v1/files/upload/public", body)
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

--- Download a file from the network.
-- @param address string hex address
-- @param dest_path string local destination path
-- @return nil, error|nil
function Client:file_download_public(address, dest_path)
    local _, _, err = self:_do_json("POST", "/v1/files/download/public", {
        address = address,
        dest_path = dest_path,
    })
    return nil, err
end

--- Upload a directory to the network.
-- @param path string local directory path
-- @param opts table optional settings: { payment_mode = string }
-- @return PutResult|nil, error|nil
function Client:dir_upload_public(path, opts)
    local body = {
        path = path,
    }
    if opts and opts.payment_mode then
        body.payment_mode = opts.payment_mode
    end
    local j, _, err = self:_do_json("POST", "/v1/dirs/upload/public", body)
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

--- Download a directory from the network.
-- @param address string hex address
-- @param dest_path string local destination path
-- @return nil, error|nil
function Client:dir_download_public(address, dest_path)
    local _, _, err = self:_do_json("POST", "/v1/dirs/download/public", {
        address = address,
        dest_path = dest_path,
    })
    return nil, err
end

--- Estimate cost of uploading a file.
-- @param path string local file path
-- @param is_public boolean whether the file will be public
-- @return string|nil cost in atto tokens, error|nil
function Client:file_cost(path, is_public)
    local j, _, err = self:_do_json("POST", "/v1/cost/file", {
        path = path,
        is_public = is_public,
    })
    if err then return nil, err end
    return str(j, "cost"), nil
end

-- ── Wallet ──

--- Get the wallet's public address.
-- @return table|nil {address=string}, error|nil
function Client:wallet_address()
    local j, _, err = self:_do_json("GET", "/v1/wallet/address", nil)
    if err then return nil, err end
    return { address = str(j, "address") }, nil
end

--- Get the wallet's token and gas balances.
-- @return table|nil {balance=string, gas_balance=string}, error|nil
function Client:wallet_balance()
    local j, _, err = self:_do_json("GET", "/v1/wallet/balance", nil)
    if err then return nil, err end
    return { balance = str(j, "balance"), gas_balance = str(j, "gas_balance") }, nil
end

--- Approve the wallet to spend tokens on payment contracts (one-time operation).
-- @return boolean|nil, error|nil
function Client:wallet_approve()
    local j, _, err = self:_do_json("POST", "/v1/wallet/approve", {})
    if err then return nil, err end
    return j.approved == true, nil
end

-- ── External Signer (Two-Phase Upload) ──

--- Prepare a file upload for external signing.
-- @param path string local file path
-- @return table|nil PrepareUploadResult, error|nil
function Client:prepare_upload(path)
    local j, _, err = self:_do_json("POST", "/v1/upload/prepare", {
        path = path,
    })
    if err then return nil, err end
    return build_prepare_result(j), nil
end

--- Prepare a data upload for external signing.
-- Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
-- @param data string raw bytes to upload
-- @return table|nil PrepareUploadResult, error|nil
function Client:prepare_data_upload(data)
    local j, _, err = self:_do_json("POST", "/v1/data/prepare", {
        data = base64.encode(data),
    })
    if err then return nil, err end
    return build_prepare_result(j), nil
end

--- Finalize an upload after an external signer has submitted payment transactions.
-- @param upload_id string the upload ID from prepare_upload
-- @param tx_hashes table map of quote_hash to tx_hash
-- @return table|nil FinalizeUploadResult, error|nil
function Client:finalize_upload(upload_id, tx_hashes)
    local j, _, err = self:_do_json("POST", "/v1/upload/finalize", {
        upload_id = upload_id,
        tx_hashes = tx_hashes,
    })
    if err then return nil, err end
    return {
        address = str(j, "address"),
        chunks_stored = num(j, "chunks_stored"),
    }, nil
end

--- Finalize a merkle-batch upload after selecting a winning pool.
-- @param upload_id string the upload ID from prepare_upload
-- @param winner_pool_hash string hash of the winning pool commitment
-- @param store_data_map boolean whether to store the data map on-network (default false)
-- @return table|nil FinalizeUploadResult, error|nil
function Client:finalize_merkle_upload(upload_id, winner_pool_hash, store_data_map)
    local j, _, err = self:_do_json("POST", "/v1/upload/finalize", {
        upload_id = upload_id,
        winner_pool_hash = winner_pool_hash,
        store_data_map = store_data_map or false,
    })
    if err then return nil, err end
    return {
        address = str(j, "address"),
        chunks_stored = num(j, "chunks_stored"),
    }, nil
end

--- Create a client using daemon port discovery.
-- Falls back to the default base URL if discovery fails.
-- @param opts table optional settings: { timeout = number }
-- @return Client client, string url
function Client.auto_discover(opts)
    local url = discover.daemon_url()
    if url == "" then
        url = Client.DEFAULT_BASE_URL
    end
    return Client:new(url, opts), url
end

return Client
