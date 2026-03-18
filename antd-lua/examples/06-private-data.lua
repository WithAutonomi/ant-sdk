--- Example: Store and retrieve private (encrypted) data.

local antd = require("antd")

local client = antd.new_client()

-- Store private data (encrypted on the network)
local secret = "This is my private data"
local result, err = client:data_put_private(secret)
if err then
    print("Put error: " .. err.message)
    os.exit(1)
end

print("Private data stored")
print("Data map: " .. result.address)
print("Cost: " .. result.cost .. " atto")

-- Retrieve private data using the data map
-- The data map is required to decrypt the data — keep it safe!
local retrieved, err2 = client:data_get_private(result.address)
if err2 then
    print("Get error: " .. err2.message)
    os.exit(1)
end

print("Retrieved: " .. retrieved)
