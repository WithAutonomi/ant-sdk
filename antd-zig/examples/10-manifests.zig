// Example 10: Manifests, ADR-0006 `.ant` files and `ant://` links.
//
// Uploads two small pieces of public data, builds a manifest that lists them
// under notes/, prints its link and entries, then decodes the link with
// `resolve` to read each entry's exact size back from the network.
//
// The two uploads are paid by the daemon wallet. Building and decoding the
// manifest uploads and pays for nothing.
//
// Environment:
//   ANTD_BASE_URL  daemon REST URL (default http://localhost:8082)

const std = @import("std");
const antd = @import("antd");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const base_url = std.process.getEnvVarOwned(allocator, "ANTD_BASE_URL") catch
        try allocator.dupe(u8, antd.default_base_url);
    defer allocator.free(base_url);

    var client = antd.Client.init(allocator, base_url);
    defer client.deinit();

    // 1. Two small pieces of public data for the manifest to list.
    const one = client.dataPutPublic("The first note in the manifest.", .auto) catch |err|
        return reportError(&client, "Upload", err);
    defer one.deinit(allocator);
    const two = client.dataPutPublic("The second note, a little longer than the first.", .auto) catch |err|
        return reportError(&client, "Upload", err);
    defer two.deinit(allocator);
    std.debug.print("Uploaded {s}\n", .{one.address});
    std.debug.print("Uploaded {s}\n", .{two.address});

    // 2. Build the manifest. Nothing is uploaded or paid for.
    const built = client.buildManifest(&.{
        .{ .path = "notes/one.txt", .address = one.address },
        .{ .path = "notes/two.txt", .address = two.address },
    }, .{ .name = "example" }) catch |err| return reportError(&client, "Build", err);
    defer built.deinit(allocator);

    std.debug.print("Manifest: {d} bytes\n", .{built.manifest.len});
    std.debug.print("Link: {s}\n", .{built.link orelse "(too long for a link; share the .ant bytes instead)"});
    for (built.entries) |entry| {
        std.debug.print("  {s}  {s}\n", .{ entry.effective_name, entry.content_address });
    }

    // 3. Decode it with resolve, which reads each entry's exact size from the
    // network. From the link when there is one, otherwise from the bytes.
    const decoded = (if (built.link) |link|
        client.decodeManifestLink(link, true)
    else
        client.decodeManifest(built.manifest, true)) catch |err| return reportError(&client, "Decode", err);
    defer decoded.deinit(allocator);

    std.debug.print("Decoded {s} \"{s}\":\n", .{ decoded.source, decoded.name orelse "" });
    for (decoded.entries) |entry| {
        if (entry.error_message) |msg| {
            std.debug.print("  {s}: not resolved: {s}\n", .{ entry.effective_name, msg });
        } else if (entry.exact_size) |size| {
            std.debug.print("  {s}: exact_size {d}\n", .{ entry.effective_name, size });
        } else {
            std.debug.print("  {s}: exact_size unknown\n", .{entry.effective_name});
        }
    }
}

fn reportError(client: *antd.Client, what: []const u8, err: anyerror) anyerror {
    std.debug.print("{s} failed: {s}\n", .{ what, @errorName(err) });
    if (client.getLastError()) |info| {
        std.debug.print("  HTTP {d}: {s}\n", .{ info.status_code, info.message });
    }
    return err;
}
