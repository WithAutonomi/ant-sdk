#pragma once

#include <cstdint>
#include <string>
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
};

/// Result of a public data put. The DataMap is stored on-network as an extra
/// chunk; `address` is the shareable retrieval handle. REST populates
/// `chunks_stored` / `payment_mode_used`; gRPC currently leaves them at
/// their defaults.
struct DataPutPublicResult {
    std::string address;              // hex on-network DataMap address
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
};

/// Result of a private file upload. The DataMap is returned to the caller;
/// it is NOT stored on-network.
struct FilePutResult {
    std::string data_map;             // hex caller-held DataMap
    std::string storage_cost_atto;    // "0" if all chunks already existed
    std::string gas_cost_wei;         // decimal string
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
};

/// Result of a public file upload. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
struct FilePutPublicResult {
    std::string address;              // hex on-network DataMap address
    std::string storage_cost_atto;    // "0" if all chunks already existed
    std::string gas_cost_wei;         // decimal string
    std::uint64_t chunks_stored{0};
    std::string payment_mode_used;
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
};

/// Result of finalizing an externally-signed upload.
struct FinalizeUploadResult {
    std::string data_map;        // hex-encoded serialized DataMap (always returned)
    std::string address;         // legacy: set when store_data_map=true was passed (paid by daemon wallet)
    std::string data_map_address; // set when prepare was called with visibility="public"
                                  // (paid in same external-signer batch); "" otherwise
    int64_t chunks_stored{0};
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

}  // namespace antd
