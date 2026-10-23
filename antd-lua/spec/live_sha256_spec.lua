--- Live sha256 checks against a running antd (0.17.0 or later) on a devnet.
--
-- Pending (skipped) unless both are set:
--
--   ANTD_TEST_URL         the daemon's REST base URL, e.g. http://127.0.0.1:18084
--   ANTD_TEST_SHA_LINK    an ant://manifest/ link with entries public.txt and
--                         private.txt (each with a sha256) and nohash.txt (none)
--
-- and, read when set (the matching checks are pending without them):
--
--   ANTD_TEST_SHA_PUBLIC_ADDRESS      a public data address
--   ANTD_TEST_SHA_PUBLIC_SHA256       its plaintext's SHA-256 (hex)
--   ANTD_TEST_SHA_DATA_MAP_SHA256     the private entry's plaintext SHA-256 (hex)
--
-- The manifest checks pay for nothing. The last check makes ONE paid public
-- data upload of a small payload and compares the result's sha256 with one
-- computed here (it shells out to `sha256sum`, so it needs a POSIX shell).

local base_url = os.getenv("ANTD_TEST_URL")
local link = os.getenv("ANTD_TEST_SHA_LINK")

if not (base_url and base_url ~= "" and link and link ~= "") then
    describe("live sha256", function()
        pending("set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run")
    end)
    return
end

local function env(name)
    local v = os.getenv(name)
    if v == "" then return nil end
    return v
end

local public_address = env("ANTD_TEST_SHA_PUBLIC_ADDRESS")
local public_sha = env("ANTD_TEST_SHA_PUBLIC_SHA256")
local data_map_sha = env("ANTD_TEST_SHA_DATA_MAP_SHA256")

-- Load the SDK fresh, so no other spec's HTTP mock is in play.
for name in pairs(package.loaded) do
    if name == "antd" or name:find("^antd%.") then
        package.loaded[name] = nil
    end
end
local antd = require("antd")

--- The SHA-256 (lowercase hex) of `s`, through the system's sha256sum.
-- `s` must be shell-safe (letters, digits, spaces, '-', '_', '.').
local function local_sha256(s)
    assert(s:find("^[%w _%.%-]+$"), "payload is not shell-safe")
    local pipe = assert(io.popen("printf '%s' '" .. s .. "' | sha256sum", "r"))
    local out = pipe:read("*a")
    pipe:close()
    local hex = out:match("^(%x+)%s")
    assert(hex and #hex == 64, "sha256sum gave no digest: " .. tostring(out))
    return hex
end

describe("live sha256", function()
    local client = antd.new_client(base_url)

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

    it("decodes the fixture link with each entry's sha256", function()
        local m = ok(client:decode_manifest_link(link, false))
        local e = by_name(m)
        assert.is_table(e["public.txt"])
        assert.is_table(e["private.txt"])
        assert.is_table(e["nohash.txt"])
        if public_sha then
            assert.are.equal(public_sha, e["public.txt"].sha256)
        else
            assert.is_string(e["public.txt"].sha256)
        end
        if data_map_sha then
            assert.are.equal(data_map_sha, e["private.txt"].sha256)
        else
            assert.is_string(e["private.txt"].sha256)
        end
        assert.is_nil(e["nohash.txt"].sha256)
    end)

    it("builds a manifest entry carrying the sha256 it was given", function()
        if not (public_address and public_sha) then
            pending("set ANTD_TEST_SHA_PUBLIC_ADDRESS and ANTD_TEST_SHA_PUBLIC_SHA256")
            return
        end
        local built = ok(client:build_manifest({
            { path = "a.txt", address = public_address, sha256 = public_sha },
            { path = "b.txt", address = public_address },
        }))
        local e = by_name(built)
        assert.are.equal(public_sha, e["a.txt"].sha256)
        assert.is_nil(e["b.txt"].sha256)

        -- The hash survives a decode of the built manifest, too.
        local decoded = ok(client:decode_manifest(built.manifest, false))
        e = by_name(decoded)
        assert.are.equal(public_sha, e["a.txt"].sha256)
        assert.is_nil(e["b.txt"].sha256)
    end)

    it("refuses a malformed sha256 as bad_request", function()
        if not public_address then
            pending("set ANTD_TEST_SHA_PUBLIC_ADDRESS")
            return
        end
        local r, err = client:build_manifest({
            { path = "a.txt", address = public_address, sha256 = "zz" },
        })
        assert.is_nil(r)
        assert.are.equal("bad_request", err and err.type)
        assert.are.equal(400, err.status_code)
        assert.truthy(err.message:find("entries[0]", 1, true))
    end)

    it("returns the plaintext's sha256 from a public data upload (one paid call)", function()
        local payload = "sha-fanout lua " .. os.time()
        local want = local_sha256(payload)
        local result = ok(client:data_put_public(payload))
        assert.is_string(result.sha256)
        assert.are.equal(64, #result.sha256)
        assert.are.equal(want, result.sha256)
    end)
end)
