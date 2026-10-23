#pragma once

#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace antd {

/// Health check result from the antd daemon.
///
/// The diagnostic fields (version, evm_network, uptime_seconds, build_commit,
/// payment_token_address, payment_vault_address) were added in antd 0.4.0.
/// They default to empty / 0 so the struct stays usable when talking to an
/// older daemon that doesn't report them.
struct HealthStatus {
    bool ok{false};
    std::string network;
    std::string version;                ///< antd crate version, e.g. "0.4.0"
    std::string evm_network;            ///< "arbitrum-one", "arbitrum-sepolia", "local", "custom"
    std::uint64_t uptime_seconds{0};    ///< seconds since the daemon process started
    std::string build_commit;           ///< short git SHA, "" if unknown
    std::string payment_token_address;  ///< "" if unconfigured
    std::string payment_vault_address;  ///< "" if unconfigured
};

/// Payment-batching strategy for uploads.
///
/// * `Auto`   — server picks (merkle for 64+ chunks, single otherwise).
/// * `Merkle` — force merkle-batch (saves gas, min 2 chunks).
/// * `Single` — force per-chunk payments (works for any chunk count).
///
/// Pass as a typed argument to the put/cost methods; the client serializes the
/// enum to the wire string at the request boundary.
enum class PaymentMode {
    Auto,
    Merkle,
    Single,
};

/// Serialize a PaymentMode to the wire string the daemon expects.
inline std::string payment_mode_wire(PaymentMode m) {
    switch (m) {
        case PaymentMode::Auto:   return "auto";
        case PaymentMode::Merkle: return "merkle";
        case PaymentMode::Single: return "single";
    }
    return "auto";
}

/// Result of a `chunk_put` operation. The DataMap concept doesn't apply at
/// chunk level.
struct PutResult {
    std::string cost;     // atto tokens as string
    std::string address;  // hex
};

/// Result of a private data put. The DataMap is returned to the caller; it
/// is NOT stored on-network. REST populates `chunks_stored` /
/// `payment_mode_used`; gRPC currently leaves them at their defaults (proto
/// `PutDataResponse` only carries `data_map`).
struct DataPutResult {
    std::string data_map;             // hex caller-held DataMap
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
    /// The plaintext's SHA-256 (hex, 64 lowercase characters). Unset on daemons
    /// before antd 0.17.0 (REST key absent, gRPC "").
    std::optional<std::string> sha256{};
};

/// Result of a public data put. The DataMap is stored on-network as an extra
/// chunk; `address` is the shareable retrieval handle. REST populates
/// `chunks_stored` / `payment_mode_used`; gRPC currently leaves them at
/// their defaults.
struct DataPutPublicResult {
    std::string address;              // hex on-network DataMap address
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
    /// The plaintext's SHA-256 (hex, 64 lowercase characters). Unset on daemons
    /// before antd 0.17.0 (REST key absent, gRPC "").
    std::optional<std::string> sha256{};
};

/// Result of a private file upload. The DataMap is returned to the caller;
/// it is NOT stored on-network.
struct FilePutResult {
    std::string data_map;             // hex caller-held DataMap
    std::string storage_cost_atto;    // "0" if all chunks already existed
    std::string gas_cost_wei;         // decimal string
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
    /// The plaintext's SHA-256 (hex, 64 lowercase characters). Unset on daemons
    /// before antd 0.17.0 (REST key absent, gRPC "").
    std::optional<std::string> sha256{};
};

/// Result of a public file upload. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
struct FilePutPublicResult {
    std::string address;              // hex on-network DataMap address
    std::string storage_cost_atto;    // "0" if all chunks already existed
    std::string gas_cost_wei;         // decimal string
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
    /// The plaintext's SHA-256 (hex, 64 lowercase characters). Unset on daemons
    /// before antd 0.17.0 (REST key absent, gRPC "").
    std::optional<std::string> sha256{};
};

/// Wallet address response.
struct WalletAddress {
    std::string address;  // 0x-prefixed hex
};

/// Wallet balance response.
struct WalletBalance {
    std::string balance;      // atto tokens as string
    std::string gas_balance;  // atto tokens as string
};

/// A single payment required for an upload.
struct PaymentInfo {
    std::string quote_hash;      // hex
    std::string rewards_address; // hex
    std::string amount;          // atto tokens as string
};

/// A candidate node in a merkle pool commitment.
struct CandidateNodeEntry {
    std::string rewards_address; // hex with 0x prefix
    std::string amount;          // node price as decimal string
};

