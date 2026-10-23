const std = @import("std");
const Allocator = std.mem.Allocator;
const models = @import("models.zig");
const errors = @import("errors.zig");

/// Duplicate a std.json string value into an owned allocation.
fn dupeString(allocator: Allocator, value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| try allocator.dupe(u8, s),
        else => try allocator.dupe(u8, ""),
    };
}

/// An owned copy of an optional string field: `null` when the key is absent,
/// null, empty or not a string. A missing `sha256` (antd before 0.17.0) and
/// an empty one both read as `null`.
fn optionalString(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    return switch (obj.get(key) orelse return null) {
        .string => |s| if (s.len == 0) null else try allocator.dupe(u8, s),
        else => null,
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

    const uptime_seconds = dupeU64(obj.get("uptime_seconds") orelse .null);

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

/// Parse a DataPutResult from a JSON response body (private data put).
pub fn parseDataPutResult(allocator: Allocator, body: []const u8) !models.DataPutResult {
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

    const chunks_stored = dupeU64(obj.get("chunks_stored") orelse .null);

    const payment_mode_used = dupeString(allocator, obj.get("payment_mode_used") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_mode_used);

    const sha256 = try optionalString(allocator, obj, "sha256");
    errdefer if (sha256) |v| allocator.free(v);

    return .{
        .data_map = data_map,
        .chunks_stored = chunks_stored,
        .payment_mode_used = payment_mode_used,
        .sha256 = sha256,
    };
}

/// Parse a DataPutPublicResult from a JSON response body (public data put).
pub fn parseDataPutPublicResult(allocator: Allocator, body: []const u8) !models.DataPutPublicResult {
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

    const chunks_stored = dupeU64(obj.get("chunks_stored") orelse .null);

    const payment_mode_used = dupeString(allocator, obj.get("payment_mode_used") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_mode_used);

    const sha256 = try optionalString(allocator, obj, "sha256");
    errdefer if (sha256) |v| allocator.free(v);

    return .{
        .address = address,
        .chunks_stored = chunks_stored,
        .payment_mode_used = payment_mode_used,
        .sha256 = sha256,
    };
}

/// Parse a FilePutPublicResult from a JSON response body.
pub fn parseFilePutPublicResult(allocator: Allocator, body: []const u8) !models.FilePutPublicResult {
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

    const chunks_stored = dupeU64(obj.get("chunks_stored") orelse .null);

    const payment_mode_used = dupeString(allocator, obj.get("payment_mode_used") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_mode_used);

    const sha256 = try optionalString(allocator, obj, "sha256");
    errdefer if (sha256) |v| allocator.free(v);

    return .{
        .address = address,
        .storage_cost_atto = storage_cost_atto,
        .gas_cost_wei = gas_cost_wei,
        .chunks_stored = chunks_stored,
        .payment_mode_used = payment_mode_used,
        .sha256 = sha256,
    };
}

/// Parse a FilePutResult from a JSON response body (private file put).
pub fn parseFilePutResult(allocator: Allocator, body: []const u8) !models.FilePutResult {
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

    const storage_cost_atto = dupeString(allocator, obj.get("storage_cost_atto") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(storage_cost_atto);

    const gas_cost_wei = dupeString(allocator, obj.get("gas_cost_wei") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(gas_cost_wei);

    const chunks_stored = dupeU64(obj.get("chunks_stored") orelse .null);

    const payment_mode_used = dupeString(allocator, obj.get("payment_mode_used") orelse .null) catch
        return error.JsonError;
    errdefer allocator.free(payment_mode_used);

    const sha256 = try optionalString(allocator, obj, "sha256");
    errdefer if (sha256) |v| allocator.free(v);

    return .{
        .data_map = data_map,
        .storage_cost_atto = storage_cost_atto,
        .gas_cost_wei = gas_cost_wei,
        .chunks_stored = chunks_stored,
        .payment_mode_used = payment_mode_used,
        .sha256 = sha256,
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
        .chunk_count = std.math.cast(u32, dupeU64(obj.get("chunk_count") orelse .null)) orelse 0,
        .estimated_gas_cost_wei = try dupeString(allocator, obj.get("estimated_gas_cost_wei") orelse .null),
        .payment_mode = try dupeString(allocator, obj.get("payment_mode") orelse .null),
    };
}

/// Read a count from a JSON value. Only a JSON non-negative integer below
/// 2^64 converts; anything else (a float such as `1.0` or `1e20`, a negative
/// number, a string, a bool, null, an array or an object) reads as 0, so a
/// malformed body can never reach a safety-checked cast.
fn dupeU64(v: std.json.Value) u64 {
    return switch (v) {
        .integer => |n| std.math.cast(u64, n) orelse 0,
        // std.json hands over an integer that overflows i64 as its digits:
        // 2^63 .. 2^64 - 1 is still a valid count, 2^64 and beyond is not.
        // A float that overflows f64 lands here too and fails the parse.
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch 0,
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

/// Build a JSON body for a data upload with a payment_mode field.
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

/// Build a JSON body with a single `data_map` string field.
pub fn buildDataMapBody(allocator: Allocator, data_map: []const u8) ![]const u8 {
    const escaped = jsonEscapeString(allocator, data_map) catch return error.JsonError;
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "{{\"data_map\":{s}}}", .{escaped}) catch return error.JsonError;
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

/// Build a /v1/upload/finalize request body:
/// `{"upload_id":"...","tx_hashes":{...},"store_data_map":false}`.
///
/// `tx_hashes_json` is the caller's quote-hash -> tx-hash map as a JSON
/// object string (e.g. `"{\"qh1\":\"tx1\"}"`, or `"{}"` when prepare
/// reported no payments). It is parsed and re-serialised into the request,
/// so the caller never builds the request object itself. Returns
/// `error.JsonError` when it is not valid JSON or not an object.
///
/// `store_data_map` is always `false`: the SDK never asks the daemon's own
/// wallet to publish the DataMap. A public upload bundles the DataMap chunk
/// into the externally paid batch via `visibility:"public"` on prepare and
/// reports it as `data_map_address` on finalize.
pub fn buildFinalizeUploadBody(allocator: Allocator, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
    return buildFinalizeBody(allocator, upload_id, tx_hashes_json, .{ .store_data_map = false });
}

/// Build a /v1/chunks/finalize request body:
/// `{"upload_id":"...","tx_hashes":{...}}`.
///
/// `tx_hashes_json` follows the same contract as in `buildFinalizeUploadBody`:
/// a JSON object string mapping quote_hash to tx_hash, validated before it is
/// embedded (`error.JsonError` for invalid JSON or a non-object).
pub fn buildFinalizeChunkBody(allocator: Allocator, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
    return buildFinalizeBody(allocator, upload_id, tx_hashes_json, .{ .store_data_map = null });
}

const FinalizeBodyOptions = struct {
    /// `null` omits the field (chunk finalize has no such field).
    store_data_map: ?bool,
};

/// Shared builder for the two finalize endpoints. The caller's `tx_hashes`
/// map is parsed with `std.json` (rejecting anything but an object) and the
/// request is serialised as a whole, so a stray or malformed map can never
/// be sent as the request body.
fn buildFinalizeBody(
    allocator: Allocator,
    upload_id: []const u8,
    tx_hashes_json: []const u8,
    options: FinalizeBodyOptions,
) ![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, tx_hashes_json, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const tx_hashes = switch (parsed.value) {
        .object => parsed.value,
        else => return error.JsonError,
    };

    // ObjectMap keeps insertion order, so the serialised field order is fixed.
    var body = std.json.ObjectMap.init(allocator);
    defer body.deinit();
    body.put("upload_id", .{ .string = upload_id }) catch return error.JsonError;
    body.put("tx_hashes", tx_hashes) catch return error.JsonError;
    if (options.store_data_map) |flag| {
        body.put("store_data_map", .{ .bool = flag }) catch return error.JsonError;
    }

    return std.json.stringifyAlloc(allocator, std.json.Value{ .object = body }, .{}) catch
        return error.JsonError;
}

/// Parse a /v1/chunks/prepare response body into a PrepareChunkResult.
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

    const sha256 = try optionalString(allocator, obj, "sha256");
    errdefer if (sha256) |v| allocator.free(v);

    return .{
        .data_map = data_map,
        .address = address,
        .data_map_address = data_map_address,
        .chunks_stored = chunks_stored,
        .sha256 = sha256,
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

/// Structured fields of a daemon error body
/// `{"error":"...","code":"...",...}`. `code` is empty when the body carried
/// none. The chunk counts and `retryable` are sent only with
/// `code: "PARTIAL_UPLOAD"` (`retryable` by antd >= 0.14.0), and `retryable`
/// also with `code: "CLOSE_GROUP_SHORTFALL"` from a pointer finalize that
/// kept the paid state; they, and `retention_known`, read zero / false
/// otherwise.
pub const ErrorBody = struct {
    message: []const u8,
    code: []const u8,
    chunks_stored: u64 = 0,
    chunks_failed: u64 = 0,
    total_chunks: u64 = 0,
    retryable: bool = false,
    /// `true` only when `retryable` arrived as a JSON boolean.
    retention_known: bool = false,

    pub fn deinit(self: ErrorBody, allocator: Allocator) void {
        allocator.free(self.message);
        allocator.free(self.code);
    }

    /// The `ErrorInfo` a Client records for this body. `message` is
    /// borrowed from the ErrorBody; the Client stores its own copy.
    pub fn errorInfo(self: ErrorBody, status_code: u16) errors.ErrorInfo {
        return .{
            .status_code = status_code,
            .message = self.message,
            .chunks_stored = self.chunks_stored,
            .chunks_failed = self.chunks_failed,
            .total_chunks = self.total_chunks,
            .retryable = self.retryable,
            .retention_known = self.retention_known,
        };
    }
};

/// Parse a JSON error response body into an ErrorBody. Returns null when the
/// body is not a JSON object with a string "error" field, exactly like
/// `parseErrorMessage`, so callers can fall back to the raw body text.
///
/// The counts and `retryable` are read only when `code` is the string
/// "PARTIAL_UPLOAD". A count converts only from a JSON non-negative integer
/// below 2^64 and reads as 0 otherwise; `retryable` is true only for the
/// JSON boolean `true`, and `retention_known` only when `retryable` is a
/// JSON boolean (either value). With `code: "CLOSE_GROUP_SHORTFALL"` only
/// `retryable` is read, true only for the JSON boolean `true`; the counts
/// and `retention_known` stay zero / false. A malformed field never fails
/// the parse.
pub fn parseErrorBody(allocator: Allocator, body: []const u8) ?ErrorBody {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return null,
    };
    const err_val = obj.get("error") orelse return null;
    const message = switch (err_val) {
        .string => |s| allocator.dupe(u8, s) catch return null,
        else => return null,
    };
    const code = dupeString(allocator, obj.get("code") orelse .null) catch {
        allocator.free(message);
        return null;
    };

    if (std.mem.eql(u8, code, errors.close_group_shortfall_code)) {
        // Present, and true, only on a pointer finalize that kept the paid
        // state; anything else reads as not retained.
        const retryable = switch (obj.get("retryable") orelse .null) {
            .bool => |b| b,
            else => false,
        };
        return .{ .message = message, .code = code, .retryable = retryable };
    }

    if (!std.mem.eql(u8, code, errors.partial_upload_code)) {
        return .{ .message = message, .code = code };
    }

    // A missing flag (antd < 0.14.0), null or a non-boolean leaves retention
    // unknown, which is not the same as "nothing retained".
    const retryable: ?bool = switch (obj.get("retryable") orelse .null) {
        .bool => |b| b,
        else => null,
    };

    return .{
        .message = message,
        .code = code,
        .chunks_stored = dupeU64(obj.get("chunks_stored") orelse .null),
        .chunks_failed = dupeU64(obj.get("chunks_failed") orelse .null),
        .total_chunks = dupeU64(obj.get("total_chunks") orelse .null),
        .retryable = retryable orelse false,
        .retention_known = retryable != null,
    };
}

// --- Pointers ---
//
// Counters arrive as decimal strings (a final state sits at 2^64 - 1) and
// are read into a `u64`; anything that is not a decimal u64 fails the parse
// with `error.JsonError` rather than reading as 0. An unset value is JSON
// `null` (`counter`, `state`, `majority`, `transferred_to`,
// `finality_error`) and reads as Zig `null`; so does an empty string.

/// Parse a pointer counter: one or more ASCII digits, at most 2^64 - 1.
/// `std.fmt.parseInt` alone would also take a sign and `_` separators, so the
/// digits are checked first. Returns `error.JsonError` for anything else.
pub fn parsePointerCounter(s: []const u8) error{JsonError}!u64 {
    if (s.len == 0) return error.JsonError;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return error.JsonError;
    }
    return std.fmt.parseInt(u64, s, 10) catch error.JsonError;
}

/// A required counter: a JSON string holding a decimal u64.
fn pointerCounterField(obj: std.json.ObjectMap, key: []const u8) error{JsonError}!u64 {
    return switch (obj.get(key) orelse .null) {
        .string => |s| parsePointerCounter(s),
        else => error.JsonError,
    };
}

/// An optional counter: `null`, missing or `""` read as `null`; a string must
/// hold a decimal u64; any other JSON type fails the parse.
fn optionalPointerCounterField(obj: std.json.ObjectMap, key: []const u8) error{JsonError}!?u64 {
    return switch (obj.get(key) orelse .null) {
        .null => null,
        .string => |s| if (s.len == 0) null else try parsePointerCounter(s),
        else => error.JsonError,
    };
}

/// An optional string, owned: a non-empty JSON string, or `null` for JSON
/// `null`, a missing key, `""` or any other type.
fn optionalStringField(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    return switch (obj.get(key) orelse .null) {
        .string => |s| if (s.len == 0) null else try allocator.dupe(u8, s),
        else => null,
    };
}

/// A required string, owned; `""` when missing or not a string.
fn stringField(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    return dupeString(allocator, obj.get(key) orelse .null);
}

fn boolField(obj: std.json.ObjectMap, key: []const u8) bool {
    return switch (obj.get(key) orelse .null) {
        .bool => |b| b,
        else => false,
    };
}

/// The raw target tag, or `pointer_unknown_kind_tag` when it is missing or
/// not an integer in 0..255.
fn kindTagField(obj: std.json.ObjectMap) u8 {
    return switch (obj.get("kind_tag") orelse .null) {
        .integer => |n| std.math.cast(u8, n) orelse models.pointer_unknown_kind_tag,
        else => models.pointer_unknown_kind_tag,
    };
}

/// A peer count; one past `u32` reads as `maxInt(u32)`, a malformed one as 0.
fn u32Field(obj: std.json.ObjectMap, key: []const u8) u32 {
    return std.math.cast(u32, dupeU64(obj.get(key) orelse .null)) orelse std.math.maxInt(u32);
}

fn rootObject(value: std.json.Value) error{JsonError}!std.json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => error.JsonError,
    };
}

/// Build a `POST /v1/pointers` or `POST /v1/pointers/update` request body:
/// `{"owner":"...","target":"...","kind":"chunk"|"pointer"}`.
pub fn buildPointerWriteBody(allocator: Allocator, owner: []const u8, target: []const u8, kind: models.PointerKind) ![]const u8 {
    return buildJsonBody(allocator, &.{
        .{ .key = "owner", .value = .{ .string = owner } },
        .{ .key = "target", .value = .{ .string = target } },
        .{ .key = "kind", .value = .{ .string = kind.wire() } },
    });
}

/// Build a `POST /v1/pointers/transfer` request body:
/// `{"owner":"...","recipient":"..."}`.
pub fn buildPointerTransferBody(allocator: Allocator, owner: []const u8, recipient: []const u8) ![]const u8 {
    return buildJsonBody(allocator, &.{
        .{ .key = "owner", .value = .{ .string = owner } },
        .{ .key = "recipient", .value = .{ .string = recipient } },
    });
}

/// Build a `POST /v1/pointers/prepare` request body:
/// `{"owner","op","target","kind"}` for a create or update,
/// `{"owner","op","recipient"}` for a transfer, plus
/// `"include_signed_quotes":true` only when asked for.
pub fn buildPointerPrepareBody(
    allocator: Allocator,
    owner: []const u8,
    op: models.PointerOp,
    options: models.PointerPrepareOptions,
) ![]const u8 {
    // ObjectMap keeps insertion order, so the serialised field order is fixed.
    var body = std.json.ObjectMap.init(allocator);
    defer body.deinit();
    try body.put("owner", .{ .string = owner });
    try body.put("op", .{ .string = op.wire() });
    switch (op) {
        .create, .update => |w| {
            try body.put("target", .{ .string = w.target });
            try body.put("kind", .{ .string = w.kind.wire() });
        },
        .transfer => |t| try body.put("recipient", .{ .string = t.recipient }),
    }
    if (options.include_signed_quotes) {
        try body.put("include_signed_quotes", .{ .bool = true });
    }
    return std.json.stringifyAlloc(allocator, std.json.Value{ .object = body }, .{});
}

/// Build a `POST /v1/pointers/finalize` request body:
/// `{"upload_id":"...","tx_hashes":{...}}`. `tx_hashes_json` follows the
/// same contract as in `buildFinalizeUploadBody`: a JSON object string
/// mapping quote_hash to tx_hash, validated before it is embedded
/// (`error.JsonError` for invalid JSON or a non-object).
pub fn buildPointerFinalizeBody(allocator: Allocator, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
    return buildFinalizeBody(allocator, upload_id, tx_hashes_json, .{ .store_data_map = null });
}

/// Parse a `GET /v1/pointers/keys` response: `{"keys":[{"address":"..."}]}`.
pub fn parsePointerKeys(allocator: Allocator, body: []const u8) !models.PointerKeys {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |a| allocator.free(a);
        list.deinit();
    }
    switch (obj.get("keys") orelse .null) {
        .array => |arr| for (arr.items) |item| {
            const key = switch (item) {
                .object => |o| o,
                else => continue,
            };
            const address = try stringField(allocator, key, "address");
            list.append(address) catch |err| {
                allocator.free(address);
                return err;
            };
        },
        else => {},
    }
    return .{ .addresses = try list.toOwnedSlice() };
}

/// Parse a pointer create / update response: `{"address","state_id","counter"}`.
pub fn parsePointerWriteResult(allocator: Allocator, body: []const u8) !models.PointerWriteResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const counter = try pointerCounterField(obj, "counter");
    const address = try stringField(allocator, obj, "address");
    errdefer allocator.free(address);
    const state_id = try stringField(allocator, obj, "state_id");
    return .{ .address = address, .state_id = state_id, .counter = counter };
}

/// Parse a `GET /v1/pointers/{addr}` response into a PointerRecord.
pub fn parsePointerRecord(allocator: Allocator, body: []const u8) !models.PointerRecord {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const counter = try pointerCounterField(obj, "counter");
    const address = try stringField(allocator, obj, "address");
    errdefer allocator.free(address);
    const owner = try stringField(allocator, obj, "owner");
    errdefer allocator.free(owner);
    const kind = try stringField(allocator, obj, "kind");
    errdefer allocator.free(kind);
    const target = try stringField(allocator, obj, "target");
    errdefer allocator.free(target);
    const state_id = try stringField(allocator, obj, "state_id");
    errdefer allocator.free(state_id);
    const transferred_to = try optionalStringField(allocator, obj, "transferred_to");

    return .{
        .address = address,
        .owner = owner,
        .counter = counter,
        .kind = kind,
        .kind_tag = kindTagField(obj),
        .target = target,
        .state_id = state_id,
        .is_final = boolField(obj, "is_final"),
        .transferred_to = transferred_to,
    };
}

/// Parse a `GET /v1/pointers/{addr}/resolve` response into a PointerTarget.
pub fn parsePointerTarget(allocator: Allocator, body: []const u8) !models.PointerTarget {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const kind = try stringField(allocator, obj, "kind");
    errdefer allocator.free(kind);
    const target = try stringField(allocator, obj, "target");
    return .{ .kind = kind, .kind_tag = kindTagField(obj), .target = target };
}

/// Parse a `GET /v1/pointers/{addr}/finality` response into a
/// PointerFinality.
pub fn parsePointerFinality(allocator: Allocator, body: []const u8) !models.PointerFinality {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    return pointerFinalityFromObject(allocator, try rootObject(parsed.value));
}

/// A `finality` member (transfer and finalize responses): `null`, missing or
/// not an object reads as `null`.
fn optionalPointerFinality(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) !?models.PointerFinality {
    return switch (obj.get(key) orelse .null) {
        .object => |o| try pointerFinalityFromObject(allocator, o),
        else => null,
    };
}

fn pointerFinalityFromObject(allocator: Allocator, obj: std.json.ObjectMap) !models.PointerFinality {
    const counter = try optionalPointerCounterField(obj, "counter");
    const address = try stringField(allocator, obj, "address");
    errdefer allocator.free(address);
    const status_wire = switch (obj.get("status") orelse .null) {
        .string => |s| s,
        else => "",
    };
    const status = try models.PointerFinalityStatus.fromWire(allocator, status_wire);
    errdefer status.deinit(allocator);
    const state = try optionalFinalState(allocator, obj, "state");
    errdefer if (state) |s| s.deinit(allocator);
    const states = try finalStateList(allocator, obj.get("states") orelse .null);
    errdefer {
        for (states) |s| s.deinit(allocator);
        allocator.free(states);
    }
    const majority = try optionalFinalState(allocator, obj, "majority");
    errdefer if (majority) |m| m.deinit(allocator);
    const transferred_to = try optionalStringField(allocator, obj, "transferred_to");

    return .{
        .address = address,
        .group = u32Field(obj, "group"),
        .answered = u32Field(obj, "answered"),
        .status = status,
        .counter = counter,
        .state = state,
        .states = states,
        .majority = majority,
        .transferred_to = transferred_to,
    };
}

fn optionalFinalState(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) !?models.PointerFinalState {
    return switch (obj.get(key) orelse .null) {
        .object => |o| try finalStateFromObject(allocator, o),
        else => null,
    };
}

fn finalStateList(allocator: Allocator, value: std.json.Value) ![]const models.PointerFinalState {
    const items = switch (value) {
        .array => |arr| arr.items,
        else => return &.{},
    };
    var list = std.ArrayList(models.PointerFinalState).init(allocator);
    errdefer {
        for (list.items) |s| s.deinit(allocator);
        list.deinit();
    }
    for (items) |item| {
        const o = switch (item) {
            .object => |o| o,
            else => continue,
        };
        const state = try finalStateFromObject(allocator, o);
        list.append(state) catch |err| {
            state.deinit(allocator);
            return err;
        };
    }
    return list.toOwnedSlice();
}

fn finalStateFromObject(allocator: Allocator, obj: std.json.ObjectMap) !models.PointerFinalState {
    const state_id = try stringField(allocator, obj, "state_id");
    errdefer allocator.free(state_id);
    const kind = try stringField(allocator, obj, "kind");
    errdefer allocator.free(kind);
    const target = try stringField(allocator, obj, "target");
    errdefer allocator.free(target);
    const transferred_to = try optionalStringField(allocator, obj, "transferred_to");

    return .{
        .state_id = state_id,
        .kind = kind,
        .kind_tag = kindTagField(obj),
        .target = target,
        .holders = u32Field(obj, "holders"),
        .transferred_to = transferred_to,
    };
}

/// Parse a `GET /v1/pointers/{addr}/controller` response into a
/// PointerController.
pub fn parsePointerController(allocator: Allocator, body: []const u8) !models.PointerController {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const pointer = try stringField(allocator, obj, "pointer");
    errdefer allocator.free(pointer);

    var transfers = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (transfers.items) |t| allocator.free(t);
        transfers.deinit();
    }
    switch (obj.get("transfers") orelse .null) {
        .array => |arr| for (arr.items) |item| {
            const s = switch (item) {
                .string => |s| s,
                else => continue,
            };
            const owned = try allocator.dupe(u8, s);
            transfers.append(owned) catch |err| {
                allocator.free(owned);
                return err;
            };
        },
        else => {},
    }

    return .{
        .pointer = pointer,
        .transfers = try transfers.toOwnedSlice(),
        .frozen = boolField(obj, "frozen"),
    };
}

