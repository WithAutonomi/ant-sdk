const std = @import("std");
const Allocator = std.mem.Allocator;

/// Result of a health check against the antd daemon.
///
/// The diagnostic fields (version, evm_network, uptime_seconds, build_commit,
/// payment_token_address, payment_vault_address) were added in antd 0.4.0.
/// They default to empty / 0 so the struct stays usable when talking to a
/// pre-0.4.0 daemon that doesn't report them.
pub const HealthStatus = struct {
    ok: bool,
    network: []const u8,
    version: []const u8 = "",
    evm_network: []const u8 = "",
    uptime_seconds: u64 = 0,
    build_commit: []const u8 = "",
    payment_token_address: []const u8 = "",
    payment_vault_address: []const u8 = "",

    pub fn deinit(self: HealthStatus, allocator: Allocator) void {
        allocator.free(self.network);
        allocator.free(self.version);
        allocator.free(self.evm_network);
        allocator.free(self.build_commit);
        allocator.free(self.payment_token_address);
        allocator.free(self.payment_vault_address);
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

/// Pre-upload cost breakdown returned by `dataCost` and `fileCost`.
///
/// The server samples up to 5 chunk addresses and extrapolates the storage
/// cost. Gas is an advisory heuristic, not a live gas-oracle query.
pub const UploadCostEstimate = struct {
    cost: []const u8,
    file_size: u64,
    chunk_count: u32,
    estimated_gas_cost_wei: []const u8,
    payment_mode: []const u8,

    pub fn deinit(self: UploadCostEstimate, allocator: Allocator) void {
        allocator.free(self.cost);
        allocator.free(self.estimated_gas_cost_wei);
        allocator.free(self.payment_mode);
    }
};

