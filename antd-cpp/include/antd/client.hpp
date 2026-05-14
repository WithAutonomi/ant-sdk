#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "discover.hpp"
#include "errors.hpp"
#include "models.hpp"

namespace antd {

/// Default address of the antd daemon.
inline constexpr const char* kDefaultBaseURL = "http://localhost:8082";

/// Default request timeout in seconds (5 minutes).
inline constexpr int kDefaultTimeoutSeconds = 300;

/// REST client for the antd daemon.
///
/// All methods throw antd::AntdError (or a subclass) on failure.
class Client {
public:
    /// Construct a client connected to the given base URL.
    explicit Client(const std::string& base_url = kDefaultBaseURL,
                    int timeout_seconds = kDefaultTimeoutSeconds);
    ~Client();

    // Non-copyable, movable.
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;
    Client(Client&&) noexcept;
    Client& operator=(Client&&) noexcept;

    /// Create a client by auto-discovering the daemon port from the
    /// daemon.port file.  Falls back to kDefaultBaseURL if not found.
    static Client auto_discover(int timeout_seconds = kDefaultTimeoutSeconds) {
        auto url = discover_daemon_url();
        if (url.empty()) url = kDefaultBaseURL;
        return Client(url, timeout_seconds);
    }

    // --- Health ---

    /// Check daemon status.
    HealthStatus health();

    // --- Data (Immutable) ---

    /// Store public immutable data on the network.
    PutResult data_put_public(const std::vector<uint8_t>& data, const std::string& payment_mode = "");

    /// Retrieve public data by address.
    std::vector<uint8_t> data_get_public(std::string_view address);

    /// Store private encrypted data on the network.
    PutResult data_put_private(const std::vector<uint8_t>& data, const std::string& payment_mode = "");

    /// Retrieve private data using a data map.
    std::vector<uint8_t> data_get_private(std::string_view data_map);

    /// Pre-upload cost breakdown for the given bytes.
    UploadCostEstimate data_cost(const std::vector<uint8_t>& data);

    // --- Chunks ---

    /// Store a raw chunk on the network.
    PutResult chunk_put(const std::vector<uint8_t>& data);

    /// Retrieve a chunk by address.
    std::vector<uint8_t> chunk_get(std::string_view address);

    /// Prepare a single chunk for external-signer publish via POST /v1/chunks/prepare.
    ///
    /// Returns either `already_stored=true` with `address` set (no payment
    /// needed and no finalize call) or a wave-batch payment intent with
    /// `upload_id`, `payments`, and `total_amount` populated. After the
    /// external signer pays, call `finalize_chunk_upload` with the resulting
    /// tx hashes.
    ///
    /// Unlike `chunk_put`, this method does NOT require the daemon to have a
    /// wallet — all funds flow through the external signer.
    PrepareChunkResult prepare_chunk_upload(const std::vector<uint8_t>& data);

    /// Submit a prepared chunk to the network after external payment via
    /// POST /v1/chunks/finalize.
    ///
    /// `tx_hashes` maps each non-zero quote_hash from `prepare_chunk_upload`'s
    /// `payments` to the corresponding tx_hash returned by `payForQuotes()`.
    /// Returns the hex-encoded network address of the stored chunk (matches
    /// `PrepareChunkResult::address`).
    std::string finalize_chunk_upload(std::string_view upload_id,
                                      const std::map<std::string, std::string>& tx_hashes);

    // --- Files & Directories ---

    /// Upload a local file to the network.
    FileUploadResult file_upload_public(std::string_view path, const std::string& payment_mode = "");

    /// Download a file from the network to a local path.
    void file_download_public(std::string_view address, std::string_view dest_path);

    /// Upload a local directory to the network.
    FileUploadResult dir_upload_public(std::string_view path, const std::string& payment_mode = "");

    /// Download a directory from the network to a local path.
    void dir_download_public(std::string_view address, std::string_view dest_path);

    /// Pre-upload cost breakdown for the file at `path`.
    UploadCostEstimate file_cost(std::string_view path, bool is_public);

    // --- Wallet ---

    /// Get the wallet address configured on the daemon.
    WalletAddress wallet_address();

    /// Get the wallet balance (tokens and gas).
    WalletBalance wallet_balance();

    /// Approve the wallet to spend tokens on payment contracts (one-time operation).
    bool wallet_approve();

    // --- External Signer (Two-Phase Upload) ---

    /// Prepare a file upload for external signing.
    ///
    /// @param path        Path to the file to upload.
    /// @param visibility  When set, forwarded as a JSON field. Pass "public"
    ///                    to bundle the DataMap chunk into the same
    ///                    external-signer payment batch — the resulting
    ///                    `FinalizeUploadResult::data_map_address` is the
    ///                    shareable retrieval handle. When std::nullopt
    ///                    (default) the field is omitted, preserving the
    ///                    pre-public daemon wire shape.
    PrepareUploadResult prepare_upload(std::string_view path,
                                       std::optional<std::string> visibility = std::nullopt);

    /// Convenience wrapper: prepare a *public* file upload for external signing.
    /// Equivalent to `prepare_upload(path, "public")`. Requires antd >= 0.6.1.
    PrepareUploadResult prepare_upload_public(std::string_view path);

    /// Prepare a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    ///
    /// Note: `visibility="public"` returns 501 from the daemon until upstream
    /// ant-client exposes `data_prepare_upload_with_visibility`. Use
    /// `prepare_upload_public` with a file path until then.
    PrepareUploadResult prepare_data_upload(const std::vector<uint8_t>& data,
                                            std::optional<std::string> visibility = std::nullopt);

    /// Finalize a wave-batch upload after an external signer has submitted payment transactions.
    FinalizeUploadResult finalize_upload(std::string_view upload_id,
                                          const std::map<std::string, std::string>& tx_hashes,
                                          bool store_data_map = false);

    /// Finalize a merkle upload after the external signer has submitted
    /// the payForMerkleTree transaction.
    /// @param upload_id      The upload ID from prepare_upload.
    /// @param winner_pool_hash  The bytes32 value from the MerklePaymentMade event (hex with 0x prefix).
    /// @param store_data_map Whether to store the data map on-network.
    FinalizeUploadResult finalize_merkle_upload(std::string_view upload_id,
                                                 std::string_view winner_pool_hash,
                                                 bool store_data_map = false);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace antd
