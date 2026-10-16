//! Manifest API tests: the Client against a mock daemon on a loopback
//! socket, plus the request builders and response parsers it uses.
//!
//! The mock daemon serves one canned response per connection, in order, and
//! records the method, target and body of each request it was sent. Every
//! test allocates through `std.testing.allocator`, so a leak on any success
//! or error path fails it.

const std = @import("std");
const testing = std.testing;
const antd = @import("antd.zig");
const manifests = @import("manifests.zig");

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
    body_buf: [16 * 1024]u8 = undefined,
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

/// Parse a recorded request body as a JSON value for field checks.
fn parseRequest(ex: *const Exchange) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, testing.allocator, ex.requestBody(), .{});
}

fn expectString(obj: std.json.ObjectMap, key: []const u8, want: []const u8) !void {
    const v = obj.get(key) orelse {
        std.debug.print("missing request field {s}\n", .{key});
        return error.TestExpectedEqual;
    };
    switch (v) {
        .string => |s| try testing.expectEqualStrings(want, s),
        else => return error.TestExpectedEqual,
    }
}

fn expectBool(obj: std.json.ObjectMap, key: []const u8, want: bool) !void {
    const v = obj.get(key) orelse {
        std.debug.print("missing request field {s}\n", .{key});
        return error.TestExpectedEqual;
    };
    switch (v) {
        .bool => |b| try testing.expectEqual(want, b),
        else => return error.TestExpectedEqual,
    }
}

fn expectInteger(obj: std.json.ObjectMap, key: []const u8, want: i64) !void {
    const v = obj.get(key) orelse {
        std.debug.print("missing request field {s}\n", .{key});
        return error.TestExpectedEqual;
    };
    switch (v) {
        .integer => |n| try testing.expectEqual(want, n),
        else => return error.TestExpectedEqual,
    }
}

fn expectAbsent(obj: std.json.ObjectMap, key: []const u8) !void {
    if (obj.get(key) != null) {
        std.debug.print("unexpected request field {s}\n", .{key});
        return error.TestUnexpectedResult;
    }
}

/// The five-byte `.ant` header; "wUFOVAE=" is its base64.
const manifest_header = [_]u8{ 0xC1, 'A', 'N', 'T', 0x01 };

// =============================================================================
// Client against the mock daemon
// =============================================================================

