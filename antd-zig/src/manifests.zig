//! Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
//! of files, each with an optional path and size and either an embedded
//! DataMap or a public DataMap address. The daemon builds and decodes them
//! through ant-core, so callers never re-implement the format. Nothing is
//! uploaded or paid for.
//!
//! This file holds the types, the request builders and the response parsers.
//! The `Client` methods (`buildManifest`, `decodeManifest`,
//! `decodeManifestLink`) are in antd.zig.
//!
//! On the REST wire the `.ant` bytes travel as standard base64 (`manifest` in
//! the build response and the decode request). The public API always takes
//! and returns the raw bytes; callers never see base64.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// One file for `Client.buildManifest`. Set exactly one of `data_map` or
/// `address`; an empty string counts as unset.
pub const ManifestEntryInput = struct {
    /// The relative path the entry extracts under, subject to the portable
    /// path rules. `null` (or empty): it extracts under its content address.
    path: ?[]const u8 = null,
    /// The plaintext size to record, as given (the creator's claim). `null`:
    /// none is recorded, and readers take the exact size from an embedded
    /// root DataMap. `0` is a size (an empty file) and is sent as such.
    size: ?u64 = null,
    /// A hex DataMap, as `dataPut` and `filePut` return it. The entry embeds
    /// it: the manifest is the key to the file.
    data_map: ?[]const u8 = null,
    /// A public file's DataMap address (hex, 32 bytes), as `dataPutPublic`
    /// and `filePutPublic` return it.
    address: ?[]const u8 = null,
    /// The plaintext's SHA-256 (hex), recorded in the manifest. Passed to the
    /// daemon exactly as given, with no check here: the daemon validates it
    /// (upper or lower case; anything else is a 400, `error.BadRequest`).
    /// `null` or empty: not sent. Needs antd 0.17.0 or later.
    sha256: ?[]const u8 = null,
};

/// The optional parts of a `Client.buildManifest` call. `.{}` is the
/// default: no name, no torrent info hashes, and roots embedded.
pub const BuildManifestOptions = struct {
    /// A suggested root directory name (one portable path component).
    /// `null` (or empty): none.
    name: ?[]const u8 = null,
    /// BitTorrent info hashes of the same files: hex, 40 characters for v1
    /// and/or 64 for v2.
    torrent_info_hashes: []const []const u8 = &.{},
    /// Resolve each shrunk DataMap's root (fetching its wrapper records) and
    /// embed the root when it is at most 64 KiB, so recipients skip that
    /// fetch (ADR-0006's policy). This reads from the network. `false`
    /// embeds shrunk DataMaps exactly as given (antd-go's
    /// `KeepShrunkDataMaps`). Sent as `embed_roots`.
    embed_roots: bool = true,
};

/// What a manifest says about one entry. Every string is owned; free the
/// entry with `deinit`, or the whole result with its own `deinit`.
pub const ManifestEntryInfo = struct {
    /// `path`, or the content address in hex when there is none.
    effective_name: []const u8,
    /// `null` when the entry has no path.
    path: ?[]const u8 = null,
    /// The size recorded in the manifest: the creator's claim. `null` when
    /// none was recorded (never 0 for "unset").
    size: ?u64 = null,
    /// "embedded" or "public".
    kind: []const u8,
    /// Hex. The file's public DataMap address, whether or not it was ever
    /// made public; the same for private and public uploads of one file.
    content_address: []const u8,
    /// The embedded DataMap in the hex form `dataGet`, `dataStream` and
    /// `fileGet` accept. Decode only; `null` for public entries and in a
    /// build result.
    data_map: ?[]const u8 = null,
    /// The exact plaintext size: from an embedded root DataMap, or after a
    /// resolving decode. `null` when unknown (never 0 for "unset").
    exact_size: ?u64 = null,
    /// Why a resolving decode failed for this entry (the wire's `error`).
    /// `null` when it didn't. One entry's failure is not a failed call.
    error_message: ?[]const u8 = null,
    /// The plaintext's SHA-256 (lowercase hex) the manifest records for the
    /// entry. `null` when none is recorded, the key is absent or it is empty
    /// (antd before 0.17.0 never sends it).
    sha256: ?[]const u8 = null,

    pub fn deinit(self: ManifestEntryInfo, allocator: Allocator) void {
        allocator.free(self.effective_name);
        if (self.path) |s| allocator.free(s);
        allocator.free(self.kind);
        allocator.free(self.content_address);
        if (self.data_map) |s| allocator.free(s);
        if (self.error_message) |s| allocator.free(s);
        if (self.sha256) |s| allocator.free(s);
    }
};

