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
-- @return PutResult|nil, error|nil
function Client:data_put_public(data)
    local j, _, err = self:_do_json("POST", "/v1/data/public", {
        data = base64.encode(data),
    })
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
-- @return PutResult|nil, error|nil
function Client:data_put_private(data)
    local j, _, err = self:_do_json("POST", "/v1/data/private", {
        data = base64.encode(data),
    })
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

-- ── Graph ──

--- Create a graph entry (DAG node).
-- @param owner_secret_key string secret key
-- @param parents table list of parent addresses
-- @param content string hex content
-- @param descendants table list of {public_key=, content=} tables
-- @return PutResult|nil, error|nil
function Client:graph_entry_put(owner_secret_key, parents, content, descendants)
    local descs = {}
    for i, d in ipairs(descendants) do
        descs[i] = { public_key = d.public_key, content = d.content }
    end
    local j, _, err = self:_do_json("POST", "/v1/graph", {
        owner_secret_key = owner_secret_key,
        parents = parents,
        content = content,
        descendants = descs,
    })
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

--- Retrieve a graph entry by address.
-- @param address string hex address
-- @return GraphEntry|nil, error|nil
function Client:graph_entry_get(address)
    local j, _, err = self:_do_json("GET", "/v1/graph/" .. address, nil)
    if err then return nil, err end

    local descs = {}
    if j.descendants and type(j.descendants) == "table" then
        for _, d in ipairs(j.descendants) do
            if type(d) == "table" then
                descs[#descs + 1] = models.new_graph_descendant(str(d, "public_key"), str(d, "content"))
            end
        end
    end

    local parents = {}
    if j.parents and type(j.parents) == "table" then
        for _, p in ipairs(j.parents) do
            if type(p) == "string" then
                parents[#parents + 1] = p
            end
        end
    end

    return models.new_graph_entry(str(j, "owner"), parents, str(j, "content"), descs), nil
end

--- Check if a graph entry exists.
-- @param address string hex address
-- @return boolean|nil, error|nil
function Client:graph_entry_exists(address)
    local code, err = self:_do_head("/v1/graph/" .. address)
    if err then return nil, err end
    if code == 404 then return false, nil end
    if code >= 300 then
        return nil, errors.error_for_status(code, "graph entry exists check failed")
    end
    return true, nil
end

--- Estimate cost of creating a graph entry.
-- @param public_key string hex public key
-- @return string|nil cost in atto tokens, error|nil
function Client:graph_entry_cost(public_key)
    local j, _, err = self:_do_json("POST", "/v1/graph/cost", {
        public_key = public_key,
    })
    if err then return nil, err end
    return str(j, "cost"), nil
end

-- ── Files ──

--- Upload a file to the network.
-- @param path string local file path
-- @return PutResult|nil, error|nil
function Client:file_upload_public(path)
    local j, _, err = self:_do_json("POST", "/v1/files/upload/public", {
        path = path,
    })
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
-- @return PutResult|nil, error|nil
function Client:dir_upload_public(path)
    local j, _, err = self:_do_json("POST", "/v1/dirs/upload/public", {
        path = path,
    })
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

--- Retrieve an archive manifest by address.
-- @param address string hex address
-- @return Archive|nil, error|nil
function Client:archive_get_public(address)
    local j, _, err = self:_do_json("GET", "/v1/archives/public/" .. address, nil)
    if err then return nil, err end

    local entries = {}
    if j.entries and type(j.entries) == "table" then
        for _, e in ipairs(j.entries) do
            if type(e) == "table" then
                entries[#entries + 1] = models.new_archive_entry(
                    str(e, "path"),
                    str(e, "address"),
                    num(e, "created"),
                    num(e, "modified"),
                    num(e, "size")
                )
            end
        end
    end

    return models.new_archive(entries), nil
end

--- Create an archive manifest on the network.
-- @param archive table Archive with entries
-- @return PutResult|nil, error|nil
function Client:archive_put_public(archive)
    local entries = {}
    for i, e in ipairs(archive.entries) do
        entries[i] = {
            path = e.path,
            address = e.address,
            created = e.created,
            modified = e.modified,
            size = e.size,
        }
    end
    local j, _, err = self:_do_json("POST", "/v1/archives/public", {
        entries = entries,
    })
    if err then return nil, err end
    return models.new_put_result(str(j, "cost"), str(j, "address")), nil
end

--- Estimate cost of uploading a file.
-- @param path string local file path
-- @param is_public boolean whether the file will be public
-- @param include_archive boolean whether to include archive manifest
-- @return string|nil cost in atto tokens, error|nil
function Client:file_cost(path, is_public, include_archive)
    local j, _, err = self:_do_json("POST", "/v1/cost/file", {
        path = path,
        is_public = is_public,
        include_archive = include_archive,
    })
    if err then return nil, err end
    return str(j, "cost"), nil
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
