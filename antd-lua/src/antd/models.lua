--- Model constructors for the antd Lua SDK.
-- Each function returns a plain table representing the model.
-- @module antd.models

local M = {}

--- Create a HealthStatus table.
-- @param ok boolean daemon is healthy
-- @param network string network name
-- @return table
function M.new_health_status(ok, network)
    return {
        ok = ok,
        network = network,
    }
end

--- Create a PutResult table.
-- @param cost string cost in atto tokens
-- @param address string hex address or data map
-- @return table
function M.new_put_result(cost, address)
    return {
        cost = cost,
        address = address,
    }
end

--- Create a WalletAddress table.
-- @param address string wallet address (e.g. "0x...")
-- @return table
function M.new_wallet_address(address)
    return {
        address = address,
    }
end

--- Create a WalletBalance table.
-- @param balance string token balance in atto tokens
-- @param gas_balance string gas balance in atto tokens
-- @return table
function M.new_wallet_balance(balance, gas_balance)
    return {
        balance = balance,
        gas_balance = gas_balance,
    }
end

return M
