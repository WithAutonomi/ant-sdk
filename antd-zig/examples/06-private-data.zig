const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Store private (encrypted) data. The DataMap is returned to the caller;
    // it is NOT stored on-network.
    const secret_message = "This is private data";
    std.debug.print("Storing private data...\n", .{});

    const put_result = try client.dataPut(secret_message, .auto);
    defer put_result.deinit(allocator);

    std.debug.print("Data map: {s}\n", .{put_result.data_map});
    std.debug.print("Chunks: {d}, mode: {s}\n", .{ put_result.chunks_stored, put_result.payment_mode_used });

    // Retrieve private data using the caller-held DataMap.
    std.debug.print("Retrieving private data...\n", .{});

    const data = try client.dataGet(put_result.data_map);
    defer allocator.free(data);

    std.debug.print("Retrieved: {s}\n", .{data});
}
