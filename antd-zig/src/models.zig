const std = @import("std");
const Allocator = std.mem.Allocator;

/// Result of a health check against the antd daemon.
pub const HealthStatus = struct {
    ok: bool,
    network: []const u8,

    pub fn deinit(self: HealthStatus, allocator: Allocator) void {
        allocator.free(self.network);
    }
};

/// Result of a put/create operation containing cost and address.
pub const PutResult = struct {
    cost: []const u8,
    address: []const u8,

    pub fn deinit(self: PutResult, allocator: Allocator) void {
        allocator.free(self.cost);
        allocator.free(self.address);
    }
};

/// A descendant entry in a graph node.
pub const GraphDescendant = struct {
    public_key: []const u8,
    content: []const u8,

    pub fn deinit(self: GraphDescendant, allocator: Allocator) void {
        allocator.free(self.public_key);
        allocator.free(self.content);
    }
};

/// A DAG node retrieved from the network.
pub const GraphEntry = struct {
    owner: []const u8,
    parents: []const []const u8,
    content: []const u8,
    descendants: []const GraphDescendant,

    pub fn deinit(self: GraphEntry, allocator: Allocator) void {
        allocator.free(self.owner);
        for (self.parents) |p| {
            allocator.free(p);
        }
        allocator.free(self.parents);
        allocator.free(self.content);
        for (self.descendants) |d| {
            d.deinit(allocator);
        }
        allocator.free(self.descendants);
    }
};

/// A single entry in a file archive.
pub const ArchiveEntry = struct {
    path: []const u8,
    address: []const u8,
    created: i64,
    modified: i64,
    size: i64,

    pub fn deinit(self: ArchiveEntry, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.address);
    }
};

/// A collection of archive entries.
pub const Archive = struct {
    entries: []const ArchiveEntry,

    pub fn deinit(self: Archive, allocator: Allocator) void {
        for (self.entries) |e| {
            e.deinit(allocator);
        }
        allocator.free(self.entries);
    }
};
