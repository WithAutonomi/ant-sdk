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

local antd = require("antd")
local errors = require("antd.errors")
local cjson = require("cjson")
local socket = require("socket")

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

local function run_cmd(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

--- Run a command, returning its stdout. Fails loudly on a non-zero exit.
local function capture(cmd)
    local p = assert(io.popen(cmd, "r"))
    local out = p:read("*a")
    local ok, _, code = p:close()
    if not (ok == true or ok == 0 or code == 0) then
        error("command failed: " .. cmd .. "\n" .. tostring(out))
    end
    return out
end

--- Run approve + payForQuotes on-chain for a daemon prepare response via
-- `cast send`. Returns the quote_hash -> tx_hash map the finalize_* methods
-- expect. Every entry maps to the same payForQuotes tx because every quote
-- in the wave is paid in one batched call.
local function external_signer_pay(rpc_url, vault_addr, token_addr, payments)
    -- No on-chain work when every quoted chunk is already on-network.
    if #payments == 0 then
        return {}
    end

    -- Idempotent unlimited approval so subsequent runs in the same devnet
    -- session skip a fresh approve.
    capture(string.format(
        "cast send %s 'approve(address,uint256)' %s %s --rpc-url %s --private-key %s --gas-limit 500000 --json",
        token_addr, vault_addr, MAX_UINT256, rpc_url, ANVIL_KEY))

    -- payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])
    local tuples = {}
    for i, p in ipairs(payments) do
        local qh = p.quote_hash:gsub("^0x", "")
        tuples[i] = string.format("(%s,%s,0x%s)", p.rewards_address, p.amount, qh)
    end
    local pay_json = capture(string.format(
        "cast send %s 'payForQuotes((address,uint256,bytes32)[])' '[%s]' "
            .. "--rpc-url %s --private-key %s --gas-limit 1000000 --json",
        vault_addr, table.concat(tuples, ","), rpc_url, ANVIL_KEY))
    local tx_hash = cjson.decode(pay_json).transactionHash

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
-- stops shrinking as stuck. A non-retryable partial upload (older daemon, or
-- a merkle upload with unpaid batches) is returned untouched: the recovery
-- there is to re-prepare the same content, which skips the chunks already
-- stored.
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
        if not errors.is_partial_upload(err) or not err.retryable then
            return nil, err
        end
        local stuck = last_failed ~= nil and err.chunks_failed >= last_failed
        if attempt >= max_attempts or stuck then
            err.message = string.format(
                "finalize stuck after %d attempt(s): %d/%d chunks stored, %d still unstored "
                    .. "(paid attempt retained under upload_id %s — retry later or re-prepare): %s",
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
run_cmd("rm -rf " .. tmp)
assert(run_cmd("mkdir -p " .. tmp))

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
        print(string.format("  %d/%d chunks stored, %d unstored, retryable=%s",
            err2.chunks_stored, err2.total_chunks, err2.chunks_failed, tostring(err2.retryable)))
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
    run_cmd("rm -rf " .. tmp)
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
    run_cmd("rm -rf " .. tmp)
    print("chunk round-trip mismatch")
    os.exit(1)
end
print("Chunk round-trip OK!")

run_cmd("rm -rf " .. tmp)
print("\n07-external-signer OK!\n")
