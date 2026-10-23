//! Live sha256 check against a running antd 0.17.0 or later with a devnet
//! behind it.
//!
//! Skipped unless these are set:
//!
//! - `ANTD_TEST_URL`: the daemon's REST base URL
//! - `ANTD_TEST_SHA_LINK`: a manifest link with the entries `public.txt` and
//!   `private.txt` (each with a sha256) and `nohash.txt` (none)
//! - `ANTD_TEST_SHA_PUBLIC_ADDRESS`, `ANTD_TEST_SHA_PUBLIC_SHA256`: a public
//!   data upload and its plaintext's SHA-256
//! - `ANTD_TEST_SHA_DATA_MAP_SHA256`: the SHA-256 of the private upload that
//!   `private.txt` points at
//!
//! This test makes ONE PAID call: a small public data upload, whose returned
//! `sha256` must equal the SHA-256 computed here over the same bytes.
//!
//! ```text
//! source ~/sha-fanout-daemon/fixtures.env && zig build test
//! ```

const std = @import("std");
const testing = std.testing;
const antd = @import("antd.zig");

fn requiredEnv(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => err,
    };
}

fn find(entries: []const antd.ManifestEntryInfo, effective_name: []const u8) !antd.ManifestEntryInfo {
    for (entries) |e| {
        if (std.mem.eql(u8, e.effective_name, effective_name)) return e;
    }
    std.debug.print("live_sha256: no entry named {s}\n", .{effective_name});
    return error.TestUnexpectedResult;
}

test "live sha256 on manifest entries and a public upload (ANTD_TEST_URL, ANTD_TEST_SHA_LINK)" {
    const allocator = testing.allocator;
    const url = (try requiredEnv(allocator, "ANTD_TEST_URL")) orelse return error.SkipZigTest;
    defer allocator.free(url);
    const link = (try requiredEnv(allocator, "ANTD_TEST_SHA_LINK")) orelse return error.SkipZigTest;
    defer allocator.free(link);
    const public_address = (try requiredEnv(allocator, "ANTD_TEST_SHA_PUBLIC_ADDRESS")) orelse return error.SkipZigTest;
    defer allocator.free(public_address);
    const public_sha = (try requiredEnv(allocator, "ANTD_TEST_SHA_PUBLIC_SHA256")) orelse return error.SkipZigTest;
    defer allocator.free(public_sha);
    const data_map_sha = (try requiredEnv(allocator, "ANTD_TEST_SHA_DATA_MAP_SHA256")) orelse return error.SkipZigTest;
    defer allocator.free(data_map_sha);

    var client = antd.Client.init(allocator, url);
    defer client.deinit();

    // 1. Decode the fixture link without resolving.
    {
        const decoded = try client.decodeManifestLink(link, false);
        defer decoded.deinit(allocator);
        const public = try find(decoded.entries, "public.txt");
        try testing.expectEqualStrings(public_sha, public.sha256.?);
        const private = try find(decoded.entries, "private.txt");
        try testing.expectEqualStrings(data_map_sha, private.sha256.?);
        const nohash = try find(decoded.entries, "nohash.txt");
        try testing.expect(nohash.sha256 == null);
    }

    // 2. Build from the public address with the hash: it comes back.
    {
        const built = try client.buildManifest(&.{
            .{ .path = "a.txt", .address = public_address, .sha256 = public_sha },
        }, .{ .embed_roots = false });
        defer built.deinit(allocator);
        try testing.expectEqual(@as(usize, 1), built.entries.len);
        try testing.expectEqualStrings(public_sha, built.entries[0].sha256.?);
    }

    // 3. A malformed hash is the daemon's 400.
    try testing.expectError(error.BadRequest, client.buildManifest(&.{
        .{ .path = "a.txt", .address = public_address, .sha256 = "zz" },
    }, .{ .embed_roots = false }));
    const info = client.getLastError().?;
    try testing.expectEqual(@as(u16, 400), info.status_code);
    try testing.expect(std.mem.indexOf(u8, info.message, "entries[0]") != null);

    // 4. One paid call: the upload's sha256 is the plaintext's SHA-256.
    {
        const payload = try std.fmt.allocPrint(allocator, "sha-fanout zig {d}", .{std.time.timestamp()});
        defer allocator.free(payload);
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
        const want = std.fmt.bytesToHex(digest, .lower);

        const result = try client.dataPutPublic(payload, .auto);
        defer result.deinit(allocator);
        std.debug.print("live_sha256: local sha256 {s}, returned {s}\n", .{ &want, result.sha256 orelse "(none)" });
        try testing.expectEqualStrings(&want, result.sha256.?);
    }
}
