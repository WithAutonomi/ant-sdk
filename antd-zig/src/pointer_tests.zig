//! Pointer API tests: the Client against a mock daemon on a loopback socket,
//! plus the request builders, response parsers and error mapping they use.
//!
//! The mock daemon serves one canned response per connection, in order, and
//! records the method, target and body of each request it was sent. Every
//! test allocates through `std.testing.allocator`, so a leak on any success
//! or error path fails it.

const std = @import("std");
const testing = std.testing;
const antd = @import("antd.zig");
const models = @import("models.zig");
const errors = @import("errors.zig");
const json_helpers = @import("json_helpers.zig");

// =============================================================================
// Mock daemon
// =============================================================================

/// One request/response exchange with the mock daemon.
const Exchange = struct {
    status: std.http.Status = .ok,
    /// The JSON body the mock daemon answers with.
    body: []const u8,

    // Recorded by the mock daemon.
    method: ?std.http.Method = null,
    target_buf: [512]u8 = undefined,
    target_len: usize = 0,
    body_buf: [8192]u8 = undefined,
    body_len: usize = 0,

    fn target(self: *const Exchange) []const u8 {
        return self.target_buf[0..self.target_len];
    }

    fn requestBody(self: *const Exchange) []const u8 {
        return self.body_buf[0..self.body_len];
    }
};

const MockDaemon = struct {
    server: std.net.Server,
    thread: std.Thread,
    exchanges: []Exchange,
    /// Exchanges answered. Written by the server thread; read after `stop`.
    served: usize = 0,
    stopped: bool = false,
    url_buf: [64]u8 = undefined,
    url_len: usize = 0,

    /// Listen on an ephemeral loopback port and answer `exchanges` in order,
    /// one per connection. `self` must not move until `stop`.
    fn start(self: *MockDaemon, exchanges: []Exchange) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", 0);
        self.* = .{
            .server = try address.listen(.{ .reuse_address = true }),
            .thread = undefined,
            .exchanges = exchanges,
        };
        errdefer self.server.deinit();
        const listen_url = try std.fmt.bufPrint(&self.url_buf, "http://127.0.0.1:{d}", .{self.server.listen_address.getPort()});
        self.url_len = listen_url.len;
        self.thread = try std.Thread.spawn(.{}, serve, .{self});
    }

    fn url(self: *const MockDaemon) []const u8 {
        return self.url_buf[0..self.url_len];
    }

    fn serve(self: *MockDaemon) void {
        for (self.exchanges) |*ex| {
            const conn = self.server.accept() catch return;
            defer conn.stream.close();
            var read_buf: [16 * 1024]u8 = undefined;
            var http_server = std.http.Server.init(conn, &read_buf);
            var request = http_server.receiveHead() catch return;

            ex.method = request.head.method;
            const t = request.head.target;
            const n = @min(t.len, ex.target_buf.len);
            @memcpy(ex.target_buf[0..n], t[0..n]);
            ex.target_len = n;
            if (request.head.content_length != null) {
                const reader = request.reader() catch return;
                ex.body_len = reader.readAll(&ex.body_buf) catch return;
            }

            request.respond(ex.body, .{
                .status = ex.status,
                .keep_alive = false,
                .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
            }) catch return;
            self.served += 1;
        }
    }

    /// Stop serving; a second call does nothing. A connection of our own
    /// wakes an `accept` still waiting for a request the test never made, so
    /// the join cannot hang.
    fn stop(self: *MockDaemon) void {
        if (self.stopped) return;
        self.stopped = true;
        if (std.net.tcpConnectToAddress(self.server.listen_address)) |stream| {
            stream.close();
        } else |_| {}
        self.thread.join();
        self.server.deinit();
    }
};

/// Parse a recorded request body as a JSON object for field checks.
fn parseRequest(ex: *const Exchange) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, testing.allocator, ex.requestBody(), .{});
}

fn expectStringField(obj: std.json.ObjectMap, key: []const u8, want: []const u8) !void {
    const v = obj.get(key) orelse {
        std.debug.print("missing request field {s}\n", .{key});
        return error.TestExpectedEqual;
    };
    switch (v) {
        .string => |s| try testing.expectEqualStrings(want, s),
        else => return error.TestExpectedEqual,
    }
}

const addr_a = "aa00000000000000000000000000000000000000000000000000000000000001";
const addr_b = "bb00000000000000000000000000000000000000000000000000000000000002";

// =============================================================================
// Client against the mock daemon
// =============================================================================

