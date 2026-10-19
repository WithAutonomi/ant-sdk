--- Example 08: Pointers — a mutable reference to public data.
--
-- Stores two pieces of public data, creates a pointer at the first, updates
-- it to the second, reads it back and asks the close group where it stands.
--
-- Prerequisite: an antd daemon with the pointer API on a local testnet,
-- started with --pointer-keys holding the owner key.
--
--   ANTD_POINTER_OWNER=<pointer address> lua examples/08-pointers.lua
--
-- ANTD_POINTER_OWNER is a pointer address the daemon holds a key for
-- (client:pointer_keys() lists them). ANTD_BASE_URL overrides the daemon URL
-- (default http://localhost:8082).
--
-- Every pointer write pays, about the price of one chunk, and every attempt
-- pays again: this example never retries a write.

local antd = require("antd")

local owner = os.getenv("ANTD_POINTER_OWNER")
if not owner or owner == "" then
    print("Set ANTD_POINTER_OWNER to a pointer address the daemon holds a key for.")
    os.exit(1)
end

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

-- 1. Two pieces of public data to point at.
local first = check("Put", client:data_put_public("Pointer target, version one"))
local second = check("Put", client:data_put_public("Pointer target, version two"))
print("Stored version one at " .. first.address)
print("Stored version two at " .. second.address)

-- 2. Create the pointer at the first. A pointer that already exists (from an
-- earlier run) is pointed at the first with an update instead.
local w, err = client:pointer_create(owner, first.address)
if err and err.type == "already_exists" then
    print("Pointer exists already; updating it to version one instead")
    w, err = client:pointer_update(owner, first.address)
end
w = check("Create", w, err)
print(string.format("Pointer %s -> version one (counter %s)", w.address, w.counter))

-- 3. Update it to the second. Counters are decimal strings: a final state
-- sits at 2^64-1, past what a Lua number holds exactly.
local u = check("Update", client:pointer_update(owner, second.address))
print(string.format("Pointer %s -> version two (counter %s)", u.address, u.counter))
local order = check("Compare", antd.compare_pointer_counters(u.counter, w.counter))
assert(order == 1, "the update's counter should be past the create's")

-- 4. Resolve and read it, then fetch the data through it.
local resolved = check("Resolve", client:pointer_resolve(owner))
local record = check("Get", client:pointer_get(owner))
print(string.format("Resolves to %s (%s); record counter %s, target %s, final %s",
    resolved.target, resolved.kind, record.counter, record.target, tostring(record.is_final)))
local data = check("Get data", client:data_get_public(resolved.target))
print("Data through the pointer: " .. data)
assert(data == "Pointer target, version two", "the pointer should lead to version two")

-- 5. Where the pointer stands, as its whole close group reports it.
local f = check("Finality", client:pointer_finality(owner))
print(string.format("Finality: %s, %d of %d close-group peers answered, counter %s",
    f.raw_status, f.answered, f.group, tostring(f.counter)))
print("Pointer round-trip OK!")
