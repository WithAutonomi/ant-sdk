--- Example: Store and retrieve raw chunks.

local antd = require("antd")

local client = antd.new_client()

-- Store a chunk
local chunk_data = "Raw chunk content"
local result, err = client:chunk_put(chunk_data)
if err then
    print("Chunk put error: " .. err.message)
    os.exit(1)
end

print("Chunk stored at: " .. result.address)
print("Cost: " .. result.cost .. " atto")

-- Retrieve the chunk
local retrieved, err2 = client:chunk_get(result.address)
if err2 then
    print("Chunk get error: " .. err2.message)
    os.exit(1)
end

print("Retrieved chunk: " .. retrieved)
