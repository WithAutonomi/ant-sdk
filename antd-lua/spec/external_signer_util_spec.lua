--- Tests for examples/external_signer_util.lua, the shell-quoting and
-- validation helpers behind examples/07-external-signer.lua.
-- Needs a POSIX /bin/sh with printf and touch; does not need `cast`.

local spec_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
package.path = spec_dir .. "../examples/?.lua;" .. package.path

local util = require("external_signer_util")

-- Arguments that would run, split, expand or glob if they ever reached the
-- shell unquoted or double-quoted.
local HOSTILE = {
    "$(printf X)",
    "`printf X`",
    "a;printf X",
    "a && printf X",
    "a || printf X",
    "a | printf X",
    "a & printf X",
    "it's",
    "'",
    "''",
    "'\\''",
    '"double"',
    '"',
    "sp ace",
    "  leading and trailing  ",
    "tab\there",
    "new\nline",
    "*",
    "?",
    "[a-z]*",
    "~",
    "~root",
    "$HOME",
    "${HOME}",
    "$((6*7))",
    "\\",
    "back\\slash\\n",
    "!",
    "#not a comment",
    "a>b",
    "a<b",
    "{a,b}",
    "",
    "-n",
    "--",
    "https://rpc.invalid/$(printf HERMES_SUBSTITUTED)",
}

