#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace antd {

/// Result of a health check.
struct HealthStatus {
    bool ok{false};
    std::string network;
};

/// Result of a put/create operation.
struct PutResult {
    std::string cost;     // atto tokens as string
    std::string address;  // hex
};

/// Result of a public file or directory upload.
struct FileUploadResult {
    std::string address;            // hex network address
    std::string storage_cost_atto;  // storage cost in atto, "0" if all chunks already existed
    std::string gas_cost_wei;       // gas cost in wei as decimal string
    uint64_t chunks_stored{0};      // number of chunks stored on the network
    std::string payment_mode_used;  // "auto", "merkle", or "single"
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
    std::string address;         // network address (only when store_data_map=true)
    int64_t chunks_stored{0};
};

}  // namespace antd
