const std = @import("std");
const testing = std.testing;
const models = @import("models.zig");
const errors = @import("errors.zig");
const json_helpers = @import("json_helpers.zig");

// =============================================================================
// Error mapping tests
// =============================================================================

test "errorForStatus maps 400 to BadRequest" {
    try testing.expectEqual(error.BadRequest, errors.errorForStatus(400));
}

test "errorForStatus maps 402 to Payment" {
    try testing.expectEqual(error.Payment, errors.errorForStatus(402));
}

test "errorForStatus maps 404 to NotFound" {
    try testing.expectEqual(error.NotFound, errors.errorForStatus(404));
}

test "errorForStatus maps 409 to AlreadyExists" {
    try testing.expectEqual(error.AlreadyExists, errors.errorForStatus(409));
}

test "errorForStatus maps 413 to TooLarge" {
    try testing.expectEqual(error.TooLarge, errors.errorForStatus(413));
}

test "errorForStatus maps 500 to Internal" {
    try testing.expectEqual(error.Internal, errors.errorForStatus(500));
}

test "errorForStatus maps 502 to Network" {
    try testing.expectEqual(error.Network, errors.errorForStatus(502));
}

test "errorForStatus maps unknown to UnexpectedStatus" {
    try testing.expectEqual(error.UnexpectedStatus, errors.errorForStatus(418));
}

// =============================================================================
// JSON parsing tests
// =============================================================================

test "parseHealthStatus parses ok status" {
    const body =
        \\{"status":"ok","network":"local"}
    ;
    const result = try json_helpers.parseHealthStatus(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expect(result.ok);
    try testing.expectEqualStrings("local", result.network);
}

test "parseHealthStatus parses non-ok status" {
    const body =
        \\{"status":"error","network":"mainnet"}
    ;
    const result = try json_helpers.parseHealthStatus(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expect(!result.ok);
    try testing.expectEqualStrings("mainnet", result.network);
}

test "parsePutResult parses address" {
    const body =
        \\{"cost":"100","address":"abc123"}
    ;
    const result = try json_helpers.parsePutResult(testing.allocator, body, "address");
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("100", result.cost);
    try testing.expectEqualStrings("abc123", result.address);
}

test "parsePutResult parses data_map key" {
    const body =
        \\{"cost":"200","data_map":"dm123"}
    ;
    const result = try json_helpers.parsePutResult(testing.allocator, body, "data_map");
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("200", result.cost);
    try testing.expectEqualStrings("dm123", result.address);
}

test "parseBase64Data decodes data" {
    // "hello" in base64 is "aGVsbG8="
    const body =
        \\{"data":"aGVsbG8="}
    ;
    const result = try json_helpers.parseBase64Data(testing.allocator, body);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("hello", result);
}

test "parseCost extracts cost" {
    const body =
        \\{"cost":"500"}
    ;
    const result = try json_helpers.parseCost(testing.allocator, body);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("500", result);
}

// =============================================================================
// Base64 encode/decode tests
// =============================================================================

test "base64 encode and decode round-trip" {
    const original = "Hello, Autonomi!";
    const encoder = std.base64.standard;

    const encoded_len = encoder.Encoder.calcSize(original.len);
    var encoded: [256]u8 = undefined;
    _ = encoder.Encoder.encode(encoded[0..encoded_len], original);

    const decoded_len = try encoder.Decoder.calcSizeForSlice(encoded[0..encoded_len]);
    var decoded: [256]u8 = undefined;
    try encoder.Decoder.decode(decoded[0..decoded_len], encoded[0..encoded_len]);

    try testing.expectEqualStrings(original, decoded[0..decoded_len]);
}

test "base64 encode empty data" {
    const encoder = std.base64.standard;
    const encoded_len = encoder.Encoder.calcSize(0);
    try testing.expectEqual(@as(usize, 0), encoded_len);
}

// =============================================================================
// JSON body construction tests
// =============================================================================

fn getJsonString(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn getJsonBool(value: std.json.Value) ?bool {
    return switch (value) {
        .bool => |b| b,
        else => null,
    };
}

fn getJsonObject(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => null,
    };
}

fn getJsonArray(value: std.json.Value) ?std.json.Array {
    return switch (value) {
        .array => |a| a,
        else => null,
    };
}

test "buildDataBody produces valid JSON" {
    const body = try json_helpers.buildDataBody(testing.allocator, "hello");
    defer testing.allocator.free(body);

    // Parse back to verify it is valid JSON with expected structure
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const data_val = getJsonString(obj.get("data") orelse return error.JsonError) orelse return error.JsonError;
    // "hello" base64 encoded is "aGVsbG8="
    try testing.expectEqualStrings("aGVsbG8=", data_val);
}

test "buildJsonBody with string fields" {
    const body = try json_helpers.buildJsonBody(testing.allocator, &.{
        .{ .key = "path", .value = .{ .string = "/tmp/test.txt" } },
    });
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const val = getJsonString(obj.get("path") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("/tmp/test.txt", val);
}

test "buildJsonBody with boolean fields" {
    const body = try json_helpers.buildJsonBody(testing.allocator, &.{
        .{ .key = "is_public", .value = .{ .boolean = true } },
    });
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const is_public = getJsonBool(obj.get("is_public") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expect(is_public);
}

test "buildJsonBody with string array" {
    const parents = [_][]const u8{ "p1", "p2" };
    const body = try json_helpers.buildJsonBody(testing.allocator, &.{
        .{ .key = "parents", .value = .{ .string_array = &parents } },
    });
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const arr = getJsonArray(obj.get("parents") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqual(@as(usize, 2), arr.items.len);
    const v0 = getJsonString(arr.items[0]) orelse return error.JsonError;
    const v1 = getJsonString(arr.items[1]) orelse return error.JsonError;
    try testing.expectEqualStrings("p1", v0);
    try testing.expectEqualStrings("p2", v1);
}

test "parseErrorMessage extracts error field" {
    const body =
        \\{"error":"not found"}
    ;
    const msg = json_helpers.parseErrorMessage(testing.allocator, body);
    defer if (msg) |m| testing.allocator.free(m);

    try testing.expect(msg != null);
    try testing.expectEqualStrings("not found", msg.?);
}

test "parseErrorMessage returns null for missing error" {
    const body =
        \\{"status":"ok"}
    ;
    const msg = json_helpers.parseErrorMessage(testing.allocator, body);
    try testing.expect(msg == null);
}

// =============================================================================
// Model deinit tests (verify no leaks with testing allocator)
// =============================================================================

test "HealthStatus deinit frees memory" {
    const network = try testing.allocator.dupe(u8, "local");
    const hs = models.HealthStatus{ .ok = true, .network = network };
    hs.deinit(testing.allocator);
}

test "PutResult deinit frees memory" {
    const cost = try testing.allocator.dupe(u8, "100");
    const address = try testing.allocator.dupe(u8, "abc");
    const pr = models.PutResult{ .cost = cost, .address = address };
    pr.deinit(testing.allocator);
}

// Note: Integration tests that exercise the full Client against a running antd
// daemon are not included here. To run integration tests, start the daemon with
// `ant dev start` and write tests that create a Client pointing at the daemon URL.