local function printf_argv(args)
    local argv = { "printf", "%s\\n" }
    for _, a in ipairs(args) do
        argv[#argv + 1] = a
    end
    return argv
end

local function expected_printf_output(args)
    return table.concat(args, "\n") .. "\n"
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function fresh_canary()
    -- os.tmpname creates the file on some platforms; remove it so only a
    -- command that ran can bring it back.
    local path = os.tmpname()
    os.remove(path)
    assert.is_false(exists(path))
    return path
end

local function hex(n)
    return string.rep("a1B2", n / 4)
end

describe("external_signer_util", function()
    describe("shell_quote / command_line", function()
        it("wraps in single quotes and escapes an embedded quote as '\\''", function()
            assert.are.equal("'abc'", util.shell_quote("abc"))
            assert.are.equal("''", util.shell_quote(""))
            assert.are.equal("'it'\\''s'", util.shell_quote("it's"))
            assert.are.equal("'$(x)'", util.shell_quote("$(x)"))
        end)

        it("rejects a NUL byte and non-string arguments", function()
            assert.has_error(function() util.shell_quote("a\0b") end)
            assert.has_error(function() util.shell_quote(1) end)
            assert.has_error(function() util.shell_quote(nil) end)
            assert.has_error(function() util.command_line({}) end)
        end)

        it("passes every hostile argument to printf byte for byte through io.popen", function()
            local p = assert(io.popen(util.command_line(printf_argv(HOSTILE)), "r"))
            local out = p:read("*a")
            p:close()
            assert.are.equal(expected_printf_output(HOSTILE), out)
        end)

        it("passes each hostile argument on its own byte for byte", function()
            for _, a in ipairs(HOSTILE) do
                local out = util.run_capture(printf_argv({ a }))
                assert.are.equal(a .. "\n", out, "argument " .. string.format("%q", a))
            end
        end)

        it("delivers the substitution probe URL literally", function()
            local probe = "https://rpc.invalid/$(printf HERMES_SUBSTITUTED)"
            local out = util.run_capture(printf_argv({ probe }))
            assert.are.equal(probe .. "\n", out)
            assert.is_nil(out:find("rpc.invalid/HERMES_SUBSTITUTED", 1, true))
        end)

        it("never runs a command embedded in an argument", function()
            local canary = fresh_canary()
            local attempts = {
                "$(touch " .. canary .. ")",
                "`touch " .. canary .. "`",
                "x; touch " .. canary,
                "x && touch " .. canary,
                "x | touch " .. canary,
                "'; touch " .. canary .. "; '",
                '"; touch ' .. canary .. '; "',
                "x\ntouch " .. canary,
            }
            local out = util.run_capture(printf_argv(attempts))
            assert.are.equal(expected_printf_output(attempts), out)
            assert.is_false(exists(canary), "canary was created: an argument ran as a command")
        end)
    end)

    describe("run_capture", function()
        it("returns stdout exactly, with or without a trailing newline", function()
            assert.are.equal("abc", util.run_capture({ "printf", "abc" }))
            assert.are.equal("abc\n\n", util.run_capture({ "printf", "abc\\n\\n" }))
            assert.are.equal("", util.run_capture({ "true" }))
        end)

        it("returns output larger than a pipe buffer intact", function()
            -- 100 KiB: above the 64 KiB pipe buffer, below Linux's 128 KiB
            -- per-argument limit (the whole command line is one sh -c argument).
            local big = string.rep("0123456789abcdef", 6400)
            assert.are.equal(big, util.run_capture({ "printf", "%s", big }))
        end)

        it("raises on a non-zero exit, naming only the program", function()
            local key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
            local ok, err = pcall(util.run_capture, { "sh", "-c", "exit 3", "sh", key })
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("sh exited with status 3", 1, true))
            assert.is_nil(tostring(err):find(key, 1, true))
            assert.is_nil(tostring(err):find("exit 3", 1, true))
        end)
    end)

    describe("validators", function()
        local addr = "0x" .. hex(40)

        it("is_address accepts 0x + 40 hex digits only", function()
            assert.is_true(util.is_address(addr))
            assert.is_true(util.is_address("0x" .. string.rep("0", 40)))
            for _, bad in ipairs({
                hex(40), "0X" .. hex(40), "0x" .. hex(36) .. "abc", "0x" .. hex(44),
                "0x" .. hex(36) .. "abcg", addr .. "\n", addr .. ";id", " " .. addr,
                "0x" .. hex(36) .. "'; x", "", 42, true,
            }) do
                assert.is_false(util.is_address(bad), "accepted " .. tostring(bad))
            end
            assert.is_false(util.is_address(nil))
        end)

        it("is_uint256_decimal accepts canonical decimals up to 2^256 - 1", function()
            for _, good in ipairs({ "0", "1", "1000000000000000000", util.MAX_UINT256_DECIMAL,
                "99999999999999999999999999999999999999999999999999999999999999999999999999999" }) do
                assert.is_true(util.is_uint256_decimal(good), "rejected " .. good)
            end
            for _, bad in ipairs({
                "", "-1", "+1", "1.5", "1e3", "0x10", " 1", "1 ", "01", "00",
                "115792089237316195423570985008687907853269984665640564039457584007913129639936",
                "200000000000000000000000000000000000000000000000000000000000000000000000000000",
                "1" .. string.rep("0", 78), "1;id", "$(id)", 1,
            }) do
                assert.is_false(util.is_uint256_decimal(bad), "accepted " .. tostring(bad))
            end
            assert.is_false(util.is_uint256_decimal(nil))
        end)

        it("is_quote_hash accepts 64 hex digits with or without 0x", function()
            assert.is_true(util.is_quote_hash(hex(64)))
            assert.is_true(util.is_quote_hash("0x" .. hex(64)))
            for _, bad in ipairs({
                hex(60) .. "abc", hex(68), "0x0x" .. hex(64), hex(60) .. "abcz",
                hex(64) .. "'", "'" .. hex(64), hex(64) .. "\n", "", 7,
            }) do
                assert.is_false(util.is_quote_hash(bad), "accepted " .. tostring(bad))
            end
            assert.is_false(util.is_quote_hash(nil))
        end)

        it("is_tx_hash accepts 0x + 64 hex digits only", function()
            assert.is_true(util.is_tx_hash("0x" .. hex(64)))
            for _, bad in ipairs({ hex(64), "0x" .. hex(60) .. "abc", "0x" .. hex(68),
                "0x" .. hex(64) .. "\n", "0x", "", {} }) do
                assert.is_false(util.is_tx_hash(bad), "accepted " .. tostring(bad))
            end
            assert.is_false(util.is_tx_hash(nil))
        end)

        it("is_rpc_url accepts http(s) URLs of printable ASCII", function()
            for _, good in ipairs({
                "http://127.0.0.1:8545",
                "https://arb1.arbitrum.io/rpc",
                "https://rpc.example/v1/key?x=1&y=2",
                -- printable ASCII with no space, so it passes validation;
                -- quoting is what keeps it from running (tests above)
                "https://rpc.invalid/$(id)`id`;id",
                "http://h/" .. string.rep("a", util.MAX_RPC_URL_LENGTH - 9),
            }) do
                assert.is_true(util.is_rpc_url(good), "rejected " .. good)
            end
            for _, bad in ipairs({
                "", "ftp://host", "file:///etc/passwd", "http://", "https:///path",
                "//host", "host:8545", "-http://host", " http://host", "http://host ",
                -- the substitution probe contains a space, so validation
                -- rejects it as well as quoting neutralising it
                "https://rpc.invalid/$(printf HERMES_SUBSTITUTED)",
                "http://a b", "http://a\tb", "http://a\nb", "http://a\rb", "http://a\0b",
                "http://a\27[31mb", "http://h\127", "http://ho\195\164st",
                "http://h/" .. string.rep("a", util.MAX_RPC_URL_LENGTH - 8),
                42,
            }) do
                assert.is_false(util.is_rpc_url(bad), "accepted " .. tostring(bad))
            end
            assert.is_false(util.is_rpc_url(nil))
        end)
    end)

    describe("validate_signing_request", function()
        local key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

        local function good_request()
            return {
                rpc_url = "http://127.0.0.1:8545",
                payment_vault_address = "0x" .. hex(40),
                payment_token_address = "0x" .. string.rep("1", 40),
                payments = {
                    { rewards_address = "0x" .. string.rep("2", 40), amount = "1",
                        quote_hash = "0x" .. hex(64) },
                    { rewards_address = "0x" .. string.rep("3", 40), amount = util.MAX_UINT256_DECIMAL,
                        quote_hash = hex(64) },
                },
            }
        end

        it("accepts a well-formed request", function()
            local ok, why = util.validate_signing_request(good_request())
            assert.is_true(ok)
            assert.is_nil(why)
        end)

        local injection = "'; touch /tmp/pwned; '"
        local cases = {
            { "rpc_url", function(r) r.rpc_url = "http://h; touch /tmp/pwned" end },
            { "payment_vault_address", function(r) r.payment_vault_address = "0x1 " .. injection end },
            { "payment_token_address", function(r) r.payment_token_address = "$(touch /tmp/pwned)" end },
            { "payments must be a list", function(r) r.payments = "x" end },
            { "payments[2] must be a table", function(r) r.payments[2] = injection end },
            { "payments[1].rewards_address",
                function(r) r.payments[1].rewards_address = r.payments[1].rewards_address .. injection end },
            { "payments[2].amount", function(r) r.payments[2].amount = "1" .. injection end },
            { "payments[2].amount", function(r) r.payments[2].amount = "-1" end },
            { "payments[1].quote_hash", function(r) r.payments[1].quote_hash = hex(64) .. injection end },
        }
        for _, case in ipairs(cases) do
            local field, mutate = case[1], case[2]
            it("rejects a bad " .. field .. " naming the field, not the value", function()
                local req = good_request()
                mutate(req)
                local ok, why = util.validate_signing_request(req)
                assert.is_nil(ok)
                assert.is_truthy(why:find(field, 1, true), why)
                assert.is_nil(why:find("pwned", 1, true), why)
                assert.is_nil(why:find(key, 1, true), why)
            end)
        end

        it("rejects a non-table request", function()
            assert.is_nil(util.validate_signing_request(nil))
            assert.is_nil(util.validate_signing_request("x"))
        end)
    end)

    describe("tx_hash_from_cast_json", function()
        it("returns a well-formed transactionHash", function()
            local tx = "0x" .. hex(64)
            assert.are.equal(tx, util.tx_hash_from_cast_json(
                '{"status":"0x1","transactionHash":"' .. tx .. '"}'))
        end)

        it("rejects anything else without echoing the output", function()
            for _, out in ipairs({
                "", "not json", "[]", '"0x' .. hex(64) .. '"', "{}",
                '{"transactionHash":null}', '{"transactionHash":1}',
                '{"transactionHash":"0x' .. hex(60) .. 'abc"}',
                '{"transactionHash":"$(touch /tmp/pwned)"}',
            }) do
                local tx, why = util.tx_hash_from_cast_json(out)
                assert.is_nil(tx, "accepted " .. out)
                assert.is_string(why)
                assert.is_nil(why:find("pwned", 1, true))
            end
        end)
    end)
end)
