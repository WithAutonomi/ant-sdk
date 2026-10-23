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

-- Error bodies are decoded with a private, strict cjson instance. The
-- default instance accepts number literals that are not JSON (NaN, Infinity
-- and hex such as 0x10), which would let a malformed body slip a count past
-- the JSON-number check in antd.errors. A private instance leaves the
-- caller's global cjson configuration untouched.
local error_json = cjson.new()
error_json.decode_invalid_numbers(false)

--- Map a non-2xx response body onto an antd error without raising.
-- The body's `error` field becomes the message only when it is a JSON
-- string; any other `error` (a table, number, boolean or JSON null), or a
-- body that is not strict JSON, falls back to the raw body text.
-- @param status number HTTP status code
-- @param resp_body string raw response body
-- @return table error object
local function error_from_body(status, resp_body)
    local ok, parsed = pcall(error_json.decode, resp_body)
    if not ok then
        parsed = nil
    end
    local msg = resp_body
    if type(parsed) == "table" and type(parsed.error) == "string" then
        msg = parsed.error
    end
    return errors.error_for_response(status, msg, parsed)
end

--- Perform an HTTP request that sends/receives JSON.
function Client:_do_json(method, path, body)
    local req_body
    local headers = {}

    if body ~= nil then
        -- A string body is JSON the caller encoded itself (antd.manifests).
        req_body = type(body) == "string" and body or cjson.encode(body)
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
        return nil, status, error_from_body(status, resp_body)
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

