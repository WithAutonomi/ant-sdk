--- Example: Store and retrieve public data.

local antd = require("antd")

local client = antd.new_client()

-- Store public data
local data = "Hello, Autonomi!"
local result, err = client:data_put_public(data)
if err then
    print("Put error: " .. err.message)
    os.exit(1)
end

print("Stored at: " .. result.address)
print("Cost: " .. result.cost .. " atto")

-- Retrieve it back
local retrieved, err2 = client:data_get_public(result.address)
if err2 then
    print("Get error: " .. err2.message)
    os.exit(1)
end

print("Retrieved: " .. retrieved)

-- Estimate cost before storing
local cost, err3 = client:data_cost("Some data to estimate")
if err3 then
    print("Cost error: " .. err3.message)
    os.exit(1)
end

print("Estimated cost: " .. cost .. " atto")
