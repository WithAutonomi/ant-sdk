const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    // Upload a file
    const file_path = "/tmp/example.txt";
    std.debug.print("Uploading file: {s}\n", .{file_path});

    const upload_result = try client.fileUploadPublic(file_path, null);
    defer upload_result.deinit(allocator);

    std.debug.print("Uploaded at: {s}\n", .{upload_result.address});
    std.debug.print("Storage cost: {s} atto, gas: {s} wei\n", .{ upload_result.storage_cost_atto, upload_result.gas_cost_wei });
    std.debug.print("Chunks stored: {d}, payment mode: {s}\n", .{ upload_result.chunks_stored, upload_result.payment_mode_used });

    // Download the file
    const dest_path = "/tmp/downloaded.txt";
    std.debug.print("Downloading to: {s}\n", .{dest_path});
    try client.fileDownloadPublic(upload_result.address, dest_path);
    std.debug.print("Download complete\n", .{});

    // Estimate file cost
    const cost = try client.fileCost(file_path, true, false);
    defer allocator.free(cost);

    std.debug.print("Estimated file cost: {s} atto\n", .{cost});

    // Upload a directory
    const dir_path = "/tmp/example-dir";
    std.debug.print("Uploading directory: {s}\n", .{dir_path});

    const dir_result = try client.dirUploadPublic(dir_path, null);
    defer dir_result.deinit(allocator);

    std.debug.print("Directory uploaded at: {s}\n", .{dir_result.address});
    std.debug.print("Storage cost: {s} atto, gas: {s} wei\n", .{ dir_result.storage_cost_atto, dir_result.gas_cost_wei });
    std.debug.print("Chunks stored: {d}, payment mode: {s}\n", .{ dir_result.chunks_stored, dir_result.payment_mode_used });
}