--- Perform a streaming HTTP request, forwarding the decrypted/raw response
-- body to a caller-supplied per-chunk sink callback.
--
-- This is the streaming counterpart to :func:`_do_json`. Instead of
-- buffering the whole response, each chunk handed to us by LuaSocket is
-- forwarded straight to `sink_cb`, so memory stays constant regardless of
-- payload size.
--
-- LuaSocket only surfaces the HTTP status code *after* the transfer has
-- finished, by which point body chunks may already have been pumped. To
-- keep success-path streaming truly constant-memory while still mapping a
-- non-2xx response onto an antd error, we gate forwarding on the first
-- chunk: the daemon's error bodies are short JSON blobs delivered before
-- any large payload, so we hold back only the *first* chunk until we can
-- be sure of the status. On a 2xx response the held chunk is flushed and
-- all subsequent chunks stream through untouched.
--
-- @param method string HTTP method
-- @param path string request path
-- @param body table|nil JSON request body
-- @param sink_cb function callback invoked as sink_cb(chunk) for each
--   non-empty body chunk on a 2xx response; called zero or more times.
-- @return boolean|nil ok (true on success), error|nil
function Client:_do_stream(method, path, body, sink_cb)
    if type(sink_cb) ~= "function" then
        return nil, errors.bad_request("data_stream requires a sink callback function")
    end

    local req_body
    local headers = {}
    local source = nil
    if body ~= nil then
        req_body = cjson.encode(body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#req_body)
        source = ltn12.source.string(req_body)
    end

    -- LuaSocket runs the sink synchronously inside http.request and only
    -- surfaces the status code as a return value afterwards. We cannot know
    -- the status while the first chunk arrives. To keep the success path
    -- constant-memory while still mapping a non-2xx response onto an antd
    -- error, we gate only the FIRST chunk: it is held in `head_chunk` until
    -- the request returns and the status is known. Subsequent chunks are
    -- forwarded straight to the caller's `sink_cb` as they arrive, so at
    -- most one chunk (~the daemon's HTTP chunk size) is ever buffered.
    --
    -- On a non-2xx response the daemon sends a short JSON error body, which
    -- fits in the gated first chunk and is therefore never handed to the
    -- caller; we decode it into an antd error instead.
    local head_chunk = nil
    local head_seen = false
    local started_streaming = false

    local stream_sink = function(chunk, err)
        if err then
            return nil, err
        end
        if chunk == nil or chunk == "" then
            return 1
        end
        if not head_seen then
            head_chunk = chunk
            head_seen = true
            return 1
        end
        -- We already buffered the first chunk; more data means this is a
        -- real (large) 2xx body. Flush the head chunk once, then stream.
        if not started_streaming then
            started_streaming = true
            sink_cb(head_chunk)
            head_chunk = nil
        end
        sink_cb(chunk)
        return 1
    end

    local _, status = http.request({
        url = self:_url(path),
        method = method,
        headers = headers,
        source = source,
        sink = stream_sink,
        timeout = self.timeout,
    })

    if not status or type(status) ~= "number" then
        return nil, errors.network(tostring(status or "connection failed"))
    end

    if status < 200 or status >= 300 then
        return nil, error_from_body(status, head_chunk or "")
    end

    -- 2xx: flush any still-buffered head chunk (single-chunk responses never
    -- triggered the streaming branch). For multi-chunk responses the head was
    -- already flushed and head_chunk cleared.
    if head_chunk ~= nil then
        sink_cb(head_chunk)
    end

    return true, nil
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

--- Optional string field: the string when it is a non-empty string, else nil
-- (absent, JSON null and "" all mean unset).
local function opt_str(t, key)
    local v = t[key]
    if type(v) == "string" and v ~= "" then return v end
    return nil
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
        str(j, "payment_mode_used"),
        opt_str(j, "sha256")
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
        str(j, "payment_mode_used"),
        opt_str(j, "sha256")
    ), nil
end

--- Retrieve private data using a caller-held DataMap.
function Client:data_get(data_map)
    local j, _, err = self:_do_json("POST", "/v1/data/get", { data_map = data_map })
    if err then return nil, err end
    return base64.decode(str(j, "data")), nil
end

--- Stream private data using a caller-held DataMap, forwarding decrypted bytes
-- to a per-chunk sink callback instead of buffering the whole object.
--
-- This is the streaming counterpart to :func:`data_get`, suitable for large
-- blobs or piping straight to a file. The daemon decrypts the data and
-- streams the raw (already-decoded) bytes back; unlike :func:`data_get`, the
-- chunks are NOT base64-encoded.
--
-- @param data_map string caller-held DataMap (hex)
-- @param sink_cb function callback invoked as sink_cb(chunk) for each body
--   chunk; receives raw bytes. Called zero or more times on success.
-- @return boolean|nil ok (true on success), error|nil
function Client:data_stream(data_map, sink_cb)
    return self:_do_stream("POST", "/v1/data/stream", { data_map = data_map }, sink_cb)
end

--- Stream public data by address — the streaming counterpart to
-- :func:`data_get_public`. The daemon streams raw (already-decoded) bytes.
--
-- @param address string on-network DataMap address
-- @param sink_cb function callback invoked as sink_cb(chunk) for each body
--   chunk; receives raw bytes. Called zero or more times on success.
-- @return boolean|nil ok (true on success), error|nil
function Client:data_stream_public(address, sink_cb)
    return self:_do_stream("GET", "/v1/data/public/" .. address .. "/stream", nil, sink_cb)
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
        str(j, "payment_mode_used"),
        opt_str(j, "sha256")
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
        str(j, "payment_mode_used"),
        opt_str(j, "sha256")
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
        sha256 = opt_str(j, "sha256"),
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
        sha256 = opt_str(j, "sha256"),
    }), nil
end

-- ── Pointers ──
--
-- A pointer's owner key lives in the daemon (`antd --pointer-keys`); a write
-- names the pointer by its address (`owner`). Needs an antd with the pointer
-- API (0.16.0 or later).
--
-- Every write (pointer_create, pointer_update, pointer_transfer,
-- pointer_finalize) pays, about the price of one chunk, and every attempt
-- pays again. The SDK never retries them, and callers should not either:
-- check the error first. Reads are free to retry; a read during an update or
-- churn can fail with `close_group_shortfall`.
--
-- Counters are decimal strings (see antd.models): a final state sits at
-- 2^64-1, which no Lua number holds exactly. A malformed counter in a
-- response is an `internal` error, never a 0. Unset values (a REST JSON
-- null) read as nil.

