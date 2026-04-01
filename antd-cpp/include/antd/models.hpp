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

/// A single entry in a file archive.
struct ArchiveEntry {
    std::string path;
    std::string address;
    int64_t created{0};
    int64_t modified{0};
    int64_t size{0};
};

/// A collection of archive entries.
struct Archive {
    std::vector<ArchiveEntry> entries;
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

/// Result of preparing an upload for external signing.
struct PrepareUploadResult {
    std::string upload_id;             // hex identifier
    std::vector<PaymentInfo> payments;
    std::string total_amount;
    std::string data_payments_address; // contract address
    std::string payment_token_address; // token contract address
    std::string rpc_url;               // EVM RPC URL
};

/// Result of finalizing an externally-signed upload.
struct FinalizeUploadResult {
    std::string address;       // hex address of stored data
    int64_t chunks_stored{0};
};

}  // namespace antd
