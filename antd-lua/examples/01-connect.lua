--- Example: Connect to antd daemon and check health.

local antd = require("antd")

-- Create a client with default settings (localhost:8080)
local client = antd.new_client()

-- Check daemon health
local health, err = client:health()
if err then
    print("Error: " .. err.message)
    os.exit(1)
end

print("Daemon healthy: " .. tostring(health.ok))
print("Network: " .. health.network)