test "buildManifest sends entries and options and returns the raw bytes" {
    const response =
        \\{"manifest":"wUFOVAE=","link":"ant://manifest/wUFOVAE","entries":[
        \\{"effective_name":"a.txt","path":"a.txt","size":10,"kind":"embedded","content_address":"cc","exact_size":10},
        \\{"effective_name":"11","kind":"public","content_address":"11"}]}
    ;
    var exchanges = [_]Exchange{.{ .body = response }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const built = try client.buildManifest(&.{
        .{ .path = "a.txt", .size = 10, .data_map = "abcd" },
        .{ .address = "11" },
    }, .{
        .name = "album",
        .torrent_info_hashes = &.{"0123456789012345678901234567890123456789"},
        .embed_roots = false,
    });
    defer built.deinit(testing.allocator);

    try testing.expectEqual(std.http.Method.POST, exchanges[0].method.?);
    try testing.expectEqualStrings("/v1/manifests/build", exchanges[0].target());
    const req = try parseRequest(&exchanges[0]);
    defer req.deinit();
    const body = req.value.object;
    try expectString(body, "name", "album");
    try expectBool(body, "embed_roots", false);
    const hashes = body.get("torrent_info_hashes").?.array.items;
    try testing.expectEqual(@as(usize, 1), hashes.len);
    try testing.expectEqualStrings("0123456789012345678901234567890123456789", hashes[0].string);
    const sent = body.get("entries").?.array.items;
    try testing.expectEqual(@as(usize, 2), sent.len);
    try expectString(sent[0].object, "path", "a.txt");
    try expectString(sent[0].object, "data_map", "abcd");
    try expectInteger(sent[0].object, "size", 10);
    try expectAbsent(sent[0].object, "address");
    try expectString(sent[1].object, "address", "11");
    try expectAbsent(sent[1].object, "path");
    try expectAbsent(sent[1].object, "size");
    try expectAbsent(sent[1].object, "data_map");

    try testing.expectEqualSlices(u8, &manifest_header, built.manifest);
    try testing.expectEqualStrings("ant://manifest/wUFOVAE", built.link.?);
    try testing.expectEqual(@as(usize, 2), built.entries.len);
    const a = built.entries[0];
    try testing.expectEqualStrings("a.txt", a.effective_name);
    try testing.expectEqualStrings("a.txt", a.path.?);
    try testing.expectEqualStrings("embedded", a.kind);
    try testing.expectEqualStrings("cc", a.content_address);
    try testing.expectEqual(@as(?u64, 10), a.size);
    try testing.expectEqual(@as(?u64, 10), a.exact_size);
    try testing.expect(a.data_map == null);
    try testing.expect(a.error_message == null);
    // Unset reads as null, not 0.
    const p = built.entries[1];
    try testing.expectEqualStrings("11", p.effective_name);
    try testing.expectEqualStrings("public", p.kind);
    try testing.expect(p.path == null);
    try testing.expect(p.size == null);
    try testing.expect(p.exact_size == null);
}

test "buildManifest embeds roots by default and omits unset options" {
    var exchanges = [_]Exchange{.{ .body = "{\"manifest\":\"\",\"entries\":[]}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const built = try client.buildManifest(&.{.{ .address = "11", .path = "" }}, .{});
    defer built.deinit(testing.allocator);

    const req = try parseRequest(&exchanges[0]);
    defer req.deinit();
    const body = req.value.object;
    try expectBool(body, "embed_roots", true);
    try expectAbsent(body, "name");
    try expectAbsent(body, "torrent_info_hashes");
    // An empty path is unset, as in antd-go.
    try expectAbsent(body.get("entries").?.array.items[0].object, "path");

    try testing.expectEqual(@as(usize, 0), built.manifest.len);
    try testing.expect(built.link == null);
    try testing.expectEqual(@as(usize, 0), built.entries.len);
}

test "a zero size is sent and read back as 0, not as unset" {
    const response =
        \\{"manifest":"wUFOVAE=","entries":[
        \\{"effective_name":"empty","path":"empty","size":0,"kind":"public","content_address":"11","exact_size":0}]}
    ;
    var exchanges = [_]Exchange{.{ .body = response }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const built = try client.buildManifest(&.{.{ .path = "empty", .size = 0, .address = "11" }}, .{});
    defer built.deinit(testing.allocator);

    const req = try parseRequest(&exchanges[0]);
    defer req.deinit();
    try expectInteger(req.value.object.get("entries").?.array.items[0].object, "size", 0);
    try testing.expectEqual(@as(?u64, 0), built.entries[0].size);
    try testing.expectEqual(@as(?u64, 0), built.entries[0].exact_size);
}

test "buildManifest rejects an entry with both or neither before sending" {
    // Never dialled: the check runs before any request.
    var client = antd.Client.init(testing.allocator, "http://127.0.0.1:1");
    defer client.deinit();

    // One bad entry.
    try testing.expectError(error.BadRequest, client.buildManifest(&.{
        .{ .address = "11" },
        .{ .data_map = "aa", .address = "bb" },
    }, .{}));
    try testing.expectEqual(@as(u16, 400), client.getLastError().?.status_code);
    try testing.expectEqualStrings(
        "1 invalid entries: entries[1]: give data_map or address, not both",
        client.getLastError().?.message,
    );

    // Two bad entries are reported together, as the daemon does.
    try testing.expectError(error.BadRequest, client.buildManifest(&.{
        .{ .data_map = "aa", .address = "bb" },
        .{ .address = "11" },
        .{ .path = "a.txt" },
    }, .{}));
    try testing.expectEqual(@as(u16, 400), client.getLastError().?.status_code);
    try testing.expectEqualStrings(
        "2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address",
        client.getLastError().?.message,
    );

    // Empty strings count as unset.
    try testing.expectError(error.BadRequest, client.buildManifest(&.{.{ .data_map = "", .address = "" }}, .{}));
    try testing.expectEqualStrings(
        "1 invalid entries: entries[0]: needs a data_map or an address",
        client.getLastError().?.message,
    );
}

test "invalidEntriesMessage names at most 20 entries, then counts the rest" {
    var entries: [23]antd.ManifestEntryInput = undefined;
    for (&entries) |*e| e.* = .{};
    const msg = (try manifests.invalidEntriesMessage(testing.allocator, &entries)).?;
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.startsWith(u8, msg, "23 invalid entries: entries[0]: needs a data_map or an address; entries[1]:"));
    try testing.expect(std.mem.indexOf(u8, msg, "entries[19]") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "entries[20]") == null);
    try testing.expect(std.mem.endsWith(u8, msg, "; and 3 more"));
    try testing.expect((try manifests.invalidEntriesMessage(testing.allocator, &.{.{ .address = "aa" }})) == null);
}

test "firstInvalidEntry treats empty strings as unset" {
    try testing.expectEqual(@as(?usize, null), manifests.firstInvalidEntry(&.{}));
    try testing.expectEqual(@as(?usize, null), manifests.firstInvalidEntry(&.{
        .{ .data_map = "aa" },
        .{ .address = "bb" },
        .{ .data_map = "", .address = "cc" },
        .{ .data_map = "dd", .address = "" },
    }));
    try testing.expectEqual(@as(?usize, 0), manifests.firstInvalidEntry(&.{.{}}));
    try testing.expectEqual(@as(?usize, 1), manifests.firstInvalidEntry(&.{
        .{ .address = "bb" },
        .{ .data_map = "aa", .address = "bb" },
    }));
    try testing.expectEqual(@as(?usize, 0), manifests.firstInvalidEntry(&.{.{ .data_map = "", .address = "" }}));
    try testing.expectError(error.BadRequest, manifests.buildManifestBuildBody(testing.allocator, &.{.{}}, .{}));
}

test "decodeManifest sends base64 and reads the header and entries" {
    const response =
        \\{"source":"manifest","name":"album","torrent_info_hash_v2":"bb","entries":[
        \\{"effective_name":"a.txt","path":"a.txt","kind":"embedded","content_address":"cc","data_map":"abcd","exact_size":3},
        \\{"effective_name":"b","path":"b","kind":"public","content_address":"dd","error":"Record not found: gone"}]}
    ;
    var exchanges = [_]Exchange{.{ .body = response }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const decoded = try client.decodeManifest(&manifest_header, true);
    defer decoded.deinit(testing.allocator);

    try testing.expectEqualStrings("/v1/manifests/decode", exchanges[0].target());
    const req = try parseRequest(&exchanges[0]);
    defer req.deinit();
    try expectString(req.value.object, "manifest", "wUFOVAE=");
    try expectBool(req.value.object, "resolve", true);
    try expectAbsent(req.value.object, "link");

    try testing.expectEqualStrings("manifest", decoded.source);
    try testing.expectEqualStrings("album", decoded.name.?);
    try testing.expect(decoded.torrent_info_hash_v1 == null);
    try testing.expectEqualStrings("bb", decoded.torrent_info_hash_v2.?);
    try testing.expectEqual(@as(usize, 2), decoded.entries.len);
    const a = decoded.entries[0];
    try testing.expectEqualStrings("abcd", a.data_map.?);
    try testing.expectEqual(@as(?u64, 3), a.exact_size);
    try testing.expect(a.size == null);
    try testing.expect(a.error_message == null);
    // One entry's resolve failure is in its error, not a failed call.
    const b = decoded.entries[1];
    try testing.expectEqualStrings("Record not found: gone", b.error_message.?);
    try testing.expect(b.exact_size == null);
    try testing.expect(b.data_map == null);
}

test "decodeManifestLink sends the link and no bytes" {
    const addr = "42424242424242424242424242424242424242424242424242424242424242aa";
    var exchanges = [_]Exchange{.{ .body = "{\"source\":\"file_link\",\"entries\":[{\"effective_name\":\"" ++ addr ++
        "\",\"kind\":\"public\",\"content_address\":\"" ++ addr ++ "\"}]}" }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const decoded = try client.decodeManifestLink(addr, false);
    defer decoded.deinit(testing.allocator);

    const req = try parseRequest(&exchanges[0]);
    defer req.deinit();
    try expectString(req.value.object, "link", addr);
    try expectBool(req.value.object, "resolve", false);
    try expectAbsent(req.value.object, "manifest");

    try testing.expectEqualStrings("file_link", decoded.source);
    try testing.expect(decoded.name == null);
    try testing.expectEqual(@as(usize, 1), decoded.entries.len);
    try testing.expectEqualStrings(addr, decoded.entries[0].content_address);
    try testing.expect(decoded.entries[0].path == null);
}

test "decode rejects empty input before sending" {
    var client = antd.Client.init(testing.allocator, "http://127.0.0.1:1");
    defer client.deinit();
    try testing.expectError(error.BadRequest, client.decodeManifest("", false));
    try testing.expectEqual(@as(u16, 400), client.getLastError().?.status_code);
    try testing.expectEqualStrings("needs a manifest (base64 .ant bytes) or a link", client.getLastError().?.message);
    try testing.expectError(error.BadRequest, client.decodeManifestLink("", true));
    try testing.expectEqual(@as(u16, 400), client.getLastError().?.status_code);
    try testing.expectEqualStrings("needs a manifest (base64 .ant bytes) or a link", client.getLastError().?.message);
}

test "the .ant bytes round-trip through base64 byte for byte" {
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    var b64_buf: [std.base64.standard.Encoder.calcSize(256)]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&b64_buf, &bytes);

    const build_body = try std.fmt.allocPrint(testing.allocator, "{{\"manifest\":\"{s}\",\"entries\":[]}}", .{b64});
    defer testing.allocator.free(build_body);
    var exchanges = [_]Exchange{
        .{ .body = build_body },
        .{ .body = "{\"source\":\"manifest\",\"entries\":[]}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    const built = try client.buildManifest(&.{.{ .address = "11" }}, .{});
    defer built.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &bytes, built.manifest);

    const decoded = try client.decodeManifest(built.manifest, false);
    defer decoded.deinit(testing.allocator);
    const req = try parseRequest(&exchanges[1]);
    defer req.deinit();
    try expectString(req.value.object, "manifest", b64);
}

test "a 400 maps to error.BadRequest and keeps the daemon's message" {
    const message = "Bad request: 1 invalid entries: entries[0]: invalid path \\\"../x\\\": path component \\\"..\\\" is not allowed";
    var exchanges = [_]Exchange{
        .{ .status = .bad_request, .body = "{\"error\":\"" ++ message ++ "\",\"code\":\"BAD_REQUEST\"}" },
        .{ .status = .bad_request, .body = "{\"error\":\"Bad request: not a manifest: missing or invalid header\",\"code\":\"BAD_REQUEST\"}" },
    };
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();

    try testing.expectError(error.BadRequest, client.buildManifest(&.{.{ .path = "../x", .address = "11" }}, .{}));
    const info = client.getLastError().?;
    try testing.expectEqual(@as(u16, 400), info.status_code);
    try testing.expectEqualStrings(
        "Bad request: 1 invalid entries: entries[0]: invalid path \"../x\": path component \"..\" is not allowed",
        info.message,
    );

    try testing.expectError(error.BadRequest, client.decodeManifest("nope", false));
    try testing.expectEqualStrings("Bad request: not a manifest: missing or invalid header", client.getLastError().?.message);
}

test "sizes up to u64 max read exactly; null reads as unset" {
    const response =
        \\{"source":"manifest","entries":[
        \\{"effective_name":"big","kind":"public","content_address":"11","size":18446744073709551615,"exact_size":null}]}
    ;
    var exchanges = [_]Exchange{.{ .body = response }};
    var mock: MockDaemon = undefined;
    try mock.start(&exchanges);
    defer mock.stop();

    var client = antd.Client.init(testing.allocator, mock.url());
    defer client.deinit();
    const decoded = try client.decodeManifestLink("ant://manifest/x", false);
    defer decoded.deinit(testing.allocator);
    try testing.expectEqual(@as(?u64, std.math.maxInt(u64)), decoded.entries[0].size);
    try testing.expect(decoded.entries[0].exact_size == null);
}

// =============================================================================
// Parsers and builders
// =============================================================================

test "malformed responses fail with error.JsonError and leak nothing" {
    const a = testing.allocator;
    const entry = "\"effective_name\":\"n\",\"kind\":\"public\",\"content_address\":\"11\"";
    // Build responses.
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "{\"entries\":[]}"));
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "{\"manifest\":\"not base64!\",\"entries\":[]}"));
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "{\"manifest\":5}"));
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "[]"));
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "{\"manifest\":\"wUFOVAE=\",\"link\":\"l\",\"entries\":{}}"));
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "{\"manifest\":\"wUFOVAE=\",\"link\":7,\"entries\":[]}"));
    // A failure after earlier entries parsed frees them too.
    try testing.expectError(error.JsonError, manifests.parseBuiltManifest(a, "{\"manifest\":\"wUFOVAE=\",\"link\":\"l\",\"entries\":[{" ++ entry ++ "},3]}"));
    // Decode responses.
    try testing.expectError(error.JsonError, manifests.parseDecodedManifest(a, "{\"entries\":[]}"));
    try testing.expectError(error.JsonError, manifests.parseDecodedManifest(a, "{\"source\":\"manifest\",\"name\":\"n\",\"entries\":[{\"kind\":\"public\",\"content_address\":\"11\"}]}"));
    // A size that is not a JSON integer within u64 is malformed, not unset.
    const bad_sizes = [_][]const u8{ "-1", "1.5", "\"10\"", "true", "18446744073709551616", "1e400" };
    for (bad_sizes) |s| {
        const body = try std.fmt.allocPrint(a, "{{\"source\":\"manifest\",\"name\":\"n\",\"entries\":[{{" ++ entry ++ "}},{{" ++ entry ++ ",\"path\":\"p\",\"size\":{s}}}]}}", .{s});
        defer a.free(body);
        try testing.expectError(error.JsonError, manifests.parseDecodedManifest(a, body));
    }
    const bad_exact = try std.fmt.allocPrint(a, "{{\"source\":\"manifest\",\"entries\":[{{" ++ entry ++ ",\"data_map\":\"dd\",\"error\":\"e\",\"exact_size\":-5}}]}}", .{});
    defer a.free(bad_exact);
    try testing.expectError(error.JsonError, manifests.parseDecodedManifest(a, bad_exact));
}

