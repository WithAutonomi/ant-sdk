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

### External signer (two-phase upload)

| Method | Signature | Description |
|--------|-----------|-------------|
| `prepareUpload` | `fn (self: *Client, path: []const u8, visibility: ?[]const u8) ![]const u8` | Prepare a file upload for external payment — returns the raw prepare response (`upload_id`, `payments`, ...) |
| `prepareUploadPublic` | `fn (self: *Client, path: []const u8) ![]const u8` | `prepareUpload` with `visibility: "public"` |
| `prepareDataUpload` | `fn (self: *Client, data: []const u8, visibility: ?[]const u8) ![]const u8` | Prepare an in-memory data upload for external payment |
| `finalizeUpload` | `fn (self: *Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8` | Store the prepared upload after payment — returns the raw finalize response (`data_map`, `data_map_address`) |
| `prepareChunkUpload` | `fn (self: *Client, data: []const u8) !PrepareChunkResult` | Prepare a single chunk for external payment |
| `finalizeChunkUpload` | `fn (self: *Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8` | Store the prepared chunk after payment — returns its address |

Both finalize methods take the same two arguments: the `upload_id` from the prepare response and `tx_hashes_json`, the quote-hash → tx-hash map from the on-chain `payForQuotes()` payment as a JSON object string — only the map, not a request object. The SDK builds the request body itself (`{"upload_id": ..., "tx_hashes": {...}}`, plus `"store_data_map": false` for `finalizeUpload`) and returns `error.JsonError` without sending anything if the string is not a JSON object. Pass `{}` when prepare reported no payments (every chunk was already stored). The flow is specified in [docs/external-signer-flow.md](../docs/external-signer-flow.md).

```zig
// After payForQuotes() confirmed with tx_hash, for every payment p in the
// prepare response: tx_hashes[p.quote_hash] = tx_hash
const tx_hashes_json = "{\"<quote_hash_0>\":\"<tx_hash>\",\"<quote_hash_1>\":\"<tx_hash>\"}";
const body = try client.finalizeUpload(upload_id, tx_hashes_json);
defer allocator.free(body);
const result = try antd.json_helpers.parseFinalizeUploadResult(allocator, body);
defer result.deinit(allocator);
```

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

### `error.PartialUpload` replaces `error.Network` for partial uploads

This is an intentional change. A REST partial upload (HTTP 502 with `code: "PARTIAL_UPLOAD"`) used to surface as `error.Network`, the plain 502 mapping. It now surfaces as `error.PartialUpload`, because it has been paid for and needs different recovery than a network failure. Zig error sets have no subtyping, so an existing `error.Network => ...` prong no longer sees it, and a `switch` over `AntdError` without an `else` prong must name the new error. Add an `error.PartialUpload` prong:

```zig
const body = client.finalizeUpload(upload_id, tx_hashes_json) catch |err| switch (err) {
    // Previously this case fell through to error.Network below.
    error.PartialUpload => {
        const info = client.getLastError() orelse return err;
        std.debug.print("partial upload: {d}/{d} chunks stored (retryable={}, retention_known={})\n", .{
            info.chunks_stored, info.total_chunks, info.retryable, info.retention_known,
        });
        return err; // recover as described in "Partial uploads" below
    },
    error.Network => return err, // a plain 502: the finalize reported no partial store
    else => return err,
};
```

Or handle both in one prong while migrating:

```zig
const body = client.finalizeUpload(upload_id, tx_hashes_json) catch |err| switch (err) {
    error.Network, error.PartialUpload => {
        std.debug.print("finalize failed: {s}\n", .{@errorName(err)});
        return err;
    },
    else => return err,
};
```

Whichever form you choose, never send a partial upload down a recovery path that re-prepares and pays again, as you might after a network failure. Follow the three cases in the next section.

### Partial uploads

