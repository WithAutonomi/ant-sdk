//! Live pointer round trip against a running antd with a devnet behind it.
//!
//! Skipped unless both are set:
//!
//! - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
//! - `ANTD_TEST_POINTER_OWNERS`: two comma-separated pointer addresses the
//!   daemon holds keys for (`antd --pointer-keys`) and that have **never been
//!   written**. The test creates both, transfers the first to the second, and
//!   leaves the second with a prepared write awaiting payment, so each pair
//!   can be used once.
//!
//! Every write is paid by the daemon's wallet, so run it against a devnet:
//!
//! ```text
//! ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_POINTER_OWNERS=<hex>,<hex> zig build test
//! ```

const std = @import("std");
const testing = std.testing;
const antd = @import("antd.zig");

const target_one = "antd-zig pointer target one";
const target_two = "antd-zig pointer target two";

test "live pointer round trip (ANTD_TEST_URL, ANTD_TEST_POINTER_OWNERS)" {
    const allocator = testing.allocator;
    const url = std.process.getEnvVarOwned(allocator, "ANTD_TEST_URL") catch return error.SkipZigTest;
    defer allocator.free(url);
    const owners = std.process.getEnvVarOwned(allocator, "ANTD_TEST_POINTER_OWNERS") catch return error.SkipZigTest;
    defer allocator.free(owners);
    var it = std.mem.splitScalar(u8, owners, ',');
    const a = std.mem.trim(u8, it.next() orelse return error.SkipZigTest, " ");
    const b = std.mem.trim(u8, it.next() orelse return error.SkipZigTest, " ");
    if (a.len == 0 or b.len == 0) return error.SkipZigTest;

    var client = antd.Client.init(allocator, url);
    defer client.deinit();

    // Both owners must be writable through this daemon.
    {
        const keys = try client.pointerKeys();
        defer keys.deinit(allocator);
        if (!keys.contains(a) or !keys.contains(b)) {
            std.debug.print("live_pointers: the daemon holds no key for one of {s}, {s}\n", .{ a, b });
            return error.TestUnexpectedResult;
        }
    }

    // Real targets, so the chain can be followed back to bytes.
    const put_one = try client.dataPutPublic(target_one, .auto);
    defer put_one.deinit(allocator);
    const put_two = try client.dataPutPublic(target_two, .auto);
    defer put_two.deinit(allocator);
    const one = put_one.address;
    const two = put_two.address;

    // --- create, read, update ---
    if (client.pointerGet(a)) |r| {
        r.deinit(allocator);
        std.debug.print("live_pointers: owner {s} has been written before; use a fresh pair\n", .{a});
        return error.TestUnexpectedResult;
    } else |err| try testing.expectEqual(@as(anyerror, error.NotFound), err);

    {
        const w = try client.pointerCreate(a, one, .chunk);
        defer w.deinit(allocator);
        try testing.expectEqual(@as(u64, 0), w.counter);
        try testing.expect(antd.pointerAddressEql(w.address, a));
    }
    try testing.expectError(error.AlreadyExists, client.pointerCreate(a, two, .chunk));
    {
        const r = try client.pointerGet(a);
        defer r.deinit(allocator);
        try testing.expectEqual(@as(u64, 0), r.counter);
        try testing.expectEqualStrings(one, r.target);
        try testing.expect(!r.is_final);
        try testing.expect(r.transferred_to == null);
        try testing.expectEqual(antd.PointerKind.chunk, r.targetKind().?);
        try testing.expectEqual(@as(usize, 2 * 1952), r.owner.len);
    }
    {
        const res = try client.pointerResolve(a);
        defer res.deinit(allocator);
        try testing.expectEqualStrings(one, res.target);
        const bytes = try client.dataGetPublic(res.target);
        defer allocator.free(bytes);
        try testing.expectEqualStrings(target_one, bytes);
    }

    {
        const w = try client.pointerUpdate(a, two, .chunk);
        defer w.deinit(allocator);
        try testing.expectEqual(@as(u64, 1), w.counter);
    }
    {
        const res = try client.pointerResolve(a);
        defer res.deinit(allocator);
        try testing.expectEqualStrings(two, res.target);
    }
    {
        const f = try client.pointerFinality(a);
        defer f.deinit(allocator);
        try testing.expect(f.status == .open);
        try testing.expectEqual(@as(?u64, 1), f.counter);
        try testing.expectEqual(f.group, f.answered);
    }

    // --- the recipient, then transfer a -> b ---
    {
        const w = try client.pointerCreate(b, one, .chunk);
        defer w.deinit(allocator);
        try testing.expectEqual(@as(u64, 0), w.counter);
    }
    {
        const t = try client.pointerTransfer(a, b);
        defer t.deinit(allocator);
        const f = t.finality orelse {
            std.debug.print("live_pointers: no finality after the transfer: {s}\n", .{t.finality_error orelse "(none)"});
            return error.TestUnexpectedResult;
        };
        try testing.expect(f.isFinal());
        try testing.expect(antd.pointerAddressEql(f.transferred_to.?, b));
    }
    {
        const r = try client.pointerGet(a);
        defer r.deinit(allocator);
        try testing.expect(r.is_final);
        try testing.expectEqual(antd.pointer_final_counter, r.counter);
        try testing.expect(antd.pointerAddressEql(r.transferred_to.?, b));
    }
    {
        const c = try client.pointerController(a);
        defer c.deinit(allocator);
        try testing.expect(antd.pointerAddressEql(c.pointer, b));
        try testing.expectEqual(@as(usize, 1), c.transfers.len);
        try testing.expect(antd.pointerAddressEql(c.transfers[0], b));
        try testing.expect(!c.frozen);
    }
    {
        // a now resolves through b.
        const res = try client.pointerResolve(a);
        defer res.deinit(allocator);
        try testing.expectEqualStrings(one, res.target);
        const f = try client.pointerFinality(a);
        defer f.deinit(allocator);
        try testing.expect(f.isFinal());
    }

    // A final pointer refuses every write, before anything is paid.
    try testing.expectError(error.PointerFinal, client.pointerUpdate(a, one, .chunk));
    try testing.expectError(error.PointerFinal, client.pointerTransfer(a, b));

    // --- external signer, up to the quote ---
    // Last: the prepared write blocks b's other writes until it expires.
    {
        const p = try client.pointerPrepareWithOptions(
            b,
            .{ .update = .{ .target = two, .kind = .chunk } },
            .{ .include_signed_quotes = true },
        );
        defer p.deinit(allocator);
        try testing.expectEqualStrings("update", p.op);
        try testing.expectEqual(@as(u64, 1), p.counter);
        try testing.expectEqualStrings("wave_batch", p.payment_type);
        try testing.expect(p.payments.len > 0);
        try testing.expect(p.upload_id.len > 0);
        try testing.expectEqual(p.payments.len, p.signed_quotes.len);

        try testing.expectError(error.Conflict, client.pointerUpdate(b, two, .chunk));
        try testing.expectError(error.Conflict, client.pointerPrepare(b, .{ .update = .{ .target = two } }));
        // A finalize without the payment is refused and keeps the session.
        try testing.expectError(error.BadRequest, client.pointerFinalize(p.upload_id, "{}"));
        try testing.expectError(error.Conflict, client.pointerUpdate(b, two, .chunk));
    }
}
