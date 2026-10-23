//! sha256 tests: the upload results and the manifest entries read and send
//! `sha256` (antd 0.17.0). The Client runs against the mock daemon from
//! manifest_tests.zig; every test allocates through `std.testing.allocator`,
//! so a leak on any path fails it.

const std = @import("std");
const testing = std.testing;
const antd = @import("antd.zig");
const json_helpers = @import("json_helpers.zig");
const mt = @import("manifest_tests.zig");

const Exchange = mt.Exchange;
const MockDaemon = mt.MockDaemon;

const hash_a = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
const hash_b = "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7";

// =============================================================================
// Upload results
// =============================================================================

test "dataPut and dataPutPublic read sha256 when present" {
    var exchanges = [_]Exchange{
        .{ .body = "{\"data_map\":\"dm\",\"chunks_stored\":3,\"payment_mode_used\":\"auto\",\"sha256\":\"" ++ hash_a ++ "\"}" },
        .{ .body = "{\"address\":\"ad\",\"chunks_stored\":4,\"payment_mode_used\":\"auto\",\"sha256\":\"" ++ hash_b ++ "\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const private = try client.dataPut("hello", .auto);
    defer private.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/data", exchanges[0].target());
    try testing.expectEqualStrings("dm", private.data_map);
    try testing.expectEqualStrings(hash_a, private.sha256.?);

    const public = try client.dataPutPublic("hello", .auto);
    defer public.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/data/public", exchanges[1].target());
    try testing.expectEqualStrings("ad", public.address);
    try testing.expectEqualStrings(hash_b, public.sha256.?);
}

test "filePut and filePutPublic read sha256 when present" {
    var exchanges = [_]Exchange{
        .{ .body = "{\"data_map\":\"dm\",\"storage_cost_atto\":\"1\",\"gas_cost_wei\":\"2\",\"chunks_stored\":3,\"payment_mode_used\":\"auto\",\"sha256\":\"" ++ hash_a ++ "\"}" },
        .{ .body = "{\"address\":\"ad\",\"storage_cost_atto\":\"1\",\"gas_cost_wei\":\"2\",\"chunks_stored\":4,\"payment_mode_used\":\"auto\",\"sha256\":\"" ++ hash_b ++ "\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const private = try client.filePut("/tmp/x", .auto);
    defer private.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/files", exchanges[0].target());
    try testing.expectEqualStrings(hash_a, private.sha256.?);

    const public = try client.filePutPublic("/tmp/x", .auto);
    defer public.deinit(testing.allocator);
    try testing.expectEqualStrings("/v1/files/public", exchanges[1].target());
    try testing.expectEqualStrings(hash_b, public.sha256.?);
}

test "upload results read sha256 as null when the key is absent" {
    var exchanges = [_]Exchange{
        .{ .body = "{\"data_map\":\"dm\",\"chunks_stored\":3,\"payment_mode_used\":\"auto\"}" },
        .{ .body = "{\"address\":\"ad\",\"chunks_stored\":4,\"payment_mode_used\":\"auto\"}" },
        .{ .body = "{\"data_map\":\"dm\",\"storage_cost_atto\":\"1\",\"gas_cost_wei\":\"2\",\"chunks_stored\":3,\"payment_mode_used\":\"auto\"}" },
        .{ .body = "{\"address\":\"ad\",\"storage_cost_atto\":\"1\",\"gas_cost_wei\":\"2\",\"chunks_stored\":4,\"payment_mode_used\":\"auto\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const a = try client.dataPut("x", .auto);
    defer a.deinit(testing.allocator);
    try testing.expect(a.sha256 == null);
    const b = try client.dataPutPublic("x", .auto);
    defer b.deinit(testing.allocator);
    try testing.expect(b.sha256 == null);
    const c = try client.filePut("/tmp/x", .auto);
    defer c.deinit(testing.allocator);
    try testing.expect(c.sha256 == null);
    const d = try client.filePutPublic("/tmp/x", .auto);
    defer d.deinit(testing.allocator);
    try testing.expect(d.sha256 == null);
}

test "upload results read an empty or null sha256 as null" {
    const alloc = testing.allocator;
    const empty =
        \\{"data_map":"dm","address":"ad","storage_cost_atto":"1","gas_cost_wei":"2","chunks_stored":1,"payment_mode_used":"auto","sha256":""}
    ;
    const null_hash =
        \\{"data_map":"dm","address":"ad","storage_cost_atto":"1","gas_cost_wei":"2","chunks_stored":1,"payment_mode_used":"auto","sha256":null}
    ;
    for ([_][]const u8{ empty, null_hash }) |body| {
        const a = try json_helpers.parseDataPutResult(alloc, body);
        defer a.deinit(alloc);
        try testing.expect(a.sha256 == null);
        const b = try json_helpers.parseDataPutPublicResult(alloc, body);
        defer b.deinit(alloc);
        try testing.expect(b.sha256 == null);
        const c = try json_helpers.parseFilePutResult(alloc, body);
        defer c.deinit(alloc);
        try testing.expect(c.sha256 == null);
        const d = try json_helpers.parseFilePutPublicResult(alloc, body);
        defer d.deinit(alloc);
        try testing.expect(d.sha256 == null);
        const e = try json_helpers.parseFinalizeUploadResult(alloc, body);
        defer e.deinit(alloc);
        try testing.expect(e.sha256 == null);
    }
}

test "parseFinalizeUploadResult reads sha256, and null when absent" {
    const alloc = testing.allocator;
    const with = try json_helpers.parseFinalizeUploadResult(
        alloc,
        "{\"data_map\":\"dm\",\"data_map_address\":\"ad\",\"chunks_stored\":4,\"sha256\":\"" ++ hash_a ++ "\"}",
    );
    defer with.deinit(alloc);
    try testing.expectEqualStrings("dm", with.data_map);
    try testing.expectEqualStrings(hash_a, with.sha256.?);

    const without = try json_helpers.parseFinalizeUploadResult(alloc, "{\"data_map\":\"dm\",\"chunks_stored\":4}");
    defer without.deinit(alloc);
    try testing.expect(without.sha256 == null);
}

// =============================================================================
// Manifest entries
// =============================================================================

test "buildManifest sends sha256 on the entries that set it and omits it elsewhere" {
    const response = "{\"manifest\":\"wUFOVAE=\",\"entries\":[" ++
        "{\"effective_name\":\"a.txt\",\"path\":\"a.txt\",\"kind\":\"embedded\",\"content_address\":\"cc\",\"sha256\":\"" ++ hash_a ++ "\"}," ++
        "{\"effective_name\":\"b.txt\",\"path\":\"b.txt\",\"kind\":\"public\",\"content_address\":\"dd\"}," ++
        "{\"effective_name\":\"c.txt\",\"path\":\"c.txt\",\"kind\":\"public\",\"content_address\":\"ee\",\"sha256\":\"\"}]}";
    var exchanges = [_]Exchange{.{ .body = response }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const built = try client.buildManifest(&.{
        .{ .path = "a.txt", .data_map = "abcd", .sha256 = hash_a },
        .{ .path = "b.txt", .address = "11" },
        .{ .path = "c.txt", .address = "22", .sha256 = "" },
        // Passed through exactly as given: no case change, no checks.
        .{ .path = "d.txt", .address = "33", .sha256 = "ABCDEF" },
    }, .{});
    defer built.deinit(testing.allocator);

    const req = try mt.parseRequest(&exchanges[0]);
    defer req.deinit();
    const sent = req.value.object.get("entries").?.array.items;
    try testing.expectEqual(@as(usize, 4), sent.len);
    try mt.expectString(sent[0].object, "sha256", hash_a);
    try mt.expectAbsent(sent[1].object, "sha256");
    try mt.expectAbsent(sent[2].object, "sha256");
    try mt.expectString(sent[3].object, "sha256", "ABCDEF");

    // The build response carries sha256 on the entry that has one.
    try testing.expectEqual(@as(usize, 3), built.entries.len);
    try testing.expectEqualStrings(hash_a, built.entries[0].sha256.?);
    try testing.expect(built.entries[1].sha256 == null);
    try testing.expect(built.entries[2].sha256 == null);
}

test "decodeManifest reads sha256 per entry, and null when absent or empty" {
    const response = "{\"source\":\"manifest\",\"entries\":[" ++
        "{\"effective_name\":\"public.txt\",\"path\":\"public.txt\",\"kind\":\"public\",\"content_address\":\"11\",\"sha256\":\"" ++ hash_a ++ "\"}," ++
        "{\"effective_name\":\"private.txt\",\"path\":\"private.txt\",\"kind\":\"embedded\",\"content_address\":\"22\",\"data_map\":\"ab\",\"sha256\":\"" ++ hash_b ++ "\"}," ++
        "{\"effective_name\":\"nohash.txt\",\"path\":\"nohash.txt\",\"kind\":\"public\",\"content_address\":\"33\"}," ++
        "{\"effective_name\":\"empty.txt\",\"path\":\"empty.txt\",\"kind\":\"public\",\"content_address\":\"44\",\"sha256\":\"\"}]}";
    var exchanges = [_]Exchange{ .{ .body = response }, .{ .body = response } };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const by_link = try client.decodeManifestLink("ant://manifest/x", false);
    defer by_link.deinit(testing.allocator);
    const by_bytes = try client.decodeManifest("x", false);
    defer by_bytes.deinit(testing.allocator);
    for ([_]antd.DecodedManifest{ by_link, by_bytes }) |decoded| {
        try testing.expectEqual(@as(usize, 4), decoded.entries.len);
        try testing.expectEqualStrings(hash_a, decoded.entries[0].sha256.?);
        try testing.expectEqualStrings(hash_b, decoded.entries[1].sha256.?);
        try testing.expect(decoded.entries[2].sha256 == null);
        try testing.expect(decoded.entries[3].sha256 == null);
    }
}

test "a 400 for a bad sha256 maps to error.BadRequest and keeps the daemon's message" {
    const message = "Bad request: entries[0]: invalid hex sha256: Invalid character 'z' at position 0";
    var exchanges = [_]Exchange{
        .{ .status = .bad_request, .body = "{\"error\":\"" ++ message ++ "\",\"code\":\"BAD_REQUEST\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    try testing.expectError(error.BadRequest, client.buildManifest(&.{.{ .path = "a.txt", .address = "11", .sha256 = "zz" }}, .{}));
    const info = client.getLastError().?;
    try testing.expectEqual(@as(u16, 400), info.status_code);
    try testing.expectEqualStrings(message, info.message);
    // The hash went to the daemon untouched.
    const req = try mt.parseRequest(&exchanges[0]);
    defer req.deinit();
    try mt.expectString(req.value.object.get("entries").?.array.items[0].object, "sha256", "zz");
}
