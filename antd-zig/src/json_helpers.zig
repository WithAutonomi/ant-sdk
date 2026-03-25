const std = @import("std");
const Allocator = std.mem.Allocator;
const models = @import("models.zig");

/// Duplicate a std.json string value into an owned allocation.
fn dupeString(allocator: Allocator, value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| try allocator.dupe(u8, s),
        else => try allocator.dupe(u8, ""),
    };
}

/// Extract an integer from a JSON value (handles both integer and float).
fn jsonInt(value: std.json.Value) i64 {
    return switch (value) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    };
}

/// Parse a HealthStatus from a JSON response body.
pub fn parseHealthStatus(allocator: Allocator, body: []const u8) !models.HealthStatus {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const status_val = obj.get("status") orelse return error.JsonError;
    const ok = switch (status_val) {
        .string => |s| std.mem.eql(u8, s, "ok"),
        else => false,
    };

    const network = dupeString(allocator, obj.get("network") orelse .null) catch
        return error.JsonError;

    return .{ .ok = ok, .network = network };
}

/// Parse a PutResult from a JSON response body. The address_key parameter
/// specifies which JSON field holds the address (e.g. "address" or "data_map").
pub fn parsePutResult(allocator: Allocator, body: []const u8, address_key: []const u8) !models.PutResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const cost = dupeString(allocator, obj.get("cost") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(cost);

    const address = dupeString(allocator, obj.get(address_key) orelse .null) catch
        return error.JsonError;

    return .{ .cost = cost, .address = address };
}

/// Parse base64-encoded "data" field from JSON response and decode it.
pub fn parseBase64Data(allocator: Allocator, body: []const u8) ![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const data_val = obj.get("data") orelse return error.JsonError;
    const b64_str = switch (data_val) {
        .string => |s| s,
        else => return error.JsonError,
    };

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(b64_str) catch return error.JsonError;
    const decoded = allocator.alloc(u8, decoded_len) catch return error.JsonError;
    std.base64.standard.Decoder.decode(decoded, b64_str) catch {
        allocator.free(decoded);
        return error.JsonError;
    };
    return decoded;
}

/// Parse a cost string from a JSON response body.
pub fn parseCost(allocator: Allocator, body: []const u8) ![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    return dupeString(allocator, obj.get("cost") orelse .null) catch
        return error.JsonError;
}

/// Parse a GraphEntry from a JSON response body.
pub fn parseGraphEntry(allocator: Allocator, body: []const u8) !models.GraphEntry {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const owner = dupeString(allocator, obj.get("owner") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(owner);

    const content = dupeString(allocator, obj.get("content") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(content);

    // Parse parents array
    const parents = blk: {
        const parents_val = obj.get("parents") orelse break :blk &[_][]const u8{};
        const parents_arr = switch (parents_val) {
            .array => |a| a,
            else => break :blk &[_][]const u8{},
        };
        if (parents_arr.items.len == 0) break :blk &[_][]const u8{};

        const parents_slice = allocator.alloc([]const u8, parents_arr.items.len) catch
            return error.JsonError;
        var count: usize = 0;
        errdefer {
            for (parents_slice[0..count]) |p| allocator.free(p);
            allocator.free(parents_slice);
        }
        for (parents_arr.items) |item| {
            parents_slice[count] = dupeString(allocator, item) catch return error.JsonError;
            count += 1;
        }
        break :blk parents_slice;
    };
    errdefer {
        for (parents) |p| allocator.free(p);
        if (parents.len > 0) allocator.free(parents);
    }

    // Parse descendants array
    const descendants = blk: {
        const desc_val = obj.get("descendants") orelse break :blk &[_]models.GraphDescendant{};
        const desc_arr = switch (desc_val) {
            .array => |a| a,
            else => break :blk &[_]models.GraphDescendant{},
        };
        if (desc_arr.items.len == 0) break :blk &[_]models.GraphDescendant{};

        const desc_slice = allocator.alloc(models.GraphDescendant, desc_arr.items.len) catch
            return error.JsonError;
        var count: usize = 0;
        errdefer {
            for (desc_slice[0..count]) |d| d.deinit(allocator);
            allocator.free(desc_slice);
        }
        for (desc_arr.items) |item| {
            const d_obj = switch (item) {
                .object => |o| o,
                else => return error.JsonError,
            };
            const pk = dupeString(allocator, d_obj.get("public_key") orelse .null) catch
                return error.JsonError;
            errdefer allocator.free(pk);
            const dc = dupeString(allocator, d_obj.get("content") orelse .null) catch
                return error.JsonError;
            desc_slice[count] = .{ .public_key = pk, .content = dc };
            count += 1;
        }
        break :blk desc_slice;
    };

    return .{
        .owner = owner,
        .parents = parents,
        .content = content,
        .descendants = descendants,
    };
}

/// Parse an Archive from a JSON response body.
pub fn parseArchive(allocator: Allocator, body: []const u8) !models.Archive {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const entries_val = obj.get("entries") orelse return .{ .entries = &[_]models.ArchiveEntry{} };
    const entries_arr = switch (entries_val) {
        .array => |a| a,
        else => return .{ .entries = &[_]models.ArchiveEntry{} },
    };

    if (entries_arr.items.len == 0) return .{ .entries = &[_]models.ArchiveEntry{} };

    const entries = allocator.alloc(models.ArchiveEntry, entries_arr.items.len) catch
        return error.JsonError;
    var count: usize = 0;
    errdefer {
        for (entries[0..count]) |e| e.deinit(allocator);
        allocator.free(entries);
    }

    for (entries_arr.items) |item| {
        const e_obj = switch (item) {
            .object => |o| o,
            else => return error.JsonError,
        };
        const path = dupeString(allocator, e_obj.get("path") orelse .null) catch
            return error.JsonError;
        errdefer allocator.free(path);
        const address = dupeString(allocator, e_obj.get("address") orelse .null) catch
            return error.JsonError;

        entries[count] = .{
            .path = path,
            .address = address,
            .created = jsonInt(e_obj.get("created") orelse .null),
            .modified = jsonInt(e_obj.get("modified") orelse .null),
            .size = jsonInt(e_obj.get("size") orelse .null),
        };
        count += 1;
    }

    return .{ .entries = entries };
}

// --- JSON body construction helpers ---
// These use manual string building to avoid std.json.writeStream API differences
// across Zig versions.

/// Escape a string for JSON output.
fn jsonEscapeString(allocator: Allocator, s: []const u8) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    try list.writer(allocator).print("\\u{x:0>4}", .{c});
                } else {
                    try list.append(allocator, c);
                }
            },
        }
    }
    try list.append(allocator, '"');
    return list.toOwnedSlice(allocator);
}

