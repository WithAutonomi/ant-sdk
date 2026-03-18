--- Example: Create and read graph entries (DAG nodes).

local antd = require("antd")

local client = antd.new_client()

-- Create a graph entry
local result, err = client:graph_entry_put(
    "your_secret_key_hex",
    {},  -- no parents (root node)
    "content_hash_hex",
    {}   -- no descendants
)
if err then
    print("Graph put error: " .. err.message)
    os.exit(1)
end

print("Graph entry at: " .. result.address)
print("Cost: " .. result.cost .. " atto")

-- Read the graph entry back
local entry, err2 = client:graph_entry_get(result.address)
if err2 then
    print("Graph get error: " .. err2.message)
    os.exit(1)
end

print("Owner: " .. entry.owner)
print("Content: " .. entry.content)
print("Parents: " .. #entry.parents)
print("Descendants: " .. #entry.descendants)

-- Check if it exists
local exists, err3 = client:graph_entry_exists(result.address)
if err3 then
    print("Exists error: " .. err3.message)
    os.exit(1)
end

print("Exists: " .. tostring(exists))

-- Estimate creation cost
local cost, err4 = client:graph_entry_cost("your_public_key_hex")
if err4 then
    print("Cost error: " .. err4.message)
    os.exit(1)
end

print("Estimated cost: " .. cost .. " atto")
