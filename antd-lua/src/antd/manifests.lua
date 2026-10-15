--- Manifests (ADR-0006): `.ant` files and `ant://` links.
--
-- A manifest describes a set of files, each with an optional path and size
-- and either an embedded DataMap (the manifest is the key to the file) or a
-- public file's DataMap address. The daemon builds and decodes manifests
-- through ant-core, so callers never re-implement the format. Nothing is
-- uploaded or paid for: `build_manifest` and a resolving decode only read
-- from the network, so they can time out and are free to retry.
--
-- The `.ant` bytes are a Lua string of raw bytes on both sides of the API;
-- base64 is only the REST wire form (`manifest` in the build response and
-- the decode request).
--
-- Sizes are Lua numbers, exact up to 2^53, far past any real file. An unset
-- size reads as nil, never 0. Optional strings (`path`, `data_map`, `error`,
-- `link`, `name` and the torrent info hashes) read as nil when unset too.
--
-- These methods are installed on antd.client's Client by `install`. Needs an
-- antd with the manifest API (the antd release after 0.15.0).
--
-- @module antd.manifests

local cjson = require("cjson")
local base64 = require("antd.base64")
local errors = require("antd.errors")

local M = {}

--- What a manifest entry carries. The string values are the wire format.
--
-- * `EMBEDDED` — the entry embeds its DataMap: the manifest is the key.
-- * `PUBLIC`   — the entry names a public file's DataMap address.
M.ManifestEntryKind = {
    EMBEDDED = "embedded",
    PUBLIC = "public",
}

--- What a decode read. The string values are the wire format.
--
-- * `MANIFEST`  — `.ant` bytes or a manifest link.
-- * `FILE_LINK` — a file link or a bare address, reported as one public
--                 entry with no path.
M.ManifestSource = {
    MANIFEST = "manifest",
    FILE_LINK = "file_link",
}

--- The largest size a Lua number holds exactly (2^53).
M.MAX_MANIFEST_SIZE = 2 ^ 53

-- ── internal helpers ──

local function str(t, key)
    local v = t[key]
    if type(v) == "string" then return v end
    return ""
end

--- Optional string: the string when it is a non-empty string, else nil
-- (absent, JSON null and "" all mean unset).
local function opt_str(t, key)
    local v = t[key]
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

--- A whole, non-negative number no larger than 2^53.
local function is_size(v)
    return type(v) == "number" and v == v and v >= 0 and v <= M.MAX_MANIFEST_SIZE
        and v == math.floor(v)
end

--- Optional size: the number when it is a whole, non-negative JSON number,
-- else nil. Absent and JSON null mean unset, never 0. On Lua 5.3+ the
-- value is an integer, so it prints without a ".0".
local function opt_size(t, key)
    local v = t[key]
    if not is_size(v) then return nil end
    if math.tointeger then
        return math.tointeger(v) or v
    end
    return v
end

--- Set means a non-empty string; the daemon reads "" as not given too.
local function is_set(v)
    return v ~= nil and v ~= ""
end

