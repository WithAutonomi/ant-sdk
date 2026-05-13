const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Store public data
    const message = "Hello, Autonomi!";
    std.debug.print("Storing public data: {s}\n", .{message});

    const put_result = try client.dataPutPublic(message, null);
    defer put_result.deinit(allocator);

    std.debug.print("Stored at address: {s}\n", .{put_result.address});
    std.debug.print("Cost: {s} atto\n", .{put_result.cost});

    // Retrieve public data
    const data = try client.dataGetPublic(put_result.address);
    defer allocator.free(data);

    std.debug.print("Retrieved: {s}\n", .{data});

    // Estimate storage cost
    const est = try client.dataCost("some data to estimate");
    defer est.deinit(allocator);

    std.debug.print(
        "Estimate: {d} bytes in {d} chunks, storage {s} atto, gas {s} wei, mode {s}\n",
        .{ est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode },
    );
}