An external-signer finalize (`finalizeUpload`, `finalizeChunkUpload`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. The daemon reports this as HTTP 502 with `code: "PARTIAL_UPLOAD"`, which the SDK returns as `error.PartialUpload` (a plain 502 stays `error.Network`). The on-chain payment persists and the stored chunks stay on the network. `getLastError()` carries the structured detail:

| `ErrorInfo` field | Meaning |
|-------------------|---------|
| `chunks_stored` | Chunks the daemon stored before giving up |
| `chunks_failed` | Chunks still unstored after the daemon's retries |
| `total_chunks` | Chunks in the upload |
| `retryable` | `true` when the daemon kept the paid attempt for a retry. Sent by antd >= 0.14.0. It reads `false` when absent or malformed, so check `retention_known` before taking `false` to mean nothing was retained |
| `retention_known` | `true` when the body carried `retryable` as a JSON boolean, meaning the daemon stated whether it kept the paid attempt. `false` when the flag was missing (every daemon older than 0.14.0), null or not a boolean: retention is unknown. Always `true` when `retryable` is |

These fields are zero / `false` for every other error. A malformed body never panics: a count that is not a JSON non-negative integer below 2^64 reads as 0, a `retryable` that is not a JSON boolean reads as `false` with `retention_known` `false`, and a body whose `code` is not the string `"PARTIAL_UPLOAD"` maps by HTTP status alone.

- **`retryable`** -- the daemon kept the paid attempt (payment proofs plus the unstored chunks) under the same `upload_id`. Call the **same finalize function again with the same arguments** (the same `upload_id` and the same `tx_hashes_json` map); the remainder is stored against the same payment -- no re-prepare, no second signature, no double payment. Bound the loop: a persistent failure returns `error.PartialUpload` on every call, so cap the attempts and treat a `chunks_failed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL (one hour).
- **`retention_known and !retryable`** -- the daemon confirmed that nothing was retained (a merkle finalize with deliberately unpaid batches, for example). Re-prepare the same content: already-stored chunks are skipped, so the retry pays only for the remainder.
- **`!retention_known`** -- retention is unknown. The flag was missing, as it is from every daemon older than 0.14.0, or it was null or not a boolean. `retryable == false` does **not** mean that nothing was retained here: the daemon records the resume handle before it returns the error, so it may still hold the paid attempt under the same `upload_id`. Stop automatic recovery. Keep the `upload_id` and the original payment artefacts (the `tx_hashes_json` map and the transactions behind it), and reconcile before re-preparing or paying again. Never pay again on this signal alone.

The contract is specified in [docs/external-signer-flow.md, section 6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment). A bounded retry helper around `finalizeUpload` -- five attempts, linear backoff, stuck detection -- that only retries when `retryable`. It returns any other partial upload untouched, and when retention is unknown it stops without re-preparing or paying:

```zig
/// Finalize with a bounded retry against the same payment. `upload_id` and
/// `tx_hashes_json` (the quote-hash -> tx-hash map as a JSON object string)
/// are passed to `finalizeUpload` unchanged on every attempt. Returns the
/// finalize response body (caller frees) or the finalize error. A
/// non-retryable `error.PartialUpload` is returned untouched: re-prepare
/// only when `retention_known` says nothing was retained; when retention is
/// unknown, keep `upload_id` and the payment artefacts and reconcile first.
fn finalizeWithRetry(client: *antd.Client, upload_id: []const u8, tx_hashes_json: []const u8) ![]const u8 {
    const max_attempts = 5;
    var last_failed: ?u64 = null;
    var attempt: u32 = 1;
    while (true) : (attempt += 1) {
        return client.finalizeUpload(upload_id, tx_hashes_json) catch |err| {
            if (err != error.PartialUpload) return err;
            const info = client.getLastError() orelse return err;
            if (!info.retryable) {
                // Confirmed that nothing was retained: the caller re-prepares.
                if (info.retention_known) return err;
                // Retention unknown (daemon < 0.14.0, or a missing / malformed
                // flag): the daemon may still hold the paid attempt. Stop here
                // -- no re-prepare, no second payment.
                std.debug.print(
                    "finalize stored {d}/{d} chunks; retention unknown -- keep upload_id {s} and the payment artefacts and reconcile before re-preparing or paying again\n",
                    .{ info.chunks_stored, info.total_chunks, upload_id },
                );
                return err;
            }

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
