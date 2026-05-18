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
    errdefer allocator.free(network);

    const version = dupeString(allocator, obj.get("version") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(version);

    const evm_network = dupeString(allocator, obj.get("evm_network") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(evm_network);

    const uptime_seconds: u64 = blk: {
        const v = obj.get("uptime_seconds") orelse break :blk 0;
        const n = jsonInt(v);
        break :blk if (n < 0) 0 else @intCast(n);
    };

    const build_commit = dupeString(allocator, obj.get("build_commit") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(build_commit);

    const payment_token_address = dupeString(allocator, obj.get("payment_token_address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_token_address);

    const payment_vault_address = dupeString(allocator, obj.get("payment_vault_address") orelse .null) catch
        return error.JsonError;

    return .{
        .ok = ok,
        .network = network,
        .version = version,
        .evm_network = evm_network,
        .uptime_seconds = uptime_seconds,
        .build_commit = build_commit,
        .payment_token_address = payment_token_address,
        .payment_vault_address = payment_vault_address,
    };
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

/// Parse a FileUploadResult from a JSON response body. Used for both
/// file_upload_public and dir_upload_public responses.
pub fn parseFileUploadResult(allocator: Allocator, body: []const u8) !models.FileUploadResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const address = dupeString(allocator, obj.get("address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(address);

    const storage_cost_atto = dupeString(allocator, obj.get("storage_cost_atto") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(storage_cost_atto);

    const gas_cost_wei = dupeString(allocator, obj.get("gas_cost_wei") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(gas_cost_wei);

    const chunks_stored: u64 = blk: {
        const v = obj.get("chunks_stored") orelse break :blk 0;
        break :blk switch (v) {
            .integer => |i| if (i < 0) 0 else @intCast(i),
            .float => |f| @intFromFloat(f),
            else => 0,
        };
    };

    const payment_mode_used = dupeString(allocator, obj.get("payment_mode_used") orelse .null) catch
        return error.JsonError;

    return .{
        .address = address,
        .storage_cost_atto = storage_cost_atto,
        .gas_cost_wei = gas_cost_wei,
        .chunks_stored = chunks_stored,
        .payment_mode_used = payment_mode_used,
    };
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

/// Parse an UploadCostEstimate from a JSON response body.
pub fn parseCostEstimate(allocator: Allocator, body: []const u8) !models.UploadCostEstimate {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const root = parsed.value;

    const obj = switch (root) {
        .object => |o| o,
        else => return error.JsonError,
    };

    return models.UploadCostEstimate{
        .cost = try dupeString(allocator, obj.get("cost") orelse .null),
        .file_size = dupeU64(obj.get("file_size") orelse .null),
        .chunk_count = @intCast(dupeU64(obj.get("chunk_count") orelse .null)),
        .estimated_gas_cost_wei = try dupeString(allocator, obj.get("estimated_gas_cost_wei") orelse .null),
        .payment_mode = try dupeString(allocator, obj.get("payment_mode") orelse .null),
    };
}

fn dupeU64(v: std.json.Value) u64 {
    return switch (v) {
        .integer => |n| if (n < 0) 0 else @intCast(n),
        .float => |f| if (f < 0) 0 else @intFromFloat(f),
        else => 0,
    };
}


// --- JSON body construction helpers ---
// These use manual string building to avoid std.json.writeStream API differences
// across Zig versions.

/// Escape a string for JSON output.
fn jsonEscapeString(allocator: Allocator, s: []const u8) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try list.append('"');
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice("\\\""),
            '\\' => try list.appendSlice("\\\\"),
            '\n' => try list.appendSlice("\\n"),
            '\r' => try list.appendSlice("\\r"),
            '\t' => try list.appendSlice("\\t"),
            else => {
                if (c < 0x20) {
                    try list.writer().print("\\u{x:0>4}", .{c});
                } else {
                    try list.append(c);
                }
            },
        }
    }
    try list.append('"');
    return list.toOwnedSlice();
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

/// Build a JSON body for a data upload with an optional payment_mode field.
pub fn buildDataBodyWithPaymentMode(allocator: Allocator, data: []const u8, payment_mode: []const u8) ![]const u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
    const encoded = allocator.alloc(u8, encoded_len) catch return error.JsonError;
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, data);

    const escaped_data = jsonEscapeString(allocator, encoded) catch return error.JsonError;
    defer allocator.free(escaped_data);

    const escaped_mode = jsonEscapeString(allocator, payment_mode) catch return error.JsonError;
    defer allocator.free(escaped_mode);

    return std.fmt.allocPrint(allocator, "{{\"data\":{s},\"payment_mode\":{s}}}", .{ escaped_data, escaped_mode }) catch return error.JsonError;
}

/// Values supported in JSON body construction.
pub const JsonValue = union(enum) {
    string: []const u8,
    boolean: bool,
    string_array: []const []const u8,
};

/// Build a JSON request body from key-value pairs.
pub fn buildJsonBody(allocator: Allocator, fields: []const struct { key: []const u8, value: JsonValue }) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    try buf.append('{');

    for (fields, 0..) |field, i| {
        if (i > 0) try buf.append(',');

        // Write key
        const escaped_key = jsonEscapeString(allocator, field.key) catch return error.JsonError;
        defer allocator.free(escaped_key);
        try buf.appendSlice(escaped_key);
        try buf.append(':');

        // Write value
        switch (field.value) {
            .string => |s| {
                const escaped_val = jsonEscapeString(allocator, s) catch return error.JsonError;
                defer allocator.free(escaped_val);
                try buf.appendSlice(escaped_val);
            },
            .boolean => |b| {
                try buf.appendSlice(if (b) "true" else "false");
            },
            .string_array => |arr| {
                try buf.append('[');
                for (arr, 0..) |item, j| {
                    if (j > 0) try buf.append(',');
                    const escaped_item = jsonEscapeString(allocator, item) catch return error.JsonError;
                    defer allocator.free(escaped_item);
                    try buf.appendSlice(escaped_item);
                }
                try buf.append(']');
            },
        }
    }

    try buf.append('}');
    return buf.toOwnedSlice();
}

/// Build a /v1/upload/prepare request body: `{"path":"...", "visibility":"..."}`.
/// The `visibility` field is omitted entirely when null, preserving the pre-0.6.1
/// wire shape that older daemons expect.
pub fn buildPrepareUploadBody(allocator: Allocator, path: []const u8, visibility: ?[]const u8) ![]const u8 {
    if (visibility) |v| {
        return buildJsonBody(allocator, &.{
            .{ .key = "path", .value = .{ .string = path } },
            .{ .key = "visibility", .value = .{ .string = v } },
        });
    }
    return buildJsonBody(allocator, &.{
        .{ .key = "path", .value = .{ .string = path } },
    });
}

/// Build a /v1/data/prepare request body: `{"data":"<base64>", "visibility":"..."}`.
/// The `visibility` field is omitted entirely when null.
pub fn buildPrepareDataBody(allocator: Allocator, data: []const u8, visibility: ?[]const u8) ![]const u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
    const encoded = allocator.alloc(u8, encoded_len) catch return error.JsonError;
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, data);

    if (visibility) |v| {
        return buildJsonBody(allocator, &.{
            .{ .key = "data", .value = .{ .string = encoded } },
            .{ .key = "visibility", .value = .{ .string = v } },
        });
    }
    return buildJsonBody(allocator, &.{
        .{ .key = "data", .value = .{ .string = encoded } },
    });
}

/// Build a /v1/chunks/finalize request body from a pre-built `tx_hashes` JSON
/// object literal (e.g. `"{\"qh1\":\"tx1\"}"`).
///
/// Mirrors the `finalizeUpload` shape: callers assemble the inner map
/// themselves because std.json's writeStream API is version-fragile, and
/// quote_hash/tx_hash maps are small and easy to format by hand.
pub fn buildFinalizeChunkBody(allocator: Allocator, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
    const escaped_id = jsonEscapeString(allocator, upload_id) catch return error.JsonError;
    defer allocator.free(escaped_id);
    return std.fmt.allocPrint(
        allocator,
        "{{\"upload_id\":{s},\"tx_hashes\":{s}}}",
        .{ escaped_id, tx_hashes_json },
    ) catch return error.JsonError;
}

/// Parse a /v1/chunks/prepare response body into a PrepareChunkResult.
///
/// The "already-stored" branch returns only `address` + `already_stored:true`;
/// the wave-batch branch additionally populates `upload_id`, `payment_type`,
/// `payments`, `total_amount`, and the EVM config (vault/token/rpc).
pub fn parsePrepareChunkResult(allocator: Allocator, body: []const u8) !models.PrepareChunkResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const address = dupeString(allocator, obj.get("address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(address);

    const already_stored = switch (obj.get("already_stored") orelse .null) {
        .bool => |b| b,
        else => false,
    };

    const upload_id = dupeString(allocator, obj.get("upload_id") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(upload_id);

    const payment_type = dupeString(allocator, obj.get("payment_type") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_type);

    const total_amount = dupeString(allocator, obj.get("total_amount") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(total_amount);

    const payment_vault_address = dupeString(allocator, obj.get("payment_vault_address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_vault_address);

    const payment_token_address = dupeString(allocator, obj.get("payment_token_address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_token_address);

    const rpc_url = dupeString(allocator, obj.get("rpc_url") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(rpc_url);

    // Parse payments array (may be missing/null on the already_stored branch).
    var payments_list = std.ArrayList(models.PaymentInfo).init(allocator);
    errdefer {
        for (payments_list.items) |p| p.deinit(allocator);
        payments_list.deinit();
    }

    if (obj.get("payments")) |pv| {
        const items_opt: ?[]std.json.Value = switch (pv) {
            .array => |a| a.items,
            else => null,
        };
        if (items_opt) |items| {
            for (items) |item| {
                const item_obj = switch (item) {
                    .object => |o| o,
                    else => continue,
                };
                const qh = dupeString(allocator, item_obj.get("quote_hash") orelse .null) catch
                    return error.JsonError;
                errdefer allocator.free(qh);
                const ra = dupeString(allocator, item_obj.get("rewards_address") orelse .null) catch
                    return error.JsonError;
                errdefer allocator.free(ra);
                const am = dupeString(allocator, item_obj.get("amount") orelse .null) catch
                    return error.JsonError;
                errdefer allocator.free(am);
                payments_list.append(.{
                    .quote_hash = qh,
                    .rewards_address = ra,
                    .amount = am,
                }) catch return error.JsonError;
            }
        }
    }

    const payments_slice = payments_list.toOwnedSlice() catch return error.JsonError;

    return .{
        .address = address,
        .already_stored = already_stored,
        .upload_id = upload_id,
        .payment_type = payment_type,
        .payments = payments_slice,
        .total_amount = total_amount,
        .payment_vault_address = payment_vault_address,
        .payment_token_address = payment_token_address,
        .rpc_url = rpc_url,
    };
}

/// Parse a /v1/upload/finalize response body into a FinalizeUploadResult.
///
/// `data_map_address` is populated only when prepare was called with
/// visibility="public" (antd >= 0.6.1). Older daemons omit the field, which
/// parses cleanly to the empty default.
pub fn parseFinalizeUploadResult(allocator: Allocator, body: []const u8) !models.FinalizeUploadResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.JsonError,
    };

    const data_map = dupeString(allocator, obj.get("data_map") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(data_map);

    const address = dupeString(allocator, obj.get("address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(address);

    const data_map_address = dupeString(allocator, obj.get("data_map_address") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(data_map_address);

    const chunks_stored = dupeU64(obj.get("chunks_stored") orelse .null);

    return .{
        .data_map = data_map,
        .address = address,
        .data_map_address = data_map_address,
        .chunks_stored = chunks_stored,
    };
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

/// Extract a boolean field from a JSON response body.
pub fn parseBoolField(allocator: Allocator, body: []const u8, key: []const u8) !bool {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.JsonError,
    };
    const val = obj.get(key) orelse return false;
    return switch (val) {
        .bool => |b| b,
        else => false,
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
