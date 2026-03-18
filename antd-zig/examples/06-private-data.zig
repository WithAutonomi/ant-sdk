const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Store private (encrypted) data
    const secret_message = "This is private data";
    std.debug.print("Storing private data...\n", .{});

    const put_result = try client.dataPutPrivate(secret_message);
    defer put_result.deinit(allocator);

    std.debug.print("Data map: {s}\n", .{put_result.address});
    std.debug.print("Cost: {s} atto\n", .{put_result.cost});

    // Retrieve private data using the data map
    std.debug.print("Retrieving private data...\n", .{});

    const data = try client.dataGetPrivate(put_result.address);
    defer allocator.free(data);

    std.debug.print("Retrieved: {s}\n", .{data});
}