/// Parse a `POST /v1/pointers/transfer` response into a
/// PointerTransferResult.
pub fn parsePointerTransferResult(allocator: Allocator, body: []const u8) !models.PointerTransferResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const address = try stringField(allocator, obj, "address");
    errdefer allocator.free(address);
    const state_id = try stringField(allocator, obj, "state_id");
    errdefer allocator.free(state_id);
    const finality = try optionalPointerFinality(allocator, obj, "finality");
    errdefer if (finality) |f| f.deinit(allocator);
    const finality_error = try optionalStringField(allocator, obj, "finality_error");

    return .{
        .address = address,
        .state_id = state_id,
        .finality = finality,
        .finality_error = finality_error,
    };
}

/// Parse a `POST /v1/pointers/prepare` response into a PointerPrepareResult.
pub fn parsePointerPrepareResult(allocator: Allocator, body: []const u8) !models.PointerPrepareResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const counter = try pointerCounterField(obj, "counter");
    const upload_id = try stringField(allocator, obj, "upload_id");
    errdefer allocator.free(upload_id);
    const op = try stringField(allocator, obj, "op");
    errdefer allocator.free(op);
    const address = try stringField(allocator, obj, "address");
    errdefer allocator.free(address);
    const state_id = try stringField(allocator, obj, "state_id");
    errdefer allocator.free(state_id);
    const payment_type = try stringField(allocator, obj, "payment_type");
    errdefer allocator.free(payment_type);
    const payments = try paymentList(allocator, obj.get("payments") orelse .null);
    errdefer {
        for (payments) |p| p.deinit(allocator);
        allocator.free(payments);
    }
    const total_amount = try stringField(allocator, obj, "total_amount");
    errdefer allocator.free(total_amount);
    const payment_vault_address = try stringField(allocator, obj, "payment_vault_address");
    errdefer allocator.free(payment_vault_address);
    const payment_token_address = try stringField(allocator, obj, "payment_token_address");
    errdefer allocator.free(payment_token_address);
    const rpc_url = try stringField(allocator, obj, "rpc_url");
    errdefer allocator.free(rpc_url);
    const signed_quotes = try signedQuoteList(allocator, obj.get("signed_quotes") orelse .null);

    return .{
        .upload_id = upload_id,
        .op = op,
        .address = address,
        .state_id = state_id,
        .counter = counter,
        .payment_type = payment_type,
        .payments = payments,
        .total_amount = total_amount,
        .payment_vault_address = payment_vault_address,
        .payment_token_address = payment_token_address,
        .rpc_url = rpc_url,
        .signed_quotes = signed_quotes,
    };
}