/// The result of `Client.buildManifest`. Free it with `deinit`.
pub const BuiltManifest = struct {
    /// The raw `.ant` bytes (owned), already decoded from the wire's base64.
    manifest: []const u8,
    /// The `ant://manifest/` link, set only when it fits the recommended
    /// 1,500 bytes; `null` otherwise. Share `manifest` as a file instead.
    link: ?[]const u8 = null,
    /// In encoded order (sorted by effective name).
    entries: []ManifestEntryInfo = &.{},

    pub fn deinit(self: BuiltManifest, allocator: Allocator) void {
        allocator.free(self.manifest);
        if (self.link) |s| allocator.free(s);
        freeEntries(allocator, self.entries);
    }
};

/// The result of `Client.decodeManifest` and `Client.decodeManifestLink`.
/// Free it with `deinit`.
pub const DecodedManifest = struct {
    /// "manifest", or "file_link" for a file link or bare address (reported
    /// as one public entry with no path).
    source: []const u8,
    /// The suggested root directory name; `null` when the manifest has none.
    name: ?[]const u8 = null,
    /// Hex; `null` when absent.
    torrent_info_hash_v1: ?[]const u8 = null,
    /// Hex; `null` when absent.
    torrent_info_hash_v2: ?[]const u8 = null,
    entries: []ManifestEntryInfo = &.{},

    pub fn deinit(self: DecodedManifest, allocator: Allocator) void {
        allocator.free(self.source);
        if (self.name) |s| allocator.free(s);
        if (self.torrent_info_hash_v1) |s| allocator.free(s);
        if (self.torrent_info_hash_v2) |s| allocator.free(s);
        freeEntries(allocator, self.entries);
    }
};

fn freeEntries(allocator: Allocator, entries: []ManifestEntryInfo) void {
    for (entries) |e| e.deinit(allocator);
    allocator.free(entries);
}

/// What `Client.decodeManifest` / `decodeManifestLink` send.
pub const DecodeInput = union(enum) {
    /// Raw `.ant` bytes; sent as base64.
    manifest: []const u8,
    /// An `ant://` manifest link, file link, or bare 64-hex address.
    link: []const u8,
};

fn nonEmpty(s: ?[]const u8) ?[]const u8 {
    const v = s orelse return null;
    return if (v.len == 0) null else v;
}

/// The daemon's cap on entry errors it names in one message.
const max_reported_entry_errors = 20;

/// The index of the first entry that does not set exactly one of `data_map`
/// or `address` (an empty string counts as unset), or `null` when every entry
/// does. antd-go's `checkManifestEntries`; the Client runs it before sending.
pub fn firstInvalidEntry(entries: []const ManifestEntryInput) ?usize {
    for (entries, 0..) |e, i| {
        if (entryProblem(e) != null) return i;
    }
    return null;
}

fn entryProblem(e: ManifestEntryInput) ?[]const u8 {
    const has_map = nonEmpty(e.data_map) != null;
    const has_addr = nonEmpty(e.address) != null;
    if (has_map and has_addr) return "give data_map or address, not both";
    if (!has_map and !has_addr) return "needs a data_map or an address";
    return null;
}

/// The message the daemon's 400 carries when entries fail the both-or-neither
/// check (`parse_entries` / `entry_errors_message` in antd), so a refusal
/// here and there read the same: `N invalid entries: entries[i]: ...; ...`,
/// at most 20 named, then `; and K more`. `null` when every entry is valid.
/// The caller frees the result.
pub fn invalidEntriesMessage(allocator: Allocator, entries: []const ManifestEntryInput) !?[]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    var count: usize = 0;
    for (entries, 0..) |e, i| {
        const problem = entryProblem(e) orelse continue;
        if (count < max_reported_entry_errors) {
            if (count > 0) try buf.appendSlice("; ");
            try buf.writer().print("entries[{d}]: {s}", .{ i, problem });
        }
        count += 1;
    }
    if (count == 0) {
        buf.deinit();
        return null;
    }
    if (count > max_reported_entry_errors) {
        try buf.writer().print("; and {d} more", .{count - max_reported_entry_errors});
    }
    const head = try std.fmt.allocPrint(allocator, "{d} invalid entries: ", .{count});
    defer allocator.free(head);
    try buf.insertSlice(0, head);
    return try buf.toOwnedSlice();
}

