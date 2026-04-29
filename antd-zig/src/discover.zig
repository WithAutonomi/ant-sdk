const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const port_file_name = "daemon.port";
const data_dir_name = "ant";
const sdk_subdir_name = "sdk";

/// Reads the daemon.port file written by antd on startup and returns
/// the REST base URL (e.g. "http://127.0.0.1:8082").
/// Returns null if the port file is not found or unreadable.
/// Caller owns the returned memory.
pub fn discoverDaemonUrl(allocator: Allocator) ?[]const u8 {
    const ports = readPortFile(allocator) orelse return null;
    if (ports.rest == 0) return null;
    return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{ports.rest}) catch null;
}

/// Reads the daemon.port file written by antd on startup and returns
/// the gRPC target (e.g. "127.0.0.1:50051").
/// Returns null if the port file is not found or has no gRPC line.
/// Caller owns the returned memory.
pub fn discoverGrpcTarget(allocator: Allocator) ?[]const u8 {
    const ports = readPortFile(allocator) orelse return null;
    if (ports.grpc == 0) return null;
    return std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{ports.grpc}) catch null;
}

const Ports = struct {
    rest: u16,
    grpc: u16,
};

fn readPortFile(allocator: Allocator) ?Ports {
    const dir = dataDir(allocator) orelse return null;
    defer allocator.free(dir);

    const path = std.fs.path.join(allocator, &.{ dir, port_file_name }) catch return null;
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    var buf: [256]u8 = undefined;
    const n = file.readAll(&buf) catch return null;
    if (n == 0) return null;

    const contents = std.mem.trimRight(u8, buf[0..n], &.{ ' ', '\t', '\r', '\n' });

    var rest: u16 = 0;
    var grpc: u16 = 0;
    var pid_line: ?[]const u8 = null;

    var line_iter = std.mem.splitSequence(u8, contents, "\n");
    if (line_iter.next()) |first_line| {
        rest = parsePort(first_line);
    }
    if (line_iter.next()) |second_line| {
        grpc = parsePort(second_line);
    }
    if (line_iter.next()) |third_line| {
        pid_line = third_line;
    }

    // Line 3: PID of the daemon process (optional stale-detection)
    if (pid_line) |pl| {
        const trimmed = std.mem.trim(u8, pl, &.{ ' ', '\t', '\r' });
        if (trimmed.len > 0) {
            const pid = std.fmt.parseInt(i32, trimmed, 10) catch 0;
            if (pid > 0 and !isProcessAlive(pid)) {
                return null;
            }
        }
    }

    return .{ .rest = rest, .grpc = grpc };
}

/// Check if a process with the given PID is alive.
/// On Linux, checks if /proc/{pid} exists.
/// On other platforms (Windows, macOS), trusts the port file.
fn isProcessAlive(pid: i32) bool {
    if (builtin.os.tag == .linux) {
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "/proc/{d}", .{pid}) catch return true;
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    }
    // On Windows, macOS, and other platforms, trust the port file
    return true;
}

fn parsePort(s: []const u8) u16 {
    const trimmed = std.mem.trim(u8, s, &.{ ' ', '\t', '\r' });
    return std.fmt.parseInt(u16, trimmed, 10) catch 0;
}

fn dataDir(allocator: Allocator) ?[]const u8 {
    switch (builtin.os.tag) {
        .windows => {
            const appdata = std.process.getEnvVarOwned(allocator, "APPDATA") catch return null;
            defer allocator.free(appdata);
            if (appdata.len == 0) return null;
            return std.fs.path.join(allocator, &.{ appdata, data_dir_name, sdk_subdir_name }) catch null;
        },
        .macos => {
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
            defer allocator.free(home);
            if (home.len == 0) return null;
            return std.fs.path.join(allocator, &.{ home, "Library", "Application Support", data_dir_name, sdk_subdir_name }) catch null;
        },
        else => {
            // Linux and other Unix-like systems
            if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg| {
                defer allocator.free(xdg);
                if (xdg.len > 0) {
                    return std.fs.path.join(allocator, &.{ xdg, data_dir_name, sdk_subdir_name }) catch null;
                }
            } else |_| {}
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
            defer allocator.free(home);
            if (home.len == 0) return null;
            return std.fs.path.join(allocator, &.{ home, ".local", "share", data_dir_name, sdk_subdir_name }) catch null;
        },
    }
}