test "empty and null optional strings read as null" {
    const decoded = try manifests.parseDecodedManifest(testing.allocator,
        \\{"source":"manifest","name":"","torrent_info_hash_v1":null,"torrent_info_hash_v2":"",
        \\"entries":[{"effective_name":"n","path":"","kind":"public","content_address":"11","data_map":null,"error":""}]}
    );
    defer decoded.deinit(testing.allocator);
    try testing.expect(decoded.name == null);
    try testing.expect(decoded.torrent_info_hash_v1 == null);
    try testing.expect(decoded.torrent_info_hash_v2 == null);
    const e = decoded.entries[0];
    try testing.expect(e.path == null);
    try testing.expect(e.data_map == null);
    try testing.expect(e.error_message == null);
}

test "request bodies escape strings and carry sizes past 2^53 exactly" {
    const a = testing.allocator;
    const body = try manifests.buildManifestBuildBody(a, &.{
        .{ .path = "dir/\"quoted\"\n.txt", .size = std.math.maxInt(u64), .data_map = "abcd" },
    }, .{ .name = "caf\u{e9}" });
    defer a.free(body);
    try testing.expectEqualStrings(
        "{\"entries\":[{\"path\":\"dir/\\\"quoted\\\"\\n.txt\",\"size\":18446744073709551615,\"data_map\":\"abcd\"}],\"embed_roots\":true,\"name\":\"caf\u{e9}\"}",
        body,
    );

    const decode = try manifests.buildManifestDecodeBody(a, .{ .link = "ant://manifest/x" }, true);
    defer a.free(decode);
    try testing.expectEqualStrings("{\"link\":\"ant://manifest/x\",\"resolve\":true}", decode);
}
