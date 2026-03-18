const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    const status = client.health() catch |err| {
        std.debug.print("Failed to connect to antd daemon: {}\n", .{err});
        if (client.getLastError()) |info| {
            std.debug.print("  Status: {d}, Message: {s}\n", .{ info.status_code, info.message });
        }
        return err;
    };
    defer status.deinit(allocator);

    std.debug.print("Connected to antd daemon\n", .{});
    std.debug.print("  OK: {}\n", .{status.ok});
    std.debug.print("  Network: {s}\n", .{status.network});
}
