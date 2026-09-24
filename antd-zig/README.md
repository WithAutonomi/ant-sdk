# antd-zig

Zig SDK for the [antd](../antd/) daemon -- the gateway to the Autonomi decentralized network.

## Installation

Add `antd-zig` as a dependency in your `build.zig.zon`:

```zig
.dependencies = .{
    .antd = .{
        .url = "https://github.com/WithAutonomi/ant-sdk/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const antd_dep = b.dependency("antd", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("antd", antd_dep.module("antd"));
```

Or fetch directly:

```bash
zig fetch --save https://github.com/WithAutonomi/ant-sdk/archive/<commit>.tar.gz
```

## Quick Start

```zig
const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Check daemon health
    const status = try client.health();
    defer status.deinit(allocator);
    std.debug.print("OK: {}, Network: {s}\n", .{ status.ok, status.network });

    // Store data
    const result = try client.dataPutPublic("Hello, Autonomi!");
    defer result.deinit(allocator);
    std.debug.print("Stored at {s} (chunks: {d})\n", .{ result.address, result.chunks_stored });

    // Retrieve data
    const data = try client.dataGetPublic(result.address);
    defer allocator.free(data);
    std.debug.print("Retrieved: {s}\n", .{data});
}
```

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```zig
// Default: http://localhost:8082
var client = antd.Client.init(allocator, antd.default_base_url);
defer client.deinit();

// Custom URL
var client = antd.Client.init(allocator, "http://custom-host:9090");
defer client.deinit();
```

## API Reference

All methods return `!T` (error union) using Zig's standard error handling.

### Health

| Method | Signature | Description |
|--------|-----------|-------------|
| `health` | `fn (self: *Client) !HealthStatus` | Check daemon status |

### Data (Immutable)

| Method | Signature | Description |
|--------|-----------|-------------|
| `dataPutPublic` | `fn (self: *Client, data: []const u8, payment_mode: PaymentMode) !DataPutPublicResult` | Store public data — DataMap stored on-network |
| `dataGetPublic` | `fn (self: *Client, address: []const u8) ![]const u8` | Retrieve public data by address |
| `dataPut` | `fn (self: *Client, data: []const u8, payment_mode: PaymentMode) !DataPutResult` | Store encrypted private data — DataMap returned to caller |
| `dataGet` | `fn (self: *Client, data_map: []const u8) ![]const u8` | Retrieve private data using a caller-held DataMap |
| `dataCost` | `fn (self: *Client, data: []const u8, payment_mode: PaymentMode) !UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

### Chunks

| Method | Signature | Description |
|--------|-----------|-------------|
| `chunkPut` | `fn (self: *Client, data: []const u8) !PutResult` | Store a raw chunk |
| `chunkGet` | `fn (self: *Client, address: []const u8) ![]const u8` | Retrieve a chunk |

### Files

| Method | Signature | Description |
|--------|-----------|-------------|
| `filePut` | `fn (self: *Client, path: []const u8, payment_mode: PaymentMode) !FilePutResult` | Upload a file privately — DataMap returned to caller |
| `fileGet` | `fn (self: *Client, data_map: []const u8, dest_path: []const u8) !void` | Download a private file using a caller-held DataMap |
| `filePutPublic` | `fn (self: *Client, path: []const u8, payment_mode: PaymentMode) !FilePutPublicResult` | Upload a file publicly — DataMap stored on-network |
| `fileGetPublic` | `fn (self: *Client, address: []const u8, dest_path: []const u8) !void` | Download a public file by address |
| `fileCost` | `fn (self: *Client, path: []const u8, is_public: bool, payment_mode: PaymentMode) !UploadCostEstimate` | Estimate upload cost — size, chunks, gas, payment mode |

## Error Handling

Methods return errors from the `AntdError` error set. Use Zig's error handling patterns:

```zig
const result = client.dataPutPublic("data") catch |err| switch (err) {
    error.NotFound => {
        std.debug.print("Data not found on network\n", .{});
        return err;
    },
    error.Payment => {
        std.debug.print("Insufficient funds\n", .{});
        return err;
    },
    else => return err,
};
```

For detailed error information, check `client.getLastError()` after a failed call:

```zig
const result = client.health() catch |err| {
    if (client.getLastError()) |info| {
        std.debug.print("HTTP {d}: {s}\n", .{ info.status_code, info.message });
    }
    return err;
};
```

| Error | HTTP Status | When |
|-------|-------------|------|
| `BadRequest` | 400 | Invalid parameters |
| `Payment` | 402 | Insufficient funds |
| `NotFound` | 404 | Resource not found |
| `AlreadyExists` | 409 | Resource exists |
| `TooLarge` | 413 | Payload too large |
| `Internal` | 500 | Server error |
| `Network` | 502 | Network unreachable |
| `PartialUpload` | 502 (`code: PARTIAL_UPLOAD`) | Finalize stored some chunks but not all -- see [Partial uploads](#partial-uploads) |
| `UnexpectedStatus` | other | Unmapped status code |
| `HttpError` | -- | Connection/transport failure |
| `JsonError` | -- | JSON parse/encode failure |

### Partial uploads

An external-signer finalize (`finalizeUpload`, `finalizeChunkUpload`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. The daemon reports this as HTTP 502 with `code: "PARTIAL_UPLOAD"`, which the SDK returns as `error.PartialUpload` (a plain 502 stays `error.Network`). The on-chain payment persists and the stored chunks stay on the network. `getLastError()` carries the structured detail:

| `ErrorInfo` field | Meaning |
|-------------------|---------|
| `chunks_stored` | Chunks the daemon stored before giving up |
| `chunks_failed` | Chunks still unstored after the daemon's retries |
| `total_chunks` | Chunks in the upload |
| `retryable` | How to finish the upload (see below). Sent by antd >= 0.14.0; absent on older daemons, where it reads `false` |

These fields are zero / `false` for every other error.

- **`retryable == true`** -- the daemon kept the paid attempt (payment proofs plus the unstored chunks) under the same `upload_id`. Call the **same finalize function again with the same arguments**; the remainder is stored against the same payment -- no re-prepare, no second signature, no double payment. Bound the loop: a persistent failure returns `error.PartialUpload` on every call, so cap the attempts and treat a `chunks_failed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL (one hour).
- **`retryable == false`** -- nothing was retained (an older daemon, or a merkle finalize with deliberately unpaid batches). Re-prepare the same content: already-stored chunks are skipped, so the retry pays only for the remainder.

