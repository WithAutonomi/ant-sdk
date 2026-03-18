const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Create a graph entry
    std.debug.print("Creating graph entry...\n", .{});

    const empty_parents = [_][]const u8{};
    const empty_descendants = [_]antd.GraphDescendant{};

    const put_result = try client.graphEntryPut(
        "my_secret_key_hex",
        &empty_parents,
        "content_hash_hex",
        &empty_descendants,
    );
    defer put_result.deinit(allocator);

    std.debug.print("Graph entry created at: {s}\n", .{put_result.address});
    std.debug.print("Cost: {s} atto\n", .{put_result.cost});

    // Retrieve the graph entry
    const entry = try client.graphEntryGet(put_result.address);
    defer entry.deinit(allocator);

    std.debug.print("Owner: {s}\n", .{entry.owner});
    std.debug.print("Content: {s}\n", .{entry.content});
    std.debug.print("Parents: {d}\n", .{entry.parents.len});
    std.debug.print("Descendants: {d}\n", .{entry.descendants.len});

    // Check existence
    const exists = try client.graphEntryExists(put_result.address);
    std.debug.print("Exists: {}\n", .{exists});

    // Estimate cost
    const cost = try client.graphEntryCost("my_public_key_hex");
    defer allocator.free(cost);

    std.debug.print("Estimated graph entry cost: {s} atto\n", .{cost});
}
