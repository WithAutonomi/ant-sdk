--- Example: Store and retrieve private (encrypted) data.

local antd = require("antd")

local client = antd.new_client()

-- Store private data (encrypted on the network). The DataMap is returned to
-- the caller; it is NOT stored on-network.
local secret = "This is my private data"
local result, err = client:data_put(secret)
if err then
    print("Put error: " .. err.message)
    os.exit(1)
end

print("Private data stored")
print("Data map: " .. result.data_map)
print(string.format("Chunks: %d, mode: %s", result.chunks_stored, result.payment_mode_used))

-- Retrieve private data using the caller-held DataMap.
local retrieved, err2 = client:data_get(result.data_map)
if err2 then
    print("Get error: " .. err2.message)
    os.exit(1)
end

print("Retrieved: " .. retrieved)