/// Parse a `POST /v1/pointers/finalize` response into a
/// PointerFinalizeResult.
pub fn parsePointerFinalizeResult(allocator: Allocator, body: []const u8) !models.PointerFinalizeResult {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.JsonError;
    defer parsed.deinit();
    const obj = try rootObject(parsed.value);

    const counter = try pointerCounterField(obj, "counter");
    const address = try stringField(allocator, obj, "address");
    errdefer allocator.free(address);
    const state_id = try stringField(allocator, obj, "state_id");
    errdefer allocator.free(state_id);
    const finality = try optionalPointerFinality(allocator, obj, "finality");

    return .{
        .address = address,
        .state_id = state_id,
        .counter = counter,
        .finality = finality,
    };
}

fn paymentList(allocator: Allocator, value: std.json.Value) ![]const models.PaymentInfo {
    const items = switch (value) {
        .array => |arr| arr.items,
        else => return &.{},
    };
    var list = std.ArrayList(models.PaymentInfo).init(allocator);
    errdefer {
        for (list.items) |p| p.deinit(allocator);
        list.deinit();
    }
    for (items) |item| {
        const o = switch (item) {
            .object => |o| o,
            else => continue,
        };
        const quote_hash = try stringField(allocator, o, "quote_hash");
        errdefer allocator.free(quote_hash);
        const rewards_address = try stringField(allocator, o, "rewards_address");
        errdefer allocator.free(rewards_address);
        const amount = try stringField(allocator, o, "amount");
        errdefer allocator.free(amount);
        try list.append(.{
            .quote_hash = quote_hash,
            .rewards_address = rewards_address,
            .amount = amount,
        });
    }
    return list.toOwnedSlice();
}

fn signedQuoteList(allocator: Allocator, value: std.json.Value) ![]const models.SignedQuoteEntry {
    const items = switch (value) {
        .array => |arr| arr.items,
        else => return &.{},
    };
    var list = std.ArrayList(models.SignedQuoteEntry).init(allocator);
    errdefer {
        for (list.items) |q| q.deinit(allocator);
        list.deinit();
    }
    for (items) |item| {
        const o = switch (item) {
            .object => |o| o,
            else => continue,
        };
        const quote_hash = try stringField(allocator, o, "quote_hash");
        errdefer allocator.free(quote_hash);
        const quote = try stringField(allocator, o, "quote");
        errdefer allocator.free(quote);
        const commitment_sidecar = try optionalStringField(allocator, o, "commitment_sidecar");
        errdefer if (commitment_sidecar) |s| allocator.free(s);
        try list.append(.{
            .quote_hash = quote_hash,
            .quote = quote,
            .commitment_sidecar = commitment_sidecar,
        });
    }
    return list.toOwnedSlice();
}
