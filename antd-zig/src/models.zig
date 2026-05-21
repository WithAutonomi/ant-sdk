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

/// Payment-batching strategy for uploads.
///
/// - `.auto`   — server picks (merkle for 64+ chunks, single otherwise).
/// - `.merkle` — force merkle-batch (saves gas, min 2 chunks).
/// - `.single` — force per-chunk payments (works for any chunk count).
pub const PaymentMode = enum {
    auto,
    merkle,
    single,

    /// The wire-format string the daemon accepts.
    pub fn wire(self: PaymentMode) []const u8 {
        return switch (self) {
            .auto => "auto",
            .merkle => "merkle",
            .single => "single",
        };
    }
};

/// Result of `chunkPut`. The DataMap concept doesn't apply at chunk level.
pub const PutResult = struct {
    cost: []const u8,
    address: []const u8,

    pub fn deinit(self: PutResult, allocator: Allocator) void {
        allocator.free(self.cost);
        allocator.free(self.address);
    }
};

/// Result of a private data put. The DataMap is returned to the caller; it
/// is NOT stored on-network.
pub const DataPutResult = struct {
    data_map: []const u8,
    chunks_stored: u64 = 0,
    payment_mode_used: []const u8 = "",

    pub fn deinit(self: DataPutResult, allocator: Allocator) void {
        allocator.free(self.data_map);
        allocator.free(self.payment_mode_used);
    }
};

/// Result of a public data put. The DataMap is stored on-network as an extra
/// chunk; `address` is the shareable retrieval handle.
pub const DataPutPublicResult = struct {
    address: []const u8,
    chunks_stored: u64 = 0,
    payment_mode_used: []const u8 = "",

    pub fn deinit(self: DataPutPublicResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.payment_mode_used);
    }
};

/// Result of a private file upload. The DataMap is returned to the caller;
/// it is NOT stored on-network.
pub const FilePutResult = struct {
    data_map: []const u8,
    storage_cost_atto: []const u8,
    gas_cost_wei: []const u8,
    chunks_stored: u64,
    payment_mode_used: []const u8,

    pub fn deinit(self: FilePutResult, allocator: Allocator) void {
        allocator.free(self.data_map);
        allocator.free(self.storage_cost_atto);
        allocator.free(self.gas_cost_wei);
        allocator.free(self.payment_mode_used);
    }
};

/// Result of a public file upload. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
pub const FilePutPublicResult = struct {
    address: []const u8,
    storage_cost_atto: []const u8,
    gas_cost_wei: []const u8,
    chunks_stored: u64,
    payment_mode_used: []const u8,

    pub fn deinit(self: FilePutPublicResult, allocator: Allocator) void {
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

/// A single payment entry returned by a prepare-upload (wave-batch) response.
/// One per non-zero quote in the close group; the external signer feeds these
/// directly into `payForQuotes()`.
pub const PaymentInfo = struct {
    quote_hash: []const u8,
    rewards_address: []const u8,
    amount: []const u8,

    pub fn deinit(self: PaymentInfo, allocator: Allocator) void {
        allocator.free(self.quote_hash);
        allocator.free(self.rewards_address);
        allocator.free(self.amount);
    }
};

/// Result of `POST /v1/chunks/prepare` — the single-chunk external-signer
/// prepare endpoint (antd >= 0.7.0).
pub const PrepareChunkResult = struct {
    address: []const u8,
    already_stored: bool,

    upload_id: []const u8 = "",
    payment_type: []const u8 = "",
    payments: []PaymentInfo = &.{},
    total_amount: []const u8 = "",
    payment_vault_address: []const u8 = "",
    payment_token_address: []const u8 = "",
    rpc_url: []const u8 = "",

    pub fn deinit(self: PrepareChunkResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.upload_id);
        allocator.free(self.payment_type);
        for (self.payments) |p| p.deinit(allocator);
        allocator.free(self.payments);
        allocator.free(self.total_amount);
        allocator.free(self.payment_vault_address);
        allocator.free(self.payment_token_address);
        allocator.free(self.rpc_url);
    }
};

/// Result of `POST /v1/upload/finalize` — the two-phase upload's phase-2
/// response.
pub const FinalizeUploadResult = struct {
    data_map: []const u8,
    address: []const u8 = "",
    data_map_address: []const u8 = "",
    chunks_stored: u64 = 0,

    pub fn deinit(self: FinalizeUploadResult, allocator: Allocator) void {
        allocator.free(self.data_map);
        allocator.free(self.address);
        allocator.free(self.data_map_address);
    }
};
