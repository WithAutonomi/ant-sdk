--- Model constructors for the antd Lua SDK.
-- Each function returns a plain table representing the model.
-- @module antd.models

local M = {}

--- An optional SHA-256 hex string: the string when it is a non-empty string,
-- else nil (absent, JSON null and "" all mean none; never "").
local function opt_sha256(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

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
-- @param sha256 string|nil the plaintext's SHA-256 (hex); nil on antd < 0.17.0
-- @return table
function M.new_data_put_result(data_map, chunks_stored, payment_mode_used, sha256)
    return {
        data_map = data_map,
        chunks_stored = chunks_stored or 0,
        payment_mode_used = payment_mode_used or "",
        sha256 = opt_sha256(sha256),
    }
end

--- Create a DataPutPublicResult table.
-- Result of a public data put. The DataMap is stored on-network as an extra
-- chunk; `address` is the shareable retrieval handle.
-- @param address string hex on-network DataMap address
-- @param chunks_stored number number of chunks stored on the network
-- @param payment_mode_used string "auto", "merkle", or "single"
-- @param sha256 string|nil the plaintext's SHA-256 (hex); nil on antd < 0.17.0
-- @return table
function M.new_data_put_public_result(address, chunks_stored, payment_mode_used, sha256)
    return {
        address = address,
        chunks_stored = chunks_stored or 0,
        payment_mode_used = payment_mode_used or "",
        sha256 = opt_sha256(sha256),
    }
end

--- Create a FilePutResult table.
-- Result of a private file upload. The DataMap is returned to the caller;
-- it is NOT stored on-network.
-- @param sha256 string|nil the plaintext's SHA-256 (hex); nil on antd < 0.17.0
-- @return table
function M.new_file_put_result(data_map, storage_cost_atto, gas_cost_wei, chunks_stored, payment_mode_used, sha256)
    return {
        data_map = data_map,
        storage_cost_atto = storage_cost_atto,
        gas_cost_wei = gas_cost_wei,
        chunks_stored = chunks_stored,
        payment_mode_used = payment_mode_used,
        sha256 = opt_sha256(sha256),
    }
end

--- Create a FilePutPublicResult table.
-- Result of a public file upload. The DataMap is stored on-network as an
-- extra chunk; `address` is the shareable retrieval handle.
-- @param sha256 string|nil the plaintext's SHA-256 (hex); nil on antd < 0.17.0
-- @return table
function M.new_file_put_public_result(address, storage_cost_atto, gas_cost_wei, chunks_stored,
                                      payment_mode_used, sha256)
    return {
        address = address,
        storage_cost_atto = storage_cost_atto,
        gas_cost_wei = gas_cost_wei,
        chunks_stored = chunks_stored,
        payment_mode_used = payment_mode_used,
        sha256 = opt_sha256(sha256),
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
        sha256 = opt_sha256(opts.sha256),
    }
end

-- ── Pointers (ADR-0016 / ADR-0018 in ant-node) ──
--
-- A pointer is a small, owner-signed, mutable reference. Its address is
-- derived from the owner's key and never changes; its target (a chunk, such
-- as a public file's data map, or another pointer) can be changed by the
-- owner. antd signs with owner keys it loaded at startup (`--pointer-keys`),
-- so a write names the pointer by its address (`owner`), never by a key.
--
-- Counters are decimal strings, never Lua numbers. A final state (after a
-- transfer or a freeze) sits at 2^64-1, and a Lua number cannot hold that:
-- LuaJIT and Lua 5.1 numbers are IEEE-754 doubles, exact only up to 2^53,
-- and Lua 5.4 integers are signed 64-bit. The daemon sends counters as
-- strings for the same reason. The SDK checks each one (digits only, at most
-- 2^64-1), drops leading zeros so equal counters compare equal as strings,
-- and treats anything else as an error rather than a zero. Compare counters
-- with `compare_pointer_counters`, not with `<` on the strings.

--- What a pointer's target is. The string values are the wire format.
--
-- * `CHUNK`   — an immutable chunk, such as a public file's data map. The
--               daemon's default when no kind is sent.
-- * `POINTER` — another pointer: a forwarding the owner can still change.
--               Use a transfer to hand a pointer over for good.
M.PointerKind = {
    CHUNK = "chunk",
    POINTER = "pointer",
}

--- The write a pointer prepare signs. The string values are the wire format.
M.PointerOp = {
    CREATE = "create",
    UPDATE = "update",
    TRANSFER = "transfer",
}

--- Where a pointer stands with respect to finality, as its close group
-- reports it (`status` of a finality table).
--
-- * `OPEN`        — no peer that answered holds a final state: the owner can
--                   still move the pointer.
-- * `SETTLING`    — one final state, not yet held by a majority.
-- * `UNCONFIRMED` — one final state held by a majority, but not every peer
--                   answered, so a rival could still be unseen. Ask again.
-- * `FINAL`       — one final state held by a majority, every peer answered,
--                   no rival. The only status a recipient should rely on.
-- * `FORKED`      — the owner signed two or more different final states.
-- * `UNKNOWN`     — a status this SDK does not know (a newer daemon); the
--                   wire value is in the table's `raw_status`.
M.PointerFinalityStatus = {
    OPEN = "open",
    SETTLING = "settling",
    UNCONFIRMED = "unconfirmed",
    FINAL = "final",
    FORKED = "forked",
    UNKNOWN = "unknown",
}

local KNOWN_FINALITY_STATUS = {
    open = true,
    settling = true,
    unconfirmed = true,
    final = true,
    forked = true,
}

--- Map the daemon's finality status string onto `PointerFinalityStatus`:
-- a known status is returned as is, anything else reads as "unknown".
-- @param raw any the wire `status`
-- @return string
function M.pointer_finality_status(raw)
    if type(raw) == "string" and KNOWN_FINALITY_STATUS[raw] then
        return raw
    end
    return M.PointerFinalityStatus.UNKNOWN
end

--- The counter of a pointer's final state (2^64-1), after a transfer or a
-- freeze: nothing can replace it.
M.POINTER_FINAL_COUNTER = "18446744073709551615"

--- Compare two canonical digit strings of the same length byte by byte.
-- (`<` on strings goes through strcoll, which is locale-dependent.)
local function compare_same_length(a, b)
    for i = 1, #a do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

--- Check and canonicalise a pointer counter.
--
-- Accepts only a string of ASCII digits whose value is at most 2^64-1, and
-- returns it without leading zeros ("0" stays "0"). Anything else (a Lua
-- number, a sign, whitespace, a fraction, an exponent, hex, an empty string,
-- or a value past 2^64-1) returns nil and a reason.
-- @param s any value to check
-- @return string|nil canonical counter, string|nil reason
function M.parse_pointer_counter(s)
    if type(s) ~= "string" then
        return nil, "expected a decimal string, got a " .. type(s)
    end
    if not s:find("^[0-9]+$") then
        return nil, string.format("%q is not a decimal counter", s)
    end
    local canonical = s:gsub("^0+", "")
    if canonical == "" then
        canonical = "0"
    end
    local max = M.POINTER_FINAL_COUNTER
    if #canonical > #max or (#canonical == #max and compare_same_length(canonical, max) > 0) then
        return nil, string.format("%q is past the largest counter, 2^64-1", s)
    end
    return canonical, nil
end

--- Compare two pointer counters (decimal strings) by value.
-- Lua numbers cannot hold every counter, so the comparison runs on the
-- digits: a shorter canonical string is smaller, and equal lengths compare
-- digit by digit.
-- @param a string counter
-- @param b string counter
-- @return number|nil -1, 0 or 1; nil and a reason if either is not a counter
function M.compare_pointer_counters(a, b)
    local ca, why_a = M.parse_pointer_counter(a)
    if not ca then
        return nil, "first counter: " .. why_a
    end
    local cb, why_b = M.parse_pointer_counter(b)
    if not cb then
        return nil, "second counter: " .. why_b
    end
    if #ca ~= #cb then
        return #ca < #cb and -1 or 1
    end
    return compare_same_length(ca, cb)
end

--- Normalise a pointer, chunk or state address for comparison: drops a
-- leading `0x` / `0X` and lowercases the hex. The daemon accepts the prefix
-- but always returns bare lowercase hex, so compare normalised values.
-- @param address string
-- @return string|nil normalised address; nil when `address` is not a string
function M.normalize_address(address)
    if type(address) ~= "string" then
        return nil
    end
    return (address:gsub("^0[xX]", "")):lower()
end

--- Build a pointer prepare op that creates the pointer at `target`.
-- Refused if the pointer already exists.
-- @param target string address to point at
-- @param kind string|nil PointerKind (nil leaves the daemon's default, chunk)
-- @return table
function M.pointer_create_op(target, kind)
    return { op = M.PointerOp.CREATE, target = target, kind = kind }
end

--- Build a pointer prepare op that points the pointer at `target`, creating
-- it if it does not exist.
-- @param target string address to point at
-- @param kind string|nil PointerKind (nil leaves the daemon's default, chunk)
-- @return table
function M.pointer_update_op(target, kind)
    return { op = M.PointerOp.UPDATE, target = target, kind = kind }
end

--- Build a pointer prepare op that hands the pointer over for good to the
-- pointer at `recipient`, which must already exist. Irreversible once stored.
-- @param recipient string address of the recipient's pointer
-- @return table
function M.pointer_transfer_op(recipient)
    return { op = M.PointerOp.TRANSFER, recipient = recipient }
end

return M
