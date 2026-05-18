const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;

pub const models = @import("models.zig");
pub const errors = @import("errors.zig");
pub const json_helpers = @import("json_helpers.zig");
pub const discover = @import("discover.zig");

pub const HealthStatus = models.HealthStatus;
pub const PutResult = models.PutResult;
pub const FileUploadResult = models.FileUploadResult;
pub const WalletAddress = models.WalletAddress;
pub const WalletBalance = models.WalletBalance;
pub const UploadCostEstimate = models.UploadCostEstimate;
pub const PaymentInfo = models.PaymentInfo;
pub const PrepareChunkResult = models.PrepareChunkResult;
pub const FinalizeUploadResult = models.FinalizeUploadResult;
pub const AntdError = errors.AntdError;
pub const ErrorInfo = errors.ErrorInfo;
pub const errorForStatus = errors.errorForStatus;
pub const JsonValue = json_helpers.JsonValue;
pub const discoverDaemonUrl = discover.discoverDaemonUrl;
pub const discoverGrpcTarget = discover.discoverGrpcTarget;

/// Default antd daemon address.
pub const default_base_url = "http://localhost:8082";

/// REST client for the antd daemon.
pub const Client = struct {
    allocator: Allocator,
    base_url: []const u8,

    /// Last error info from a failed request.
    last_error: ?ErrorInfo = null,

    /// Create a new client.
    pub fn init(allocator: Allocator, base_url: []const u8) Client {
        return .{
            .allocator = allocator,
            .base_url = base_url,
        };
    }

    /// Create a client using daemon port discovery.
    /// Falls back to the default base URL if discovery fails.
    /// Note: if a discovered URL is returned, the caller owns that memory.
    pub fn autoDiscover(allocator: Allocator) Client {
        const url = discover.discoverDaemonUrl(allocator);
        return .{
            .allocator = allocator,
            .base_url = url orelse default_base_url,
        };
    }

    /// Clean up client resources.
    pub fn deinit(self: *Client) void {
        if (self.last_error) |info| {
            if (info.message.len > 0) {
                self.allocator.free(info.message);
            }
            self.last_error = null;
        }
    }

    /// Get the last error info, if any.
    pub fn getLastError(self: *const Client) ?ErrorInfo {
        return self.last_error;
    }

    // --- Internal helpers ---

    fn setLastError(self: *Client, status_code: u16, message: []const u8) void {
        if (self.last_error) |info| {
            if (info.message.len > 0) {
                self.allocator.free(info.message);
            }
        }
        self.last_error = .{
            .status_code = status_code,
            .message = self.allocator.dupe(u8, message) catch "",
        };
    }

    fn buildUrl(self: *const Client, path: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
    }

    fn buildUrlWithParam(self: *const Client, path: []const u8, param: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ self.base_url, path, param });
    }

    /// Perform an HTTP request and return the response body.
    /// Returns null body for HEAD requests or empty responses.
    fn doRequest(self: *Client, method: http.Method, path: []const u8, body: ?[]const u8) !?[]const u8 {
        const url_str = try self.buildUrl(path);
        defer self.allocator.free(url_str);

        const uri = std.Uri.parse(url_str) catch return error.HttpError;

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var header_buf: [4096]u8 = undefined;
        var req = client.open(method, uri, .{
            .server_header_buffer = &header_buf,
            .extra_headers = if (body != null)
                &.{.{ .name = "Content-Type", .value = "application/json" }}
            else
                &.{},
        }) catch return error.HttpError;
        defer req.deinit();

        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
        }

        req.send() catch return error.HttpError;

        if (body) |b| {
            req.writer().writeAll(b) catch return error.HttpError;
            req.finish() catch return error.HttpError;
        }

        req.wait() catch return error.HttpError;

        const status_code = @intFromEnum(req.response.status);

        // For HEAD requests, just check status
        if (method == .HEAD) {
            if (status_code >= 200 and status_code < 300) {
                return null;
            }
            if (status_code == 404) {
                return error.NotFound;
            }
            self.setLastError(@intCast(status_code), "head request failed");
            return errors.errorForStatus(@intCast(status_code));
        }

        // Read response body
        var resp_body = std.ArrayList(u8).init(self.allocator);
        defer resp_body.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = req.reader().read(&buf) catch return error.HttpError;
            if (n == 0) break;
            resp_body.appendSlice(buf[0..n]) catch return error.HttpError;
        }

        const resp_bytes = resp_body.toOwnedSlice() catch return error.HttpError;

        if (status_code < 200 or status_code >= 300) {
            // Try to extract error message from JSON
            const msg = json_helpers.parseErrorMessage(self.allocator, resp_bytes) orelse
                self.allocator.dupe(u8, resp_bytes) catch "";
            defer if (msg.len > 0) self.allocator.free(msg);
            self.allocator.free(resp_bytes);
            self.setLastError(@intCast(status_code), msg);
            return errors.errorForStatus(@intCast(status_code));
        }

        if (resp_bytes.len == 0) {
            self.allocator.free(resp_bytes);
            return null;
        }

        return resp_bytes;
    }

    // --- Health ---

    /// Check the antd daemon status.
    pub fn health(self: *Client) !HealthStatus {
        const body = try self.doRequest(.GET, "/health", null) orelse return error.JsonError;
        defer self.allocator.free(body);
        return json_helpers.parseHealthStatus(self.allocator, body);
    }

    // --- Data ---

    /// Store public immutable data on the network.
    pub fn dataPutPublic(self: *Client, data: []const u8, payment_mode: ?[]const u8) !PutResult {
        const req_body = if (payment_mode) |mode|
            try json_helpers.buildDataBodyWithPaymentMode(self.allocator, data, mode)
        else
            try json_helpers.buildDataBody(self.allocator, data);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/public", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parsePutResult(self.allocator, resp, "address");
    }

    /// Retrieve public data by address.
    pub fn dataGetPublic(self: *Client, address: []const u8) ![]const u8 {
        const path = try std.fmt.allocPrint(self.allocator, "/v1/data/public/{s}", .{address});
        defer self.allocator.free(path);
        const resp = try self.doRequest(.GET, path, null) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseBase64Data(self.allocator, resp);
    }

    /// Store private encrypted data on the network.
    pub fn dataPutPrivate(self: *Client, data: []const u8, payment_mode: ?[]const u8) !PutResult {
        const req_body = if (payment_mode) |mode|
            try json_helpers.buildDataBodyWithPaymentMode(self.allocator, data, mode)
        else
            try json_helpers.buildDataBody(self.allocator, data);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/private", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parsePutResult(self.allocator, resp, "data_map");
    }

    /// Retrieve private data using a data map.
    pub fn dataGetPrivate(self: *Client, data_map: []const u8) ![]const u8 {
        const path = try std.fmt.allocPrint(self.allocator, "/v1/data/private?data_map={s}", .{data_map});
        defer self.allocator.free(path);
        const resp = try self.doRequest(.GET, path, null) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseBase64Data(self.allocator, resp);
    }

    /// Pre-upload cost breakdown for the given bytes.
    pub fn dataCost(self: *Client, data: []const u8) !models.UploadCostEstimate {
        const req_body = try json_helpers.buildDataBody(self.allocator, data);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/cost", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseCostEstimate(self.allocator, resp);
    }

    // --- Chunks ---

    /// Store a raw chunk on the network.
    pub fn chunkPut(self: *Client, data: []const u8) !PutResult {
        const req_body = try json_helpers.buildDataBody(self.allocator, data);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/chunks", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parsePutResult(self.allocator, resp, "address");
    }

    /// Retrieve a chunk by address.
    pub fn chunkGet(self: *Client, address: []const u8) ![]const u8 {
        const path = try std.fmt.allocPrint(self.allocator, "/v1/chunks/{s}", .{address});
        defer self.allocator.free(path);
        const resp = try self.doRequest(.GET, path, null) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseBase64Data(self.allocator, resp);
    }

    // --- Wallet ---

    /// Get the wallet's public address.
    pub fn walletAddress(self: *Client) !WalletAddress {
        const resp = try self.doRequest(.GET, "/v1/wallet/address", null) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseWalletAddress(self.allocator, resp);
    }

    /// Get the wallet's token and gas balances.
    pub fn walletBalance(self: *Client) !WalletBalance {
        const resp = try self.doRequest(.GET, "/v1/wallet/balance", null) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseWalletBalance(self.allocator, resp);
    }

    /// Approve the wallet to spend tokens on payment contracts (one-time operation).
    pub fn walletApprove(self: *Client) !bool {
        const resp = try self.doRequest(.POST, "/v1/wallet/approve", "{}") orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseBoolField(self.allocator, resp, "approved");
    }

    // --- Files ---

    /// Upload a local file to the network.
    pub fn fileUploadPublic(self: *Client, path: []const u8, payment_mode: ?[]const u8) !FileUploadResult {
        const req_body = if (payment_mode) |mode|
            try json_helpers.buildJsonBody(self.allocator, &.{
                .{ .key = "path", .value = .{ .string = path } },
                .{ .key = "payment_mode", .value = .{ .string = mode } },
            })
        else
            try json_helpers.buildJsonBody(self.allocator, &.{
                .{ .key = "path", .value = .{ .string = path } },
            });
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/files/upload/public", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseFileUploadResult(self.allocator, resp);
    }

    /// Download a file from the network to a local path.
    pub fn fileDownloadPublic(self: *Client, address: []const u8, dest_path: []const u8) !void {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "address", .value = .{ .string = address } },
            .{ .key = "dest_path", .value = .{ .string = dest_path } },
        });
        defer self.allocator.free(req_body);
        _ = try self.doRequest(.POST, "/v1/files/download/public", req_body);
    }

    /// Upload a local directory to the network.
    pub fn dirUploadPublic(self: *Client, path: []const u8, payment_mode: ?[]const u8) !FileUploadResult {
        const req_body = if (payment_mode) |mode|
            try json_helpers.buildJsonBody(self.allocator, &.{
                .{ .key = "path", .value = .{ .string = path } },
                .{ .key = "payment_mode", .value = .{ .string = mode } },
            })
        else
            try json_helpers.buildJsonBody(self.allocator, &.{
                .{ .key = "path", .value = .{ .string = path } },
            });
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/dirs/upload/public", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseFileUploadResult(self.allocator, resp);
    }

    /// Download a directory from the network to a local path.
    pub fn dirDownloadPublic(self: *Client, address: []const u8, dest_path: []const u8) !void {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "address", .value = .{ .string = address } },
            .{ .key = "dest_path", .value = .{ .string = dest_path } },
        });
        defer self.allocator.free(req_body);
        _ = try self.doRequest(.POST, "/v1/dirs/download/public", req_body);
    }

    // --- External Signer (Two-Phase Upload) ---

    /// Prepare a file upload for external signing.
    ///
    /// `visibility` is `"public"` to bundle the DataMap chunk into the same
    /// external-signer payment batch (after finalize, the response's
    /// `data_map_address` is the shareable retrieval handle). `"private"` or
    /// `null` keeps the existing private-only behaviour. When `null`, the
    /// `visibility` field is omitted from the request body — preserving the
    /// pre-0.6.1 wire shape that older daemons expect.
    ///
    /// Returns the raw JSON response body that the caller must parse.
    pub fn prepareUpload(self: *Client, path: []const u8, visibility: ?[]const u8) ![]const u8 {
        const req_body = try json_helpers.buildPrepareUploadBody(self.allocator, path, visibility);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/upload/prepare", req_body) orelse return error.JsonError;
        return resp;
    }

    /// Convenience wrapper for a public file upload prepare.
    /// Equivalent to `prepareUpload(path, "public")`.
    pub fn prepareUploadPublic(self: *Client, path: []const u8) ![]const u8 {
        return self.prepareUpload(path, "public");
    }

    /// Prepare a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    ///
    /// `visibility` semantics match `prepareUpload`. Note: as of writing,
    /// the daemon returns 501 for visibility="public" on this endpoint
    /// until upstream ant-client exposes `data_prepare_upload_with_visibility`;
    /// use `prepareUploadPublic` with a file path instead.
    ///
    /// Returns the raw JSON response body that the caller must parse.
    pub fn prepareDataUpload(self: *Client, data: []const u8, visibility: ?[]const u8) ![]const u8 {
        const req_body = try json_helpers.buildPrepareDataBody(self.allocator, data, visibility);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/prepare", req_body) orelse return error.JsonError;
        return resp;
    }

    /// Finalize an upload after an external signer has submitted payment transactions.
    /// Returns raw JSON response body that the caller must parse (see
    /// `json_helpers.parseFinalizeUploadResult`).
    pub fn finalizeUpload(self: *Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
        // Caller must provide a pre-built JSON body with upload_id and tx_hashes
        const resp = try self.doRequest(.POST, "/v1/upload/finalize", tx_hashes_json) orelse return error.JsonError;
        _ = upload_id;
        return resp;
    }

    // --- External Signer (Single-Chunk, antd >= 0.7.0) ---

    /// Prepare a single chunk for external-signer publish via
    /// POST /v1/chunks/prepare.
    ///
    /// The daemon collects storage quotes from the close group, stashes the
    /// prepared state, and returns either:
    ///
    ///   - `already_stored = true` with `address` set, if the chunk is already
    ///     on-network. No payment or finalize call is needed.
    ///   - `already_stored = false` with `upload_id` + `payments` +
    ///     `total_amount` populated, in which case the caller signs and
    ///     submits payForQuotes() externally, then calls `finalizeChunkUpload`
    ///     with the resulting tx hashes.
    ///
    /// Unlike `chunkPut`, this method does NOT require the daemon to have a
    /// wallet — all funds flow through the external signer.
    ///
    /// Caller owns the returned struct's memory (call `.deinit(allocator)`).
    pub fn prepareChunkUpload(self: *Client, data: []const u8) !PrepareChunkResult {
        const req_body = try json_helpers.buildDataBody(self.allocator, data);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/chunks/prepare", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parsePrepareChunkResult(self.allocator, resp);
    }

    /// Submit a prepared chunk to the network after external payment via
    /// POST /v1/chunks/finalize.
    ///
    /// `tx_hashes_json` is a pre-built JSON object literal mapping non-zero
    /// `quote_hash` from `PrepareChunkResult.payments` to the `tx_hash`
    /// returned by `payForQuotes()` — e.g. `"{\"0xqh1\":\"0xtx1\"}"`. Caller
    /// formats this map by hand (matches the existing `finalizeUpload`
    /// pattern).
    ///
    /// Returns the hex-encoded network address of the stored chunk (matches
    /// `PrepareChunkResult.address`). Caller owns the returned bytes.
    pub fn finalizeChunkUpload(self: *Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
        const req_body = try json_helpers.buildFinalizeChunkBody(self.allocator, upload_id, tx_hashes_json);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/chunks/finalize", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);

        // Extract "address" string from response.
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, resp, .{}) catch
            return error.JsonError;
        defer parsed.deinit();
        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.JsonError,
        };
        const addr_val = obj.get("address") orelse return error.JsonError;
        return switch (addr_val) {
            .string => |s| try self.allocator.dupe(u8, s),
            else => error.JsonError,
        };
    }

    /// Pre-upload cost breakdown for the file at `path`.
    pub fn fileCost(self: *Client, path: []const u8, is_public: bool) !models.UploadCostEstimate {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "path", .value = .{ .string = path } },
            .{ .key = "is_public", .value = .{ .boolean = is_public } },
        });
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/files/cost", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseCostEstimate(self.allocator, resp);
    }
};

test {
    _ = @import("tests.zig");
}
