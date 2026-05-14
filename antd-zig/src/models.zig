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
///
/// When [already_stored] is true, the chunk is already on-network; only
/// `address` and `already_stored` are populated and no finalize call is
/// needed. Otherwise the wave-batch payment fields describe what the external
/// signer must submit before calling `finalizeChunkUpload`.
pub const PrepareChunkResult = struct {
    /// Content-addressed BLAKE3 of the chunk bytes (hex, 64 chars). Always set.
    address: []const u8,
    /// True if the chunk is already stored on the network and no payment is needed.
    already_stored: bool,

    // Fields below are only populated when already_stored == false.

    upload_id: []const u8 = "",
    /// Always "wave_batch" for single-chunk publishes.
    payment_type: []const u8 = "",
    /// Per-quote payment entries for payForQuotes(). Caller-owned.
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
///
/// - `data_map` is the hex-encoded serialised DataMap (always returned).
/// - `address` is the legacy field set when `store_data_map=true` was passed
///   (paid by the daemon's wallet). Empty otherwise.
/// - `data_map_address` is set when the upload was prepared with
///   visibility="public" — the DataMap chunk was bundled into the same
///   external-signer payment batch and stored on-network. This is the
///   shareable retrieval handle for public uploads. Empty for private
///   uploads (or against pre-0.6.1 daemons).
/// - `chunks_stored` is the number of chunks stored on the network.
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