/// A pool commitment for the merkle payment contract.
struct PoolCommitmentEntry {
    std::string pool_hash;                    // hex, 32 bytes with 0x prefix
    std::vector<CandidateNodeEntry> candidates; // exactly 16 nodes
};

/// Result of preparing an upload for external signing.
/// payment_type is "wave_batch" or "merkle" -- determines which fields are populated
/// and which contract call the external signer must make.
struct PrepareUploadResult {
    std::string upload_id;             // hex identifier
    std::string payment_type;          // "wave_batch" or "merkle"

    // Wave-batch fields (present when payment_type == "wave_batch")
    std::vector<PaymentInfo> payments;        // per-quote payments for payForQuotes()

    // Merkle fields (present when payment_type == "merkle")
    int depth{0};                                        // merkle tree depth (1-8)
    std::vector<PoolCommitmentEntry> pool_commitments;   // for payForMerkleTree()
    uint64_t merkle_payment_timestamp{0};                // unix seconds

    // Common fields (always present)
    std::string total_amount;
    std::string payment_vault_address; // unified payment vault contract address
    std::string payment_token_address; // token contract address
    std::string rpc_url;               // EVM RPC URL

    // Already-stored preflight (added in antd 0.10.0). 0 against older daemons.
    // The external signer pays for (total_chunks - already_stored_count) chunks.
    uint64_t total_chunks{0};          // total chunks incl. already-stored
    uint64_t already_stored_count{0};  // chunks skipped (already on-network)
};

/// Result of finalizing an externally-signed upload.
struct FinalizeUploadResult {
    std::string data_map;        // hex-encoded serialized DataMap (always returned)
    std::string address;         // legacy: set when store_data_map=true was passed (paid by daemon wallet)
    std::string data_map_address; // set when prepare was called with visibility="public"
                                  // (paid in same external-signer batch); "" otherwise
    int64_t chunks_stored{0};
    /// The plaintext's SHA-256 (hex, 64 lowercase characters). Unset on daemons
    /// before antd 0.17.0 (REST key absent, gRPC "").
    std::optional<std::string> sha256{};
};

/// Result of preparing a single-chunk publish for external signing via
/// POST /v1/chunks/prepare.
///
/// When `already_stored` is true, the chunk is already on-network — only
/// `address` and `already_stored` are populated, and no finalize call is
/// needed. Otherwise the wave-batch payment fields describe what the external
/// signer must submit before calling `finalize_chunk_upload`.
struct PrepareChunkResult {
    // Content-addressed BLAKE3 of the chunk bytes (hex, 64 chars). Always set.
    std::string address;
    // True if the chunk is already stored on the network and no payment is needed.
    bool already_stored{false};

    // Fields below are only populated when already_stored == false.

    // Opaque identifier to pass back to finalize_chunk_upload.
    std::string upload_id;
    // Always "wave_batch" for single-chunk publishes (well below the merkle threshold).
    std::string payment_type;
    // Per-quote payment entries for payForQuotes(). Typically 5-7 (one per peer in the close group).
    std::vector<PaymentInfo> payments;
    // Total amount to pay (atto tokens, decimal string).
    std::string total_amount;
    // Payment vault contract address (hex with 0x prefix).
    std::string payment_vault_address;
    // Payment token contract address (hex with 0x prefix).
    std::string payment_token_address;
    // EVM RPC URL for submitting transactions.
    std::string rpc_url;
};

/// A fetch-progress update emitted during a streaming download when progress
/// is requested. Counts are in *chunks*, not bytes — the byte denominator is
/// the download's total size (the `x-content-length` response metadata over
/// gRPC, the NDJSON `meta` frame over REST). `total` is 0 while still unknown
/// (mid DataMap-resolution).
///
/// `phase` is one of:
///   * `"resolving_map"` — walking the hierarchical DataMap to learn the chunk count
///   * `"resolved"`      — DataMap resolved, `total` now holds the real chunk count
///   * `"fetching"`      — fetching data chunks; `fetched`/`total` advance the bar
struct DownloadProgress {
    std::string phase;
    std::uint64_t fetched{0};
    std::uint64_t total{0};
};