--- Optional table field: the table when it is one, else nil (absent or JSON
-- null).
local function opt_table(t, key)
    local v = t[key]
    if type(v) == "table" then return v end
    return nil
end

--- Array field: the table when it is one, else an empty table.
local function arr(t, key)
    local v = t[key]
    if type(v) == "table" then return v end
    return {}
end

--- A pointer's raw target tag: an integer 0..255, else nil.
local function kind_tag(t)
    local v = t.kind_tag
    if type(v) == "number" and v >= 0 and v <= 255 and v == math.floor(v) then
        return v
    end
    return nil
end

--- Required counter field, checked and canonicalised (antd.models).
-- @return string|nil counter, table|nil error
local function counter_field(t, key)
    local c, why = models.parse_pointer_counter(t[key])
    if not c then
        return nil, errors.internal("invalid pointer " .. key .. ": " .. why)
    end
    return c, nil
end

--- Percent-encode one URL path segment, so an address can never reach
-- another route ("abc/resolve") or add a query. The class is spelled out
-- rather than `%w`, which follows the C locale.
local function path_segment(s)
    return (s:gsub("[^0-9A-Za-z%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

--- Reject a missing or non-string argument before any request is sent.
local function check_string(name, v)
    if type(v) ~= "string" or v == "" then
        return errors.bad_request(name .. " must be a non-empty string")
    end
    return nil
end

local function parse_pointer_write(j)
    local counter, err = counter_field(j, "counter")
    if err then return nil, err end
    return {
        address = str(j, "address"),
        state_id = str(j, "state_id"),
        counter = counter,
    }, nil
end

local function parse_pointer_final_state(t)
    return {
        state_id = str(t, "state_id"),
        kind = str(t, "kind"),
        kind_tag = kind_tag(t),
        target = str(t, "target"),
        holders = num(t, "holders"),
        transferred_to = opt_str(t, "transferred_to"),
    }
end

local function parse_pointer_finality(j)
    -- `counter` is set for "open" only: JSON null (REST) or "" means unset.
    -- Any other value must be a counter.
    local counter = nil
    local raw_counter = j.counter
    if raw_counter ~= nil and raw_counter ~= cjson.null and raw_counter ~= "" then
        local err
        counter, err = counter_field(j, "counter")
        if err then return nil, err end
    end

    local states = {}
    for _, s in ipairs(arr(j, "states")) do
        if type(s) == "table" then
            states[#states + 1] = parse_pointer_final_state(s)
        end
    end

    local state = opt_table(j, "state")
    local majority = opt_table(j, "majority")
    local raw_status = str(j, "status")
    return {
        address = str(j, "address"),
        group = num(j, "group"),
        answered = num(j, "answered"),
        status = models.pointer_finality_status(raw_status),
        raw_status = raw_status,
        counter = counter,
        state = state and parse_pointer_final_state(state) or nil,
        states = states,
        majority = majority and parse_pointer_final_state(majority) or nil,
        transferred_to = opt_str(j, "transferred_to"),
    }, nil
end

--- Parse an optional `finality` object (transfer and finalize responses).
-- @return table|nil finality, table|nil error
local function opt_finality(j)
    local f = opt_table(j, "finality")
    if not f then return nil, nil end
    return parse_pointer_finality(f)
end

--- The pointers this daemon holds owner keys for (`GET /v1/pointers/keys`).
-- Only these can be written through this daemon.
-- @return table|nil list of pointer addresses (hex strings), error|nil
function Client:pointer_keys()
    local j, _, err = self:_do_json("GET", "/v1/pointers/keys", nil)
    if err then return nil, err end
    local keys = {}
    for _, k in ipairs(arr(j or {}, "keys")) do
        if type(k) == "table" and type(k.address) == "string" then
            keys[#keys + 1] = k.address
        end
    end
    return keys, nil
end

function Client:_pointer_write(path, owner, target, kind)
    local bad = check_string("owner", owner) or check_string("target", target)
    if bad then return nil, bad end
    local body = { owner = owner, target = target }
    if kind ~= nil then
        body.kind = kind
    end
    local j, _, err = self:_do_json("POST", path, body)
    if err then return nil, err end
    return parse_pointer_write(j or {})
end

--- Create the pointer at `owner`, pointing at `target`, paid by the daemon
-- wallet (`POST /v1/pointers`). `owner` is the pointer's address; the daemon
-- must hold its key (see `pointer_keys`).
--
-- Pays once per call and is never retried. Returns an `already_exists` error,
-- refused before anything is paid, if the pointer exists: use
-- `pointer_update`.
-- @param owner string pointer address
-- @param target string address to point at
-- @param kind string|nil PointerKind ("chunk" or "pointer"); nil leaves the
--   daemon's default, "chunk"
-- @return table|nil PointerWrite { address, state_id, counter }, error|nil
function Client:pointer_create(owner, target, kind)
    return self:_pointer_write("/v1/pointers", owner, target, kind)
end

--- Point the pointer at `owner` at `target`, paid by the daemon wallet
-- (`POST /v1/pointers/update`). A pointer that does not exist yet is created
-- at counter "0".
--
-- Pays once per call and is never retried. Returns a `pointer_final` error if
-- the pointer was transferred or frozen (usually refused before anything is
-- paid; see `errors.pointer_final`), and a `conflict` error if a prepared
-- write to it awaits payment (refused before paying) or the update lost to a
-- newer state while in flight (possibly after paying). Read the pointer
-- before writing again.
-- @param owner string pointer address
-- @param target string address to point at
-- @param kind string|nil PointerKind; nil leaves the daemon's default, "chunk"
-- @return table|nil PointerWrite { address, state_id, counter }, error|nil
function Client:pointer_update(owner, target, kind)
    return self:_pointer_write("/v1/pointers/update", owner, target, kind)
end

--- Hand the pointer at `owner` over to the pointer at `recipient`, for good,
-- paid by the daemon wallet (`POST /v1/pointers/transfer`). Readers of the
-- address are redirected to the recipient's pointer, which only its owner can
-- move; the address stays the same. Irreversible once stored.
--
-- Pays once per call and is never retried. Refused before paying if
-- `recipient` does not exist or leads back (`bad_request`), and usually if
-- the pointer is already final (`pointer_final`). A `close_group_shortfall`
-- means too few of the close group answered or stored it. That can happen
-- before paying (the transfer checks every peer first) or after, so check the
-- pointer with `pointer_finality` before paying again.
-- @param owner string pointer address
-- @param recipient string address of the recipient's pointer
-- @return table|nil PointerTransferResult { address, state_id, finality,
--   finality_error }, error|nil. `finality` is nil when the check after the
--   write failed (`finality_error` says why); the transfer is stored either
--   way, so ask again with `pointer_finality`.
function Client:pointer_transfer(owner, recipient)
    local bad = check_string("owner", owner) or check_string("recipient", recipient)
    if bad then return nil, bad end
    local j, _, err = self:_do_json("POST", "/v1/pointers/transfer", {
        owner = owner,
        recipient = recipient,
    })
    if err then return nil, err end
    j = j or {}
    local finality, ferr = opt_finality(j)
    if ferr then return nil, ferr end
    return {
        address = str(j, "address"),
        state_id = str(j, "state_id"),
        finality = finality,
        finality_error = opt_str(j, "finality_error"),
    }, nil
end

--- Read the pointer at `address` (`GET /v1/pointers/{address}`). Returns a
-- `not_found` error if there is none.
-- @param address string pointer address
-- @return table|nil PointerRecord { address, owner, counter, kind, kind_tag,
--   target, state_id, is_final, transferred_to }, error|nil
function Client:pointer_get(address)
    local bad = check_string("address", address)
    if bad then return nil, bad end
    local j, _, err = self:_do_json("GET", "/v1/pointers/" .. path_segment(address), nil)
    if err then return nil, err end
    j = j or {}
    local counter, cerr = counter_field(j, "counter")
    if cerr then return nil, cerr end
    return {
        address = str(j, "address"),
        owner = str(j, "owner"),
        counter = counter,
        kind = str(j, "kind"),
        kind_tag = kind_tag(j),
        target = str(j, "target"),
        state_id = str(j, "state_id"),
        is_final = j.is_final == true,
        transferred_to = opt_str(j, "transferred_to"),
    }, nil
end

--- Follow a chain of pointers from `address` to the target at its end
-- (`GET /v1/pointers/{address}/resolve`, at most 16 hops), through
-- forwardings and transfers alike. Returns a `not_found` error if a pointer
-- on the chain does not exist.
-- @param address string pointer address
-- @return table|nil PointerTarget { kind, kind_tag, target }, error|nil
function Client:pointer_resolve(address)
    local bad = check_string("address", address)
    if bad then return nil, bad end
    local j, _, err = self:_do_json("GET", "/v1/pointers/" .. path_segment(address) .. "/resolve", nil)
    if err then return nil, err end
    j = j or {}
    return {
        kind = str(j, "kind"),
        kind_tag = kind_tag(j),
        target = str(j, "target"),
    }, nil
end

--- Ask the whole close group where the pointer at `address` stands with
-- respect to finality (`GET /v1/pointers/{address}/finality`). Check this
-- before relying on a transfer: only `status == "final"` means one final
-- state, held by a majority, with no rival seen.
-- @param address string pointer address
-- @return table|nil PointerFinality { address, group, answered, status,
--   raw_status, counter, state, states, majority, transferred_to },
--   error|nil
function Client:pointer_finality(address)
    local bad = check_string("address", address)
    if bad then return nil, bad end
    local j, _, err = self:_do_json("GET", "/v1/pointers/" .. path_segment(address) .. "/finality", nil)
    if err then return nil, err end
    return parse_pointer_finality(j or {})
end

--- Follow the transfers of the pointer at `address` to the pointer whose
-- owner now decides what it resolves to
-- (`GET /v1/pointers/{address}/controller`).
-- @param address string pointer address
-- @return table|nil PointerController { pointer, transfers, frozen },
--   error|nil
function Client:pointer_controller(address)
    local bad = check_string("address", address)
    if bad then return nil, bad end
    local j, _, err = self:_do_json("GET", "/v1/pointers/" .. path_segment(address) .. "/controller", nil)
    if err then return nil, err end
    j = j or {}
    local transfers = {}
    for _, t in ipairs(arr(j, "transfers")) do
        if type(t) == "string" then
            transfers[#transfers + 1] = t
        end
    end
    return {
        pointer = str(j, "pointer"),
        transfers = transfers,
        frozen = j.frozen == true,
    }, nil
end

--- Have the daemon sign `op` on the pointer at `owner` with its loaded key
-- and quote it for an external signer (`POST /v1/pointers/prepare`). Pay the
-- result's `payments` with `payForQuotes()`, then call `pointer_finalize`.
-- Needs no daemon wallet and pays nothing itself.
--
-- Every check the daemon-wallet methods make before paying is made here,
-- before anything is quoted. While the prepared write awaits payment, other
-- writes to the pointer answer `conflict` until it is finalized or expires
-- (one hour).
-- @param owner string pointer address
-- @param op table built with antd.models.pointer_create_op(target, kind),
--   pointer_update_op(target, kind) or pointer_transfer_op(recipient)
-- @param opts table|nil { include_signed_quotes = boolean }: populate the
--   result's `signed_quotes`
-- @return table|nil PointerPrepareResult { upload_id, op, address, state_id,
--   counter, payment_type, payments, total_amount, payment_vault_address,
--   payment_token_address, rpc_url, signed_quotes }, error|nil
function Client:pointer_prepare(owner, op, opts)
    local bad = check_string("owner", owner)
    if bad then return nil, bad end
    if type(op) ~= "table" then
        return nil, errors.bad_request("op must be a table built with pointer_create_op, "
            .. "pointer_update_op or pointer_transfer_op")
    end
    bad = check_string("op.op", op.op)
    if bad then return nil, bad end
    local body = { owner = owner, op = op.op }
    if op.target ~= nil then body.target = op.target end
    if op.kind ~= nil then body.kind = op.kind end
    if op.recipient ~= nil then body.recipient = op.recipient end
    if opts and opts.include_signed_quotes then
        body.include_signed_quotes = true
    end

    local j, _, err = self:_do_json("POST", "/v1/pointers/prepare", body)
    if err then return nil, err end
    j = j or {}
    local counter, cerr = counter_field(j, "counter")
    if cerr then return nil, cerr end

    local payments = {}
    for _, p in ipairs(arr(j, "payments")) do
        if type(p) == "table" then
            payments[#payments + 1] = {
                quote_hash = str(p, "quote_hash"),
                rewards_address = str(p, "rewards_address"),
                amount = str(p, "amount"),
            }
        end
    end

    local signed_quotes = {}
    for _, q in ipairs(arr(j, "signed_quotes")) do
        if type(q) == "table" then
            signed_quotes[#signed_quotes + 1] = {
                quote_hash = str(q, "quote_hash"),
                quote = str(q, "quote"),
                commitment_sidecar = opt_str(q, "commitment_sidecar"),
            }
        end
    end

    return {
        upload_id = str(j, "upload_id"),
        op = str(j, "op"),
        address = str(j, "address"),
        state_id = str(j, "state_id"),
        counter = counter,
        payment_type = str(j, "payment_type"),
        payments = payments,
        total_amount = str(j, "total_amount"),
        payment_vault_address = str(j, "payment_vault_address"),
        payment_token_address = str(j, "payment_token_address"),
        rpc_url = str(j, "rpc_url"),
        signed_quotes = signed_quotes,
    }, nil
end

--- Store a prepared pointer write once its external signer has paid
-- (`POST /v1/pointers/finalize`). `tx_hashes` maps each `quote_hash` from the
-- prepare's `payments` to the `payForQuotes()` transaction hash.
--
-- Never retried by the SDK. A write that falls short after payment returns a
-- `close_group_shortfall` error with `retryable == true`: the daemon kept the
-- paid state under the same `upload_id`, and calling this method again with
-- the same `upload_id` stores it against the same payment (`tx_hashes` is
-- then ignored). Bound that loop. Any other error: do not pay again on it
-- alone. A finalize without the payment's hashes is a `bad_request` and
-- keeps the session, so it can be corrected.
-- @param upload_id string from pointer_prepare
-- @param tx_hashes table quote_hash -> tx_hash
-- @return table|nil PointerFinalizeResult { address, state_id, counter,
--   finality }, error|nil. `finality` is set for a transfer only.
function Client:pointer_finalize(upload_id, tx_hashes)
    local bad = check_string("upload_id", upload_id)
    if bad then return nil, bad end
    -- An empty Lua table encodes as the JSON object {} (cjson's default),
    -- which is what the daemon's map expects.
    local j, _, err = self:_do_json("POST", "/v1/pointers/finalize", {
        upload_id = upload_id,
        tx_hashes = tx_hashes or {},
    })
    if err then return nil, err end
    j = j or {}
    local counter, cerr = counter_field(j, "counter")
    if cerr then return nil, cerr end
    local finality, ferr = opt_finality(j)
    if ferr then return nil, ferr end
    return {
        address = str(j, "address"),
        state_id = str(j, "state_id"),
        counter = counter,
        finality = finality,
    }, nil
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

-- Manifests (build_manifest, decode_manifest, decode_manifest_link) live in
-- antd.manifests.
require("antd.manifests").install(Client)

return Client
