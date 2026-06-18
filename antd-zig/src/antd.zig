const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;

pub const models = @import("models.zig");
pub const errors = @import("errors.zig");
pub const json_helpers = @import("json_helpers.zig");
pub const discover = @import("discover.zig");

pub const HealthStatus = models.HealthStatus;
pub const PaymentMode = models.PaymentMode;
pub const PutResult = models.PutResult;
pub const DataPutResult = models.DataPutResult;
pub const DataPutPublicResult = models.DataPutPublicResult;
pub const FilePutResult = models.FilePutResult;
pub const FilePutPublicResult = models.FilePutPublicResult;
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
///
/// Naming convention (post v1.0):
///   - Unqualified verb (`dataPut`, `dataGet`, `filePut`, `fileGet`) = private —
///     the DataMap is returned to the caller and NOT stored on-network.
///   - `_public` suffix = public — the DataMap is stored on-network as an
///     extra chunk; the call returns the shareable address.
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

    /// Perform an HTTP request and stream a successful (2xx) response body to
    /// the caller-provided `writer`, in fixed-size chunks (constant memory).
    ///
    /// Unlike `doRequest`, the response body is NOT buffered: it is the
    /// streaming counterpart used by `dataStream`/`dataStreamPublic`. On a
    /// non-2xx status the (short) error body is buffered and parsed for a
    /// `{"error":"..."}` message, mirroring `doRequest`'s error handling.
    ///
    /// `writer` must be a `std.io.Writer` (anytype so any concrete writer —
    /// e.g. a file, an `ArrayList(u8).writer()`, or a network socket — works).
    fn doStream(self: *Client, method: http.Method, path: []const u8, body: ?[]const u8, writer: anytype) !void {
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

        if (status_code < 200 or status_code >= 300) {
            // Non-2xx: error bodies are short; buffer and parse the JSON
            // `{"error":"..."}` message, mirroring doRequest.
            var resp_body = std.ArrayList(u8).init(self.allocator);
            defer resp_body.deinit();
            var buf: [4096]u8 = undefined;
            while (true) {
                const n = req.reader().read(&buf) catch return error.HttpError;
                if (n == 0) break;
                resp_body.appendSlice(buf[0..n]) catch return error.HttpError;
            }
            const msg = json_helpers.parseErrorMessage(self.allocator, resp_body.items) orelse
                self.allocator.dupe(u8, resp_body.items) catch "";
            defer if (msg.len > 0) self.allocator.free(msg);
            self.setLastError(@intCast(status_code), msg);
            return errors.errorForStatus(@intCast(status_code));
        }

        // 2xx: stream the body straight to the caller's writer in fixed-size
        // chunks. The daemon sets Content-Length, so a stream that ends short
        // (a read error) surfaces as error.HttpError to the caller.
        var buf: [16 * 1024]u8 = undefined;
        while (true) {
            const n = req.reader().read(&buf) catch return error.HttpError;
            if (n == 0) break;
            writer.writeAll(buf[0..n]) catch return error.HttpError;
        }
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
    pub fn dataPutPublic(self: *Client, data: []const u8, payment_mode: PaymentMode) !DataPutPublicResult {
        const req_body = try json_helpers.buildDataBodyWithPaymentMode(self.allocator, data, payment_mode.wire());
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/public", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseDataPutPublicResult(self.allocator, resp);
    }

    /// Retrieve public data by address.
    pub fn dataGetPublic(self: *Client, address: []const u8) ![]const u8 {
        const path = try std.fmt.allocPrint(self.allocator, "/v1/data/public/{s}", .{address});
        defer self.allocator.free(path);
        const resp = try self.doRequest(.GET, path, null) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseBase64Data(self.allocator, resp);
    }

    /// Store private encrypted data on the network. The returned DataMap is
    /// the caller's key to retrieve the data later via `dataGet`.
    pub fn dataPut(self: *Client, data: []const u8, payment_mode: PaymentMode) !DataPutResult {
        const req_body = try json_helpers.buildDataBodyWithPaymentMode(self.allocator, data, payment_mode.wire());
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseDataPutResult(self.allocator, resp);
    }

    /// Retrieve private data using a caller-held DataMap.
    pub fn dataGet(self: *Client, data_map: []const u8) ![]const u8 {
        const req_body = try json_helpers.buildDataMapBody(self.allocator, data_map);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/get", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseBase64Data(self.allocator, resp);
    }

    /// Stream public data by address to a caller-provided `writer`, in constant
    /// memory. The streaming counterpart to `dataGetPublic`: instead of
    /// buffering and base64-decoding the whole object, decrypted bytes are
    /// written straight to `writer` as they arrive.
    ///
    /// `writer` is any `std.io.Writer` (e.g. a file's writer, an
    /// `ArrayList(u8).writer()`, or a socket). On a non-2xx response the daemon
    /// returns `{"error":"..."}`, which is mapped to an `AntdError` exactly like
    /// the buffered methods (and recorded in `last_error`).
    pub fn dataStreamPublic(self: *Client, address: []const u8, writer: anytype) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/v1/data/public/{s}/stream", .{address});
        defer self.allocator.free(path);
        return self.doStream(.GET, path, null, writer);
    }

    /// Stream private data, using a caller-held DataMap, to a caller-provided
    /// `writer`, in constant memory. The streaming counterpart to `dataGet`.
    /// Sends the same `{"data_map":"<hex>"}` body as `dataGet` but to
    /// `POST /v1/data/stream`; decrypted bytes are written straight to `writer`.
    ///
    /// `writer` is any `std.io.Writer`. Non-2xx `{"error":"..."}` responses are
    /// mapped to an `AntdError` exactly like the buffered methods.
    pub fn dataStream(self: *Client, data_map: []const u8, writer: anytype) !void {
        const req_body = try json_helpers.buildDataMapBody(self.allocator, data_map);
        defer self.allocator.free(req_body);
        return self.doStream(.POST, "/v1/data/stream", req_body, writer);
    }

    /// Pre-upload cost breakdown for the given bytes.
    pub fn dataCost(self: *Client, data: []const u8, payment_mode: PaymentMode) !models.UploadCostEstimate {
        const req_body = try json_helpers.buildDataBodyWithPaymentMode(self.allocator, data, payment_mode.wire());
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

    /// Upload a local file to the network *publicly*.
    pub fn filePutPublic(self: *Client, path: []const u8, payment_mode: PaymentMode) !FilePutPublicResult {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "path", .value = .{ .string = path } },
            .{ .key = "payment_mode", .value = .{ .string = payment_mode.wire() } },
        });
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/files/public", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseFilePutPublicResult(self.allocator, resp);
    }

    /// Download a public file from an on-network DataMap address.
    pub fn fileGetPublic(self: *Client, address: []const u8, dest_path: []const u8) !void {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "address", .value = .{ .string = address } },
            .{ .key = "dest_path", .value = .{ .string = dest_path } },
        });
        defer self.allocator.free(req_body);
        _ = try self.doRequest(.POST, "/v1/files/public/get", req_body);
    }

    /// Upload a local file to the network *privately*. The returned DataMap is
    /// the caller's key to retrieve the file later via `fileGet`.
    pub fn filePut(self: *Client, path: []const u8, payment_mode: PaymentMode) !FilePutResult {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "path", .value = .{ .string = path } },
            .{ .key = "payment_mode", .value = .{ .string = payment_mode.wire() } },
        });
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/files", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parseFilePutResult(self.allocator, resp);
    }

    /// Download a private file from a caller-held DataMap into `dest_path`.
    pub fn fileGet(self: *Client, data_map: []const u8, dest_path: []const u8) !void {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "data_map", .value = .{ .string = data_map } },
            .{ .key = "dest_path", .value = .{ .string = dest_path } },
        });
        defer self.allocator.free(req_body);
        _ = try self.doRequest(.POST, "/v1/files/get", req_body);
    }

    // --- External Signer (Two-Phase Upload) ---

    /// Prepare a file upload for external signing.
    pub fn prepareUpload(self: *Client, path: []const u8, visibility: ?[]const u8) ![]const u8 {
        const req_body = try json_helpers.buildPrepareUploadBody(self.allocator, path, visibility);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/upload/prepare", req_body) orelse return error.JsonError;
        return resp;
    }

    /// Convenience wrapper for a public file upload prepare.
    pub fn prepareUploadPublic(self: *Client, path: []const u8) ![]const u8 {
        return self.prepareUpload(path, "public");
    }

    /// Prepare a data upload for external signing.
    pub fn prepareDataUpload(self: *Client, data: []const u8, visibility: ?[]const u8) ![]const u8 {
        const req_body = try json_helpers.buildPrepareDataBody(self.allocator, data, visibility);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/data/prepare", req_body) orelse return error.JsonError;
        return resp;
    }

    /// Finalize an upload after an external signer has submitted payment transactions.
    pub fn finalizeUpload(self: *Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
        const resp = try self.doRequest(.POST, "/v1/upload/finalize", tx_hashes_json) orelse return error.JsonError;
        _ = upload_id;
        return resp;
    }

    // --- External Signer (Single-Chunk, antd >= 0.7.0) ---

    /// Prepare a single chunk for external-signer publish via
    /// POST /v1/chunks/prepare.
    pub fn prepareChunkUpload(self: *Client, data: []const u8) !PrepareChunkResult {
        const req_body = try json_helpers.buildDataBody(self.allocator, data);
        defer self.allocator.free(req_body);
        const resp = try self.doRequest(.POST, "/v1/chunks/prepare", req_body) orelse return error.JsonError;
        defer self.allocator.free(resp);
        return json_helpers.parsePrepareChunkResult(self.allocator, resp);
    }

    /// Submit a prepared chunk to the network after external payment via
    /// POST /v1/chunks/finalize.
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
    pub fn fileCost(self: *Client, path: []const u8, is_public: bool, payment_mode: PaymentMode) !models.UploadCostEstimate {
        const req_body = try json_helpers.buildJsonBody(self.allocator, &.{
            .{ .key = "path", .value = .{ .string = path } },
            .{ .key = "is_public", .value = .{ .boolean = is_public } },
            .{ .key = "payment_mode", .value = .{ .string = payment_mode.wire() } },
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
