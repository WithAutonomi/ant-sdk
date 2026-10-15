--- Live manifest round trip against a running antd with a devnet behind it.
--
-- Pending (skipped) unless both are set:
--
--   ANTD_TEST_URL                   the daemon's REST base URL, e.g.
--                                   http://127.0.0.1:8082
--   ANTD_TEST_MANIFEST_ADDRESSES    two comma-separated addresses of public
--                                   data already uploaded
--
-- and, read when set:
--
--   ANTD_TEST_MANIFEST_SIZES        the two uploads' exact sizes, comma-separated
--   ANTD_TEST_MANIFEST_DATA_MAP     a private upload's DataMap (hex)
--   ANTD_TEST_MANIFEST_DATA_MAP_SIZE  its exact size
--   ANTD_TEST_MANIFEST_LINK         an ant://manifest/ link to decode
--
-- Nothing is uploaded or paid for: it only builds and decodes manifests of
-- data that is already on the network.

local base_url = os.getenv("ANTD_TEST_URL")
local addresses = os.getenv("ANTD_TEST_MANIFEST_ADDRESSES")
local first, second
if addresses then
    first, second = addresses:match("^%s*([^,%s]+)%s*,%s*([^,%s]+)%s*$")
end

if not (base_url and base_url ~= "" and first and second) then
    describe("live manifests", function()
        pending("set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run")
    end)
    return
end

local function env(name)
    local v = os.getenv(name)
    if v == "" then return nil end
    return v
end

local size1, size2
local sizes = env("ANTD_TEST_MANIFEST_SIZES")
if sizes then
    size1, size2 = sizes:match("^%s*(%d+)%s*,%s*(%d+)%s*$")
    size1, size2 = tonumber(size1), tonumber(size2)
end
local data_map = env("ANTD_TEST_MANIFEST_DATA_MAP")
local data_map_size = tonumber(env("ANTD_TEST_MANIFEST_DATA_MAP_SIZE") or "")
local fixture_link = env("ANTD_TEST_MANIFEST_LINK")

-- Load the SDK fresh, so no other spec's HTTP mock is in play.
for name in pairs(package.loaded) do
    if name == "antd" or name:find("^antd%.") then
        package.loaded[name] = nil
    end
end
local antd = require("antd")

