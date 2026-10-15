//! Live manifest round trip against a running antd with a devnet behind it.
//!
//! Skipped unless both are set:
//!
//! - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
//! - `ANTD_TEST_MANIFEST_ADDRESSES`: two comma-separated addresses of public
//!   data already uploaded
//!
//! Used when set:
//!
//! - `ANTD_TEST_MANIFEST_SIZES`: the exact plaintext sizes of those two
//! - `ANTD_TEST_MANIFEST_DATA_MAP` and `ANTD_TEST_MANIFEST_DATA_MAP_SIZE`: a
//!   private upload's hex DataMap and its exact size
//! - `ANTD_TEST_MANIFEST_LINK`: an `ant://manifest/` link to decode
//!
//! Nothing is uploaded or paid for: the test only builds and decodes
//! manifests of data that is already on the network.
//!
//! ```text
//! ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> zig build test
//! ```

const std = @import("std");
const testing = std.testing;
const antd = @import("antd.zig");

const name = "antd-zig-live";
const path_one = "public/one.txt";
const path_two = "public/two.txt";
const path_private = "private/three.txt";

fn optionalEnv(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => err,
    };
}

fn parseSize(s: []const u8) !u64 {
    return std.fmt.parseInt(u64, std.mem.trim(u8, s, " "), 10);
}

fn find(entries: []const antd.ManifestEntryInfo, effective_name: []const u8) !antd.ManifestEntryInfo {
    for (entries) |e| {
        if (std.mem.eql(u8, e.effective_name, effective_name)) return e;
    }
    std.debug.print("live_manifests: no entry named {s}\n", .{effective_name});
    return error.TestUnexpectedResult;
}

const Fixtures = struct {
    addresses: [2][]const u8,
    sizes: ?[2]u64,
    data_map: ?[]const u8,
    data_map_size: ?u64,
};

/// The checks every resolving decode of the manifest built here must pass.
fn expectResolved(decoded: antd.DecodedManifest, fx: Fixtures) !void {
    try testing.expectEqualStrings("manifest", decoded.source);
    try testing.expectEqualStrings(name, decoded.name.?);
    try testing.expectEqual(@as(usize, if (fx.data_map != null) 3 else 2), decoded.entries.len);
    for (decoded.entries) |e| {
        if (e.error_message) |msg| {
            std.debug.print("live_manifests: {s} failed to resolve: {s}\n", .{ e.effective_name, msg });
            return error.TestUnexpectedResult;
        }
        try testing.expect(e.exact_size != null);
    }

    const one = try find(decoded.entries, path_one);
    const two = try find(decoded.entries, path_two);
    try testing.expectEqualStrings("public", one.kind);
    try testing.expectEqualStrings(fx.addresses[0], one.content_address);
    try testing.expect(one.data_map == null);
    try testing.expect(one.size == null);
    try testing.expectEqualStrings(fx.addresses[1], two.content_address);
    if (fx.sizes) |sizes| {
        try testing.expectEqual(@as(?u64, sizes[0]), one.exact_size);
        try testing.expectEqual(@as(?u64, sizes[1]), two.exact_size);
        try testing.expectEqual(@as(?u64, sizes[1]), two.size);
    }

    if (fx.data_map != null) {
        const private = try find(decoded.entries, path_private);
        try testing.expectEqualStrings("embedded", private.kind);
        try testing.expect(private.data_map.?.len > 0);
        try testing.expect(private.content_address.len == 64);
        if (fx.data_map_size) |size| try testing.expectEqual(@as(?u64, size), private.exact_size);
    }
}

