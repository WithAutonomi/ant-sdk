--- Example 09: Manifests — one `.ant` file and `ant://` link for a set of files.
--
-- Stores two pieces of public data, builds a manifest of them under
-- notes/one.txt and notes/two.txt, prints its link and entries, then decodes
-- the link with resolve to read each entry's exact size.
--
-- Prerequisite: an antd daemon with the manifest API on a local testnet.
--
--   lua examples/09-manifests.lua
--
-- ANTD_BASE_URL overrides the daemon URL (default http://localhost:8082).
--
-- The two uploads pay. Building and decoding the manifest upload and pay
-- for nothing.

local antd = require("antd")

local base_url = os.getenv("ANTD_BASE_URL")
if base_url == "" then
    base_url = nil
end
local client = antd.new_client(base_url)

--- Exit on an error, else return the value.
local function check(what, value, err)
    if err then
        print(string.format("%s error (%s): %s", what, err.type, tostring(err.message)))
        os.exit(1)
    end
    return value
end

--- A size for printing: nil (unset) reads as "unknown".
local function size_text(n)
    if n == nil then
        return "unknown"
    end
    return string.format("%.0f bytes", n)
end

-- 1. Two pieces of public data.
local one = check("Put", client:data_put_public("Manifest example, note one"))
local two = check("Put", client:data_put_public("Manifest example, note two, a little longer"))
print("Stored note one at " .. one.address)
print("Stored note two at " .. two.address)

-- 2. A manifest naming them. Each entry sets a data_map or an address.
local built = check("Build", client:build_manifest({
    { path = "notes/one.txt", address = one.address },
    { path = "notes/two.txt", address = two.address },
}, { name = "example" }))
print(string.format("Manifest: %d bytes", #built.manifest))
print("Link: " .. tostring(built.link))
for _, e in ipairs(built.entries) do
    print(string.format("  %s -> %s (%s)", e.effective_name, e.content_address, e.kind))
end

-- 3. Decode it with resolve, which fetches each DataMap for its exact size.
-- The link is nil when it would not fit 1,500 bytes; decode the bytes then.
local decoded
if built.link then
    decoded = check("Decode", client:decode_manifest_link(built.link, true))
else
    decoded = check("Decode", client:decode_manifest(built.manifest, true))
end
print(string.format("Decoded %s %q with %d entries:", decoded.source, tostring(decoded.name), #decoded.entries))
for _, e in ipairs(decoded.entries) do
    if e.error then
        print(string.format("  %s: %s", e.effective_name, e.error))
    else
        print(string.format("  %s: exact size %s", e.effective_name, size_text(e.exact_size)))
    end
end
print("Manifest round-trip OK!")
