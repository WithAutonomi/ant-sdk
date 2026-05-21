--- Model constructors for the antd Lua SDK.
-- Each function returns a plain table representing the model.
-- @module antd.models

local M = {}

--- Payment-batching strategy for uploads.
--
-- * `AUTO`   — server picks (merkle for 64+ chunks, single otherwise).
-- * `MERKLE` — force merkle-batch (saves gas, min 2 chunks).
-- * `SINGLE` — force per-chunk payments (works for any chunk count).
--
-- The string values are the wire-format the daemon accepts.
M.PaymentMode = {
    AUTO = "auto",
    MERKLE = "merkle",
    SINGLE = "single",
}

--- Create a HealthStatus table.
--
-- The diagnostic fields (version, evm_network, uptime_seconds, build_commit,
-- payment_token_address, payment_vault_address) were added in antd 0.4.0.
-- The optional opts table populates them; missing keys default to "" / 0 so
-- the function stays backward-compatible with the original 2-arg call shape.
--
-- @param ok boolean daemon is healthy
-- @param network string network name
-- @param opts table optional diagnostic fields
-- @return table
function M.new_health_status(ok, network, opts)
    opts = opts or {}
    return {
        ok = ok,
        network = network,
        version = opts.version or "",
        evm_network = opts.evm_network or "",
        uptime_seconds = opts.uptime_seconds or 0,
        build_commit = opts.build_commit or "",
        payment_token_address = opts.payment_token_address or "",
        payment_vault_address = opts.payment_vault_address or "",
    }
end

--- Create a PutResult table (returned by chunk_put only).
-- @param cost string cost in atto tokens
-- @param address string hex address
-- @return table
function M.new_put_result(cost, address)
    return {
        cost = cost,
        address = address,
    }
end

--- Create a DataPutResult table.
-- Result of a private data put. The DataMap is returned to the caller;
-- it is NOT stored on-network.
-- @param data_map string hex-encoded caller-held DataMap
-- @param chunks_stored number number of chunks stored on the network
-- @param payment_mode_used string "auto", "merkle", or "single"
-- @return table
function M.new_data_put_result(data_map, chunks_stored, payment_mode_used)
    return {
        data_map = data_map,
        chunks_stored = chunks_stored or 0,
        payment_mode_used = payment_mode_used or "",
    }
end

--- Create a DataPutPublicResult table.
-- Result of a public data put. The DataMap is stored on-network as an extra
-- chunk; `address` is the shareable retrieval handle.
-- @param address string hex on-network DataMap address
-- @param chunks_stored number number of chunks stored on the network
-- @param payment_mode_used string "auto", "merkle", or "single"
-- @return table
function M.new_data_put_public_result(address, chunks_stored, payment_mode_used)
    return {
        address = address,
        chunks_stored = chunks_stored or 0,
        payment_mode_used = payment_mode_used or "",
    }
end

--- Create a FilePutResult table.
-- Result of a private file upload. The DataMap is returned to the caller;
-- it is NOT stored on-network.
-- @return table
function M.new_file_put_result(data_map, storage_cost_atto, gas_cost_wei, chunks_stored, payment_mode_used)
    return {
        data_map = data_map,
        storage_cost_atto = storage_cost_atto,
        gas_cost_wei = gas_cost_wei,
        chunks_stored = chunks_stored,
        payment_mode_used = payment_mode_used,
    }
end

--- Create a FilePutPublicResult table.
-- Result of a public file upload. The DataMap is stored on-network as an
-- extra chunk; `address` is the shareable retrieval handle.
-- @return table
function M.new_file_put_public_result(address, storage_cost_atto, gas_cost_wei, chunks_stored, payment_mode_used)
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

--- Create a PrepareChunkResult table.
-- @return table
function M.new_prepare_chunk_result(opts)
    opts = opts or {}
    return {
        address = opts.address or "",
        already_stored = opts.already_stored == true,
        upload_id = opts.upload_id or "",
        payment_type = opts.payment_type or "",
        payments = opts.payments or {},
        total_amount = opts.total_amount or "",
        payment_vault_address = opts.payment_vault_address or "",
        payment_token_address = opts.payment_token_address or "",
        rpc_url = opts.rpc_url or "",
    }
end

--- Create a FinalizeUploadResult table.
-- @return table
function M.new_finalize_upload_result(opts)
    opts = opts or {}
    return {
        address = opts.address or "",
        chunks_stored = opts.chunks_stored or 0,
        data_map = opts.data_map or "",
        data_map_address = opts.data_map_address or "",
    }
end

return M