test "pointerKeys lists the daemon's owner addresses" {
    var exchanges = [_]Exchange{.{ .body = "{\"keys\":[{\"address\":\"" ++ addr_a ++ "\"},{\"address\":\"" ++ addr_b ++ "\"}]}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const keys = try client.pointerKeys();
    defer keys.deinit(testing.allocator);

    try testing.expectEqual(std.http.Method.GET, exchanges[0].method.?);
    try testing.expectEqualStrings("/v1/pointers/keys", exchanges[0].target());
    try testing.expectEqual(@as(usize, 2), keys.addresses.len);
    try testing.expectEqualStrings(addr_a, keys.addresses[0]);
    try testing.expectEqualStrings(addr_b, keys.addresses[1]);
    // The daemon returns bare hex; a caller's 0x prefix or upper case still
    // matches.
    try testing.expect(keys.contains(addr_a));
    try testing.expect(keys.contains("0x" ++ addr_b));
    try testing.expect(keys.contains("0XBB00000000000000000000000000000000000000000000000000000000000002"));
    try testing.expect(!keys.contains("cc"));
}

test "pointerCreate and pointerUpdate send owner, target and kind" {
    const write = "{\"address\":\"" ++ addr_a ++ "\",\"state_id\":\"ss\",\"counter\":\"7\"}";
    var exchanges = [_]Exchange{ .{ .body = write }, .{ .body = write } };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const created = try client.pointerCreate(addr_a, "tt", .chunk);
    defer created.deinit(testing.allocator);
    try testing.expectEqualStrings(addr_a, created.address);
    try testing.expectEqualStrings("ss", created.state_id);
    try testing.expectEqual(@as(u64, 7), created.counter);

    const updated = try client.pointerUpdate(addr_a, addr_b, .pointer);
    defer updated.deinit(testing.allocator);

    try testing.expectEqual(std.http.Method.POST, exchanges[0].method.?);
    try testing.expectEqualStrings("/v1/pointers", exchanges[0].target());
    try testing.expectEqualStrings(
        "{\"owner\":\"" ++ addr_a ++ "\",\"target\":\"tt\",\"kind\":\"chunk\"}",
        exchanges[0].requestBody(),
    );
    try testing.expectEqual(std.http.Method.POST, exchanges[1].method.?);
    try testing.expectEqualStrings("/v1/pointers/update", exchanges[1].target());
    const req = try parseRequest(&exchanges[1]);
    defer req.deinit();
    try expectStringField(req.value.object, "owner", addr_a);
    try expectStringField(req.value.object, "target", addr_b);
    try expectStringField(req.value.object, "kind", "pointer");
}

test "pointerGet reads the final counter exactly" {
    var exchanges = [_]Exchange{.{ .body = "{\"address\":\"" ++ addr_a ++ "\",\"owner\":\"pk\",\"counter\":\"18446744073709551615\"," ++
        "\"kind\":\"pointer\",\"kind_tag\":1,\"target\":\"" ++ addr_b ++ "\",\"state_id\":\"ss\"," ++
        "\"is_final\":true,\"transferred_to\":\"" ++ addr_b ++ "\"}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const r = try client.pointerGet(addr_a);
    defer r.deinit(testing.allocator);

    try testing.expectEqual(std.http.Method.GET, exchanges[0].method.?);
    try testing.expectEqualStrings("/v1/pointers/" ++ addr_a, exchanges[0].target());
    try testing.expectEqual(models.pointer_final_counter, r.counter);
    try testing.expectEqual(std.math.maxInt(u64), r.counter);
    try testing.expect(r.is_final);
    try testing.expectEqualStrings(addr_b, r.transferred_to.?);
    try testing.expectEqual(@as(u8, 1), r.kind_tag);
    try testing.expectEqual(models.PointerKind.pointer, r.targetKind().?);
    try testing.expectEqualStrings("pk", r.owner);
    try testing.expectEqualStrings("pointer", r.kind);
    try testing.expectEqualStrings(addr_b, r.target);
}

test "pointerGet reads a null transferred_to as null" {
    var exchanges = [_]Exchange{.{ .body = "{\"address\":\"aa\",\"owner\":\"pk\",\"counter\":\"0\",\"kind\":\"chunk\"," ++
        "\"kind_tag\":0,\"target\":\"tt\",\"state_id\":\"ss\",\"is_final\":false,\"transferred_to\":null}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const r = try client.pointerGet("aa");
    defer r.deinit(testing.allocator);

    try testing.expectEqual(@as(u64, 0), r.counter);
    try testing.expect(!r.is_final);
    try testing.expect(r.transferred_to == null);
    try testing.expectEqual(models.PointerKind.chunk, r.targetKind().?);
}

test "a malformed counter fails the call instead of reading as zero" {
    var exchanges = [_]Exchange{.{ .body = "{\"address\":\"aa\",\"counter\":3}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    try testing.expectError(error.JsonError, client.pointerGet("aa"));
}

test "pointerFinality reads open and forked answers" {
    var exchanges = [_]Exchange{
        .{ .body = "{\"address\":\"aa\",\"group\":7,\"answered\":7,\"status\":\"open\",\"counter\":\"3\"," ++
            "\"state\":null,\"states\":[],\"majority\":null,\"transferred_to\":null}" },
        .{ .body = "{\"address\":\"bb\",\"group\":7,\"answered\":6,\"status\":\"forked\",\"counter\":null," ++
            "\"state\":null,\"states\":[" ++
            "{\"state_id\":\"s1\",\"kind\":\"pointer\",\"kind_tag\":1,\"target\":\"t1\",\"holders\":4,\"transferred_to\":\"t1\"}," ++
            "{\"state_id\":\"s2\",\"kind\":\"chunk\",\"kind_tag\":0,\"target\":\"t2\",\"holders\":2,\"transferred_to\":null}]," ++
            "\"majority\":{\"state_id\":\"s1\",\"kind\":\"pointer\",\"kind_tag\":1,\"target\":\"t1\",\"holders\":4,\"transferred_to\":\"t1\"}," ++
            "\"transferred_to\":null}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const open = try client.pointerFinality("aa");
    defer open.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/pointers/aa/finality", exchanges[0].target());
    try testing.expect(open.status == .open);
    try testing.expectEqual(@as(?u64, 3), open.counter);
    try testing.expect(open.state == null);
    try testing.expect(open.majority == null);
    try testing.expect(open.transferred_to == null);
    try testing.expectEqual(@as(usize, 0), open.states.len);
    try testing.expectEqual(@as(u32, 7), open.group);
    try testing.expectEqual(@as(u32, 7), open.answered);
    try testing.expect(!open.isFinal());

    const forked = try client.pointerFinality("bb");
    defer forked.deinit(testing.allocator);
    try testing.expect(forked.status == .forked);
    try testing.expect(forked.counter == null);
    try testing.expectEqual(@as(u32, 6), forked.answered);
    try testing.expectEqual(@as(usize, 2), forked.states.len);
    try testing.expectEqualStrings("s1", forked.states[0].state_id);
    try testing.expectEqualStrings("t1", forked.states[0].transferred_to.?);
    try testing.expect(forked.states[1].transferred_to == null);
    try testing.expectEqual(@as(u32, 2), forked.states[1].holders);
    try testing.expectEqual(@as(u32, 4), forked.majority.?.holders);
    try testing.expectEqualStrings("s1", forked.majority.?.state_id);
}

test "pointerController and pointerResolve" {
    var exchanges = [_]Exchange{
        .{ .body = "{\"pointer\":\"cc\",\"transfers\":[\"bb\",\"cc\"],\"frozen\":false}" },
        .{ .body = "{\"kind\":\"unknown\",\"kind_tag\":42,\"target\":\"tt\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const ctl = try client.pointerController("aa");
    defer ctl.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/pointers/aa/controller", exchanges[0].target());
    try testing.expectEqualStrings("cc", ctl.pointer);
    try testing.expectEqual(@as(usize, 2), ctl.transfers.len);
    try testing.expectEqualStrings("bb", ctl.transfers[0]);
    try testing.expectEqualStrings("cc", ctl.transfers[1]);
    try testing.expect(!ctl.frozen);

    const res = try client.pointerResolve("aa");
    defer res.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/pointers/aa/resolve", exchanges[1].target());
    try testing.expectEqualStrings("unknown", res.kind);
    try testing.expectEqual(@as(u8, 42), res.kind_tag);
    try testing.expect(res.targetKind() == null);
    try testing.expectEqualStrings("tt", res.target);
}

test "pointerTransfer keeps a failed finality check" {
    var exchanges = [_]Exchange{.{ .body = "{\"address\":\"aa\",\"state_id\":\"ss\",\"finality\":null,\"finality_error\":\"only 3 answered\"}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const tr = try client.pointerTransfer("aa", "bb");
    defer tr.deinit(testing.allocator);

    try testing.expectEqual(std.http.Method.POST, exchanges[0].method.?);
    try testing.expectEqualStrings("/v1/pointers/transfer", exchanges[0].target());
    try testing.expectEqualStrings("{\"owner\":\"aa\",\"recipient\":\"bb\"}", exchanges[0].requestBody());
    try testing.expect(tr.finality == null);
    try testing.expectEqualStrings("only 3 answered", tr.finality_error.?);
    try testing.expectEqualStrings("ss", tr.state_id);
}

test "pointerTransfer reads the close group's finality" {
    var exchanges = [_]Exchange{.{ .body = "{\"address\":\"aa\",\"state_id\":\"ss\",\"finality\":{\"address\":\"aa\",\"group\":7," ++
        "\"answered\":7,\"status\":\"final\",\"counter\":null,\"state\":{\"state_id\":\"ss\",\"kind\":\"pointer\",\"kind_tag\":1," ++
        "\"target\":\"bb\",\"holders\":7,\"transferred_to\":\"bb\"},\"states\":[],\"majority\":null,\"transferred_to\":\"bb\"}}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const tr = try client.pointerTransfer("aa", "bb");
    defer tr.deinit(testing.allocator);

    const f = tr.finality.?;
    try testing.expect(f.isFinal());
    try testing.expectEqualStrings("bb", f.transferred_to.?);
    try testing.expectEqual(@as(u32, 7), f.state.?.holders);
    try testing.expect(tr.finality_error == null);
}

test "pointerPrepare for a transfer, then pointerFinalize" {
    var exchanges = [_]Exchange{
        .{ .body = "{\"upload_id\":\"up\",\"op\":\"transfer\",\"address\":\"aa\",\"state_id\":\"ss\"," ++
            "\"counter\":\"18446744073709551615\",\"payment_type\":\"wave_batch\"," ++
            "\"payments\":[{\"quote_hash\":\"0xq\",\"rewards_address\":\"0xr\",\"amount\":\"5\"}]," ++
            "\"total_amount\":\"5\",\"payment_vault_address\":\"0xv\",\"payment_token_address\":\"0xt\",\"rpc_url\":\"http://rpc\"}" },
        .{ .body = "{\"address\":\"aa\",\"state_id\":\"ss\",\"counter\":\"18446744073709551615\"," ++
            "\"finality\":{\"address\":\"aa\",\"group\":7,\"answered\":7,\"status\":\"final\"," ++
            "\"state\":{\"state_id\":\"ss\",\"kind\":\"pointer\",\"kind_tag\":1,\"target\":\"bb\",\"holders\":7,\"transferred_to\":\"bb\"}," ++
            "\"states\":[],\"transferred_to\":\"bb\"}}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const prep = try client.pointerPrepare("aa", .{ .transfer = .{ .recipient = "bb" } });
    defer prep.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/pointers/prepare", exchanges[0].target());
    // A transfer sends no target or kind, and signed quotes only on request.
    try testing.expectEqualStrings(
        "{\"owner\":\"aa\",\"op\":\"transfer\",\"recipient\":\"bb\"}",
        exchanges[0].requestBody(),
    );
    try testing.expectEqualStrings("up", prep.upload_id);
    try testing.expectEqualStrings("transfer", prep.op);
    try testing.expectEqual(models.pointer_final_counter, prep.counter);
    try testing.expectEqualStrings("wave_batch", prep.payment_type);
    try testing.expectEqual(@as(usize, 1), prep.payments.len);
    try testing.expectEqualStrings("0xq", prep.payments[0].quote_hash);
    try testing.expectEqualStrings("0xr", prep.payments[0].rewards_address);
    try testing.expectEqualStrings("5", prep.payments[0].amount);
    try testing.expectEqualStrings("5", prep.total_amount);
    try testing.expectEqualStrings("0xv", prep.payment_vault_address);
    try testing.expectEqualStrings("0xt", prep.payment_token_address);
    try testing.expectEqualStrings("http://rpc", prep.rpc_url);
    try testing.expectEqual(@as(usize, 0), prep.signed_quotes.len);

    const fin = try client.pointerFinalize("up", "{\"0xq\":\"0xtx\"}");
    defer fin.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/pointers/finalize", exchanges[1].target());
    try testing.expectEqualStrings(
        "{\"upload_id\":\"up\",\"tx_hashes\":{\"0xq\":\"0xtx\"}}",
        exchanges[1].requestBody(),
    );
    try testing.expectEqual(models.pointer_final_counter, fin.counter);
    const f = fin.finality.?;
    try testing.expect(f.isFinal());
    try testing.expectEqualStrings("bb", f.transferred_to.?);
    // A missing majority reads as null.
    try testing.expect(f.majority == null);
}

test "pointerPrepareWithOptions for an update asks for signed quotes" {
    var exchanges = [_]Exchange{.{ .body = "{\"upload_id\":\"up\",\"op\":\"update\",\"address\":\"aa\",\"state_id\":\"ss\",\"counter\":\"4\"," ++
        "\"payment_type\":\"wave_batch\",\"payments\":[{\"quote_hash\":\"0xq\",\"rewards_address\":\"0xr\",\"amount\":\"5\"}]," ++
        "\"total_amount\":\"5\",\"payment_vault_address\":\"0xv\",\"payment_token_address\":\"0xt\",\"rpc_url\":\"http://rpc\"," ++
        "\"signed_quotes\":[{\"quote_hash\":\"0xq\",\"quote\":\"cXVvdGU=\",\"commitment_sidecar\":\"c2lkZQ==\"}," ++
        "{\"quote_hash\":\"0xq2\",\"quote\":\"cTI=\"}]}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const prep = try client.pointerPrepareWithOptions(
        "aa",
        .{ .update = .{ .target = "tt", .kind = .pointer } },
        .{ .include_signed_quotes = true },
    );
    defer prep.deinit(testing.allocator);

    try testing.expectEqualStrings(
        "{\"owner\":\"aa\",\"op\":\"update\",\"target\":\"tt\",\"kind\":\"pointer\",\"include_signed_quotes\":true}",
        exchanges[0].requestBody(),
    );
    try testing.expectEqual(@as(u64, 4), prep.counter);
    try testing.expectEqual(@as(usize, 2), prep.signed_quotes.len);
    try testing.expectEqualStrings("0xq", prep.signed_quotes[0].quote_hash);
    try testing.expectEqualStrings("cXVvdGU=", prep.signed_quotes[0].quote);
    try testing.expectEqualStrings("c2lkZQ==", prep.signed_quotes[0].commitment_sidecar.?);
    try testing.expect(prep.signed_quotes[1].commitment_sidecar == null);
}

test "pointerFinalize rejects a tx_hashes map that is not a JSON object before sending" {
    // Nothing listens on port 1: an attempted request would be an HttpError.
    var client = antd.Client.init(testing.allocator, "http://127.0.0.1:1");
    defer client.deinit();
    try testing.expectError(error.JsonError, client.pointerFinalize("up", "[\"0xtx\"]"));
    try testing.expectError(error.JsonError, client.pointerFinalize("up", "not json"));
}

/// Expected mapping of one daemon error response.
const ErrorCase = struct {
    status: std.http.Status,
    body: []const u8,
    err: anyerror,
    retryable: bool = false,
};

test "pointer errors map by the body's code" {
    const cases = [_]ErrorCase{
        .{ .status = .conflict, .body = "{\"error\":\"x\",\"code\":\"POINTER_FINAL\"}", .err = error.PointerFinal },
        .{ .status = .conflict, .body = "{\"error\":\"x\",\"code\":\"POINTER_FORKED\"}", .err = error.PointerForked },
        .{ .status = .conflict, .body = "{\"error\":\"x\",\"code\":\"CONFLICT\"}", .err = error.Conflict },
        // ALREADY_EXISTS, and a 409 without a code, keep the status mapping.
        .{ .status = .conflict, .body = "{\"error\":\"x\",\"code\":\"ALREADY_EXISTS\"}", .err = error.AlreadyExists },
        .{ .status = .conflict, .body = "{\"error\":\"x\"}", .err = error.AlreadyExists },
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"SERVICE_UNAVAILABLE\"}", .err = error.ServiceUnavailable },
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"CLOSE_GROUP_SHORTFALL\",\"retryable\":true}", .err = error.CloseGroupShortfall, .retryable = true },
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"CLOSE_GROUP_SHORTFALL\",\"retryable\":false}", .err = error.CloseGroupShortfall },
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"CLOSE_GROUP_SHORTFALL\"}", .err = error.CloseGroupShortfall },
        // Only the JSON boolean true marks a retained paid state.
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"CLOSE_GROUP_SHORTFALL\",\"retryable\":\"true\"}", .err = error.CloseGroupShortfall },
        .{ .status = .not_found, .body = "{\"error\":\"x\",\"code\":\"NOT_FOUND\"}", .err = error.NotFound },
        .{ .status = .bad_request, .body = "{\"error\":\"x\",\"code\":\"BAD_REQUEST\"}", .err = error.BadRequest },
    };
    for (cases) |case| {
        var exchanges = [_]Exchange{.{ .status = case.status, .body = case.body }};
        var mock: MockDaemon = undefined;
        try mock.start(&exchanges);
        defer mock.stop();

        var client = antd.Client.init(testing.allocator, mock.url());
        defer client.deinit();
        const result = client.pointerUpdate("aa", "tt", .chunk);
        if (result) |w| {
            w.deinit(testing.allocator);
            return error.TestUnexpectedResult;
        } else |err| {
            testing.expectEqual(case.err, @as(anyerror, err)) catch |e| {
                std.debug.print("body {s}: got {s}\n", .{ case.body, @errorName(err) });
                return e;
            };
        }
        const info = client.getLastError().?;
        try testing.expectEqual(@as(u16, @intFromEnum(case.status)), info.status_code);
        try testing.expectEqualStrings("x", info.message);
        try testing.expectEqual(case.retryable, info.retryable);
        // The partial-upload fields stay zero for every pointer error.
        try testing.expect(!info.retention_known);
        try testing.expectEqual(@as(u64, 0), info.chunks_stored);
    }
}

test "a failed paid write is sent once, never retried" {
    // The mock would answer a second attempt; the client must not make one.
    var exchanges = [_]Exchange{
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"CLOSE_GROUP_SHORTFALL\"}" },
        .{ .body = "{\"address\":\"aa\",\"state_id\":\"ss\",\"counter\":\"1\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    try testing.expectError(error.CloseGroupShortfall, client.pointerUpdate("aa", "tt", .chunk));

    mock.stop();
    try testing.expectEqual(@as(usize, 1), mock.served);
}

test "a retained pointer finalize is not retried by the SDK" {
    var exchanges = [_]Exchange{
        .{ .status = .service_unavailable, .body = "{\"error\":\"x\",\"code\":\"CLOSE_GROUP_SHORTFALL\",\"retryable\":true}" },
        .{ .body = "{\"address\":\"aa\",\"state_id\":\"ss\",\"counter\":\"1\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    try testing.expectError(error.CloseGroupShortfall, client.pointerFinalize("up", "{}"));
    try testing.expect(client.getLastError().?.retryable);

    mock.stop();
    try testing.expectEqual(@as(usize, 1), mock.served);
}

// =============================================================================
// Error mapping without a daemon
// =============================================================================

test "errorForResponse maps the pointer codes" {
    try testing.expectEqual(error.PointerFinal, errors.errorForResponse(409, "POINTER_FINAL"));
    try testing.expectEqual(error.PointerForked, errors.errorForResponse(409, "POINTER_FORKED"));
    try testing.expectEqual(error.Conflict, errors.errorForResponse(409, "CONFLICT"));
    try testing.expectEqual(error.CloseGroupShortfall, errors.errorForResponse(503, "CLOSE_GROUP_SHORTFALL"));
    // Older codes and a missing code keep the status mapping.
    try testing.expectEqual(error.AlreadyExists, errors.errorForResponse(409, "ALREADY_EXISTS"));
    try testing.expectEqual(error.AlreadyExists, errors.errorForResponse(409, ""));
    try testing.expectEqual(error.ServiceUnavailable, errors.errorForResponse(503, ""));
    // The code is matched exactly.
    try testing.expectEqual(error.AlreadyExists, errors.errorForResponse(409, "pointer_final"));
}

test "parseErrorBody reads retryable for CLOSE_GROUP_SHORTFALL only as a JSON true" {
    const cases = [_]struct { field: []const u8, retryable: bool }{
        .{ .field = ",\"retryable\":true", .retryable = true },
        .{ .field = ",\"retryable\":false", .retryable = false },
        .{ .field = "", .retryable = false },
        .{ .field = ",\"retryable\":null", .retryable = false },
        .{ .field = ",\"retryable\":\"true\"", .retryable = false },
        .{ .field = ",\"retryable\":1", .retryable = false },
    };
    for (cases) |case| {
        const body = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"error\":\"Close group shortfall: 3/7\",\"code\":\"CLOSE_GROUP_SHORTFALL\",\"chunks_stored\":5{s}}}",
            .{case.field},
        );
        defer testing.allocator.free(body);

        const parsed = json_helpers.parseErrorBody(testing.allocator, body) orelse return error.JsonError;
        defer parsed.deinit(testing.allocator);
        try testing.expectEqualStrings("CLOSE_GROUP_SHORTFALL", parsed.code);
        try testing.expectEqual(case.retryable, parsed.retryable);
        // Counts and retention_known belong to PARTIAL_UPLOAD only.
        try testing.expectEqual(@as(u64, 0), parsed.chunks_stored);
        try testing.expect(!parsed.retention_known);
    }
}

// =============================================================================
// Counters
// =============================================================================

test "parsePointerCounter reads the whole u64 range" {
    try testing.expectEqual(@as(u64, 0), try json_helpers.parsePointerCounter("0"));
    try testing.expectEqual(@as(u64, 7), try json_helpers.parsePointerCounter("7"));
    try testing.expectEqual(@as(u64, 7), try json_helpers.parsePointerCounter("007"));
    try testing.expectEqual(@as(u64, std.math.maxInt(i64)), try json_helpers.parsePointerCounter("9223372036854775807"));
    try testing.expectEqual(@as(u64, 1) << 63, try json_helpers.parsePointerCounter("9223372036854775808"));
    try testing.expectEqual(models.pointer_final_counter, try json_helpers.parsePointerCounter("18446744073709551615"));
}

test "parsePointerCounter rejects anything but decimal digits within u64" {
    const bad = [_][]const u8{
        "",
        "+1",
        "-1",
        "-0",
        "1_000",
        " 1",
        "1 ",
        "0x10",
        "1.0",
        "1e3",
        "18446744073709551616",
        "99999999999999999999999",
        "abc",
    };
    for (bad) |s| {
        testing.expectError(error.JsonError, json_helpers.parsePointerCounter(s)) catch |e| {
            std.debug.print("counter {s} was accepted\n", .{s});
            return e;
        };
    }
}

test "a required counter must be a decimal string" {
    const values = [_][]const u8{ "3", "-1", "1.5", "null", "true", "[]", "{}", "\"\"", "\"+3\"", "\"18446744073709551616\"" };
    for (values) |value| {
        const body = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"address\":\"aa\",\"state_id\":\"ss\",\"counter\":{s}}}",
            .{value},
        );
        defer testing.allocator.free(body);
        try testing.expectError(error.JsonError, json_helpers.parsePointerWriteResult(testing.allocator, body));
        try testing.expectError(error.JsonError, json_helpers.parsePointerRecord(testing.allocator, body));
        try testing.expectError(error.JsonError, json_helpers.parsePointerFinalizeResult(testing.allocator, body));
    }
    // A missing counter fails too.
    try testing.expectError(
        error.JsonError,
        json_helpers.parsePointerWriteResult(testing.allocator, "{\"address\":\"aa\",\"state_id\":\"ss\"}"),
    );
}

test "a finality counter that is null, missing or empty reads as null" {
    const values = [_][]const u8{ ",\"counter\":null", "", ",\"counter\":\"\"" };
    for (values) |value| {
        const body = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"address\":\"aa\",\"group\":7,\"answered\":7,\"status\":\"open\"{s}}}",
            .{value},
        );
        defer testing.allocator.free(body);
        const f = try json_helpers.parsePointerFinality(testing.allocator, body);
        defer f.deinit(testing.allocator);
        try testing.expect(f.counter == null);
    }
}

test "a malformed finality counter fails the parse without leaking" {
    // The counter sits after allocated members in a transfer's finality, so
    // the error path has to free what was already copied.
    const bodies = [_][]const u8{
        "{\"address\":\"aa\",\"group\":7,\"answered\":7,\"status\":\"open\",\"counter\":3}",
        "{\"address\":\"aa\",\"group\":7,\"answered\":7,\"status\":\"open\",\"counter\":\"x\"}",
    };
    for (bodies) |body| {
        try testing.expectError(error.JsonError, json_helpers.parsePointerFinality(testing.allocator, body));
    }
    const transfer =
        \\{"address":"aa","state_id":"ss","finality":{"address":"aa","group":7,"answered":7,"status":"mystery","counter":"-1","states":[{"state_id":"s1","kind":"chunk","kind_tag":0,"target":"t","holders":1}]},"finality_error":"e"}
    ;
    try testing.expectError(error.JsonError, json_helpers.parsePointerTransferResult(testing.allocator, transfer));
}

// =============================================================================
// Models and builders
// =============================================================================

test "PointerFinalityStatus keeps an unknown status" {
    const known = [_]struct { wire: []const u8, tag: std.meta.Tag(models.PointerFinalityStatus) }{
        .{ .wire = "open", .tag = .open },
        .{ .wire = "settling", .tag = .settling },
        .{ .wire = "unconfirmed", .tag = .unconfirmed },
        .{ .wire = "final", .tag = .final },
        .{ .wire = "forked", .tag = .forked },
    };
    for (known) |k| {
        const status = try models.PointerFinalityStatus.fromWire(testing.allocator, k.wire);
        defer status.deinit(testing.allocator);
        try testing.expectEqual(k.tag, std.meta.activeTag(status));
        try testing.expectEqualStrings(k.wire, status.wire());
    }

    const body =
        \\{"address":"aa","group":7,"answered":5,"status":"quarantined","counter":null}
    ;
    const f = try json_helpers.parsePointerFinality(testing.allocator, body);
    defer f.deinit(testing.allocator);
    switch (f.status) {
        .unknown => |s| try testing.expectEqualStrings("quarantined", s),
        else => return error.TestUnexpectedResult,
    }
    try testing.expectEqualStrings("quarantined", f.status.wire());
    try testing.expect(!f.isFinal());
}

test "kind tags and peer counts outside their range" {
    const body =
        \\{"address":"aa","group":4294967296,"answered":-1,"status":"settling","state":{"state_id":"s","kind":"unknown","kind_tag":300,"target":"t","holders":2.5}}
    ;
    const f = try json_helpers.parsePointerFinality(testing.allocator, body);
    defer f.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), f.group);
    try testing.expectEqual(@as(u32, 0), f.answered);
    try testing.expectEqual(models.pointer_unknown_kind_tag, f.state.?.kind_tag);
    try testing.expectEqual(@as(u32, 0), f.state.?.holders);

    try testing.expectEqual(models.PointerKind.chunk, models.PointerKind.fromTag(0).?);
    try testing.expectEqual(models.PointerKind.pointer, models.PointerKind.fromTag(1).?);
    try testing.expect(models.PointerKind.fromTag(2) == null);
    try testing.expect(models.PointerKind.fromTag(models.pointer_unknown_kind_tag) == null);
}

test "pointerAddressEql ignores a 0x prefix and hex case" {
    try testing.expect(models.pointerAddressEql("abcd", "abcd"));
    try testing.expect(models.pointerAddressEql("0xabcd", "ABCD"));
    try testing.expect(models.pointerAddressEql("0XAbCd", "0xaBcD"));
    try testing.expect(!models.pointerAddressEql("abcd", "abce"));
    try testing.expect(!models.pointerAddressEql("abcd", "abcd00"));
}

test "buildPointerPrepareBody serialises each op" {
    const create = try json_helpers.buildPointerPrepareBody(testing.allocator, "aa", .{ .create = .{ .target = "tt" } }, .{});
    defer testing.allocator.free(create);
    try testing.expectEqualStrings("{\"owner\":\"aa\",\"op\":\"create\",\"target\":\"tt\",\"kind\":\"chunk\"}", create);

    const update = try json_helpers.buildPointerPrepareBody(testing.allocator, "aa", .{ .update = .{ .target = "tt", .kind = .pointer } }, .{});
    defer testing.allocator.free(update);
    try testing.expectEqualStrings("{\"owner\":\"aa\",\"op\":\"update\",\"target\":\"tt\",\"kind\":\"pointer\"}", update);

    const transfer = try json_helpers.buildPointerPrepareBody(testing.allocator, "aa", .{ .transfer = .{ .recipient = "bb" } }, .{ .include_signed_quotes = true });
    defer testing.allocator.free(transfer);
    try testing.expectEqualStrings("{\"owner\":\"aa\",\"op\":\"transfer\",\"recipient\":\"bb\",\"include_signed_quotes\":true}", transfer);
}

test "pointer request builders escape their strings" {
    const write = try json_helpers.buildPointerWriteBody(testing.allocator, "a\"a", "t\\t", .chunk);
    defer testing.allocator.free(write);
    try testing.expectEqualStrings("{\"owner\":\"a\\\"a\",\"target\":\"t\\\\t\",\"kind\":\"chunk\"}", write);

    const transfer = try json_helpers.buildPointerTransferBody(testing.allocator, "aa", "b\"b");
    defer testing.allocator.free(transfer);
    try testing.expectEqualStrings("{\"owner\":\"aa\",\"recipient\":\"b\\\"b\"}", transfer);

    const finalize = try json_helpers.buildPointerFinalizeBody(testing.allocator, "u\"p", "{}");
    defer testing.allocator.free(finalize);
    try testing.expectEqualStrings("{\"upload_id\":\"u\\\"p\",\"tx_hashes\":{}}", finalize);
}