/// The daemon's message for a decode with neither bytes nor a link.
pub const empty_decode_message = "needs a manifest (base64 .ant bytes) or a link";

// --- Request bodies ---

/// The POST /v1/manifests/build body. Unset (null or empty) `path`, `sha256`,
/// `name` and torrent hashes are omitted, as is an unset `size`; `embed_roots` is
/// always sent. Returns `error.BadRequest` if an entry fails
/// `firstInvalidEntry`. The caller frees the result.
pub fn buildManifestBuildBody(allocator: Allocator, entries: []const ManifestEntryInput, options: BuildManifestOptions) ![]u8 {
    if (firstInvalidEntry(entries) != null) return error.BadRequest;

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    var w = std.json.writeStream(buf.writer(), .{});

    try w.beginObject();
    try w.objectField("entries");
    try w.beginArray();
    for (entries) |e| {
        try w.beginObject();
        if (nonEmpty(e.path)) |p| {
            try w.objectField("path");
            try w.write(p);
        }
        if (e.size) |s| {
            try w.objectField("size");
            try w.write(s);
        }
        if (nonEmpty(e.data_map)) |dm| {
            try w.objectField("data_map");
            try w.write(dm);
        } else {
            try w.objectField("address");
            try w.write(e.address.?);
        }
        if (nonEmpty(e.sha256)) |h| {
            try w.objectField("sha256");
            try w.write(h);
        }
        try w.endObject();
    }
    try w.endArray();
    try w.objectField("embed_roots");
    try w.write(options.embed_roots);
    if (nonEmpty(options.name)) |n| {
        try w.objectField("name");
        try w.write(n);
    }
    if (options.torrent_info_hashes.len > 0) {
        try w.objectField("torrent_info_hashes");
        try w.write(options.torrent_info_hashes);
    }
    try w.endObject();

    return buf.toOwnedSlice();
}

/// The POST /v1/manifests/decode body: `{"manifest":"<base64>"}` or
/// `{"link":"..."}`, plus `resolve`. The caller frees the result.
pub fn buildManifestDecodeBody(allocator: Allocator, input: DecodeInput, resolve: bool) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    var w = std.json.writeStream(buf.writer(), .{});

    try w.beginObject();
    switch (input) {
        .manifest => |bytes| {
            const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
            defer allocator.free(encoded);
            try w.objectField("manifest");
            try w.write(std.base64.standard.Encoder.encode(encoded, bytes));
        },
        .link => |link| {
            try w.objectField("link");
            try w.write(link);
        },
    }
    try w.objectField("resolve");
    try w.write(resolve);
    try w.endObject();

    return buf.toOwnedSlice();
}

// --- Response parsers ---
//
// Strict where a lenient read would mislead: a missing `manifest`, `source`,
// `effective_name`, `kind` or `content_address`, invalid base64, a
// non-object entry, or a size that is not a JSON integer within u64 fails
// with `error.JsonError`. Absent, null and empty optional strings read as
// `null`; absent and null sizes read as `null`, never 0.

/// Parse a POST /v1/manifests/build response. The caller frees the result
/// with `deinit`.
pub fn parseBuiltManifest(allocator: Allocator, body: []const u8) !BuiltManifest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const b64 = switch (obj.get("manifest") orelse return error.JsonError) {
        .string => |s| s,
        else => return error.JsonError,
    };
    const manifest = try decodeBase64(allocator, b64);
    errdefer allocator.free(manifest);

    const link = try optionalString(allocator, obj, "link");
    errdefer if (link) |s| allocator.free(s);

    const entries = try parseEntries(allocator, obj);

    return .{ .manifest = manifest, .link = link, .entries = entries };
}

