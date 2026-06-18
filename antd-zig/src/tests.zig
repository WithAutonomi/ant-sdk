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
    // Pre-0.4.0 daemon shape: diagnostic fields default to empty / 0.
    try testing.expectEqualStrings("", result.version);
    try testing.expectEqualStrings("", result.evm_network);
    try testing.expect(result.uptime_seconds == 0);
}

test "parseHealthStatus parses 0.4.0 diagnostic fields" {
    const body =
        \\{"status":"ok","network":"local","version":"0.4.0","evm_network":"local","uptime_seconds":42,"build_commit":"abcdef123456","payment_token_address":"0xtoken","payment_vault_address":"0xvault"}
    ;
    const result = try json_helpers.parseHealthStatus(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expect(result.ok);
    try testing.expectEqualStrings("local", result.network);
    try testing.expectEqualStrings("0.4.0", result.version);
    try testing.expectEqualStrings("local", result.evm_network);
    try testing.expect(result.uptime_seconds == 42);
    try testing.expectEqualStrings("abcdef123456", result.build_commit);
    try testing.expectEqualStrings("0xtoken", result.payment_token_address);
    try testing.expectEqualStrings("0xvault", result.payment_vault_address);
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

test "parseFilePutPublicResult parses all fields" {
    const body =
        \\{"address":"file1","storage_cost_atto":"1000","gas_cost_wei":"42","chunks_stored":3,"payment_mode_used":"auto"}
    ;
    const result = try json_helpers.parseFilePutPublicResult(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("file1", result.address);
    try testing.expectEqualStrings("1000", result.storage_cost_atto);
    try testing.expectEqualStrings("42", result.gas_cost_wei);
    try testing.expectEqual(@as(u64, 3), result.chunks_stored);
    try testing.expectEqualStrings("auto", result.payment_mode_used);
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

test "parseCostEstimate extracts cost" {
    const body =
        \\{"cost":"500","file_size":0,"chunk_count":0,"estimated_gas_cost_wei":"0","payment_mode":""}
    ;
    const result = try json_helpers.parseCostEstimate(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("500", result.cost);
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

// =============================================================================
// V2-249 PR4 / V2-274: prepare-upload visibility forwarding,
//                      data_map_address on finalize, single-chunk external signer.
// =============================================================================
//
// These tests cover the wire-shape of the new surfaces. They don't spin up a
// mock HTTP server — antd-zig's existing test scaffolding parses/builds JSON
// bodies directly, so this stays consistent with the file. The Go and Python
// SDKs have their own end-to-end mock tests in client_test.go / test_rest_client.py.

test "buildPrepareUploadBody omits visibility when null (pre-0.6.1 wire shape)" {
    const body = try json_helpers.buildPrepareUploadBody(testing.allocator, "/tmp/x.bin", null);
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const path_val = getJsonString(obj.get("path") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("/tmp/x.bin", path_val);
    // visibility key MUST NOT be present — pre-0.6.1 daemons reject unknown fields.
    try testing.expect(obj.get("visibility") == null);
}

test "buildPrepareUploadBody forwards visibility=public (prepareUploadPublic shape)" {
    const body = try json_helpers.buildPrepareUploadBody(testing.allocator, "/tmp/x.bin", "public");
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const path_val = getJsonString(obj.get("path") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("/tmp/x.bin", path_val);
    const vis_val = getJsonString(obj.get("visibility") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("public", vis_val);
}

test "buildPrepareDataBody forwards visibility and base64-encodes data" {
    const body = try json_helpers.buildPrepareDataBody(testing.allocator, "hello", "private");
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    // "hello" → "aGVsbG8="
    const data_val = getJsonString(obj.get("data") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("aGVsbG8=", data_val);
    const vis_val = getJsonString(obj.get("visibility") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("private", vis_val);

    // Null visibility must drop the field entirely.
    const body_null = try json_helpers.buildPrepareDataBody(testing.allocator, "hello", null);
    defer testing.allocator.free(body_null);
    const parsed_null = try std.json.parseFromSlice(std.json.Value, testing.allocator, body_null, .{});
    defer parsed_null.deinit();
    const obj_null = getJsonObject(parsed_null.value) orelse return error.JsonError;
    try testing.expect(obj_null.get("visibility") == null);
}

test "parseFinalizeUploadResult surfaces data_map_address for public uploads" {
    const body =
        \\{"data_map":"deadbeef","data_map_address":"cafebabe","chunks_stored":4}
    ;
    const result = try json_helpers.parseFinalizeUploadResult(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("deadbeef", result.data_map);
    try testing.expectEqualStrings("cafebabe", result.data_map_address);
    try testing.expectEqualStrings("", result.address); // legacy field, only set when store_data_map=true
    try testing.expectEqual(@as(u64, 4), result.chunks_stored);
}

test "parseFinalizeUploadResult defaults data_map_address to empty for old/private daemons" {
    // Pre-0.6.1 daemons (and private uploads) omit data_map_address.
    const body =
        \\{"data_map":"deadbeef","chunks_stored":2}
    ;
    const result = try json_helpers.parseFinalizeUploadResult(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("deadbeef", result.data_map);
    try testing.expectEqualStrings("", result.data_map_address);
    try testing.expectEqualStrings("", result.address);
    try testing.expectEqual(@as(u64, 2), result.chunks_stored);
}

test "parsePrepareChunkResult parses already_stored branch" {
    // already_stored:true → only address + already_stored populated.
    const body =
        \\{"address":"bb1111111111111111111111111111111111111111111111111111111111111111","already_stored":true}
    ;
    const result = try json_helpers.parsePrepareChunkResult(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expect(result.already_stored);
    try testing.expectEqualStrings(
        "bb1111111111111111111111111111111111111111111111111111111111111111",
        result.address,
    );
    try testing.expectEqualStrings("", result.upload_id);
    try testing.expectEqualStrings("", result.payment_type);
    try testing.expectEqual(@as(usize, 0), result.payments.len);
    try testing.expectEqualStrings("", result.total_amount);
}

test "parsePrepareChunkResult parses wave-batch branch with payments" {
    const body =
        \\{"address":"aa00","already_stored":false,"upload_id":"chunk-1","payment_type":"wave_batch","payments":[{"quote_hash":"qh1","rewards_address":"ra1","amount":"100"},{"quote_hash":"qh2","rewards_address":"ra2","amount":"200"}],"total_amount":"300","payment_vault_address":"0xvault","payment_token_address":"0xtoken","rpc_url":"http://localhost:8545"}
    ;
    const result = try json_helpers.parsePrepareChunkResult(testing.allocator, body);
    defer result.deinit(testing.allocator);

    try testing.expect(!result.already_stored);
    try testing.expectEqualStrings("aa00", result.address);
    try testing.expectEqualStrings("chunk-1", result.upload_id);
    try testing.expectEqualStrings("wave_batch", result.payment_type);
    try testing.expectEqual(@as(usize, 2), result.payments.len);
    try testing.expectEqualStrings("qh1", result.payments[0].quote_hash);
    try testing.expectEqualStrings("ra1", result.payments[0].rewards_address);
    try testing.expectEqualStrings("100", result.payments[0].amount);
    try testing.expectEqualStrings("qh2", result.payments[1].quote_hash);
    try testing.expectEqualStrings("200", result.payments[1].amount);
    try testing.expectEqualStrings("300", result.total_amount);
    try testing.expectEqualStrings("0xvault", result.payment_vault_address);
    try testing.expectEqualStrings("0xtoken", result.payment_token_address);
    try testing.expectEqualStrings("http://localhost:8545", result.rpc_url);
}

test "buildFinalizeChunkBody embeds upload_id and tx_hashes literal" {
    const body = try json_helpers.buildFinalizeChunkBody(
        testing.allocator,
        "chunk-1",
        "{\"qh1\":\"tx1\",\"qh2\":\"tx2\"}",
    );
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const id_val = getJsonString(obj.get("upload_id") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("chunk-1", id_val);

    const tx_obj = getJsonObject(obj.get("tx_hashes") orelse return error.JsonError) orelse return error.JsonError;
    const tx1 = getJsonString(tx_obj.get("qh1") orelse return error.JsonError) orelse return error.JsonError;
    const tx2 = getJsonString(tx_obj.get("qh2") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("tx1", tx1);
    try testing.expectEqualStrings("tx2", tx2);
}

// =============================================================================
// V2-289 Phase 1 (REST): streaming download fan-out.
//
// dataStream/dataStreamPublic are the streaming counterparts to
// dataGet/dataGetPublic. Like the rest of this file, these tests don't spin up
// a mock HTTP server — they assert the wire-shape contracts that the streaming
// methods rely on:
//   - dataStream POSTs the SAME {"data_map":"<hex>"} body as dataGet (just to
//     /v1/data/stream instead of /v1/data/get).
//   - dataStreamPublic GETs /v1/data/public/{address}/stream (no body).
// End-to-end byte-streaming behaviour is covered by the daemon's E2E suite and
// the antd-go SDK's integration tests.
// =============================================================================

test "dataStream reuses the data_map request body shape of dataGet" {
    // dataStream sends buildDataMapBody(data_map) exactly like dataGet, so the
    // private-stream body must base64-free, hex-string match the buffered get.
    const body = try json_helpers.buildDataMapBody(testing.allocator, "deadbeef");
    defer testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const obj = getJsonObject(parsed.value) orelse return error.JsonError;

    const dm = getJsonString(obj.get("data_map") orelse return error.JsonError) orelse return error.JsonError;
    try testing.expectEqualStrings("deadbeef", dm);
    // No other fields — same shape POST /v1/data/get accepts.
    try testing.expectEqual(@as(usize, 1), obj.count());
}

test "streaming non-2xx error body parses into the SDK {\"error\"} contract" {
    // doStream maps non-2xx {"error":"..."} bodies via parseErrorMessage, the
    // same path the buffered methods use. Verify that contract holds.
    const body =
        \\{"error":"data map not found","code":"not_found"}
    ;
    const msg = json_helpers.parseErrorMessage(testing.allocator, body);
    defer if (msg) |m| testing.allocator.free(m);

    try testing.expect(msg != null);
    try testing.expectEqualStrings("data map not found", msg.?);
}

// Note: Integration tests that exercise the full Client against a running antd
// daemon are not included here. To run integration tests, start the daemon with
// `ant dev start` and write tests that create a Client pointing at the daemon URL.
