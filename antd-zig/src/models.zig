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

    /// The plaintext's SHA-256 (lowercase hex, 64 characters). `null` when
    /// the daemon sent none (antd before 0.17.0) or sent an empty string.
    sha256: ?[]const u8 = null,

    pub fn deinit(self: DataPutResult, allocator: Allocator) void {
        allocator.free(self.data_map);
        allocator.free(self.payment_mode_used);
        if (self.sha256) |v| allocator.free(v);
    }
};

/// Result of a public data put. The DataMap is stored on-network as an extra
/// chunk; `address` is the shareable retrieval handle.
pub const DataPutPublicResult = struct {
    address: []const u8,
    chunks_stored: u64 = 0,
    payment_mode_used: []const u8 = "",

    /// The plaintext's SHA-256 (lowercase hex, 64 characters). `null` when
    /// the daemon sent none (antd before 0.17.0) or sent an empty string.
    sha256: ?[]const u8 = null,

    pub fn deinit(self: DataPutPublicResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.payment_mode_used);
        if (self.sha256) |v| allocator.free(v);
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

    /// The plaintext's SHA-256 (lowercase hex, 64 characters). `null` when
    /// the daemon sent none (antd before 0.17.0) or sent an empty string.
    sha256: ?[]const u8 = null,

    pub fn deinit(self: FilePutResult, allocator: Allocator) void {
        allocator.free(self.data_map);
        allocator.free(self.storage_cost_atto);
        allocator.free(self.gas_cost_wei);
        allocator.free(self.payment_mode_used);
        if (self.sha256) |v| allocator.free(v);
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

    /// The plaintext's SHA-256 (lowercase hex, 64 characters). `null` when
    /// the daemon sent none (antd before 0.17.0) or sent an empty string.
    sha256: ?[]const u8 = null,

    pub fn deinit(self: FilePutPublicResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.storage_cost_atto);
        allocator.free(self.gas_cost_wei);
        allocator.free(self.payment_mode_used);
        if (self.sha256) |v| allocator.free(v);
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

    /// The plaintext's SHA-256 (lowercase hex, 64 characters). `null` when
    /// the daemon sent none (antd before 0.17.0) or sent an empty string.
    sha256: ?[]const u8 = null,

    pub fn deinit(self: FinalizeUploadResult, allocator: Allocator) void {
        allocator.free(self.data_map);
        allocator.free(self.address);
        allocator.free(self.data_map_address);
        if (self.sha256) |v| allocator.free(v);
    }
};

/// One `payments[]` quote in full signed form, returned by a prepare call
/// asked for `include_signed_quotes`. Both blobs are opaque base64; only antd
/// (`/v1/verify/quotes`) parses them.
pub const SignedQuoteEntry = struct {
    /// Quote hash (hex with 0x prefix), matching the `payments[]` entry.
    quote_hash: []const u8,
    /// base64(msgpack-serialized signed PaymentQuote).
    quote: []const u8,
    /// base64(msgpack-serialized StorageCommitment) for a commitment-bound
    /// quote; `null` for a baseline quote.
    commitment_sidecar: ?[]const u8 = null,

    pub fn deinit(self: SignedQuoteEntry, allocator: Allocator) void {
        allocator.free(self.quote_hash);
        allocator.free(self.quote);
        if (self.commitment_sidecar) |s| allocator.free(s);
    }
};

// --- Pointers (ADR-0016 / ADR-0018 in ant-node) ---
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; its target (a chunk, such
// as a public file's data map, or another pointer) can be changed by the
// owner. antd signs with owner keys it loaded at startup (`--pointer-keys`),
// so a write names the pointer by its address (`owner`), never by a key.
//
// Every write pays, and every attempt pays again: do not retry a create,
// update, transfer or finalize automatically.
//
// Counters are `u64`. The daemon sends them as decimal strings, because a
// final state sits at 2^64 - 1 (`pointer_final_counter`), past what a JSON
// number keeps exactly in several languages.

/// The counter of a pointer's final state, after a transfer or a freeze:
/// nothing can replace it.
pub const pointer_final_counter: u64 = std.math.maxInt(u64);

/// The `kind_tag` this SDK reports when the daemon sent none, or one that is
/// not a `u8`. No known kind uses it.
pub const pointer_unknown_kind_tag: u8 = std.math.maxInt(u8);

/// What a pointer's target is.
pub const PointerKind = enum {
    /// An immutable chunk, such as a public file's data map.
    chunk,
    /// Another pointer: a forwarding the owner can still change. Use
    /// `pointerTransfer` to hand a pointer over for good.
    pointer,

    /// The wire-format string the daemon accepts.
    pub fn wire(self: PointerKind) []const u8 {
        return switch (self) {
            .chunk => "chunk",
            .pointer => "pointer",
        };
    }

    /// The kind a raw target tag names, if this SDK knows it (`0` chunk,
    /// `1` pointer).
    pub fn fromTag(tag: u8) ?PointerKind {
        return switch (tag) {
            0 => .chunk,
            1 => .pointer,
            else => null,
        };
    }
};

/// The target and kind of a create or update that `pointerPrepare` signs.
pub const PointerWriteOp = struct {
    /// Address to point at (hex).
    target: []const u8,
    kind: PointerKind = .chunk,
};

/// The recipient of a transfer that `pointerPrepare` signs.
pub const PointerTransferOp = struct {
    /// The recipient's pointer, which must already exist.
    recipient: []const u8,
};

/// The write `pointerPrepare` signs for an external signer to pay.
pub const PointerOp = union(enum) {
    /// Create the pointer at `target`. Refused if it already exists.
    create: PointerWriteOp,
    /// Point the pointer at `target`, creating it if it does not exist.
    update: PointerWriteOp,
    /// Hand the pointer over for good to the pointer at `recipient`, which
    /// must already exist. Irreversible once stored.
    transfer: PointerTransferOp,

    /// The wire-format `op` string the daemon accepts.
    pub fn wire(self: PointerOp) []const u8 {
        return @tagName(self);
    }
};

/// Options for `pointerPrepareWithOptions`.
pub const PointerPrepareOptions = struct {
    /// Ask the daemon for each quote in full signed form
    /// (`PointerPrepareResult.signed_quotes`), for an independent
    /// `/v1/verify/quotes` check before paying.
    include_signed_quotes: bool = false,
};

/// Compare two pointer addresses as the daemon does: an optional `0x` /
/// `0X` prefix and hex case do not matter. The daemon accepts a prefix but
/// always returns bare lowercase hex.
pub fn pointerAddressEql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(stripHexPrefix(a), stripHexPrefix(b));
}

fn stripHexPrefix(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) return s[2..];
    return s;
}