The contract is specified in [docs/external-signer-flow.md, section 6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment). A bounded retry helper around `finalizeUpload` -- five attempts, linear backoff, stuck detection -- that only retries when `retryable` and returns a non-retryable partial upload untouched:

```zig
/// Finalize with a bounded retry against the same payment. Returns the
/// finalize response body (caller frees) or the finalize error; a
/// non-retryable `error.PartialUpload` is returned untouched (re-prepare).
fn finalizeWithRetry(client: *antd.Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
    const max_attempts = 5;
    var last_failed: ?u64 = null;
    var attempt: u32 = 1;
    while (true) : (attempt += 1) {
        return client.finalizeUpload(upload_id, tx_hashes_json) catch |err| {
            if (err != error.PartialUpload) return err;
            const info = client.getLastError() orelse return err;
            if (!info.retryable) return err; // nothing retained: re-prepare instead

            const stuck = if (last_failed) |prev| info.chunks_failed >= prev else false;
            if (attempt >= max_attempts or stuck) {
                std.debug.print(
                    "finalize stuck after {d} attempt(s): {d}/{d} chunks stored, {d} still unstored (paid attempt retained under upload_id {s} -- retry later or re-prepare)\n",
                    .{ attempt, info.chunks_stored, info.total_chunks, info.chunks_failed, upload_id },
                );
                return err;
            }
            last_failed = info.chunks_failed;
            std.debug.print(
                "finalize stored {d}/{d} chunks, {d} still unstored -- retrying against the same payment (attempt {d}/{d})\n",
                .{ info.chunks_stored, info.total_chunks, info.chunks_failed, attempt + 1, max_attempts },
            );
            std.Thread.sleep(@as(u64, attempt) * 2 * std.time.ns_per_s);
            continue;
        };
    }
}
```

## Memory Management

The Zig SDK follows Zig's explicit memory management conventions:

- **Caller owns all returned allocations.** You must free them when done.
- Struct results (`HealthStatus`, `PutResult`, `DataPutResult`, `DataPutPublicResult`, `FilePutResult`, `FilePutPublicResult`, `UploadCostEstimate`) have a `deinit(allocator)` method that frees all owned memory.
- Raw byte slices (`[]const u8`) returned by `dataGetPublic`, `dataGet`, and `chunkGet` must be freed with `allocator.free(result)`.
- Use `defer` immediately after receiving a result to ensure cleanup.

```zig
const result = try client.dataPutPublic("data");
defer result.deinit(allocator);
// use result...
```

## Building

```bash
# Build the library
zig build

# Run tests
zig build test

# Run an example
zig build run-01-connect
zig build run-02-data
zig build run-03-chunks
zig build run-04-files
zig build run-06-private-data
```

## Examples

See the [examples/](examples/) directory:

- `01-connect` -- Health check
- `02-data` -- Public data put/get
- `03-chunks` -- Chunk put/get
- `04-files` -- File upload/download
- `06-private-data` -- Private data put/get