test "live manifest round trip (ANTD_TEST_URL, ANTD_TEST_MANIFEST_ADDRESSES)" {
    const allocator = testing.allocator;
    const url = (try optionalEnv(allocator, "ANTD_TEST_URL")) orelse return error.SkipZigTest;
    defer allocator.free(url);
    const addresses = (try optionalEnv(allocator, "ANTD_TEST_MANIFEST_ADDRESSES")) orelse return error.SkipZigTest;
    defer allocator.free(addresses);
    var it = std.mem.splitScalar(u8, addresses, ',');
    const a = std.mem.trim(u8, it.next() orelse return error.SkipZigTest, " ");
    const b = std.mem.trim(u8, it.next() orelse return error.SkipZigTest, " ");
    if (a.len == 0 or b.len == 0) return error.SkipZigTest;

    const sizes_env = try optionalEnv(allocator, "ANTD_TEST_MANIFEST_SIZES");
    defer if (sizes_env) |s| allocator.free(s);
    const data_map = try optionalEnv(allocator, "ANTD_TEST_MANIFEST_DATA_MAP");
    defer if (data_map) |s| allocator.free(s);
    const data_map_size_env = try optionalEnv(allocator, "ANTD_TEST_MANIFEST_DATA_MAP_SIZE");
    defer if (data_map_size_env) |s| allocator.free(s);
    const link_env = try optionalEnv(allocator, "ANTD_TEST_MANIFEST_LINK");
    defer if (link_env) |s| allocator.free(s);

    var fx = Fixtures{
        .addresses = .{ a, b },
        .sizes = null,
        .data_map = if (data_map) |d| (if (d.len > 0) d else null) else null,
        .data_map_size = if (data_map_size_env) |s| try parseSize(s) else null,
    };
    if (sizes_env) |s| {
        var sit = std.mem.splitScalar(u8, s, ',');
        fx.sizes = .{ try parseSize(sit.next() orelse ""), try parseSize(sit.next() orelse "") };
    }

    var client = antd.Client.init(allocator, url);
    defer client.deinit();

    // --- build: the two public addresses and the DataMap, with paths ---
    const inputs: [3]antd.ManifestEntryInput = .{
        // No size: it must come back unset, not 0.
        .{ .path = path_one, .address = a },
        .{ .path = path_two, .address = b, .size = if (fx.sizes) |sz| sz[1] else null },
        .{ .path = path_private, .data_map = fx.data_map },
    };
    const entries: []const antd.ManifestEntryInput = if (fx.data_map != null) &inputs else inputs[0..2];

    const built = try client.buildManifest(entries, .{ .name = name });
    defer built.deinit(allocator);
    try testing.expect(built.manifest.len > 5);
    try testing.expectEqualSlices(u8, &.{ 0xC1, 'A', 'N', 'T', 0x01 }, built.manifest[0..5]);
    const link = built.link orelse {
        std.debug.print("live_manifests: the build returned no link\n", .{});
        return error.TestUnexpectedResult;
    };
    try testing.expect(std.mem.startsWith(u8, link, "ant://manifest/"));
    try testing.expectEqual(entries.len, built.entries.len);
    {
        const one = try find(built.entries, path_one);
        try testing.expectEqualStrings("public", one.kind);
        try testing.expectEqualStrings(path_one, one.path.?);
        try testing.expectEqualStrings(a, one.content_address);
        try testing.expect(one.size == null);
        try testing.expect(one.exact_size == null);
        try testing.expect(one.data_map == null);
        const two = try find(built.entries, path_two);
        try testing.expectEqualStrings("public", two.kind);
        try testing.expectEqualStrings(b, two.content_address);
        if (fx.sizes) |sz| try testing.expectEqual(@as(?u64, sz[1]), two.size);
        if (fx.data_map != null) {
            const private = try find(built.entries, path_private);
            try testing.expectEqualStrings("embedded", private.kind);
            // The build result carries no DataMap; a decode does.
            try testing.expect(private.data_map == null);
        }
    }

    // --- decode the bytes and the link, resolving sizes ---
    {
        const decoded = try client.decodeManifest(built.manifest, true);
        defer decoded.deinit(allocator);
        try expectResolved(decoded, fx);
    }
    {
        const decoded = try client.decodeManifestLink(link, true);
        defer decoded.deinit(allocator);
        try expectResolved(decoded, fx);
    }

    // Without resolve a public entry's exact size is unknown: null, not 0.
    {
        const decoded = try client.decodeManifest(built.manifest, false);
        defer decoded.deinit(allocator);
        const one = try find(decoded.entries, path_one);
        try testing.expect(one.exact_size == null);
        try testing.expect(one.error_message == null);
    }

    // A bare address decodes as a file link: one public entry, no path.
    {
        const decoded = try client.decodeManifestLink(a, false);
        defer decoded.deinit(allocator);
        try testing.expectEqualStrings("file_link", decoded.source);
        try testing.expectEqual(@as(usize, 1), decoded.entries.len);
        try testing.expectEqualStrings("public", decoded.entries[0].kind);
        try testing.expectEqualStrings(a, decoded.entries[0].content_address);
        try testing.expect(decoded.entries[0].path == null);
    }

    // --- the fixture link ---
    if (link_env) |fixture_link| {
        const decoded = try client.decodeManifestLink(fixture_link, true);
        defer decoded.deinit(allocator);
        try testing.expectEqualStrings("manifest", decoded.source);
        try testing.expect(decoded.entries.len > 0);
        for (decoded.entries) |e| {
            if (e.error_message) |msg| {
                std.debug.print("live_manifests: fixture entry {s} failed to resolve: {s}\n", .{ e.effective_name, msg });
                return error.TestUnexpectedResult;
            }
            const exact = e.exact_size orelse return error.TestUnexpectedResult;
            if (std.mem.eql(u8, e.kind, "embedded")) {
                try testing.expect(e.data_map.?.len > 0);
                if (fx.data_map_size) |size| try testing.expectEqual(size, exact);
            } else if (fx.sizes) |sz| {
                if (std.mem.eql(u8, e.content_address, a)) try testing.expectEqual(sz[0], exact);
                if (std.mem.eql(u8, e.content_address, b)) try testing.expectEqual(sz[1], exact);
            }
        }
    }

    // --- bad entries ---
    // Both sources: refused before sending.
    try testing.expectError(error.BadRequest, client.buildManifest(&.{.{ .data_map = "aa", .address = a }}, .{}));
    try testing.expectEqual(@as(u16, 0), client.getLastError().?.status_code);
    // An invalid path: the daemon's 400, naming the entry.
    try testing.expectError(error.BadRequest, client.buildManifest(&.{
        .{ .path = path_one, .address = a },
        .{ .path = "../x", .address = b },
    }, .{}));
    const info = client.getLastError().?;
    try testing.expectEqual(@as(u16, 400), info.status_code);
    try testing.expect(std.mem.indexOf(u8, info.message, "entries[1]") != null);
}
