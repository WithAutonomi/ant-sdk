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

/// Result of a public file or directory upload.
pub const FileUploadResult = struct {
    address: []const u8,
    storage_cost_atto: []const u8,
    gas_cost_wei: []const u8,
    chunks_stored: u64,
    payment_mode_used: []const u8,

    pub fn deinit(self: FileUploadResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.storage_cost_atto);
        allocator.free(self.gas_cost_wei);
        allocator.free(self.payment_mode_used);
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