/// One frame of a progress-enabled streaming download: the total size (`meta`),
/// a plaintext data chunk (`data`), or a [DownloadProgress] update
/// (`progress`). Exactly one of the three optionals is set per frame; use
/// `is_meta()` / `is_progress()` to discriminate.
///
/// Returned (via a callback sink) by the `*_with_progress` streaming methods;
/// the plain `data_stream` / `data_stream_public` methods stay a pure byte
/// stream for callers that don't need progress.
struct DownloadFrame {
    std::optional<std::vector<uint8_t>> data;
    std::optional<DownloadProgress> progress;
    /// Total download size in *bytes* — the progress *denominator*, surfaced
    /// from the gRPC `x-content-length` response metadata or the REST NDJSON
    /// `meta` frame. Emitted at most once, before any data, when the daemon
    /// reports it. Pair it with the byte count of the `data` frames (or with
    /// the [DownloadProgress] chunk counts) to render a byte-accurate bar.
    std::optional<std::uint64_t> total_size;

    /// True when this frame carries the total-bytes denominator.
    bool is_meta() const { return total_size.has_value(); }

    /// True when this frame carries a progress update rather than data bytes.
    bool is_progress() const { return progress.has_value(); }

    /// Construct a meta frame carrying the total download size in bytes.
    static DownloadFrame from_meta(std::uint64_t total) {
        return DownloadFrame{std::nullopt, std::nullopt, total};
    }

    /// Construct a data frame from raw bytes.
    static DownloadFrame from_data(std::vector<uint8_t> bytes) {
        return DownloadFrame{std::move(bytes), std::nullopt, std::nullopt};
    }

    /// Construct a progress frame.
    static DownloadFrame from_progress(DownloadProgress p) {
        return DownloadFrame{std::nullopt, std::move(p), std::nullopt};
    }
};

/// Pre-upload cost breakdown returned by data_cost and file_cost.
///
/// The server samples up to 5 chunk addresses and extrapolates the storage
/// cost. Gas is an advisory heuristic, not a live gas-oracle query.
struct UploadCostEstimate {
    std::string cost;                    // storage cost in atto tokens
    uint64_t file_size{0};               // original file size in bytes
    uint32_t chunk_count{0};             // number of data chunks
    std::string estimated_gas_cost_wei;  // advisory gas heuristic in wei
    std::string payment_mode;            // "auto" | "merkle" | "single"
};