/// Parse a POST /v1/manifests/decode response. The caller frees the result
/// with `deinit`.
pub fn parseDecodedManifest(allocator: Allocator, body: []const u8) !DecodedManifest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const source = try requiredString(allocator, obj, "source");
    errdefer allocator.free(source);
    const name = try optionalString(allocator, obj, "name");
    errdefer if (name) |s| allocator.free(s);
    const v1 = try optionalString(allocator, obj, "torrent_info_hash_v1");
    errdefer if (v1) |s| allocator.free(s);
    const v2 = try optionalString(allocator, obj, "torrent_info_hash_v2");
    errdefer if (v2) |s| allocator.free(s);

    const entries = try parseEntries(allocator, obj);

    return .{
        .source = source,
        .name = name,
        .torrent_info_hash_v1 = v1,
        .torrent_info_hash_v2 = v2,
        .entries = entries,
    };
}

fn parseEntries(allocator: Allocator, obj: std.json.ObjectMap) ![]ManifestEntryInfo {
    const items: []const std.json.Value = switch (obj.get("entries") orelse .null) {
        .null => &.{},
        .array => |a| a.items,
        else => return error.JsonError,
    };

    var list = try std.ArrayList(ManifestEntryInfo).initCapacity(allocator, items.len);
    errdefer {
        for (list.items) |e| e.deinit(allocator);
        list.deinit();
    }
    for (items) |item| {
        const o = switch (item) {
            .object => |o| o,
            else => return error.JsonError,
        };
        list.appendAssumeCapacity(try parseEntry(allocator, o));
    }
    return list.toOwnedSlice();
}

fn parseEntry(allocator: Allocator, o: std.json.ObjectMap) !ManifestEntryInfo {
    const effective_name = try requiredString(allocator, o, "effective_name");
    errdefer allocator.free(effective_name);
    const path = try optionalString(allocator, o, "path");
    errdefer if (path) |s| allocator.free(s);
    const size = try optionalU64(o, "size");
    const kind = try requiredString(allocator, o, "kind");
    errdefer allocator.free(kind);
    const content_address = try requiredString(allocator, o, "content_address");
    errdefer allocator.free(content_address);
    const data_map = try optionalString(allocator, o, "data_map");
    errdefer if (data_map) |s| allocator.free(s);
    const exact_size = try optionalU64(o, "exact_size");
    const error_message = try optionalString(allocator, o, "error");
    errdefer if (error_message) |s| allocator.free(s);
    const sha256 = try optionalString(allocator, o, "sha256");

    return .{
        .effective_name = effective_name,
        .path = path,
        .size = size,
        .kind = kind,
        .content_address = content_address,
        .data_map = data_map,
        .exact_size = exact_size,
        .error_message = error_message,
        .sha256 = sha256,
    };
}

/// An owned copy of a string field that must be present.
fn requiredString(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    return switch (obj.get(key) orelse return error.JsonError) {
        .string => |s| try allocator.dupe(u8, s),
        else => error.JsonError,
    };
}

/// An owned copy of an optional string field: `null` when absent, null or
/// empty; `error.JsonError` when it is not a string.
fn optionalString(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    return switch (obj.get(key) orelse return null) {
        .null => null,
        .string => |s| if (s.len == 0) null else try allocator.dupe(u8, s),
        else => error.JsonError,
    };
}

/// An optional size: `null` when absent or null, the value for a JSON
/// integer within u64, and `error.JsonError` for anything else (a float, a
/// negative number, a string), so a malformed size never reads as 0 or as
/// unset.
fn optionalU64(obj: std.json.ObjectMap, key: []const u8) !?u64 {
    return switch (obj.get(key) orelse return null) {
        .null => null,
        .integer => |n| std.math.cast(u64, n) orelse return error.JsonError,
        // std.json hands over an integer past i64 as its digits: 2^63 ..
        // 2^64 - 1 is still a u64, a negative or anything past 2^64 - 1 is
        // not. A float past f64 lands here too, and parseInt rejects it.
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch return error.JsonError,
        else => error.JsonError,
    };
}

fn decodeBase64(allocator: Allocator, b64: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const len = decoder.calcSizeForSlice(b64) catch return error.JsonError;
    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);
    decoder.decode(out, b64) catch return error.JsonError;
    return out;
}
