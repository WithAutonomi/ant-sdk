--- Shell-safe process and validation helpers for 07-external-signer.lua.
--
-- Lua's standard library cannot start a process without a shell: io.popen
-- and os.execute both hand their string to `/bin/sh -c`. So the example
-- never splices a raw value into a command line. Every argument goes
-- through `shell_quote`, the command line is built only from quoted
-- arguments (`command_line`), and every value the daemon supplies (RPC URL,
-- contract and rewards addresses, amounts, quote hashes) is validated by
-- `validate_signing_request` before any process starts. The transaction
-- hash `cast` prints is validated too (`tx_hash_from_cast_json`).
--
-- Validation errors name the offending field, never its value, and process
-- errors name only the program, never its arguments (one of them is the
-- signing key).
--
-- POSIX sh only: cmd.exe does not use single-quote quoting.

local cjson = require("cjson")

local M = {}

--- Largest uint256, in decimal.
M.MAX_UINT256_DECIMAL =
    "115792089237316195423570985008687907853269984665640564039457584007913129639935"

--- Upper bound on the length of an accepted RPC URL.
M.MAX_RPC_URL_LENGTH = 2048

local ADDRESS_PATTERN = "^0x" .. string.rep("%x", 40) .. "$"
local BYTES32_HEX_PATTERN = "^" .. string.rep("%x", 64) .. "$"

-- ── Quoting and process execution ──

--- Quote one argument for POSIX sh.
-- Inside single quotes the shell treats every byte literally: no `$()`,
-- backticks, variables, globs, `;`, `|` or `&`. The single quote itself is
-- the only byte that needs handling; it becomes '\'' (close the quote, an
-- escaped quote, reopen). A NUL byte cannot be passed through a C string,
-- so it is rejected rather than silently truncating the argument.
-- @param s string argument
-- @return string the quoted argument
function M.shell_quote(s)
    if type(s) ~= "string" then
        error("shell_quote: argument must be a string, got " .. type(s), 2)
    end
    if s:find("\0", 1, true) then
        error("shell_quote: argument contains a NUL byte", 2)
    end
    return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

--- Build a sh command line from an argument vector, quoting every element.
-- @param argv table list of string arguments, program first
-- @return string
function M.command_line(argv)
    if type(argv) ~= "table" or #argv == 0 then
        error("command_line: argv must be a non-empty list", 2)
    end
    local parts = {}
    for i = 1, #argv do
        parts[i] = M.shell_quote(argv[i])
    end
    return table.concat(parts, " ")
end

--- Run an argument vector and return its stdout.
-- The exit status is appended by the shell as a final line (a fixed string,
-- no interpolation) because Lua 5.1 and LuaJIT do not report it from
-- io.popen's close. On a non-zero exit this raises an error that names only
-- the program, never its other arguments.
-- @param argv table list of string arguments, program first
-- @return string stdout of the command
function M.run_capture(argv)
    local cmd = M.command_line(argv) .. "; printf '\\n%s' \"$?\""
    local program = argv[1]
    local p = io.popen(cmd, "r")
    if not p then
        error(program .. ": failed to start", 2)
    end
    local out = p:read("*a") or ""
    p:close()
    local body, status = out:match("^(.*)\n(%d+)$")
    if not body then
        error(program .. ": exit status unavailable", 2)
    end
    if status ~= "0" then
        error(program .. " exited with status " .. status, 2)
    end
    return body
end

-- ── Validation ──

--- True when `v` is `0x` followed by exactly 40 hex digits.
function M.is_address(v)
    return type(v) == "string" and v:match(ADDRESS_PATTERN) ~= nil
end

--- True when `v` is a canonical decimal uint256: digits only, no sign, no
-- leading zero (other than "0" itself), at most 2^256 - 1.
function M.is_uint256_decimal(v)
    if type(v) ~= "string" or not v:match("^[0-9]+$") then
        return false
    end
    if #v > 1 and v:sub(1, 1) == "0" then
        return false
    end
    local max = M.MAX_UINT256_DECIMAL
    if #v ~= #max then
        return #v < #max
    end
    -- Same length, no leading zeros: digit order is numeric order. Compare
    -- bytes directly rather than with `<=`, which goes through strcoll.
    for i = 1, #v do
        local a, b = v:byte(i), max:byte(i)
        if a ~= b then
            return a < b
        end
    end
    return true
end

--- True when `v` is a 32-byte quote hash: 64 hex digits, optionally with a
-- `0x` prefix.
function M.is_quote_hash(v)
    if type(v) ~= "string" then
        return false
    end
    if v:sub(1, 2) == "0x" then
        v = v:sub(3)
    end
    return v:match(BYTES32_HEX_PATTERN) ~= nil
end

--- True when `v` is a bytes32 transaction hash: `0x` + 64 hex digits.
function M.is_tx_hash(v)
    return type(v) == "string" and v:sub(1, 2) == "0x"
        and v:sub(3):match(BYTES32_HEX_PATTERN) ~= nil
end

--- True when `v` is an http(s) URL of printable ASCII (no whitespace, no
-- control characters, nothing outside 0x21-0x7E) with a non-empty host
-- part, no longer than MAX_RPC_URL_LENGTH.
function M.is_rpc_url(v)
    if type(v) ~= "string" or #v > M.MAX_RPC_URL_LENGTH then
        return false
    end
    if v:find("[^!-~]") then
        return false
    end
    return v:match("^https?://[^/?#]") ~= nil
end

--- Validate every daemon-supplied value the signer passes to `cast`.
-- @param req table { rpc_url, payment_vault_address, payment_token_address,
--   payments = { { rewards_address, amount, quote_hash }, ... } }
-- @return true, or nil plus a message naming the invalid field (never its
--   value)
function M.validate_signing_request(req)
    if type(req) ~= "table" then
        return nil, "signing request must be a table"
    end
    if not M.is_rpc_url(req.rpc_url) then
        return nil, "rpc_url must be an http(s) URL of printable ASCII with no whitespace, "
            .. "at most " .. M.MAX_RPC_URL_LENGTH .. " bytes"
    end
    if not M.is_address(req.payment_vault_address) then
        return nil, "payment_vault_address must be 0x followed by 40 hex digits"
    end
    if not M.is_address(req.payment_token_address) then
        return nil, "payment_token_address must be 0x followed by 40 hex digits"
    end
    if type(req.payments) ~= "table" then
        return nil, "payments must be a list"
    end
    for i, p in ipairs(req.payments) do
        local where = "payments[" .. i .. "]"
        if type(p) ~= "table" then
            return nil, where .. " must be a table"
        end
        if not M.is_address(p.rewards_address) then
            return nil, where .. ".rewards_address must be 0x followed by 40 hex digits"
        end
        if not M.is_uint256_decimal(p.amount) then
            return nil, where .. ".amount must be a decimal uint256"
        end
        if not M.is_quote_hash(p.quote_hash) then
            return nil, where .. ".quote_hash must be 64 hex digits"
        end
    end
    return true
end

--- Extract and validate `transactionHash` from `cast send --json` output.
-- @param out string stdout of cast
-- @return string tx hash, or nil plus a message (never echoing the output)
function M.tx_hash_from_cast_json(out)
    local ok, receipt = pcall(cjson.decode, out)
    if not ok or type(receipt) ~= "table" then
        return nil, "cast did not print a JSON receipt"
    end
    if not M.is_tx_hash(receipt.transactionHash) then
        return nil, "cast receipt transactionHash is not 0x followed by 64 hex digits"
    end
    return receipt.transactionHash
end

return M