/// The pointers this daemon holds owner keys for (`pointerKeys`). Only these
/// can be written through it.
pub const PointerKeys = struct {
    /// Each pointer's address (bare hex), derived from its owner key.
    addresses: []const []const u8,

    pub fn deinit(self: PointerKeys, allocator: Allocator) void {
        for (self.addresses) |a| allocator.free(a);
        allocator.free(self.addresses);
    }

    /// Whether the daemon holds the key for `address`, compared with
    /// `pointerAddressEql`, so a `0x` prefix or upper-case hex still match.
    pub fn contains(self: PointerKeys, address: []const u8) bool {
        for (self.addresses) |a| {
            if (pointerAddressEql(a, address)) return true;
        }
        return false;
    }
};

/// The state a pointer write stored (`pointerCreate`, `pointerUpdate`).
pub const PointerWriteResult = struct {
    address: []const u8,
    /// The identifier the state was paid against (hex).
    state_id: []const u8,
    /// The state's counter. A final state sits at `pointer_final_counter`.
    counter: u64,

    pub fn deinit(self: PointerWriteResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.state_id);
    }
};

/// A pointer's current state, as the network serves it (`pointerGet`).
pub const PointerRecord = struct {
    address: []const u8,
    /// The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
    /// derived from it, so it is the proof of who owns the pointer.
    owner: []const u8,
    counter: u64,
    /// `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not
    /// know; `kind_tag` carries the raw value either way.
    kind: []const u8,
    kind_tag: u8,
    target: []const u8,
    state_id: []const u8,
    /// The state is at the final counter: the pointer was handed over or
    /// frozen, and nothing can replace it.
    is_final: bool,
    /// The pointer this one was handed over to, when its final state is a
    /// transfer; `null` otherwise.
    transferred_to: ?[]const u8 = null,

    pub fn deinit(self: PointerRecord, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.owner);
        allocator.free(self.kind);
        allocator.free(self.target);
        allocator.free(self.state_id);
        if (self.transferred_to) |t| allocator.free(t);
    }

    /// The target's kind, if this SDK knows its tag.
    pub fn targetKind(self: PointerRecord) ?PointerKind {
        return PointerKind.fromTag(self.kind_tag);
    }
};

