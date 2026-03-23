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
        .base_url = "http://localhost:8080",
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
const result = try client.dataPutPublic("Hello, Autonomi!");
defer result.deinit(allocator);
std.debug.print("Address: {s}\n", .{result.address});
std.debug.print("Cost: {d} atto tokens\n", .{result.cost});

// Retrieve
const data = try client.dataGetPublic(result.address);
defer allocator.free(data);
std.debug.print("{s}\n", .{data}); // "Hello, Autonomi!"

// Cost estimation
const cost = try client.dataCost("some data");
std.debug.print("Would cost: {d} atto tokens\n", .{cost});
```

## Private Data

```zig
// Store (self-encrypting)
const result = try client.dataPutPrivate("secret message");
defer result.deinit(allocator);
const data_map = result.address; // Keep this secret!

// Retrieve (decrypt)
const data = try client.dataGetPrivate(data_map);
defer allocator.free(data);
std.debug.print("{s}\n", .{data});
```

## Files

```zig
// Upload a file
const result = try client.fileUploadPublic("/path/to/file.txt");
defer result.deinit(allocator);
std.debug.print("File address: {s}\n", .{result.address});

// Download a file
try client.fileDownloadPublic(result.address, "/path/to/output.txt");

// Upload a directory
const dir_result = try client.dirUploadPublic("/path/to/directory");
defer dir_result.deinit(allocator);

// Download a directory
try client.dirDownloadPublic(dir_result.address, "/path/to/output_dir");

// Cost estimation
const cost = try client.fileCost("/path/to/file.txt");
```

## Graph Entries (DAG Nodes)

```zig
var prng = std.Random.DefaultPrng.init(blk: {
    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
    break :blk seed;
});
const random = prng.random();

var key_buf: [32]u8 = undefined;
random.bytes(&key_buf);
const key = std.fmt.bytesToHex(key_buf, .lower);

var content_buf: [32]u8 = undefined;
random.bytes(&content_buf);
const content = std.fmt.bytesToHex(content_buf, .lower);

// Create root node
const result = try client.graphEntryPut(&key, &.{}, &content, &.{});
defer result.deinit(allocator);
std.debug.print("Graph entry: {s}\n", .{result.address});

// Read
const entry = try client.graphEntryGet(result.address);
defer entry.deinit(allocator);
std.debug.print("Owner: {s}\n", .{entry.owner});
std.debug.print("Content: {s}\n", .{entry.content});

// Check existence
const exists = try client.graphEntryExists(result.address);
std.debug.print("Exists: {}\n", .{exists});
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

## Examples

```bash
cd antd-zig/examples

zig build run -- 1      # Connect
zig build run -- 2      # Public data
zig build run -- 3      # Chunks
zig build run -- 4      # Files
zig build run -- 5      # Graph entries
zig build run -- 6      # Private data
zig build run -- all    # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l zig
ant dev example all -l zig
```
