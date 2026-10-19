--- Live pointer round trip against a running antd with a devnet behind it.
--
-- Pending (skipped) unless both are set:
--
--   ANTD_TEST_URL             the daemon's REST base URL, e.g.
--                             http://127.0.0.1:8082
--   ANTD_TEST_POINTER_OWNERS  two comma-separated pointer addresses the
--                             daemon holds keys for (antd --pointer-keys) and
--                             that have never been written. The test creates
--                             both, transfers the first to the second, and
--                             leaves the second with a prepared write
--                             awaiting payment, so each pair can be used once.
--
-- Every write is paid by the daemon's wallet, so run it against a devnet:
--
--   ANTD_TEST_URL=http://127.0.0.1:8082 \
--   ANTD_TEST_POINTER_OWNERS=<hex>,<hex> busted spec/live_pointers_spec.lua

local base_url = os.getenv("ANTD_TEST_URL")
local owners = os.getenv("ANTD_TEST_POINTER_OWNERS")
local first, second
if owners then
    first, second = owners:match("^%s*([^,%s]+)%s*,%s*([^,%s]+)%s*$")
end

if not (base_url and base_url ~= "" and first and second) then
    describe("live pointers", function()
        pending("set ANTD_TEST_URL and ANTD_TEST_POINTER_OWNERS to run")
    end)
    return
end

-- Load the SDK fresh, so no other spec's HTTP mock is in play.
for name in pairs(package.loaded) do
    if name == "antd" or name:find("^antd%.") then
        package.loaded[name] = nil
    end
end
local antd = require("antd")

describe("live pointers", function()
    it("create, update, read, transfer, prepare", function()
        local norm = antd.normalize_address
        local a, b = norm(first), norm(second)
        local client = antd.new_client(base_url)

        local function ok(value, err)
            assert(err == nil, err and (err.type .. ": " .. tostring(err.message)))
            return value
        end

        local function fails_with(want, value, err)
            assert(value == nil, "expected a " .. want .. " error, got a result")
            assert.are.equal(want, err and err.type)
        end

        -- Both owners must be writable through this daemon.
        local held = {}
        for _, k in ipairs(ok(client:pointer_keys())) do
            held[norm(k)] = true
        end
        assert(held[a] and held[b], "the daemon holds no key for one of the owners")

        -- Real targets, so the chain can be followed back to bytes.
        local one = ok(client:data_put_public("antd-lua pointer target one")).address
        local two = ok(client:data_put_public("antd-lua pointer target two")).address

        -- ── create, read, update ──
        local r0, e0 = client:pointer_get(a)
        assert(r0 == nil and e0 and e0.type == "not_found",
            "owner " .. a .. " has been written before; use a fresh pair")

        local w = ok(client:pointer_create(a, one))
        assert.are.equal("0", w.counter)
        assert.are.equal(a, norm(w.address))
        fails_with("already_exists", client:pointer_create(a, two))

        local r = ok(client:pointer_get(a))
        assert.are.equal("0", r.counter)
        assert.are.equal(one, r.target)
        assert.are.equal("chunk", r.kind)
        assert.are.equal(0, r.kind_tag)
        assert.is_false(r.is_final)
        assert.is_nil(r.transferred_to)
        assert.are.equal(2 * 1952, #r.owner)

        -- The daemon accepts a 0x prefix and answers with bare hex.
        assert.are.equal(a, ok(client:pointer_get("0x" .. a)).address)

        local res = ok(client:pointer_resolve(a))
        assert.are.equal(one, res.target)
        assert.are.equal("antd-lua pointer target one", ok(client:data_get_public(res.target)))

        w = ok(client:pointer_update(a, two))
        assert.are.equal("1", w.counter)
        res = ok(client:pointer_resolve(a))
        assert.are.equal(two, res.target)
        assert.are.equal("antd-lua pointer target two", ok(client:data_get_public(res.target)))

        local f = ok(client:pointer_finality(a))
        assert.are.equal(antd.PointerFinalityStatus.OPEN, f.status)
        assert.are.equal("1", f.counter)
        assert.are.equal(f.group, f.answered)
        assert.is_nil(f.transferred_to)

        -- ── transfer a -> b ──
        assert.are.equal("0", ok(client:pointer_create(b, one)).counter)
        local t = ok(client:pointer_transfer(a, b))
        assert(t.finality, "the close group should answer after the transfer: "
            .. tostring(t.finality_error))
        assert.are.equal(antd.PointerFinalityStatus.FINAL, t.finality.status)
        assert.are.equal(b, norm(t.finality.transferred_to))

        r = ok(client:pointer_get(a))
        assert.is_true(r.is_final)
        assert.are.equal(antd.POINTER_FINAL_COUNTER, r.counter)
        assert.are.equal(1, antd.compare_pointer_counters(r.counter, "1"))
        assert.are.equal(b, norm(r.transferred_to))

        local c = ok(client:pointer_controller(a))
        assert.are.equal(b, norm(c.pointer))
        assert.are.equal(1, #c.transfers)
        assert.are.equal(b, norm(c.transfers[1]))
        assert.is_false(c.frozen)

        -- a now resolves through b.
        assert.are.equal(one, ok(client:pointer_resolve(a)).target)
        f = ok(client:pointer_finality(a))
        assert.are.equal("final", f.status)
        assert.are.equal(b, norm(f.transferred_to))

        -- A final pointer refuses every write, before anything is paid.
        fails_with("pointer_final", client:pointer_update(a, one))
        fails_with("pointer_final", client:pointer_transfer(a, b))

        -- ── external signer, up to the quote ──
        -- Last: the prepared write blocks b's other writes until it expires.
        local p = ok(client:pointer_prepare(b, antd.pointer_update_op(two)))
        assert.are.equal("update", p.op)
        assert.are.equal("1", p.counter)
        assert.are.equal("wave_batch", p.payment_type)
        assert(#p.payments > 0, "a prepared write should carry a payment")
        assert(p.upload_id ~= "", "a prepared write should carry an upload_id")

        fails_with("conflict", client:pointer_update(b, two))
        fails_with("conflict", client:pointer_prepare(b, antd.pointer_update_op(two)))
        -- A finalize without the payment is refused and keeps the session.
        fails_with("bad_request", client:pointer_finalize(p.upload_id, {}))
        fails_with("conflict", client:pointer_update(b, two))
    end)
end)
