# Zig Quickstart

A comprehensive guide to using the Autonomi network with the Zig SDK.

## Setup

```bash
# Prerequisites
# - Zig 0.13+: https://ziglang.org/download/
# - antd daemon running (ant dev start)
```

Add the dependency to your `build.zig.zon`:

```zig
.dependencies = .{
    .antd = .{
        .url = "https://github.com/WithAutonomi/ant-sdk/archive/refs/heads/main.tar.gz",
        .hash = "...",  // zig build will tell you the correct hash
    },
},
```

Then in your `build.zig`:

```zig
const antd = b.dependency("antd", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("antd", antd.module("antd"));
```

Or scaffold a new project:

```bash
ant dev init zig --name my-project
```

## Connecting

```zig
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // REST transport (default)
    var client = try antd.Client.init(allocator, .{});
    defer client.deinit();

    // Custom endpoint
    var client2 = try antd.Client.init(allocator, .{
        .transport = .rest,
        .base_url = "http://localhost:8082",
    });
    defer client2.deinit();

    // gRPC transport
    var client3 = try antd.Client.init(allocator, .{
        .transport = .grpc,
        .target = "localhost:50051",
    });
    defer client3.deinit();
}
```

**Memory ownership**: All returned slices and structs containing allocated memory are owned by the caller. You must free them when done, or use `defer` as shown in the examples.

## Health Check

```zig
const status = try client.health();
defer status.deinit(allocator);

std.debug.print("Healthy: {}\n", .{status.ok});
std.debug.print("Network: {s}\n", .{status.network}); // "local", "default", "alpha"
```

## Public Data

```zig
// Store
const result = try client.dataPutPublic("Hello, Autonomi!", .auto);
defer result.deinit(allocator);
std.debug.print("Address: {s}\n", .{result.address});
std.debug.print("Cost: {d} atto tokens\n", .{result.cost});

// Retrieve
const data = try client.dataGetPublic(result.address);
defer allocator.free(data);
std.debug.print("{s}\n", .{data}); // "Hello, Autonomi!"

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
const est = try client.dataCost("some data");
defer est.deinit(allocator);
std.debug.print("Estimate: {d} bytes in {d} chunks, {s} atto, gas {s} wei, mode {s}\n",
    .{ est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode });
```

## Private Data

```zig
// Store (self-encrypting)
const result = try client.dataPut("secret message", .auto);
defer result.deinit(allocator);
const data_map = result.data_map; // Keep this secret!

// Retrieve (decrypt)
const data = try client.dataGet(data_map);
defer allocator.free(data);
std.debug.print("{s}\n", .{data});
```

## Files

```zig
// Upload a file
const result = try client.filePutPublic("/path/to/file.txt", .auto);
defer result.deinit(allocator);
std.debug.print("File address: {s}\n", .{result.address});

// Download a file
try client.fileGetPublic(result.address, "/path/to/output.txt");

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
const est = try client.fileCost("/path/to/file.txt", true);
defer est.deinit(allocator);
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```zig
const owner = "<a pointer address from client.pointerKeys()>";

const v1 = try client.dataPutPublic("version 1", .auto);
defer v1.deinit(allocator);
const v2 = try client.dataPutPublic("version 2", .auto);
defer v2.deinit(allocator);

const created = try client.pointerCreate(owner, v1.address, .chunk);  // pays; counter 0
defer created.deinit(allocator);
const updated = try client.pointerUpdate(owner, v2.address, .chunk);  // pays again; counter 1
defer updated.deinit(allocator);

const target = try client.pointerResolve(owner);                      // free
defer target.deinit(allocator);
const finality = try client.pointerFinality(owner);
defer finality.deinit(allocator);
std.debug.print("{s}: {s}\n", .{ target.target, finality.status.wire() });  // <v2.address>: open
```

Counters are `u64`. `pointerTransfer`, `pointerGet`, `pointerController`, `pointerPrepare` and `pointerFinalize` complete the set (REST only).

Runnable example: `antd-zig/examples/09-pointers.zig`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-zig
ANTD_POINTER_OWNER=<address> zig build run-09-pointers
```

## Error Handling

```zig
const result = client.dataGetPublic("nonexistent") catch |err| switch (err) {
    error.NotFound => {
        std.debug.print("Not found\n", .{});
        return;
    },
    error.PaymentRequired => {
        std.debug.print("Payment issue\n", .{});
        return;
    },
    error.NetworkUnreachable => {
        std.debug.print("Network unreachable\n", .{});
        return;
    },
    else => {
        std.debug.print("Error: {}\n", .{err});
        return err;
    },
};
defer allocator.free(result);
```

Error union variants:

| Error | HTTP Code | When |
|-------|-----------|------|
| `error.BadRequest` | 400 | Invalid parameters |
| `error.PaymentRequired` | 402 | Insufficient funds |
| `error.NotFound` | 404 | Resource not found |
| `error.AlreadyExists` | 409 | Duplicate creation |
| `error.Fork` | 409 | Version conflict |
| `error.TooLarge` | 413 | Payload too large |
| `error.Internal` | 500 | Server error |
| `error.NetworkUnreachable` | 502 | Network unreachable |

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```zig
const one = try client.dataPutPublic("first file", .auto);    // pays
defer one.deinit(allocator);
const two = try client.dataPutPublic("second file", .auto);   // pays
defer two.deinit(allocator);

const built = try client.buildManifest(&.{                     // free
    .{ .path = "notes/one.txt", .address = one.address },
    .{ .path = "notes/two.txt", .address = two.address },
}, .{ .name = "example" });
defer built.deinit(allocator);
// built.link is null when over 1,500 bytes: share built.manifest instead

const decoded = try client.decodeManifestLink(built.link.?, true);   // free
defer decoded.deinit(allocator);
for (decoded.entries) |entry| {
    std.debug.print("{s} {s} {?d}\n", .{ entry.effective_name, entry.kind, entry.exact_size });
}
```

`decodeManifest(bytes, resolve)` takes raw `.ant` bytes. Set `.data_map` instead of `.address` for an embedded entry; `BuildManifestOptions` has `embed_roots` (default `true`). Results own their memory: call `deinit(allocator)`.

Runnable example: `antd-zig/examples/10-manifests.zig`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-zig
ANTD_BASE_URL=http://localhost:8082 zig build run-10-manifests
```

## Examples

```bash
cd antd-zig/examples

zig build run -- 1      # Connect
zig build run -- 2      # Public data
zig build run -- 3      # Chunks
zig build run -- 4      # Files
zig build run -- 6      # Private data
zig build run -- all    # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l zig
ant dev example all -l zig
```