describe("live manifests", function()
    local client = antd.new_client(base_url)
    local one, two = first:lower(), second:lower()

    local function ok(value, err)
        assert(err == nil, err and (err.type .. ": " .. tostring(err.message)))
        return value
    end

    local function by_name(m)
        local out = {}
        for _, e in ipairs(m.entries) do
            out[e.effective_name] = e
        end
        return out
    end

    --- Check a resolving decode of the manifest built below.
    local function check_resolved(m)
        assert.are.equal(antd.ManifestSource.MANIFEST, m.source)
        assert.are.equal("antd-lua", m.name)
        local e = by_name(m)
        local a, b = e["lua/one.txt"], e["lua/two.txt"]
        assert.are.equal(one, a.content_address)
        assert.are.equal(two, b.content_address)
        assert.is_nil(a.error)
        assert.is_nil(b.error)
        assert.is_nil(a.data_map)
        if size1 then
            assert.are.equal(size1, a.exact_size)
            assert.are.equal(size2, b.exact_size)
        else
            assert.is_number(a.exact_size)
            assert.is_number(b.exact_size)
        end
        if data_map then
            local p = e["lua/private.txt"]
            assert.are.equal(antd.ManifestEntryKind.EMBEDDED, p.kind)
            assert.is_string(p.data_map)
            assert.is_nil(p.error)
            if data_map_size then
                assert.are.equal(data_map_size, p.exact_size)
            end
        end
    end

    it("builds, decodes bytes and link, and refuses bad entries", function()
        local entries = {
            { path = "lua/one.txt", address = first, size = size1 },
            { path = "lua/two.txt", address = second },
        }
        if data_map then
            entries[#entries + 1] = { path = "lua/private.txt", data_map = data_map }
        end

        local built = ok(client:build_manifest(entries, { name = "antd-lua" }))
        assert(#built.manifest > 5, "the manifest should be more than its header")
        assert.are.equal("\193ANT\1", built.manifest:sub(1, 5))
        assert(built.link and built.link:find("^ant://manifest/"), "a small manifest should have a link")
        assert.are.equal(#entries, #built.entries)

        local e = by_name(built)
        local a, b = e["lua/one.txt"], e["lua/two.txt"]
        assert.are.equal(antd.ManifestEntryKind.PUBLIC, a.kind)
        assert.are.equal(antd.ManifestEntryKind.PUBLIC, b.kind)
        assert.are.equal("lua/one.txt", a.path)
        assert.are.equal(one, a.content_address)
        assert.are.equal(two, b.content_address)
        assert.are.equal(size1, a.size)
        -- No size given: none recorded, and a public entry knows no exact size.
        assert.is_nil(b.size)
        assert.is_nil(b.exact_size)
        if data_map then
            local p = e["lua/private.txt"]
            assert.are.equal(antd.ManifestEntryKind.EMBEDDED, p.kind)
            assert.are.equal(64, #p.content_address)
        end

        -- Without resolve, public entries have no exact size.
        local plain = ok(client:decode_manifest(built.manifest))
        assert.is_nil(by_name(plain)["lua/two.txt"].exact_size)

        check_resolved(ok(client:decode_manifest(built.manifest, true)))
        check_resolved(ok(client:decode_manifest_link(built.link, true)))

        -- A bare address reads as a file link: one public entry, no path.
        local fl = ok(client:decode_manifest_link(first, false))
        assert.are.equal(antd.ManifestSource.FILE_LINK, fl.source)
        assert.are.equal(1, #fl.entries)
        assert.is_nil(fl.entries[1].path)
        assert.are.equal(one, fl.entries[1].content_address)

        -- An address with nothing behind it: resolve fails for that entry
        -- alone, in its error, and the call succeeds.
        local gone = ok(client:decode_manifest_link(string.rep("ab", 32), true))
        assert.are.equal(1, #gone.entries)
        assert.is_string(gone.entries[1].error)
        assert.is_nil(gone.entries[1].exact_size)

        -- Both sources: refused before sending.
        local r, err = client:build_manifest({ { address = first, data_map = data_map or "aa" } })
        assert.is_nil(r)
        assert.are.equal("bad_request", err and err.type)

        -- A path the portable rules refuse: the daemon's 400, naming the entry.
        r, err = client:build_manifest({ { address = first }, { path = "../x", address = second } })
        assert.is_nil(r)
        assert.are.equal("bad_request", err and err.type)
        assert.are.equal(400, err.status_code)
        assert.truthy(err.message:find("entries[1]", 1, true))
    end)

    it("decodes the fixture link", function()
        if not fixture_link then
            pending("set ANTD_TEST_MANIFEST_LINK to decode a fixture link")
            return
        end
        local m = ok(client:decode_manifest_link(fixture_link, true))
        assert.are.equal(antd.ManifestSource.MANIFEST, m.source)
        local seen = {}
        for _, e in ipairs(m.entries) do
            assert.is_nil(e.error)
            assert.is_number(e.exact_size)
            seen[e.content_address] = e
        end
        assert(seen[one] and seen[two], "the fixture link should hold both addresses")
        if size1 then
            assert.are.equal(size1, seen[one].exact_size)
            assert.are.equal(size2, seen[two].exact_size)
        end
        if data_map then
            local embedded = 0
            for _, e in ipairs(m.entries) do
                if e.kind == antd.ManifestEntryKind.EMBEDDED then
                    embedded = embedded + 1
                    assert.is_string(e.data_map)
                    if data_map_size then
                        assert.are.equal(data_map_size, e.exact_size)
                    end
                end
            end
            assert.are.equal(1, embedded)
        end
    end)
end)
