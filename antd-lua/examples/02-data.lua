--- Example 02: Store and retrieve public data, with cost estimation.
--
-- Prerequisite: antd daemon running on local testnet.

local antd = require("antd")

local client = antd.new_client()

local payload = "Hello, Autonomi!"

-- Estimate cost before storing
local est, err1 = client:data_cost(payload)
if err1 then
    print("Cost error: " .. err1.message)
    os.exit(1)
end
print(string.format(
    "Estimate: %d bytes in %d chunks, storage %s atto, gas %s wei, mode %s",
    est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode
))

-- Store public data
local result, err2 = client:data_put_public(payload)
if err2 then
    print("Put error: " .. err2.message)
    os.exit(1)
end
print("Stored at address: " .. result.address)
print("Actual cost: " .. result.cost .. " atto tokens")

-- Retrieve it back
local retrieved, err3 = client:data_get_public(result.address)
if err3 then
    print("Get error: " .. err3.message)
    os.exit(1)
end
print("Retrieved: " .. retrieved)

assert(retrieved == payload, "Round-trip mismatch!")
print("Public data round-trip OK!")
