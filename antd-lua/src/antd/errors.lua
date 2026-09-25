--- Error types for the antd Lua SDK.
-- All errors are tables with type, status_code, and message fields.
-- @module antd.errors

local M = {}

--- Create a new antd error table.
-- @param err_type string error type name
-- @param status_code number HTTP status code
-- @param message string error message
-- @return table error object
local function new_error(err_type, status_code, message)
    return {
        type = err_type,
        status_code = status_code,
        message = message,
        __antd_error = true,
    }
end

--- Create a bad_request error (HTTP 400).
-- @param message string
-- @return table
function M.bad_request(message)
    return new_error("bad_request", 400, message)
end

--- Create a payment error (HTTP 402).
-- @param message string
-- @return table
function M.payment(message)
    return new_error("payment", 402, message)
end

--- Create a not_found error (HTTP 404).
-- @param message string
-- @return table
function M.not_found(message)
    return new_error("not_found", 404, message)
end

--- Create an already_exists error (HTTP 409).
-- @param message string
-- @return table
function M.already_exists(message)
    return new_error("already_exists", 409, message)
end

--- Create a fork error (HTTP 409).
-- @param message string
-- @return table
function M.fork(message)
    return new_error("fork", 409, message)
end

--- Create a too_large error (HTTP 413).
-- @param message string
-- @return table
function M.too_large(message)
    return new_error("too_large", 413, message)
end

--- Create an internal error (HTTP 500).
-- @param message string
-- @return table
function M.internal(message)
    return new_error("internal", 500, message)
end

--- Create a network error (HTTP 502).
-- @param message string
-- @return table
function M.network(message)
    return new_error("network", 502, message)
end

--- Create a service_unavailable error (HTTP 503).
-- @param message string
-- @return table
function M.service_unavailable(message)
    return new_error("service_unavailable", 503, message)
end

-- Exclusive upper bound for a PARTIAL_UPLOAD count (a u64 on the daemon
-- side). 2^64 is exactly representable as a double.
local COUNT_LIMIT = 2 ^ 64

--- Read one PARTIAL_UPLOAD count without coercion.
-- Only a Lua number (a JSON number once decoded) that is a finite,
-- non-negative integer below 2^64 is accepted; anything else reads as 0.
-- `tonumber` is deliberately avoided: it turns the strings "1", "0x10" and
-- " 1e3 " into 1, 16 and 1000.
-- @param v any decoded field value
-- @return number
local function count_field(v)
    if type(v) ~= "number" then
        return 0
    end
    -- v ~= v is NaN; v >= COUNT_LIMIT also rejects +inf, v < 0 rejects -inf.
    if v ~= v or v < 0 or v >= COUNT_LIMIT or v ~= math.floor(v) then
        return 0
    end
    if v == 0 then
        return 0 -- normalise -0
    end
    return v
end

--- Create a partial_upload error (HTTP 502, code PARTIAL_UPLOAD).
--
-- A finalize stored some chunks while others stayed unstored after the
-- daemon's own retries. The on-chain payment persists and the stored chunks
-- stay on the network. How to finish the upload depends on `retryable`:
--
--   * `retryable == true` — the daemon kept the paid attempt (payment proofs
--     + unstored chunks) under the same `upload_id`. Call the same finalize
--     method again with the same arguments to store the remainder against
--     the same payment: no re-prepare, no second signature, no double
--     payment. Bound the loop — a persistent failure returns this error on
--     every call, so cap the attempts and treat a `chunks_failed` that stops
--     shrinking as stuck. The retained attempt expires with the daemon's
--     pending-upload TTL. (antd >= 0.14.0; older daemons never send the
--     flag, so it reads false and the re-prepare path applies.)
--   * `retryable == false` — nothing was retained (a merkle finalize with
--     deliberately unpaid batches, or an older daemon). Re-preparing the
--     same content skips already-stored chunks, so a retry pays only for
--     the missing remainder.
--
-- See docs/external-signer-flow.md §6.
--
-- Fields are read strictly, never coerced. A count is taken only from a
-- JSON number that is a finite, non-negative integer below 2^64; anything
-- else (a quoted number such as "1", a boolean, a table, JSON null, or a
-- negative, fractional, NaN or infinite number) reads as 0. `retryable` is
-- true only for the JSON boolean `true`: a string "true" or the number 1
-- reads false. A malformed `fields` never raises.
--
-- @param message string
-- @param fields table|nil { chunks_stored, chunks_failed, total_chunks,
--   retryable } as decoded from the response body; absent or malformed
--   counts read as 0, an absent or malformed retryable reads as false
-- @return table
function M.partial_upload(message, fields)
    if type(fields) ~= "table" then
        fields = {}
    end
    local err = new_error("partial_upload", 502, message)
    err.chunks_stored = count_field(fields.chunks_stored)
    err.chunks_failed = count_field(fields.chunks_failed)
    err.total_chunks = count_field(fields.total_chunks)
    err.retryable = fields.retryable == true
    return err
end

--- Return the appropriate error for an HTTP status code.
-- @param code number HTTP status code
-- @param message string error message
-- @return table error object
function M.error_for_status(code, message)
    if code == 400 then return M.bad_request(message) end
    if code == 402 then return M.payment(message) end
    if code == 404 then return M.not_found(message) end
    if code == 409 then return M.already_exists(message) end
    if code == 413 then return M.too_large(message) end
    if code == 500 then return M.internal(message) end
    if code == 502 then return M.network(message) end
    if code == 503 then return M.service_unavailable(message) end
    return new_error("unknown", code, message)
end

--- Return the appropriate error for a REST error response, preferring the
-- machine-readable `code` over the bare HTTP status where they diverge.
-- PARTIAL_UPLOAD arrives as a 502 that would otherwise read as a generic
-- `network` error; every other code keeps the status-based mapping.
-- `code` must be the string "PARTIAL_UPLOAD" (Lua's `==` never coerces, so a
-- table, number, boolean or JSON null `code` keeps the status mapping), and
-- a `body` that is not a table does too.
-- @param code number HTTP status code
-- @param message string error message
-- @param body any decoded JSON error body (nil when not JSON)
-- @return table error object
function M.error_for_response(code, message, body)
    if type(body) == "table" and body.code == "PARTIAL_UPLOAD" then
        return M.partial_upload(message, body)
    end
    return M.error_for_status(code, message)
end

--- Check if a value is an antd error table.
-- @param err any value to check
-- @return boolean
function M.is_antd_error(err)
    return type(err) == "table" and err.__antd_error == true
end

--- Check if a value is a partial_upload error (see `partial_upload`).
-- @param err any value to check
-- @return boolean
function M.is_partial_upload(err)
    return M.is_antd_error(err) and err.type == "partial_upload"
end

return M