/// Where a chain of pointers ends (`pointerResolve`).
pub const PointerTarget = struct {
    /// `"chunk"`, or `"unknown"` for a target kind the daemon does not know.
    kind: []const u8,
    kind_tag: u8,
    target: []const u8,

    pub fn deinit(self: PointerTarget, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.target);
    }

    /// The target's kind, if this SDK knows its tag.
    pub fn targetKind(self: PointerTarget) ?PointerKind {
        return PointerKind.fromTag(self.kind_tag);
    }
};

/// Where a pointer stands with respect to finality, as its whole close group
/// reports it.
pub const PointerFinalityStatus = union(enum) {
    /// No peer that answered holds a final state: the owner can still move
    /// the pointer. Rules a final state out only when every peer answered.
    open,
    /// One final state, not yet held by a majority: a transfer still
    /// spreading, or a write that fell short.
    settling,
    /// One final state held by a majority, but not every peer answered, so
    /// a rival could still be unseen. Ask again.
    unconfirmed,
    /// One final state held by a majority, every peer answered, no rival.
    /// The only status a recipient should rely on.
    final,
    /// The owner signed two or more different final states.
    forked,
    /// A status this SDK does not know (a newer daemon), as sent. Owned.
    unknown: []const u8,

    /// Parse the daemon's wire string. An unknown status is copied into the
    /// `unknown` arm, which `deinit` frees.
    pub fn fromWire(allocator: Allocator, s: []const u8) !PointerFinalityStatus {
        if (std.mem.eql(u8, s, "open")) return .open;
        if (std.mem.eql(u8, s, "settling")) return .settling;
        if (std.mem.eql(u8, s, "unconfirmed")) return .unconfirmed;
        if (std.mem.eql(u8, s, "final")) return .final;
        if (std.mem.eql(u8, s, "forked")) return .forked;
        return .{ .unknown = try allocator.dupe(u8, s) };
    }

    /// The wire string: the status name, or an unknown status as sent.
    pub fn wire(self: PointerFinalityStatus) []const u8 {
        return switch (self) {
            .unknown => |s| s,
            else => @tagName(self),
        };
    }

    pub fn deinit(self: PointerFinalityStatus, allocator: Allocator) void {
        switch (self) {
            .unknown => |s| allocator.free(s),
            else => {},
        }
    }
};

/// One final state, as a finality check reports it.
pub const PointerFinalState = struct {
    state_id: []const u8,
    kind: []const u8,
    kind_tag: u8,
    target: []const u8,
    /// How many peers of the close group hold it.
    holders: u32,
    transferred_to: ?[]const u8 = null,

    pub fn deinit(self: PointerFinalState, allocator: Allocator) void {
        allocator.free(self.state_id);
        allocator.free(self.kind);
        allocator.free(self.target);
        if (self.transferred_to) |t| allocator.free(t);
    }
};