/// Build a JSON object string with a single base64-encoded "data" field.
pub fn buildDataBody(allocator: Allocator, data: []const u8) ![]const u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
    const encoded = allocator.alloc(u8, encoded_len) catch return error.JsonError;
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, data);

    const escaped = jsonEscapeString(allocator, encoded) catch return error.JsonError;
    defer allocator.free(escaped);

    return std.fmt.allocPrint(allocator, "{{\"data\":{s}}}", .{escaped}) catch return error.JsonError;
}

/// Values supported in JSON body construction.
pub const JsonValue = union(enum) {
    string: []const u8,
    boolean: bool,
    string_array: []const []const u8,
    descendants: []const models.GraphDescendant,
    archive_entries: []const models.ArchiveEntry,
};

/// Build a JSON request body from key-value pairs.
pub fn buildJsonBody(allocator: Allocator, fields: []const struct { key: []const u8, value: JsonValue }) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.append(allocator, '{');

    for (fields, 0..) |field, i| {
        if (i > 0) try buf.append(allocator, ',');

        // Write key
        const escaped_key = jsonEscapeString(allocator, field.key) catch return error.JsonError;
        defer allocator.free(escaped_key);
        try buf.appendSlice(allocator, escaped_key);
        try buf.append(allocator, ':');

        // Write value
        switch (field.value) {
            .string => |s| {
                const escaped_val = jsonEscapeString(allocator, s) catch return error.JsonError;
                defer allocator.free(escaped_val);
                try buf.appendSlice(allocator, escaped_val);
            },
            .boolean => |b| {
                try buf.appendSlice(allocator, if (b) "true" else "false");
            },
            .string_array => |arr| {
                try buf.append(allocator, '[');
                for (arr, 0..) |item, j| {
                    if (j > 0) try buf.append(allocator, ',');
                    const escaped_item = jsonEscapeString(allocator, item) catch return error.JsonError;
                    defer allocator.free(escaped_item);
                    try buf.appendSlice(allocator, escaped_item);
                }
                try buf.append(allocator, ']');
            },
            .descendants => |descs| {
                try buf.append(allocator, '[');
                for (descs, 0..) |d, j| {
                    if (j > 0) try buf.append(allocator, ',');
                    const pk = jsonEscapeString(allocator, d.public_key) catch return error.JsonError;
                    defer allocator.free(pk);
                    const ct = jsonEscapeString(allocator, d.content) catch return error.JsonError;
                    defer allocator.free(ct);
                    const entry_str = std.fmt.allocPrint(allocator, "{{\"public_key\":{s},\"content\":{s}}}", .{ pk, ct }) catch return error.JsonError;
                    defer allocator.free(entry_str);
                    try buf.appendSlice(allocator, entry_str);
                }
                try buf.append(allocator, ']');
            },
            .archive_entries => |entries| {
                try buf.append(allocator, '[');
                for (entries, 0..) |e, j| {
                    if (j > 0) try buf.append(allocator, ',');
                    const p = jsonEscapeString(allocator, e.path) catch return error.JsonError;
                    defer allocator.free(p);
                    const a = jsonEscapeString(allocator, e.address) catch return error.JsonError;
                    defer allocator.free(a);
                    const entry_str = std.fmt.allocPrint(
                        allocator,
                        "{{\"path\":{s},\"address\":{s},\"created\":{d},\"modified\":{d},\"size\":{d}}}",
                        .{ p, a, e.created, e.modified, e.size },
                    ) catch return error.JsonError;
                    defer allocator.free(entry_str);
                    try buf.appendSlice(allocator, entry_str);
                }
                try buf.append(allocator, ']');
            },
        }
    }

    try buf.append(allocator, '}');
    return buf.toOwnedSlice(allocator);
}

/// Parse a WalletAddress from a JSON response body.
pub fn parseWalletAddress(allocator: Allocator, body: []const u8) !models.WalletAddress {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    return .{
        .address = dupeString(allocator, obj.get("address") orelse .null) catch
            return error.JsonError,
    };
}

/// Parse a WalletBalance from a JSON response body.
pub fn parseWalletBalance(allocator: Allocator, body: []const u8) !models.WalletBalance {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    return .{
        .balance = dupeString(allocator, obj.get("balance") orelse .null) catch
            return error.JsonError,
        .gas_balance = dupeString(allocator, obj.get("gas_balance") orelse .null) catch
            return error.JsonError,
    };
}

/// Extract the "error" message from a JSON error response body.
pub fn parseErrorMessage(allocator: Allocator, body: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return null,
    };
    const err_val = obj.get("error") orelse return null;
    return switch (err_val) {
        .string => |s| allocator.dupe(u8, s) catch null,
        else => null,
    };
}