// ---------------------------------------------------------------------------
// Pointers (ADR-0016 / ADR-0018 in ant-node)
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; its target (a chunk, such
// as a public file's data map, or another pointer) can be changed by the
// owner, and the owner can hand it over to another pointer for good. antd
// signs with owner keys it loaded at startup (`--pointer-keys`), so a write
// names the pointer by its address (`owner`), never by a key.
//
// Every write pays, and every attempt pays again: do not retry a create,
// update, transfer or finalize automatically.
//
// Counters are std::uint64_t. The daemon sends them as decimal strings,
// because a final state sits at 2^64-1, past what a JSON number keeps exactly
// in several languages; anything that is not a decimal u64 is an error, never
// a zero. Addresses, state ids and targets are 64 hex characters; the daemon
// accepts a `0x` prefix on input but always returns bare hex.
// ---------------------------------------------------------------------------

/// The counter of a pointer's final state, after a transfer or a freeze:
/// nothing can replace it.
inline constexpr std::uint64_t kPointerFinalCounter =
    std::numeric_limits<std::uint64_t>::max();

/// What a pointer's target is.
enum class PointerKind {
    /// An immutable chunk, such as a public file's data map. The default.
    Chunk,
    /// Another pointer: a forwarding the owner can still change. Use
    /// pointer_transfer to hand a pointer over for good.
    Pointer,
};

/// Serialize a PointerKind to the wire string the daemon expects.
inline std::string pointer_kind_wire(PointerKind k) {
    switch (k) {
        case PointerKind::Chunk:   return "chunk";
        case PointerKind::Pointer: return "pointer";
    }
    return "chunk";
}

/// The kind a raw target tag names, if this SDK knows it (0 chunk,
/// 1 pointer).
inline std::optional<PointerKind> pointer_kind_from_tag(std::uint8_t tag) {
    switch (tag) {
        case 0: return PointerKind::Chunk;
        case 1: return PointerKind::Pointer;
        default: return std::nullopt;
    }
}

/// The write a pointer_prepare signs for an external signer to pay.
enum class PointerOp {
    /// Create the pointer at `target`. Refused if it already exists.
    Create,
    /// Point the pointer at `target`, creating it if it does not exist.
    Update,
    /// Hand the pointer over for good to the pointer at `recipient`, which
    /// must already exist. Irreversible once stored.
    Transfer,
};

/// Serialize a PointerOp to the wire string the daemon expects.
inline std::string pointer_op_wire(PointerOp op) {
    switch (op) {
        case PointerOp::Create:   return "create";
        case PointerOp::Update:   return "update";
        case PointerOp::Transfer: return "transfer";
    }
    return "create";
}

/// A pointer the daemon holds an owner key for.
struct PointerKey {
    std::string address;  ///< the pointer's address, derived from the owner key
};

/// The state a pointer write stored.
struct PointerWriteResult {
    std::string address;
    std::string state_id;       ///< the identifier the state was paid against
    std::uint64_t counter{0};   ///< a final state (a transfer) sits at kPointerFinalCounter
};

/// A pointer's current state, as the network serves it.
struct PointerRecord {
    std::string address;
    /// The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
    /// derived from it, so it is the proof of who owns the pointer.
    std::string owner;
    std::uint64_t counter{0};
    /// "chunk", "pointer", or "unknown" for a kind the daemon does not know;
    /// `kind_tag` carries the raw value either way.
    std::string kind;
    std::uint8_t kind_tag{0};
    std::string target;
    std::string state_id;
    /// The state is at the final counter: the pointer was handed over or
    /// frozen, and nothing can replace it.
    bool is_final{false};
    /// The pointer this one was handed over to, when its final state is a
    /// transfer.
    std::optional<std::string> transferred_to;

    /// The target's kind, if this SDK knows its tag.
    std::optional<PointerKind> target_kind() const { return pointer_kind_from_tag(kind_tag); }
};

/// Where a chain of pointers ends (pointer_resolve).
struct PointerTarget {
    /// "chunk", or "unknown" for a target kind the daemon does not know.
    std::string kind;
    std::uint8_t kind_tag{0};
    std::string target;
};

/// Where a pointer stands with respect to finality, as its whole close group
/// reports it. `Unknown` is a status this SDK does not know (a newer daemon);
/// PointerFinality::status_raw then carries the daemon's string.
enum class PointerFinalityStatus {
    /// No peer that answered holds a final state: the owner can still move
    /// the pointer. Rules a final state out only when every peer answered.
    Open,
    /// One final state, not yet held by a majority: a transfer still
    /// spreading, or a write that fell short.
    Settling,
    /// One final state held by a majority, but not every peer answered, so a
    /// rival could still be unseen. Ask again.
    Unconfirmed,
    /// One final state held by a majority, every peer answered, no rival.
    /// The only status a recipient should rely on.
    Final,
    /// The owner signed two or more different final states.
    Forked,
    /// A status this SDK does not know; see PointerFinality::status_raw.
    Unknown,
};

/// Parse the daemon's finality status string. Anything this SDK does not know
/// is `Unknown`.
inline PointerFinalityStatus pointer_finality_status_from_wire(std::string_view s) {
    if (s == "open") return PointerFinalityStatus::Open;
    if (s == "settling") return PointerFinalityStatus::Settling;
    if (s == "unconfirmed") return PointerFinalityStatus::Unconfirmed;
    if (s == "final") return PointerFinalityStatus::Final;
    if (s == "forked") return PointerFinalityStatus::Forked;
    return PointerFinalityStatus::Unknown;
}

/// One final state, as a finality check reports it.
struct PointerFinalState {
    std::string state_id;
    std::string kind;
    std::uint8_t kind_tag{0};
    std::string target;
    std::uint32_t holders{0};  ///< how many peers of the close group hold it
    std::optional<std::string> transferred_to;
};

/// The answer to a pointer finality check. Check it before relying on a
/// transfer: only `status == PointerFinalityStatus::Final` means the transfer
/// is beyond dispute.
struct PointerFinality {
    std::string address;
    std::uint32_t group{0};     ///< peers in the close group
    std::uint32_t answered{0};  ///< peers that answered
    PointerFinalityStatus status{PointerFinalityStatus::Unknown};
    /// The daemon's status string, verbatim ("open", "final", ...). The only
    /// way to read a status this SDK does not know (`status == Unknown`).
    std::string status_raw;
    /// `Open` only: the counter a read would return, if any state is
    /// corroborated. Unset when none is (REST `null`, gRPC `""`).
    std::optional<std::uint64_t> counter;
    /// `Settling`, `Unconfirmed` and `Final`: the one final state seen.
    std::optional<PointerFinalState> state;
    /// `Forked` only: every final state seen, most-held first.
    std::vector<PointerFinalState> states;
    /// `Forked` only: the state a majority holds, which reads return.
    std::optional<PointerFinalState> majority;
    /// The pointer this one was handed over to, once that is beyond dispute
    /// (status `Final`).
    std::optional<std::string> transferred_to;

    /// One final state, held by a majority, with every peer answering and no
    /// rival seen.
    bool is_final() const { return status == PointerFinalityStatus::Final; }
};

/// What a transfer stored, and where the close group says it stands.
struct PointerTransferResult {
    std::string address;
    std::string state_id;
    /// The close group's view once the write landed. Unset when that check
    /// failed (see `finality_error`), which does not undo the transfer: it is
    /// stored and final. Ask again with pointer_finality.
    std::optional<PointerFinality> finality;
    std::optional<std::string> finality_error;
};

/// Whose pointer decides what an address resolves to, after every transfer.
struct PointerController {
    std::string pointer;
    std::vector<std::string> transfers;  ///< every pointer handed over to, in order
    /// `pointer` is final without being handed over: nobody can move it.
    bool frozen{false};
};

/// One `payments` quote in full signed form. `quote` and `commitment_sidecar`
/// are opaque base64 blobs (msgpack inside) on both transports; only antd
/// parses them.
struct SignedQuoteEntry {
    std::string quote_hash;  ///< hex with 0x prefix; matches the payments entry
    std::string quote;       ///< base64(msgpack signed PaymentQuote), opaque
    /// base64(msgpack StorageCommitment) the quote's commitment pin resolves
    /// to. Unset for baseline quotes.
    std::optional<std::string> commitment_sidecar;
};

/// A pointer write for the daemon to sign with its loaded owner key and quote
/// for an external signer (pointer_prepare). Build one with create(), update()
/// or transfer().
struct PointerPrepareRequest {
    /// Address of the pointer to write; the daemon must hold its key.
    std::string owner;
    PointerOp op{PointerOp::Create};
    /// Create and update: the address to point at.
    std::string target;
    /// Create and update: what `target` is.
    PointerKind kind{PointerKind::Chunk};
    /// Transfer: the recipient's pointer, which must already exist.
    std::string recipient;
    /// Ask for every quote in full signed form (PointerPrepareResult::
    /// signed_quotes), for offline verification.
    bool include_signed_quotes{false};

    static PointerPrepareRequest create(std::string owner, std::string target,
                                        PointerKind kind = PointerKind::Chunk) {
        PointerPrepareRequest r;
        r.owner = std::move(owner);
        r.op = PointerOp::Create;
        r.target = std::move(target);
        r.kind = kind;
        return r;
    }

    static PointerPrepareRequest update(std::string owner, std::string target,
                                        PointerKind kind = PointerKind::Chunk) {
        PointerPrepareRequest r = create(std::move(owner), std::move(target), kind);
        r.op = PointerOp::Update;
        return r;
    }

    static PointerPrepareRequest transfer(std::string owner, std::string recipient) {
        PointerPrepareRequest r;
        r.owner = std::move(owner);
        r.op = PointerOp::Transfer;
        r.recipient = std::move(recipient);
        return r;
    }
};

/// A pointer write signed by the daemon and quoted for an external signer.
/// Pay `payments` with payForQuotes(), then call pointer_finalize. While it
/// awaits payment, other writes to the pointer throw ConflictError until it
/// is finalized or expires.
struct PointerPrepareResult {
    std::string upload_id;
    std::string op;  ///< "create", "update" or "transfer"
    std::string address;
    std::string state_id;
    std::uint64_t counter{0};
    std::string payment_type;  ///< always "wave_batch": one quote pays for a state
    std::vector<PaymentInfo> payments;
    std::string total_amount;  ///< atto tokens, decimal string
    std::string payment_vault_address;
    std::string payment_token_address;
    std::string rpc_url;
    /// Set only when requested with PointerPrepareRequest::include_signed_quotes.
    std::vector<SignedQuoteEntry> signed_quotes;
};

/// The state a pointer finalize stored.
struct PointerFinalizeResult {
    std::string address;
    std::string state_id;
    std::uint64_t counter{0};
    /// Transfers only: where the close group says the transfer stands.
    std::optional<PointerFinality> finality;
};

namespace detail {

/// An empty string reads as none: a proto3 string field has no presence, so
/// "" is its zero value and means "not reported" (sha256 before antd 0.17.0).
inline std::optional<std::string> none_if_empty(std::string s) {
    if (s.empty()) return std::nullopt;
    return s;
}

}  // namespace detail

}  // namespace antd
