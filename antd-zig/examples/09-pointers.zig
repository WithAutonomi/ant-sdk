// Example 09: Pointers, owner-signed mutable references.
//
// Uploads two small pieces of public data, points a pointer at the first,
// updates it to the second, reads it back and asks the close group where it
// stands. The daemon holds the owner key (`antd --pointer-keys`); the example
// names the pointer by its address.
//
// Every pointer write is paid by the daemon wallet, and every attempt pays
// again: the SDK never retries a create, update or transfer, and neither
// should you.
//
// Environment:
//   ANTD_POINTER_OWNER  address of a pointer the daemon holds the key for
//                       (required; see GET /v1/pointers/keys)
//   ANTD_BASE_URL       daemon REST URL (default http://localhost:8082)

const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const owner = std.process.getEnvVarOwned(allocator, "ANTD_POINTER_OWNER") catch {
        std.debug.print("Set ANTD_POINTER_OWNER to a pointer address the daemon holds the key for.\n", .{});
        return error.MissingPointerOwner;
    };
    defer allocator.free(owner);
    const base_url = std.process.getEnvVarOwned(allocator, "ANTD_BASE_URL") catch
        try allocator.dupe(u8, antd.default_base_url);
    defer allocator.free(base_url);

    var client = antd.Client.init(allocator, base_url);
    defer client.deinit();

    // The daemon can only write pointers it holds the owner key for.
    {
        const keys = try client.pointerKeys();
        defer keys.deinit(allocator);
        if (!keys.contains(owner)) {
            std.debug.print("The daemon holds no key for {s} ({d} keys loaded).\n", .{ owner, keys.addresses.len });
            return error.UnknownPointerOwner;
        }
    }

    // 1. Two small pieces of public data to point at.
    const first = try client.dataPutPublic("Pointer target, version one", .auto);
    defer first.deinit(allocator);
    const second = try client.dataPutPublic("Pointer target, version two", .auto);
    defer second.deinit(allocator);
    std.debug.print("First target:  {s}\n", .{first.address});
    std.debug.print("Second target: {s}\n", .{second.address});

    // 2. Create the pointer at the first target. A pointer that already
    // exists (from an earlier run) is updated instead.
    if (client.pointerCreate(owner, first.address, .chunk)) |created| {
        defer created.deinit(allocator);
        std.debug.print("Created pointer {s} at counter {d}\n", .{ created.address, created.counter });
    } else |err| switch (err) {
        error.AlreadyExists => {
            const moved = try client.pointerUpdate(owner, first.address, .chunk);
            defer moved.deinit(allocator);
            std.debug.print("Pointer {s} existed; pointed it at the first target (counter {d})\n", .{ moved.address, moved.counter });
        },
        else => return reportError(&client, err),
    }

    // 3. Point it at the second target.
    const updated = client.pointerUpdate(owner, second.address, .chunk) catch |err|
        return reportError(&client, err);
    defer updated.deinit(allocator);
    std.debug.print("Updated pointer to the second target (counter {d})\n", .{updated.counter});

    // 4. Read it back, then follow it to its target and the bytes there.
    const record = try client.pointerGet(owner);
    defer record.deinit(allocator);
    std.debug.print("Pointer: counter {d}, kind {s}, target {s}, final {}\n", .{
        record.counter, record.kind, record.target, record.is_final,
    });

    const resolved = try client.pointerResolve(owner);
    defer resolved.deinit(allocator);
    const data = try client.dataGetPublic(resolved.target);
    defer allocator.free(data);
    std.debug.print("Resolves to {s}: \"{s}\"\n", .{ resolved.target, data });

    // 5. Where the close group says it stands.
    const finality = try client.pointerFinality(owner);
    defer finality.deinit(allocator);
    std.debug.print("Finality: {s} ({d}/{d} peers answered)", .{
        finality.status.wire(), finality.answered, finality.group,
    });
    if (finality.counter) |counter| std.debug.print(", counter {d}", .{counter});
    std.debug.print("\n", .{});
}

fn reportError(client: *antd.Client, err: anyerror) anyerror {
    std.debug.print("Pointer write failed: {s}\n", .{@errorName(err)});
    if (client.getLastError()) |info| {
        std.debug.print("  HTTP {d}: {s}\n", .{ info.status_code, info.message });
    }
    return err;
}
