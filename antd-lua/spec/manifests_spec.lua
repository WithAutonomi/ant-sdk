--- Tests for the antd Lua SDK manifest API, against mocked HTTP.

local cjson = require("cjson")
local socket_http = require("socket.http")
local ltn12 = require("ltn12")

-- ── Mock HTTP layer ──
--
-- Routes are keyed by `METHOD PATH`; every request is recorded with its raw
-- and decoded body, so tests can assert on exactly what was sent.

local routes = {}
local requests = {}

local function reset()
    routes = {}
    requests = {}
end

local function route(method, path, status, body)
    if type(body) ~= "string" then
        body = cjson.encode(body)
    end
    routes[method .. " " .. path] = { status = status, body = body }
end

local function last_request()
    return requests[#requests]
end

local original_request = socket_http.request
socket_http.request = function(params)
    local method = params.method or "GET"
    local path = params.url:match("^https?://[^/]+(/.*)$") or "/"
    local raw = nil
    if params.source then
        local parts = {}
        local sink = ltn12.sink.table(parts)
        ltn12.pump.all(params.source, sink)
        raw = table.concat(parts)
    end
    local decoded = nil
    if raw and raw ~= "" then
        local ok, v = pcall(cjson.decode, raw)
        if ok then decoded = v end
    end
    requests[#requests + 1] = { method = method, path = path, raw = raw, body = decoded }

    local r = routes[method .. " " .. path]
        or { status = 404, body = cjson.encode({ error = "no route " .. path, code = "NOT_FOUND" }) }
    if params.sink then
        ltn12.pump.all(ltn12.source.string(r.body), params.sink)
    end
    return 1, r.status, {}
end

-- Load the SDK fresh, so its socket.http is the table patched above.
for name in pairs(package.loaded) do
    if name == "antd" or name:find("^antd%.") then
        package.loaded[name] = nil
    end
end
local antd = require("antd")
local base64 = require("antd.base64")

-- The five-byte `.ant` header; "wUFOVAE=" is its base64.
local HEADER = "\193ANT\1"
local HEADER_B64 = "wUFOVAE="
local ADDR = string.rep("4", 62) .. "aa"

local function built_body(overrides)
    local body = {
        manifest = HEADER_B64,
        link = "ant://manifest/wUFOVAE",
        entries = {
            { effective_name = "a.txt", path = "a.txt", size = 10, kind = "embedded",
              content_address = "cc", exact_size = 10 },
            { effective_name = "11", kind = "public", content_address = "11" },
        },
    }
    for k, v in pairs(overrides or {}) do
        body[k] = v
    end
    return body
end

local function decoded_body()
    return {
        source = "manifest",
        name = "album",
        torrent_info_hash_v2 = "bb",
        entries = {
            { effective_name = "a.txt", path = "a.txt", kind = "embedded",
              content_address = "cc", data_map = "abcd", exact_size = 3 },
            { effective_name = "b", path = "b", kind = "public", content_address = "dd",
              error = "Record not found: gone" },
        },
    }
end

local function ok(value, err)
    assert(err == nil, err and (err.type .. ": " .. tostring(err.message)))
    return value
end

local function refused(value, err)
    assert.is_nil(value)
    assert.are.equal("bad_request", err and err.type)
    return err
end

describe("manifest API", function()
    local client

    before_each(function()
        reset()
        route("POST", "/v1/manifests/build", 200, built_body())
        route("POST", "/v1/manifests/decode", 200, decoded_body())
        client = antd.new_client("http://localhost:8082")
    end)

    teardown(function()
        socket_http.request = original_request
    end)

    describe("build_manifest", function()
        it("sends each entry's source, path and size, and the options", function()
            local res = ok(client:build_manifest({
                { path = "a.txt", size = 10, data_map = "abcd" },
                { address = "11" },
            }, { name = "album", embed_roots = false }))

            local req = last_request()
            assert.are.equal("POST", req.method)
            assert.are.equal("/v1/manifests/build", req.path)
            assert.are.equal("album", req.body.name)
            assert.is_false(req.body.embed_roots)
            assert.is_nil(req.body.torrent_info_hashes)
            local first, second = req.body.entries[1], req.body.entries[2]
            assert.are.same({ path = "a.txt", size = 10, data_map = "abcd" }, first)
            assert.are.same({ address = "11" }, second)

            assert.are.equal(HEADER, res.manifest)
            assert.are.equal("ant://manifest/wUFOVAE", res.link)
            assert.are.equal(2, #res.entries)
            local a, p = res.entries[1], res.entries[2]
            assert.are.equal("embedded", a.kind)
            assert.are.equal(antd.ManifestEntryKind.EMBEDDED, a.kind)
            assert.are.equal("a.txt", a.effective_name)
            assert.are.equal("a.txt", a.path)
            assert.are.equal(10, a.size)
            assert.are.equal(10, a.exact_size)
            assert.are.equal("cc", a.content_address)
            assert.is_nil(a.data_map)
            assert.is_nil(a.error)
            assert.are.equal(antd.ManifestEntryKind.PUBLIC, p.kind)
            assert.are.equal("11", p.effective_name)
            assert.are.equal("11", p.content_address)
        end)

        it("reads an unset path, size and exact_size as nil, never 0 or \"\"", function()
            local p = ok(client:build_manifest({ { address = "11" } })).entries[2]
            assert.is_nil(p.path)
            assert.is_nil(p.size)
            assert.is_nil(p.exact_size)
            assert.is_nil(p.data_map)
            assert.is_nil(p.error)
        end)

        it("reads a JSON null size as nil", function()
            route("POST", "/v1/manifests/build", 200, built_body({
                entries = { { effective_name = "x", kind = "public", content_address = "x",
                              size = cjson.null, exact_size = cjson.null, path = cjson.null } },
            }))
            local e = ok(client:build_manifest({ { address = "11" } })).entries[1]
            assert.is_nil(e.size)
            assert.is_nil(e.exact_size)
            assert.is_nil(e.path)
        end)

        it("keeps a size of 0 as 0, on the way out and back", function()
            route("POST", "/v1/manifests/build", 200, built_body({
                entries = { { effective_name = "e", path = "e", kind = "public",
                              content_address = "e", size = 0 } },
            }))
            local e = ok(client:build_manifest({ { path = "e", size = 0, address = "11" } })).entries[1]
            assert.are.equal(0, last_request().body.entries[1].size)
            assert.are.equal(0, e.size)

            ok(client:build_manifest({ { address = "11", size = -0.0 } }))
            assert.truthy(last_request().raw:find('"size":0,', 1, true))
        end)

        it("reads sizes as integers on Lua 5.3+", function()
            if not math.type then return end
            local a = ok(client:build_manifest({ { address = "11" } })).entries[1]
            assert.are.equal("integer", math.type(a.size))
            assert.are.equal("integer", math.type(a.exact_size))
        end)

        it("defaults embed_roots to true and omits an unset name", function()
            ok(client:build_manifest({ { address = "11" } }))
            assert.is_true(last_request().body.embed_roots)
            assert.is_nil(last_request().body.name)

            ok(client:build_manifest({ { address = "11" } }, {}))
            assert.is_true(last_request().body.embed_roots)

            ok(client:build_manifest({ { address = "11" } }, { embed_roots = true, name = "" }))
            assert.is_true(last_request().body.embed_roots)
            assert.is_nil(last_request().body.name)
        end)

        it("sends torrent info hashes only when there are some", function()
            local v1, v2 = string.rep("a", 40), string.rep("b", 64)
            ok(client:build_manifest({ { address = "11" } }, { torrent_info_hashes = { v1, v2 } }))
            assert.are.same({ v1, v2 }, last_request().body.torrent_info_hashes)

            ok(client:build_manifest({ { address = "11" } }, { torrent_info_hashes = {} }))
            assert.is_nil(last_request().body.torrent_info_hashes)
        end)

        it("sends an empty entry list as a JSON array", function()
            route("POST", "/v1/manifests/build", 200, built_body({ entries = {} }))
            local res = ok(client:build_manifest({}))
            assert.truthy(last_request().raw:find('"entries":[]', 1, true))
            assert.are.same({}, res.entries)
        end)

        it("writes large sizes exactly, past cjson's 14 digits", function()
            ok(client:build_manifest({
                { address = "11", size = 123456789012345 },
                { address = "22", size = 2 ^ 53 },
            }))
            local raw = last_request().raw
            assert.truthy(raw:find('"size":123456789012345,', 1, true))
            assert.truthy(raw:find('"size":9007199254740992,', 1, true))
        end)

        it("treats an empty data_map or address as unset", function()
            ok(client:build_manifest({ { data_map = "aa", address = "" } }))
            assert.are.same({ data_map = "aa" }, last_request().body.entries[1])
            ok(client:build_manifest({ { data_map = "", address = "bb", path = "" } }))
            assert.are.same({ address = "bb" }, last_request().body.entries[1])
        end)

        it("refuses an entry with both or neither source before sending", function()
            for _, e in ipairs({
                {},
                { path = "a.txt", size = 1 },
                { data_map = "", address = "" },
                { data_map = "aa", address = "bb" },
            }) do
                local err = refused(client:build_manifest({ { address = "11" }, e }))
                assert.truthy(err.message:find("manifest entry 2", 1, true))
                assert.truthy(err.message:find("exactly one of data_map or address", 1, true))
            end
            assert.are.equal(0, #requests)
        end)

        it("refuses a malformed size, path or option before sending", function()
            for _, size in ipairs({ -1, 1.5, "10", 2 ^ 53 + 2, 0 / 0, math.huge }) do
                refused(client:build_manifest({ { address = "11", size = size } }))
            end
            refused(client:build_manifest({ { address = "11", path = 7 } }))
            refused(client:build_manifest({ { address = 11 } }))
            refused(client:build_manifest({ "11" }))
            refused(client:build_manifest({ address = "11" }))
            refused(client:build_manifest("11"))
            refused(client:build_manifest(nil))
            refused(client:build_manifest({ { address = "11" } }, "album"))
            refused(client:build_manifest({ { address = "11" } }, { embed_roots = "no" }))
            refused(client:build_manifest({ { address = "11" } }, { name = 3 }))
            refused(client:build_manifest({ { address = "11" } }, { torrent_info_hashes = "aa" }))
            refused(client:build_manifest({ { address = "11" } }, { torrent_info_hashes = { 1 } }))
            assert.are.equal(0, #requests)
        end)

        it("reads an absent link as nil", function()
            route("POST", "/v1/manifests/build", 200, built_body({ link = cjson.null }))
            assert.is_nil(ok(client:build_manifest({ { address = "11" } })).link)
            local body = built_body()
            body.link = nil
            route("POST", "/v1/manifests/build", 200, body)
            assert.is_nil(ok(client:build_manifest({ { address = "11" } })).link)
        end)

        it("maps a 400 onto bad_request and keeps the daemon's message", function()
            local msg = "Bad request: 1 invalid entries: entries[0]: invalid path \"../x\": "
                .. "path component \"..\" is not allowed"
            route("POST", "/v1/manifests/build", 400, { error = msg, code = "BAD_REQUEST" })
            local err = refused(client:build_manifest({ { address = ADDR, path = "../x" } }))
            assert.are.equal(400, err.status_code)
            assert.are.equal(msg, err.message)
            assert.is_true(antd.is_antd_error(err))
        end)
    end)

    describe("base64", function()
        -- Every byte value, so a lossy or text-mode codec would show.
        local bytes = {}
        for b = 0, 255 do
            bytes[#bytes + 1] = string.char(b)
        end
        local all = table.concat(bytes)

        it("decodes the build response's manifest to raw bytes", function()
            for _, raw in ipairs({ all, all .. "x", all .. "xy", HEADER }) do
                route("POST", "/v1/manifests/build", 200, built_body({ manifest = base64.encode(raw) }))
                assert.are.equal(raw, ok(client:build_manifest({ { address = "11" } })).manifest)
            end
        end)

        it("sends decode_manifest's bytes as base64", function()
            ok(client:decode_manifest(HEADER))
            assert.are.equal(HEADER_B64, last_request().body.manifest)
            ok(client:decode_manifest(all))
            assert.are.equal(all, base64.decode(last_request().body.manifest))
        end)

        it("round-trips the built bytes through decode_manifest", function()
            route("POST", "/v1/manifests/build", 200, built_body({ manifest = base64.encode(all) }))
            local built = ok(client:build_manifest({ { address = "11" } }))
            ok(client:decode_manifest(built.manifest))
            assert.are.equal(base64.encode(all), last_request().body.manifest)
        end)

        it("treats a malformed manifest in the response as an internal error", function()
            for _, bad in ipairs({ "wUFOVAE", "wUFO!AE=", "wU=OVAE=", "====", 7 }) do
                route("POST", "/v1/manifests/build", 200, built_body({ manifest = bad }))
                local res, err = client:build_manifest({ { address = "11" } })
                if type(bad) == "string" then
                    assert.is_nil(res)
                    assert.are.equal("internal", err and err.type)
                else
                    -- A non-string manifest reads as empty, as antd-go's does.
                    assert.are.equal("", ok(res, err).manifest)
                end
            end
        end)
    end)

    describe("decode_manifest", function()
        it("sends the bytes and resolve, and reads the header and entries", function()
            local res = ok(client:decode_manifest(HEADER, true))
            local req = last_request()
            assert.are.equal("/v1/manifests/decode", req.path)
            assert.are.same({ manifest = HEADER_B64, resolve = true }, req.body)

            assert.are.equal(antd.ManifestSource.MANIFEST, res.source)
            assert.are.equal("album", res.name)
            assert.are.equal("bb", res.torrent_info_hash_v2)
            assert.is_nil(res.torrent_info_hash_v1)
            local a, b = res.entries[1], res.entries[2]
            assert.are.equal("abcd", a.data_map)
            assert.are.equal(3, a.exact_size)
            assert.is_nil(a.size)
            -- One entry's resolve failure is in its error, not a failed call.
            assert.are.equal("Record not found: gone", b.error)
            assert.is_nil(b.exact_size)
            assert.is_nil(b.data_map)
        end)

        it("sends resolve = false by default", function()
            ok(client:decode_manifest(HEADER))
            assert.is_false(last_request().body.resolve)
        end)

        it("refuses empty bytes and a non-boolean resolve before sending", function()
            refused(client:decode_manifest(""))
            refused(client:decode_manifest(nil))
            refused(client:decode_manifest(HEADER, "yes"))
            assert.are.equal(0, #requests)
        end)

        it("maps a 400 onto bad_request and keeps the daemon's message", function()
            local msg = "Bad request: not a manifest: missing or invalid header"
            route("POST", "/v1/manifests/decode", 400, { error = msg, code = "BAD_REQUEST" })
            local err = refused(client:decode_manifest("nope"))
            assert.are.equal(msg, err.message)
        end)
    end)

    describe("decode_manifest_link", function()
        it("sends the link and resolve, and no manifest bytes", function()
            ok(client:decode_manifest_link("ant://manifest/wUFOVAE", false))
            assert.are.same({ link = "ant://manifest/wUFOVAE", resolve = false }, last_request().body)
        end)

        it("reads a file link as one public entry with no path", function()
            route("POST", "/v1/manifests/decode", 200, {
                source = "file_link",
                entries = { { effective_name = ADDR, kind = "public", content_address = ADDR } },
            })
            local res = ok(client:decode_manifest_link(ADDR, true))
            assert.is_true(last_request().body.resolve)
            assert.are.equal(antd.ManifestSource.FILE_LINK, res.source)
            assert.is_nil(res.name)
            assert.are.equal(1, #res.entries)
            assert.is_nil(res.entries[1].path)
            assert.are.equal(ADDR, res.entries[1].content_address)
        end)

        it("refuses an empty link before sending", function()
            refused(client:decode_manifest_link(""))
            refused(client:decode_manifest_link(nil, true))
            refused(client:decode_manifest_link("ant://x", 1))
            assert.are.equal(0, #requests)
        end)
    end)

    it("is installed on clients made from antd.client directly", function()
        local Client = require("antd.client")
        local c = Client:new("http://localhost:8082")
        assert.are.equal("function", type(c.build_manifest))
        assert.are.equal("function", type(c.decode_manifest))
        assert.are.equal("function", type(c.decode_manifest_link))
        assert.are.equal(2 ^ 53, antd.MAX_MANIFEST_SIZE)
    end)
end)
