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

--- Create a FileUploadResult table.
-- Returned by file_upload_public and dir_upload_public.
-- @param address string hex network address
-- @param storage_cost_atto string storage cost in atto, "0" if all chunks already existed
-- @param gas_cost_wei string gas cost in wei as decimal string
-- @param chunks_stored number number of chunks stored on the network (uint64)
-- @param payment_mode_used string "auto", "merkle", or "single"
-- @return table
function M.new_file_upload_result(address, storage_cost_atto, gas_cost_wei, chunks_stored, payment_mode_used)
    return {
        address = address,
        storage_cost_atto = storage_cost_atto,
        gas_cost_wei = gas_cost_wei,
        chunks_stored = chunks_stored,
        payment_mode_used = payment_mode_used,
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
