const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Store a chunk
    const chunk_data = "raw chunk content";
    std.debug.print("Storing chunk...\n", .{});

    const put_result = try client.chunkPut(chunk_data);
    defer put_result.deinit(allocator);

    std.debug.print("Chunk stored at: {s}\n", .{put_result.address});
    std.debug.print("Cost: {s} atto\n", .{put_result.cost});

    // Retrieve the chunk
    const data = try client.chunkGet(put_result.address);
    defer allocator.free(data);

    std.debug.print("Retrieved chunk: {s}\n", .{data});
}
