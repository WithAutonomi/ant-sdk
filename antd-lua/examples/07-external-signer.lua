--- Example 07: External-signer flow — public file + single-chunk publish.
--
-- prepare_upload_public / finalize_upload and prepare_chunk_upload /
-- finalize_chunk_upload let the wallet key stay outside the antd daemon.
-- This example uses anvil deterministic account #0 as the external signer
-- and exercises both round-trips end-to-end, retrying a partial finalize
-- against the same payment when the daemon kept the paid attempt.
--
-- See docs/external-signer-flow.md for the full reference. Lua has no
-- first-party EVM library that handles EIP-1559 + tuple ABI encoding +
-- secp256k1 signing, so this example shells out to `cast` (foundry CLI),
-- which `ant dev start --enable-evm` already depends on.
--
-- The values passed to `cast` come from the daemon's prepare response, and
-- Lua can only start a process through `/bin/sh -c`. external_signer_util
-- (next to this file) validates every one of them before any process starts
-- and shell-quotes every argument, so none of them can run as shell syntax.

local antd = require("antd")
local errors = require("antd.errors")
local socket = require("socket")

-- external_signer_util.lua sits next to this file; find it from any cwd.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
package.path = here .. "?.lua;" .. package.path
local signer_util = require("external_signer_util")

local client = antd.new_client()

-- Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
-- (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
-- use this key anywhere except a throw-away local devnet.
local ANVIL_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
local MAX_UINT256 = "0x" .. string.rep("f", 64)

local function write_file(path, content)
    local f = assert(io.open(path, "wb"))
    f:write(content)
    f:close()
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local content = f:read("*a")
    f:close()
    return content
end

--- Run a fixed local command (argument vector, each element shell-quoted).
local function run_cmd(argv)
    local ok = os.execute(signer_util.command_line(argv))
    return ok == true or ok == 0
end

--- Run approve + payForQuotes on-chain for a daemon prepare response via
-- `cast send`. Returns the quote_hash -> tx_hash map the finalize_* methods
-- expect. Every entry maps to the same payForQuotes tx because every quote
-- in the wave is paid in one batched call.
--
-- Every argument below except the fixed strings and the key comes from the
-- daemon, so the whole request is validated before any process starts, and
-- `cast` runs from an argument vector with each element shell-quoted.
-- Errors name the offending field or the program, never a value or the key.
local function external_signer_pay(rpc_url, vault_addr, token_addr, payments)
    -- No on-chain work when every quoted chunk is already on-network.
    if #payments == 0 then
        return {}
    end

    local valid, why = signer_util.validate_signing_request({
        rpc_url = rpc_url,
        payment_vault_address = vault_addr,
        payment_token_address = token_addr,
        payments = payments,
    })
    if not valid then
        error("refusing to sign the daemon's payment request: " .. why, 0)
    end

    --- `cast send <args...> --rpc-url <url> --private-key <key> --json`,
    -- returning the validated transaction hash from the receipt.
    local function cast_send(args)
        local argv = { "cast", "send" }
        for _, a in ipairs(args) do
            argv[#argv + 1] = a
        end
        for _, a in ipairs({ "--rpc-url", rpc_url, "--private-key", ANVIL_KEY, "--json" }) do
            argv[#argv + 1] = a
        end
        local tx_hash, err = signer_util.tx_hash_from_cast_json(signer_util.run_capture(argv))
        if not tx_hash then
            error(err, 0)
        end
        return tx_hash
    end

    -- Idempotent unlimited approval so subsequent runs in the same devnet
    -- session skip a fresh approve.
    cast_send({ token_addr, "approve(address,uint256)", vault_addr, MAX_UINT256,
        "--gas-limit", "500000" })

    -- payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])
    -- The tuple list is one argument, built only from validated values.
    local tuples = {}
    for i, p in ipairs(payments) do
        local qh = p.quote_hash:gsub("^0x", "")
        tuples[i] = string.format("(%s,%s,0x%s)", p.rewards_address, p.amount, qh)
    end
    local tx_hash = cast_send({ vault_addr, "payForQuotes((address,uint256,bytes32)[])",
        "[" .. table.concat(tuples, ",") .. "]", "--gas-limit", "1000000" })

    local tx_hashes = {}
    for _, p in ipairs(payments) do
        tx_hashes[p.quote_hash] = tx_hash
    end
    return tx_hashes
end

--- Finalize a wave-batch upload and, when the daemon reports a storage
-- shortfall AFTER the payment settled, retry the same call against the same
-- payment. antd >= 0.14.0 keeps the paid attempt (payment proofs + unstored
-- chunks) under the same upload_id and flags the error `retryable`, so
-- repeating finalize_upload stores only the remainder: no re-prepare, no
-- second signature, no double payment.
--
-- The loop is bounded: a persistent failure (a chunk whose close group stays
-- unreachable) returns a partial_upload error on every call, never a
-- different error, so it caps the attempts and treats a chunks_failed that
-- stops shrinking as stuck.
--
-- A partial upload that is not retryable is one of two cases:
--   * retention_known but not retryable: the daemon confirmed nothing was
--     retained (a merkle upload with unpaid batches). The error is returned
--     untouched; the recovery is to re-prepare the same content, which skips
--     the chunks already stored.
--   * not retention_known: the error did not say whether the paid attempt
--     was kept (a daemon older than 0.14.0, or a body the SDK could not
--     read), and the daemon may still hold it. The helper stops without
--     retrying, re-preparing or paying: keep the upload_id and tx hashes and
--     reconcile before re-preparing or paying again.
--
-- @return table|nil result, table|nil err
local function finalize_with_retry(cli, upload_id, tx_hashes)
    local max_attempts = 5
    local last_failed = nil
    local attempt = 1
    while true do
        local result, err = cli:finalize_upload(upload_id, tx_hashes)
        if not err then
            return result, nil -- every chunk stored
        end
        if not errors.is_partial_upload(err) then
            return nil, err
        end
        if not err.retention_known then
            -- Unknown retention: never re-prepare or pay again on this alone.
            err.message = string.format(
                "finalize stopped: retention of the paid attempt is unknown (%d/%d chunks stored). "
                    .. "The daemon may still hold it under upload_id %s: keep the upload_id and tx "
                    .. "hashes and reconcile before re-preparing or paying again: %s",
                err.chunks_stored, err.total_chunks, upload_id, err.message)
            return nil, err
        end
        if not err.retryable then
            return nil, err -- confirmed not retained: the caller re-prepares
        end
        local stuck = last_failed ~= nil and err.chunks_failed >= last_failed
        if attempt >= max_attempts or stuck then
            err.message = string.format(
                "finalize stuck after %d attempt(s): %d/%d chunks stored, %d still unstored "
                    .. "(paid attempt retained under upload_id %s: retry the same finalize later; "
                    .. "re-preparing now would pay again): %s",
                attempt, err.chunks_stored, err.total_chunks, err.chunks_failed, upload_id, err.message)
            return nil, err
        end
        last_failed = err.chunks_failed
        print(string.format(
            "finalize stored %d/%d chunks, %d still unstored — retrying against the same payment (attempt %d/%d)",
            err.chunks_stored, err.total_chunks, err.chunks_failed, attempt + 1, max_attempts))
        socket.sleep(attempt * 2)
        attempt = attempt + 1
    end
end

local tmp = "/tmp/antd-lua-07-extsig"
run_cmd({ "rm", "-rf", tmp })
assert(run_cmd({ "mkdir", "-p", tmp }))

-- --- 1. file upload via external signer ---------------------------
local src_file = tmp .. "/file.bin"
local file_content = string.rep("hello external signer from lua (file)\n", 16)
write_file(src_file, file_content)

local file_prep, err = client:prepare_upload_public(src_file)
if err then
    print("Prepare error: " .. err.message)
    os.exit(1)
end
print(string.format("File prepare: upload_id=%s..., payment_type=%s, payments=%d, total_amount=%s",
    file_prep.upload_id:sub(1, 16), file_prep.payment_type, #file_prep.payments, file_prep.total_amount))

local file_tx_hashes = external_signer_pay(file_prep.rpc_url,
    file_prep.payment_vault_address, file_prep.payment_token_address, file_prep.payments)

local file_fin, err2 = finalize_with_retry(client, file_prep.upload_id, file_tx_hashes)
if err2 then
    print("Finalize error: " .. err2.message)
    if errors.is_partial_upload(err2) then
        print(string.format("  %d/%d chunks stored, %d unstored, retryable=%s, retention_known=%s",
            err2.chunks_stored, err2.total_chunks, err2.chunks_failed, tostring(err2.retryable),
            tostring(err2.retention_known)))
    end
    os.exit(1)
end
print(string.format("File finalize: data_map_address=%s, chunks_stored=%d",
    file_fin.data_map_address, file_fin.chunks_stored))

local dst_file = src_file .. ".downloaded"
local _, err3 = client:file_get_public(file_fin.data_map_address, dst_file)
if err3 then
    print("Download error: " .. err3.message)
    os.exit(1)
end
if read_file(dst_file) ~= file_content then
    run_cmd({ "rm", "-rf", tmp })
    print("file round-trip mismatch")
    os.exit(1)
end
print("File round-trip OK!")

-- --- 2. single-chunk publish via external signer ------------------
local chunk_data = string.rep("hello external signer from lua (chunk)\n", 8)
local chunk_prep, err4 = client:prepare_chunk_upload(chunk_data)
if err4 then
    print("Chunk prepare error: " .. err4.message)
    os.exit(1)
end

if chunk_prep.already_stored then
    print("Chunk prepare: already_stored, address=" .. chunk_prep.address)
else
    print(string.format("Chunk prepare: upload_id=%s..., address=%s, payments=%d, total_amount=%s",
        chunk_prep.upload_id:sub(1, 16), chunk_prep.address, #chunk_prep.payments, chunk_prep.total_amount))

    local chunk_tx_hashes = external_signer_pay(chunk_prep.rpc_url,
        chunk_prep.payment_vault_address, chunk_prep.payment_token_address, chunk_prep.payments)

    local chunk_addr, err5 = client:finalize_chunk_upload(chunk_prep.upload_id, chunk_tx_hashes)
    if err5 then
        print("Chunk finalize error: " .. err5.message)
        os.exit(1)
    end
    print("Chunk finalize: address=" .. chunk_addr)
end

local retrieved, err6 = client:chunk_get(chunk_prep.address)
if err6 then
    print("Chunk get error: " .. err6.message)
    os.exit(1)
end
if retrieved ~= chunk_data then
    run_cmd({ "rm", "-rf", tmp })
    print("chunk round-trip mismatch")
    os.exit(1)
end
print("Chunk round-trip OK!")

run_cmd({ "rm", "-rf", tmp })
print("\n07-external-signer OK!\n")
