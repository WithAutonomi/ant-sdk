const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = antd.Client.init(allocator, antd.default_base_url);
    defer client.deinit();

    const tmp = "/tmp/antd-zig-04-files";
    std.fs.deleteTreeAbsolute(tmp) catch {};
    try std.fs.makeDirAbsolute(tmp);
    defer std.fs.deleteTreeAbsolute(tmp) catch {};

    const file_content = "Hello from a file on Autonomi!";
    const dir_file_content = "File inside an uploaded directory.";

    const src_file = tmp ++ "/hello.txt";
    {
        const f = try std.fs.createFileAbsolute(src_file, .{});
        defer f.close();
        try f.writeAll(file_content);
    }

    const src_dir = tmp ++ "/mydir";
    try std.fs.makeDirAbsolute(src_dir);
    {
        const f = try std.fs.createFileAbsolute(src_dir ++ "/file_in_dir.txt", .{});
        defer f.close();
        try f.writeAll(dir_file_content);
    }

    const est = try client.fileCost(src_file, true);
    defer est.deinit(allocator);
    std.debug.print(
        "Estimate: {d} bytes in {d} chunks, storage {s} atto, gas {s} wei, mode {s}\n",
        .{ est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode },
    );

    const upload_result = try client.fileUploadPublic(src_file, null);
    defer upload_result.deinit(allocator);

    std.debug.print("File uploaded at: {s}\n", .{upload_result.address});
    std.debug.print("Storage cost: {s} atto, gas: {s} wei\n", .{ upload_result.storage_cost_atto, upload_result.gas_cost_wei });
    std.debug.print("Chunks stored: {d}, payment mode: {s}\n", .{ upload_result.chunks_stored, upload_result.payment_mode_used });

    const dst_file = tmp ++ "/hello.txt.downloaded";
    try client.fileDownloadPublic(upload_result.address, dst_file);
    std.debug.print("File downloaded to {s}\n", .{dst_file});

    {
        const got = try std.fs.cwd().readFileAlloc(allocator, dst_file, 1 << 20);
        defer allocator.free(got);
        if (!std.mem.eql(u8, got, file_content)) {
            std.debug.print("round-trip mismatch on hello.txt\n", .{});
            return error.RoundTripMismatch;
        }
    }

    const dir_result = try client.dirUploadPublic(src_dir, null);
    defer dir_result.deinit(allocator);

    std.debug.print("Directory uploaded at: {s}\n", .{dir_result.address});
    std.debug.print("Storage cost: {s} atto, gas: {s} wei\n", .{ dir_result.storage_cost_atto, dir_result.gas_cost_wei });
    std.debug.print("Chunks stored: {d}, payment mode: {s}\n", .{ dir_result.chunks_stored, dir_result.payment_mode_used });

    const dst_dir = tmp ++ "/mydir_copy";
    try client.dirDownloadPublic(dir_result.address, dst_dir);
    std.debug.print("Directory downloaded to {s}\n", .{dst_dir});

    {
        const got = try std.fs.cwd().readFileAlloc(allocator, dst_dir ++ "/file_in_dir.txt", 1 << 20);
        defer allocator.free(got);
        if (!std.mem.eql(u8, got, dir_file_content)) {
            std.debug.print("directory round-trip mismatch on file_in_dir.txt\n", .{});
            return error.RoundTripMismatch;
        }
    }

    std.debug.print("File and directory upload/download OK!\n", .{});
}