local function parse_entries(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, e in ipairs(raw) do
        if type(e) == "table" then
            out[#out + 1] = {
                effective_name = str(e, "effective_name"),
                path = opt_str(e, "path"),
                size = opt_size(e, "size"),
                kind = str(e, "kind"),
                content_address = str(e, "content_address"),
                data_map = opt_str(e, "data_map"),
                exact_size = opt_size(e, "exact_size"),
                error = opt_str(e, "error"),
            }
        end
    end
    return out
end

--- Decode the base64 `manifest` field strictly. mime.unb64 skips symbols
-- it does not know and drops an unpadded tail, so the form is checked first.
-- @return string|nil bytes, table|nil error
local function decode_manifest_field(s)
    if s == "" then return "", nil end
    if #s % 4 ~= 0 or not s:find("^[A-Za-z0-9+/]+=?=?$") then
        return nil, errors.internal("manifest in the response is not valid base64")
    end
    local raw = base64.decode(s)
    local pad = #s:match("=*$")
    if type(raw) ~= "string" or #raw ~= #s / 4 * 3 - pad then
        return nil, errors.internal("manifest in the response is not valid base64")
    end
    return raw, nil
end

--- The daemon's cap on reported entry errors (MAX_REPORTED_ENTRY_ERRORS).
local MAX_REPORTED_ENTRY_ERRORS = 20

--- The daemon's message for a decode with neither bytes nor a link.
local EMPTY_DECODE_INPUT = "needs a manifest (base64 .ant bytes) or a link"

--- A bad_request (status 400) with the daemon's bare message. The daemon's
-- REST body prefixes "Bad request: " (AntdError's Display) and gRPC does
-- not; client-side refusals use the bare text.
local function daemon_bad_request(message)
    return errors.bad_request(message)
end

--- The daemon's `entry_errors_message`: every bad entry, at most 20 shown.
local function entry_errors_message(list)
    local shown = {}
    for i = 1, math.min(#list, MAX_REPORTED_ENTRY_ERRORS) do
        shown[i] = list[i]
    end
    local text = table.concat(shown, "; ")
    if #list > MAX_REPORTED_ENTRY_ERRORS then
        return string.format("%d invalid entries: %s; and %d more",
            #list, text, #list - MAX_REPORTED_ENTRY_ERRORS)
    end
    return string.format("%d invalid entries: %s", #list, text)
end

--- Check one entry and encode it as a JSON object.
--
-- The request body is assembled here rather than by cjson.encode: cjson
-- writes numbers with 14 significant digits by default, which would round a
-- size from 10^14 up, and it writes an empty Lua table as {} where the
-- daemon wants an empty entries array. Sizes are written with %.0f, exact
-- for every whole number up to 2^53; strings go through cjson.encode.
-- @param e any the entry
-- @return string|nil json, string|nil reason (the daemon's wording)
local function encode_entry(e)
    if type(e) ~= "table" then
        return nil, "must be a table"
    end
    local has_dm, has_addr = is_set(e.data_map), is_set(e.address)
    if has_dm and has_addr then
        return nil, "give data_map or address, not both"
    elseif not has_dm and not has_addr then
        return nil, "needs a data_map or an address"
    end
    local fields = {}
    if is_set(e.path) then
        if type(e.path) ~= "string" then
            return nil, "path must be a string"
        end
        fields[#fields + 1] = '"path":' .. cjson.encode(e.path)
    end
    if e.size ~= nil then
        if not is_size(e.size) then
            return nil, "size must be a whole number of bytes from 0 to 2^53"
        end
        -- -0 passes is_size; write it as 0, not "-0".
        local size = e.size == 0 and 0 or e.size
        fields[#fields + 1] = '"size":' .. string.format("%.0f", size)
    end
    local key, value = "data_map", e.data_map
    if has_addr then
        key, value = "address", e.address
    end
    if type(value) ~= "string" then
        return nil, key .. " must be a hex string"
    end
    fields[#fields + 1] = '"' .. key .. '":' .. cjson.encode(value)
    return "{" .. table.concat(fields, ",") .. "}", nil
end

--- Encode a build request body.
-- @return string|nil json, table|nil error
local function encode_build_body(entries, opts)
    -- A lone entry table (keys but no list part) would read as no entries.
    if type(entries) ~= "table" or (#entries == 0 and next(entries) ~= nil) then
        return nil, errors.bad_request("entries must be a list of manifest entries")
    end
    if opts ~= nil and type(opts) ~= "table" then
        return nil, errors.bad_request("opts must be a table or nil")
    end
    opts = opts or {}

    -- Every bad entry is collected, 0-based as the daemon counts.
    local encoded, bad = {}, {}
    for i, e in ipairs(entries) do
        local json, reason = encode_entry(e)
        if reason then
            bad[#bad + 1] = string.format("entries[%d]: %s", i - 1, reason)
        else
            encoded[#encoded + 1] = json
        end
    end
    if #bad > 0 then
        return nil, daemon_bad_request(entry_errors_message(bad))
    end

    -- embed_roots: nil means true, the daemon's default (ADR-0006's policy).
    if opts.embed_roots ~= nil and type(opts.embed_roots) ~= "boolean" then
        return nil, errors.bad_request("opts.embed_roots must be a boolean or nil")
    end
    local fields = {
        '"entries":[' .. table.concat(encoded, ",") .. "]",
        '"embed_roots":' .. tostring(opts.embed_roots ~= false),
    }
    if is_set(opts.name) then
        if type(opts.name) ~= "string" then
            return nil, errors.bad_request("opts.name must be a string")
        end
        fields[#fields + 1] = '"name":' .. cjson.encode(opts.name)
    end
    local hashes = opts.torrent_info_hashes
    if hashes ~= nil then
        if type(hashes) ~= "table" then
            return nil, errors.bad_request("opts.torrent_info_hashes must be a list of hex strings")
        end
        local parts = {}
        for _, h in ipairs(hashes) do
            if type(h) ~= "string" then
                return nil, errors.bad_request("opts.torrent_info_hashes must be a list of hex strings")
            end
            parts[#parts + 1] = cjson.encode(h)
        end
        if #parts > 0 then
            fields[#fields + 1] = '"torrent_info_hashes":[' .. table.concat(parts, ",") .. "]"
        end
    end
    return "{" .. table.concat(fields, ",") .. "}", nil
end

local function check_resolve(resolve)
    if resolve ~= nil and type(resolve) ~= "boolean" then
        return errors.bad_request("resolve must be a boolean or nil")
    end
    return nil
end

-- ── methods ──

local methods = {}

--- Build a `.ant` manifest from DataMaps and public addresses already in
-- hand (`POST /v1/manifests/build`). Nothing is uploaded or paid for.
--
-- Each entry sets exactly one of `data_map` or `address`; an entry with
-- both or neither is refused before anything is sent, as a `bad_request`
-- (status 400) with the daemon's own message ("1 invalid entries:
-- entries[0]: give data_map or address, not both"), listing every bad entry
-- and counting from 0. The daemon names any other invalid entry (a bad path
-- such as "../x", bad hex) the same way.
-- @param entries table list of ManifestEntryInput tables:
--   { path = string|nil, size = number|nil, data_map = string|nil,
--     address = string|nil }. `path` is the relative path the entry
--   extracts under (nil: its content address). `size` is the plaintext size
--   to record as given, the creator's claim (nil: none recorded). `data_map`
--   is a hex DataMap as the upload methods return it, embedded in the
--   manifest; `address` is a public file's DataMap address (hex).
-- @param opts table|nil BuildManifestOptions: { name = string|nil,
--   torrent_info_hashes = {hex,...}|nil, embed_roots = boolean|nil }.
--   `name` is a suggested root directory name. `torrent_info_hashes` are
--   BitTorrent info hashes of the same files (40 hex for v1, 64 for v2).
--   `embed_roots` (nil means true) resolves each shrunk DataMap and embeds
--   its root when it is at most 64 KiB, so recipients skip that fetch;
--   false embeds shrunk DataMaps exactly as given.
-- @return table|nil BuiltManifest { manifest, link, entries }, error|nil.
--   `manifest` is the raw `.ant` bytes. `link` is the `ant://manifest/`
--   link, nil when it does not fit the recommended 1,500 bytes. `entries`
--   are ManifestEntryInfo tables, in encoded order (sorted by effective
--   name).
function methods:build_manifest(entries, opts)
    local body, berr = encode_build_body(entries, opts)
    if berr then return nil, berr end
    local j, _, err = self:_do_json("POST", "/v1/manifests/build", body)
    if err then return nil, err end
    j = j or {}
    local raw, derr = decode_manifest_field(str(j, "manifest"))
    if derr then return nil, derr end
    return {
        manifest = raw,
        link = opt_str(j, "link"),
        entries = parse_entries(j.entries),
    }, nil
end

function methods:_decode_manifest(body)
    local j, _, err = self:_do_json("POST", "/v1/manifests/decode", body)
    if err then return nil, err end
    j = j or {}
    return {
        source = str(j, "source"),
        name = opt_str(j, "name"),
        torrent_info_hash_v1 = opt_str(j, "torrent_info_hash_v1"),
        torrent_info_hash_v2 = opt_str(j, "torrent_info_hash_v2"),
        entries = parse_entries(j.entries),
    }, nil
end

--- Decode `.ant` bytes (`POST /v1/manifests/decode`).
--
-- With `resolve`, the daemon fetches each entry's DataMap (and wrapper
-- records) to report `exact_size` and confirm the DataMap is on the
-- network; content chunks are not fetched. One entry's failure is reported
-- in its `error`, not as a failed call.
-- @param manifest string the raw `.ant` bytes
-- @param resolve boolean|nil fetch DataMaps for exact sizes (default false)
-- @return table|nil DecodedManifest { source, name, torrent_info_hash_v1,
--   torrent_info_hash_v2, entries }, error|nil. Each entry is a
--   ManifestEntryInfo { effective_name, path, size, kind, content_address,
--   data_map, exact_size, error }.
function methods:decode_manifest(manifest, resolve)
    if type(manifest) ~= "string" or manifest == "" then
        return nil, daemon_bad_request(EMPTY_DECODE_INPUT)
    end
    local bad = check_resolve(resolve)
    if bad then return nil, bad end
    return self:_decode_manifest({ manifest = base64.encode(manifest), resolve = resolve == true })
end

--- Decode an `ant://` manifest link, a file link or a bare 64-hex address
-- (`POST /v1/manifests/decode`). A file link or address reads as
-- `source == "file_link"`, one public entry with no path. See
-- `decode_manifest` for `resolve` and the result.
-- @param link string
-- @param resolve boolean|nil fetch DataMaps for exact sizes (default false)
-- @return table|nil DecodedManifest, error|nil
function methods:decode_manifest_link(link, resolve)
    if type(link) ~= "string" or link == "" then
        return nil, daemon_bad_request(EMPTY_DECODE_INPUT)
    end
    local bad = check_resolve(resolve)
    if bad then return nil, bad end
    return self:_decode_manifest({ link = link, resolve = resolve == true })
end

--- Install the manifest methods on a client class.
-- @param Client table antd.client's Client
function M.install(Client)
    for name, fn in pairs(methods) do
        Client[name] = fn
    end
end

return M