/// The answer to a pointer finality check (`pointerFinality`). Check it
/// before relying on a transfer: only `status == .final` means the transfer
/// is beyond dispute.
pub const PointerFinality = struct {
    address: []const u8,
    /// Peers in the close group.
    group: u32,
    /// Peers that answered.
    answered: u32,
    status: PointerFinalityStatus,
    /// `.open` only: the counter a read would return, if any state is
    /// corroborated; `null` otherwise.
    counter: ?u64 = null,
    /// `.settling`, `.unconfirmed` and `.final`: the one final state seen.
    state: ?PointerFinalState = null,
    /// `.forked` only: every final state seen, most-held first.
    states: []const PointerFinalState = &.{},
    /// `.forked` only: the state a majority holds, which reads return.
    majority: ?PointerFinalState = null,
    /// The pointer this one was handed over to, once that is beyond dispute
    /// (`status == .final`); `null` otherwise.
    transferred_to: ?[]const u8 = null,

    pub fn deinit(self: PointerFinality, allocator: Allocator) void {
        allocator.free(self.address);
        self.status.deinit(allocator);
        if (self.state) |s| s.deinit(allocator);
        for (self.states) |s| s.deinit(allocator);
        allocator.free(self.states);
        if (self.majority) |m| m.deinit(allocator);
        if (self.transferred_to) |t| allocator.free(t);
    }

    /// One final state, held by a majority, with every peer answering and
    /// no rival seen.
    pub fn isFinal(self: PointerFinality) bool {
        return self.status == .final;
    }
};

/// Whose pointer decides what an address resolves to, after following every
/// transfer (`pointerController`).
pub const PointerController = struct {
    pointer: []const u8,
    /// Every pointer the address was handed over to, in order.
    transfers: []const []const u8,
    /// `pointer` is final without being handed over: nobody can move it.
    frozen: bool,

    pub fn deinit(self: PointerController, allocator: Allocator) void {
        allocator.free(self.pointer);
        for (self.transfers) |t| allocator.free(t);
        allocator.free(self.transfers);
    }
};

/// What a transfer stored, and where the close group says it stands
/// (`pointerTransfer`).
pub const PointerTransferResult = struct {
    address: []const u8,
    state_id: []const u8,
    /// The close group's view once the write landed. `null` when that check
    /// failed (see `finality_error`), which does not undo the transfer: it is
    /// stored and final. Ask again with `pointerFinality`.
    finality: ?PointerFinality = null,
    /// Why the finality check failed, when `finality` is `null`.
    finality_error: ?[]const u8 = null,

    pub fn deinit(self: PointerTransferResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.state_id);
        if (self.finality) |f| f.deinit(allocator);
        if (self.finality_error) |e| allocator.free(e);
    }
};

/// A pointer write signed by the daemon and quoted for an external signer
/// (`pointerPrepare`). Pay `payments` with `payForQuotes()`, then call
/// `pointerFinalize`. While it awaits payment, other writes to the pointer
/// return `error.Conflict` until it is finalized or expires (one hour).
pub const PointerPrepareResult = struct {
    upload_id: []const u8,
    /// `"create"`, `"update"` or `"transfer"`.
    op: []const u8,
    address: []const u8,
    state_id: []const u8,
    counter: u64,
    /// Always `"wave_batch"`: a pointer state is paid with one quote.
    payment_type: []const u8,
    payments: []const PaymentInfo,
    /// Atto tokens, decimal string.
    total_amount: []const u8,
    payment_vault_address: []const u8,
    payment_token_address: []const u8,
    rpc_url: []const u8,
    /// Populated when asked for with
    /// `PointerPrepareOptions.include_signed_quotes`; empty otherwise.
    signed_quotes: []const SignedQuoteEntry = &.{},

    pub fn deinit(self: PointerPrepareResult, allocator: Allocator) void {
        allocator.free(self.upload_id);
        allocator.free(self.op);
        allocator.free(self.address);
        allocator.free(self.state_id);
        allocator.free(self.payment_type);
        for (self.payments) |p| p.deinit(allocator);
        allocator.free(self.payments);
        allocator.free(self.total_amount);
        allocator.free(self.payment_vault_address);
        allocator.free(self.payment_token_address);
        allocator.free(self.rpc_url);
        for (self.signed_quotes) |q| q.deinit(allocator);
        allocator.free(self.signed_quotes);
    }
};

/// The state a pointer finalize stored (`pointerFinalize`).
pub const PointerFinalizeResult = struct {
    address: []const u8,
    state_id: []const u8,
    counter: u64,
    /// Transfers only: where the close group says the transfer stands.
    finality: ?PointerFinality = null,

    pub fn deinit(self: PointerFinalizeResult, allocator: Allocator) void {
        allocator.free(self.address);
        allocator.free(self.state_id);
        if (self.finality) |f| f.deinit(allocator);
    }
};
