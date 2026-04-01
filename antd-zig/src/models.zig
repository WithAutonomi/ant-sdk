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

/// Result of a wallet address query.
pub const WalletAddress = struct {
    address: []const u8,

    pub fn deinit(self: WalletAddress, allocator: Allocator) void {
        allocator.free(self.address);
    }
};

/// Result of a wallet balance query.
pub const WalletBalance = struct {
    balance: []const u8,
    gas_balance: []const u8,

    pub fn deinit(self: WalletBalance, allocator: Allocator) void {
        allocator.free(self.balance);
        allocator.free(self.gas_balance);
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
