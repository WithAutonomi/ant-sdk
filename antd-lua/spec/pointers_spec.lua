--- Tests for the antd Lua SDK pointer API, against mocked HTTP.

local cjson = require("cjson")
local socket_http = require("socket.http")
local ltn12 = require("ltn12")

-- ── Mock HTTP layer ──
--
-- Routes are keyed by `METHOD PATH`; every request is recorded with its raw
-- and decoded body, so tests can assert on exactly what was sent and how
-- many times.

local routes = {}
local requests = {}

local function reset()
    routes = {}
    requests = {}
end

local function route(method, path, status, body)
    if type(body) ~= "string" then
        body = cjson.encode(body)
    end
    routes[method .. " " .. path] = { status = status, body = body }
end

local function last_request()
    return requests[#requests]
end

local original_request = socket_http.request
socket_http.request = function(params)
    local method = params.method or "GET"
    local path = params.url:match("^https?://[^/]+(/.*)$") or "/"
    local raw = nil
    if params.source then
        local parts = {}
        -- sink.table returns the sink and the table: keep only the sink.
        local sink = ltn12.sink.table(parts)
        ltn12.pump.all(params.source, sink)
        raw = table.concat(parts)
    end
    local decoded = nil
    if raw and raw ~= "" then
        local ok, v = pcall(cjson.decode, raw)
        if ok then decoded = v end
    end
    requests[#requests + 1] = { method = method, path = path, raw = raw, body = decoded }

    local r = routes[method .. " " .. path]
        or { status = 404, body = cjson.encode({ error = "no route " .. path, code = "NOT_FOUND" }) }
    if params.sink then
        ltn12.pump.all(ltn12.source.string(r.body), params.sink)
    end
    return 1, r.status, {}
end

-- Load the SDK fresh, so its socket.http is the table patched above.
for name in pairs(package.loaded) do
    if name == "antd" or name:find("^antd%.") then
        package.loaded[name] = nil
    end
end
local antd = require("antd")
local errors = require("antd.errors")
local models = require("antd.models")

local MAX = "18446744073709551615"
local A = string.rep("a", 64)
local B = string.rep("b", 64)
local T1 = string.rep("1", 64)
local T2 = string.rep("2", 64)
local S = string.rep("5", 64)

local function finality_body(overrides)
    local body = {
        address = A,
        group = 7,
        answered = 7,
        status = "open",
        counter = cjson.null,
        state = cjson.null,
        states = {},
        majority = cjson.null,
        transferred_to = cjson.null,
    }
    for k, v in pairs(overrides or {}) do
        body[k] = v
    end
    return body
end

local function final_state(target, holders, transferred_to)
    return {
        state_id = S,
        kind = "pointer",
        kind_tag = 1,
        target = target,
        holders = holders,
        transferred_to = transferred_to or cjson.null,
    }
end

describe("pointer API", function()
    local client

    before_each(function()
        reset()
        client = antd.new_client("http://localhost:8082")
    end)

    teardown(function()
        socket_http.request = original_request
    end)

    -- ── counters and helpers ──

    describe("parse_pointer_counter", function()
        it("keeps a decimal counter as a canonical string", function()
            assert.are.equal("0", antd.parse_pointer_counter("0"))
            assert.are.equal("42", antd.parse_pointer_counter("42"))
            assert.are.equal("7", antd.parse_pointer_counter("007"))
            assert.are.equal("0", antd.parse_pointer_counter("0000"))
            assert.are.equal(MAX, antd.parse_pointer_counter(MAX))
            assert.are.equal(MAX, antd.parse_pointer_counter("000" .. MAX))
            assert.are.equal("1", antd.parse_pointer_counter(string.rep("0", 30) .. "1"))
        end)

        it("names the final counter 2^64-1", function()
            assert.are.equal(MAX, antd.POINTER_FINAL_COUNTER)
        end)

        it("rejects counters past 2^64-1", function()
            for _, s in ipairs({
                "18446744073709551616",
                "18446744073709551620",
                "99999999999999999999",
                "100000000000000000000",
            }) do
                local c, why = antd.parse_pointer_counter(s)
                assert.is_nil(c, s)
                assert.is_string(why)
            end
        end)

        it("rejects anything that is not ASCII digits", function()
            for _, s in ipairs({ "", "-1", "+1", " 1", "1 ", "1.0", "1e3", "0x10", "abc", "١" }) do
                local c, why = antd.parse_pointer_counter(s)
                assert.is_nil(c, s)
                assert.is_string(why)
            end
        end)

        it("rejects values that are not strings, including Lua numbers", function()
            for _, v in ipairs({ 0, 1, 2 ^ 53, true, {} }) do
                assert.is_nil(antd.parse_pointer_counter(v))
            end
            assert.is_nil(antd.parse_pointer_counter(nil))
            assert.is_nil(antd.parse_pointer_counter(cjson.null))
        end)
    end)

    describe("compare_pointer_counters", function()
        it("compares by value, not by string order", function()
            assert.are.equal(-1, antd.compare_pointer_counters("1", "2"))
            assert.are.equal(1, antd.compare_pointer_counters("10", "9"))
            assert.are.equal(-1, antd.compare_pointer_counters("9", "10"))
            assert.are.equal(0, antd.compare_pointer_counters("007", "7"))
            assert.are.equal(0, antd.compare_pointer_counters(MAX, MAX))
            assert.are.equal(1, antd.compare_pointer_counters(MAX, "18446744073709551614"))
            assert.are.equal(-1, antd.compare_pointer_counters("9007199254740993", "9007199254740994"))
        end)

        it("returns nil and a reason for a malformed counter", function()
            local r, why = antd.compare_pointer_counters("1", "x")
            assert.is_nil(r)
            assert.matches("second counter", why)
            r, why = antd.compare_pointer_counters(1, "1")
            assert.is_nil(r)
            assert.matches("first counter", why)
        end)
    end)

    describe("normalize_address", function()
        it("drops a 0x prefix and lowercases", function()
            assert.are.equal("abcd", antd.normalize_address("0xABcd"))
            assert.are.equal("abcd", antd.normalize_address("0XABCD"))
            assert.are.equal(A, antd.normalize_address(A))
            assert.is_nil(antd.normalize_address(nil))
        end)
    end)

    describe("pointer_finality_status", function()
        it("passes known statuses and folds the rest into unknown", function()
            for _, s in ipairs({ "open", "settling", "unconfirmed", "final", "forked" }) do
                assert.are.equal(s, models.pointer_finality_status(s))
            end
            assert.are.equal("unknown", models.pointer_finality_status("contested"))
            assert.are.equal("unknown", models.pointer_finality_status(""))
            assert.are.equal("unknown", models.pointer_finality_status(nil))
            assert.are.equal(antd.PointerFinalityStatus.UNKNOWN, "unknown")
        end)
    end)

    -- ── reads ──

    describe("pointer_keys", function()
        it("returns the addresses the daemon can write", function()
            route("GET", "/v1/pointers/keys", 200, { keys = { { address = A }, { address = B }, "junk", {} } })
            local keys, err = client:pointer_keys()
            assert.is_nil(err)
            assert.are.same({ A, B }, keys)
        end)
    end)

    describe("pointer_get", function()
        it("reads a record and keeps the final counter exact", function()
            route("GET", "/v1/pointers/" .. A, 200, {
                address = A,
                owner = "ab",
                counter = MAX,
                kind = "chunk",
                kind_tag = 0,
                target = T1,
                state_id = S,
                is_final = true,
                transferred_to = B,
            })
            local r, err = client:pointer_get(A)
            assert.is_nil(err)
            assert.are.equal(A, r.address)
            assert.are.equal("ab", r.owner)
            assert.are.equal(MAX, r.counter)
            assert.are.equal(0, antd.compare_pointer_counters(r.counter, antd.POINTER_FINAL_COUNTER))
            assert.are.equal("chunk", r.kind)
            assert.are.equal(0, r.kind_tag)
            assert.are.equal(T1, r.target)
            assert.are.equal(S, r.state_id)
            assert.is_true(r.is_final)
            assert.are.equal(B, r.transferred_to)
        end)

        it("reads JSON null as nil and an unknown kind with its raw tag", function()
            route("GET", "/v1/pointers/" .. A, 200, {
                address = A,
                owner = "ab",
                counter = "3",
                kind = "unknown",
                kind_tag = 9,
                target = T1,
                state_id = S,
                is_final = false,
                transferred_to = cjson.null,
            })
            local r, err = client:pointer_get(A)
            assert.is_nil(err)
            assert.are.equal("3", r.counter)
            assert.are.equal("unknown", r.kind)
            assert.are.equal(9, r.kind_tag)
            assert.is_false(r.is_final)
            assert.is_nil(r.transferred_to)
        end)

        it("does not read the old `final` field as is_final", function()
            route("GET", "/v1/pointers/" .. A, 200, { address = A, counter = "1", final = true })
            local r = client:pointer_get(A)
            assert.is_false(r.is_final)
        end)

        it("reads a malformed counter as an error, never as 0", function()
            for _, bad in ipairs({ 5, "abc", "-1", "1.5", "", "18446744073709551616", cjson.null }) do
                route("GET", "/v1/pointers/" .. A, 200, { address = A, counter = bad, is_final = false })
                local r, err = client:pointer_get(A)
                assert.is_nil(r)
                assert.are.equal("internal", err.type)
                assert.matches("invalid pointer counter", err.message)
            end
            route("GET", "/v1/pointers/" .. A, 200, { address = A })
            local r, err = client:pointer_get(A)
            assert.is_nil(r)
            assert.are.equal("internal", err.type)
        end)

        it("escapes the address so it cannot reach another route", function()
            client:pointer_get("abc/resolve?x=1")
            assert.are.equal("/v1/pointers/abc%2Fresolve%3Fx%3D1", last_request().path)
            client:pointer_get("0x" .. A)
            assert.are.equal("/v1/pointers/0x" .. A, last_request().path)
        end)

        it("maps a 404 onto not_found", function()
            local r, err = client:pointer_get(A)
            assert.is_nil(r)
            assert.are.equal("not_found", err.type)
        end)
    end)

    describe("pointer_resolve", function()
        it("returns where the chain ends", function()
            route("GET", "/v1/pointers/" .. A .. "/resolve", 200, { kind = "chunk", kind_tag = 0, target = T2 })
            local t, err = client:pointer_resolve(A)
            assert.is_nil(err)
            assert.are.same({ kind = "chunk", kind_tag = 0, target = T2 }, t)
        end)

        it("leaves a malformed kind_tag unset", function()
            route("GET", "/v1/pointers/" .. A .. "/resolve", 200, { kind = "chunk", kind_tag = 256, target = T2 })
            local t = client:pointer_resolve(A)
            assert.is_nil(t.kind_tag)
        end)
    end)

    describe("pointer_controller", function()
        it("returns the controlling pointer and the transfers", function()
            route("GET", "/v1/pointers/" .. A .. "/controller", 200, { pointer = B, transfers = { B }, frozen = false })
            local c, err = client:pointer_controller(A)
            assert.is_nil(err)
            assert.are.same({ pointer = B, transfers = { B }, frozen = false }, c)
        end)
    end)

    describe("pointer_finality", function()
        local path = "/v1/pointers/" .. A .. "/finality"

        it("reads an open pointer with its counter and nulls as nil", function()
            route("GET", path, 200, finality_body({ counter = "1" }))
            local f, err = client:pointer_finality(A)
            assert.is_nil(err)
            assert.are.equal(A, f.address)
            assert.are.equal(7, f.group)
            assert.are.equal(7, f.answered)
            assert.are.equal(antd.PointerFinalityStatus.OPEN, f.status)
            assert.are.equal("open", f.raw_status)
            assert.are.equal("1", f.counter)
            assert.is_nil(f.state)
            assert.is_nil(f.majority)
            assert.is_nil(f.transferred_to)
            assert.are.same({}, f.states)
        end)

        it("reads an unset counter (null or empty) as nil", function()
            for _, unset in ipairs({ cjson.null, "" }) do
                route("GET", path, 200, finality_body({ counter = unset }))
                local f, err = client:pointer_finality(A)
                assert.is_nil(err)
                assert.is_nil(f.counter)
            end
        end)

        it("reads a malformed counter as an error", function()
            for _, bad in ipairs({ 1, "x1", "18446744073709551616", true }) do
                route("GET", path, 200, finality_body({ counter = bad }))
                local f, err = client:pointer_finality(A)
                assert.is_nil(f)
                assert.are.equal("internal", err.type)
            end
        end)

        it("reads a final transfer with its state", function()
            route("GET", path, 200, finality_body({
                status = "final",
                state = final_state(B, 7, B),
                transferred_to = B,
            }))
            local f, err = client:pointer_finality(A)
            assert.is_nil(err)
            assert.are.equal("final", f.status)
            assert.are.equal(B, f.transferred_to)
            assert.are.same({
                state_id = S,
                kind = "pointer",
                kind_tag = 1,
                target = B,
                holders = 7,
                transferred_to = B,
            }, f.state)
        end)

        it("reads a forked pointer's states and majority", function()
            route("GET", path, 200, finality_body({
                status = "forked",
                states = { final_state(T1, 5), final_state(T2, 2) },
                majority = final_state(T1, 5),
            }))
            local f, err = client:pointer_finality(A)
            assert.is_nil(err)
            assert.are.equal("forked", f.status)
            assert.are.equal(2, #f.states)
            assert.are.equal(T1, f.states[1].target)
            assert.are.equal(5, f.states[1].holders)
            assert.is_nil(f.states[1].transferred_to)
            assert.are.equal(T2, f.states[2].target)
            assert.are.equal(T1, f.majority.target)
        end)

        it("keeps a status this SDK does not know as unknown, with the raw value", function()
            route("GET", path, 200, finality_body({ status = "contested" }))
            local f, err = client:pointer_finality(A)
            assert.is_nil(err)
            assert.are.equal(antd.PointerFinalityStatus.UNKNOWN, f.status)
            assert.are.equal("contested", f.raw_status)
        end)
    end)

    -- ── writes ──

    describe("pointer_create and pointer_update", function()
        local write = { address = A, state_id = S, counter = "0" }

        it("sends owner and target, leaving kind to the daemon's default", function()
            route("POST", "/v1/pointers", 200, write)
            local w, err = client:pointer_create(A, T1)
            assert.is_nil(err)
            assert.are.same({ address = A, state_id = S, counter = "0" }, w)
            local req = last_request()
            assert.are.equal("POST", req.method)
            assert.are.equal("/v1/pointers", req.path)
            assert.are.same({ owner = A, target = T1 }, req.body)
        end)

        it("sends an explicit kind", function()
            route("POST", "/v1/pointers/update", 200, { address = A, state_id = S, counter = "12" })
            local w, err = client:pointer_update(A, B, antd.PointerKind.POINTER)
            assert.is_nil(err)
            assert.are.equal("12", w.counter)
            local req = last_request()
            assert.are.equal("/v1/pointers/update", req.path)
            assert.are.same({ owner = A, target = B, kind = "pointer" }, req.body)
        end)

        it("reads a malformed counter as an error", function()
            route("POST", "/v1/pointers", 200, { address = A, state_id = S, counter = 0 })
            local w, err = client:pointer_create(A, T1)
            assert.is_nil(w)
            assert.are.equal("internal", err.type)
        end)

        it("maps an existing pointer onto already_exists", function()
            route("POST", "/v1/pointers", 409, { error = "Already exists: pointer", code = "ALREADY_EXISTS" })
            local w, err = client:pointer_create(A, T1)
            assert.is_nil(w)
            assert.are.equal("already_exists", err.type)
            assert.are.equal(409, err.status_code)
        end)

        it("rejects a missing owner or target before sending anything", function()
            local w, err = client:pointer_create(nil, T1)
            assert.is_nil(w)
            assert.are.equal("bad_request", err.type)
            local w2, err2 = client:pointer_update(A, "")
            assert.is_nil(w2)
            assert.are.equal("bad_request", err2.type)
            assert.are.equal(0, #requests)
        end)
    end)

    describe("pointer_transfer", function()
        it("sends owner and recipient and reads the finality", function()
            route("POST", "/v1/pointers/transfer", 200, {
                address = A,
                state_id = S,
                finality = finality_body({ status = "final", state = final_state(B, 7, B), transferred_to = B }),
            })
            local t, err = client:pointer_transfer(A, B)
            assert.is_nil(err)
            assert.are.same({ owner = A, recipient = B }, last_request().body)
            assert.are.equal(A, t.address)
            assert.are.equal(S, t.state_id)
            assert.are.equal("final", t.finality.status)
            assert.are.equal(B, t.finality.transferred_to)
            assert.is_nil(t.finality_error)
        end)

        it("keeps a failed finality check as finality_error", function()
            route("POST", "/v1/pointers/transfer", 200, {
                address = A,
                state_id = S,
                finality = cjson.null,
                finality_error = "only 3 of 7 answered",
            })
            local t, err = client:pointer_transfer(A, B)
            assert.is_nil(err)
            assert.is_nil(t.finality)
            assert.are.equal("only 3 of 7 answered", t.finality_error)
        end)
    end)

    describe("pointer_prepare", function()
        local prepared = {
            upload_id = "up1",
            op = "update",
            address = A,
            state_id = S,
            counter = "4",
            payment_type = "wave_batch",
            payments = { { quote_hash = "0xq", rewards_address = "0xr", amount = "100" } },
            total_amount = "100",
            payment_vault_address = "0xv",
            payment_token_address = "0xt",
            rpc_url = "http://127.0.0.1:8545",
        }

        it("sends an update op and reads the payment intent", function()
            route("POST", "/v1/pointers/prepare", 200, prepared)
            local p, err = client:pointer_prepare(A, antd.pointer_update_op(T2))
            assert.is_nil(err)
            assert.are.same({ owner = A, op = "update", target = T2 }, last_request().body)
            assert.are.equal("up1", p.upload_id)
            assert.are.equal("update", p.op)
            assert.are.equal("4", p.counter)
            assert.are.equal("wave_batch", p.payment_type)
            assert.are.same({ { quote_hash = "0xq", rewards_address = "0xr", amount = "100" } }, p.payments)
            assert.are.equal("100", p.total_amount)
            assert.are.equal("0xv", p.payment_vault_address)
            assert.are.equal("0xt", p.payment_token_address)
            assert.are.equal("http://127.0.0.1:8545", p.rpc_url)
            assert.are.same({}, p.signed_quotes)
        end)

        it("sends a create op's kind and a transfer op's recipient", function()
            route("POST", "/v1/pointers/prepare", 200, prepared)
            client:pointer_prepare(A, antd.pointer_create_op(T1, antd.PointerKind.CHUNK))
            assert.are.same({ owner = A, op = "create", target = T1, kind = "chunk" }, last_request().body)
            client:pointer_prepare(A, antd.pointer_transfer_op(B))
            assert.are.same({ owner = A, op = "transfer", recipient = B }, last_request().body)
        end)

        it("asks for and reads signed quotes when requested", function()
            local body = {}
            for k, v in pairs(prepared) do body[k] = v end
            body.signed_quotes = {
                { quote_hash = "0xq", quote = "cXVvdGU=", commitment_sidecar = "c2lkZQ==" },
                { quote_hash = "0xq2", quote = "cTI=" },
            }
            route("POST", "/v1/pointers/prepare", 200, body)
            local p, err = client:pointer_prepare(A, antd.pointer_update_op(T2), { include_signed_quotes = true })
            assert.is_nil(err)
            assert.is_true(last_request().body.include_signed_quotes)
            assert.are.same({
                { quote_hash = "0xq", quote = "cXVvdGU=", commitment_sidecar = "c2lkZQ==" },
                { quote_hash = "0xq2", quote = "cTI=" },
            }, p.signed_quotes)
        end)

        it("rejects a missing op before sending anything", function()
            local p, err = client:pointer_prepare(A, "update")
            assert.is_nil(p)
            assert.are.equal("bad_request", err.type)
            local p2, err2 = client:pointer_prepare(A, {})
            assert.is_nil(p2)
            assert.are.equal("bad_request", err2.type)
            assert.are.equal(0, #requests)
        end)

        it("maps a pending prepared write onto conflict", function()
            route("POST", "/v1/pointers/prepare", 409, { error = "Conflict: pending", code = "CONFLICT" })
            local p, err = client:pointer_prepare(A, antd.pointer_update_op(T2))
            assert.is_nil(p)
            assert.are.equal("conflict", err.type)
        end)
    end)

    describe("pointer_finalize", function()
        it("sends upload_id and tx_hashes and reads the stored state", function()
            route("POST", "/v1/pointers/finalize", 200, { address = A, state_id = S, counter = "5" })
            local r, err = client:pointer_finalize("up1", { ["0xq"] = "0xtx" })
            assert.is_nil(err)
            assert.are.same({ upload_id = "up1", tx_hashes = { ["0xq"] = "0xtx" } }, last_request().body)
            assert.are.same({ address = A, state_id = S, counter = "5" }, r)
        end)

        it("sends empty tx_hashes as a JSON object", function()
            route("POST", "/v1/pointers/finalize", 200, { address = A, state_id = S, counter = "5" })
            client:pointer_finalize("up1", {})
            assert.matches('"tx_hashes":{}', last_request().raw, 1, true)
            client:pointer_finalize("up1")
            assert.matches('"tx_hashes":{}', last_request().raw, 1, true)
        end)

        it("reads a transfer's finality", function()
            route("POST", "/v1/pointers/finalize", 200, {
                address = A,
                state_id = S,
                counter = MAX,
                finality = finality_body({ status = "unconfirmed", answered = 6, state = final_state(B, 6, B) }),
            })
            local r, err = client:pointer_finalize("up1", { ["0xq"] = "0xtx" })
            assert.is_nil(err)
            assert.are.equal(MAX, r.counter)
            assert.are.equal("unconfirmed", r.finality.status)
            assert.are.equal(6, r.finality.answered)
        end)

        it("surfaces a retained paid state as a retryable close_group_shortfall", function()
            route("POST", "/v1/pointers/finalize", 503, {
                error = "Close group shortfall: 3 of 7 (paid attempt retained: call finalize again)",
                code = "CLOSE_GROUP_SHORTFALL",
                retryable = true,
            })
            local r, err = client:pointer_finalize("up1", { ["0xq"] = "0xtx" })
            assert.is_nil(r)
            assert.is_true(antd.is_close_group_shortfall(err))
            assert.is_true(err.retryable)
            assert.are.equal(503, err.status_code)
        end)
    end)

    describe("paid writes", function()
        it("are sent once and never retried, whatever the error", function()
            local shortfall = { error = "Close group shortfall", code = "CLOSE_GROUP_SHORTFALL" }
            local calls = {
                { "/v1/pointers", function() return client:pointer_create(A, T1) end },
                { "/v1/pointers/update", function() return client:pointer_update(A, T1) end },
                { "/v1/pointers/transfer", function() return client:pointer_transfer(A, B) end },
                { "/v1/pointers/finalize", function() return client:pointer_finalize("up1", {}) end },
            }
            for _, c in ipairs(calls) do
                for _, status in ipairs({ 502, 503 }) do
                    reset()
                    route("POST", c[1], status, shortfall)
                    local r, err = c[2]()
                    assert.is_nil(r)
                    assert.is_true(errors.is_antd_error(err))
                    assert.are.equal(1, #requests, c[1])
                end
            end
        end)
    end)

    -- ── error mapping ──

    describe("error mapping by code", function()
        local path = "/v1/pointers/update"

        local function update_error(status, body)
            route("POST", path, status, body)
            local _, err = client:pointer_update(A, T1)
            return err
        end

        it("maps the 409 codes onto their own types, not already_exists", function()
            local cases = {
                POINTER_FINAL = "pointer_final",
                POINTER_FORKED = "pointer_forked",
                CONFLICT = "conflict",
                ALREADY_EXISTS = "already_exists",
            }
            for code, want in pairs(cases) do
                local err = update_error(409, { error = "msg " .. code, code = code })
                assert.are.equal(want, err.type, code)
                assert.are.equal(409, err.status_code)
                assert.are.equal("msg " .. code, err.message)
            end
        end)

        it("keeps a 409 without a known code as already_exists", function()
            assert.are.equal("already_exists", update_error(409, { error = "x" }).type)
            assert.are.equal("already_exists", update_error(409, { error = "x", code = "SOMETHING_NEW" }).type)
            assert.are.equal("already_exists", update_error(409, { error = "x", code = 409 }).type)
            assert.are.equal("already_exists", update_error(409, "not json").type)
        end)

        it("maps CLOSE_GROUP_SHORTFALL, reading only the boolean true as retryable", function()
            local err = update_error(503, { error = "short", code = "CLOSE_GROUP_SHORTFALL" })
            assert.are.equal("close_group_shortfall", err.type)
            assert.are.equal(503, err.status_code)
            assert.is_false(err.retryable)
            for _, v in ipairs({ "true", 1, cjson.null, false }) do
                err = update_error(503, { error = "short", code = "CLOSE_GROUP_SHORTFALL", retryable = v })
                assert.is_false(err.retryable)
            end
            err = update_error(503, { error = "short", code = "CLOSE_GROUP_SHORTFALL", retryable = true })
            assert.is_true(err.retryable)
        end)

        it("keeps a plain 503 as service_unavailable", function()
            local err = update_error(503, { error = "no wallet", code = "SERVICE_UNAVAILABLE" })
            assert.are.equal("service_unavailable", err.type)
            assert.is_false(antd.is_close_group_shortfall(err))
        end)

        it("maps by code through errors.error_for_response too", function()
            assert.are.equal("pointer_final", errors.error_for_response(409, "m", { code = "POINTER_FINAL" }).type)
            assert.are.equal("conflict", errors.error_for_response(409, "m", { code = "CONFLICT" }).type)
            local e = errors.error_for_response(503, "m", { code = "CLOSE_GROUP_SHORTFALL", retryable = true })
            assert.are.equal("close_group_shortfall", e.type)
            assert.is_true(e.retryable)
            assert.are.equal("already_exists", errors.error_for_response(409, "m", nil).type)
        end)

        it("exposes the constructors", function()
            assert.are.equal("pointer_final", errors.pointer_final("m").type)
            assert.are.equal("pointer_forked", errors.pointer_forked("m").type)
            assert.are.equal("conflict", errors.conflict("m").type)
            local e = errors.close_group_shortfall("m", true)
            assert.are.equal("close_group_shortfall", e.type)
            assert.is_true(e.retryable)
            assert.is_true(errors.is_antd_error(e))
        end)
    end)
end)
