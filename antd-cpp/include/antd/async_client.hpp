#pragma once

/// @file async_client.hpp
/// Asynchronous wrapper around antd::Client using std::future.

#include "client.hpp"

#include <future>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace antd {

/// Asynchronous REST client for the antd daemon.
///
/// Every method dispatches the corresponding synchronous Client call on a
/// separate thread via std::async(std::launch::async, ...) and returns a
/// std::future<T>.  Exceptions thrown by the underlying Client propagate
/// through the future — calling .get() will rethrow them.
///
/// The class is non-copyable and non-movable because the internal Client may
/// be accessed from multiple worker threads concurrently. Each AsyncClient
/// instance creates its own Client (and therefore its own HTTP connection).
class AsyncClient {
public:
    /// Construct an async client connected to the given base URL.
    explicit AsyncClient(const std::string& base_url = kDefaultBaseURL,
                         int timeout_seconds = kDefaultTimeoutSeconds);
    ~AsyncClient();

    // Non-copyable, non-movable.
    AsyncClient(const AsyncClient&) = delete;
    AsyncClient& operator=(const AsyncClient&) = delete;
    AsyncClient(AsyncClient&&) = delete;
    AsyncClient& operator=(AsyncClient&&) = delete;

    // --- Health ---

    /// Check daemon status.
    std::future<HealthStatus> health();

    // --- Data (Immutable) ---

    /// Store public immutable data on the network.
    std::future<DataPutPublicResult> data_put_public(const std::vector<uint8_t>& data,
                                                     PaymentMode payment_mode = PaymentMode::Auto);

    /// Retrieve public data by address.
    std::future<std::vector<uint8_t>> data_get_public(std::string address);

    /// Store private encrypted data on the network.
    std::future<DataPutResult> data_put(const std::vector<uint8_t>& data,
                                        PaymentMode payment_mode = PaymentMode::Auto);

    /// Retrieve private data using a caller-held DataMap.
    std::future<std::vector<uint8_t>> data_get(std::string data_map);

    /// Pre-upload cost breakdown for the given bytes.
    std::future<UploadCostEstimate> data_cost(const std::vector<uint8_t>& data,
                                              PaymentMode payment_mode = PaymentMode::Auto);

    // --- Chunks ---

    /// Store a raw chunk on the network.
    std::future<PutResult> chunk_put(const std::vector<uint8_t>& data);

    /// Retrieve a chunk by address.
    std::future<std::vector<uint8_t>> chunk_get(std::string address);

    /// Prepare a single chunk for external-signer publish.
    /// See Client::prepare_chunk_upload.
    std::future<PrepareChunkResult> prepare_chunk_upload(const std::vector<uint8_t>& data);

    /// Submit a prepared chunk to the network after external payment.
    /// See Client::finalize_chunk_upload.
    std::future<std::string> finalize_chunk_upload(std::string upload_id,
                                                   std::map<std::string, std::string> tx_hashes);

    // --- Files ---

    /// Upload a local file *privately*.
    std::future<FilePutResult> file_put(std::string path,
                                        PaymentMode payment_mode = PaymentMode::Auto);

    /// Download a file from a caller-held DataMap into `dest_path`.
    std::future<void> file_get(std::string data_map, std::string dest_path);

    /// Upload a local file *publicly*.
    std::future<FilePutPublicResult> file_put_public(std::string path,
                                                    PaymentMode payment_mode = PaymentMode::Auto);

    /// Download a public file from an on-network DataMap address.
    std::future<void> file_get_public(std::string address, std::string dest_path);

    /// Pre-upload cost breakdown for the file at `path`.
    std::future<UploadCostEstimate> file_cost(std::string path,
                                              bool is_public,
                                              PaymentMode payment_mode = PaymentMode::Auto);

    // --- Wallet ---

    /// Get the wallet address configured on the daemon.
    std::future<WalletAddress> wallet_address();

    /// Get the wallet balance (tokens and gas).
    std::future<WalletBalance> wallet_balance();

    /// Approve the wallet to spend tokens on payment contracts (one-time op).
    std::future<bool> wallet_approve();

    // --- External Signer (Two-Phase Upload) ---

    /// Prepare a file upload for external signing. See Client::prepare_upload.
    std::future<PrepareUploadResult> prepare_upload(std::string path,
                                                    std::optional<std::string> visibility = std::nullopt);

    /// Convenience: prepare a public file upload. Equivalent to
    /// prepare_upload(path, "public").
    std::future<PrepareUploadResult> prepare_upload_public(std::string path);

    /// Prepare a data upload for external signing. See Client::prepare_data_upload.
    std::future<PrepareUploadResult> prepare_data_upload(const std::vector<uint8_t>& data,
                                                         std::optional<std::string> visibility = std::nullopt);

    /// Finalize a wave-batch upload after external signer submits payments.
    std::future<FinalizeUploadResult> finalize_upload(std::string upload_id,
                                                     std::map<std::string, std::string> tx_hashes,
                                                     bool store_data_map = false);

    /// Finalize a merkle upload after external signer submits payForMerkleTree.
    std::future<FinalizeUploadResult> finalize_merkle_upload(std::string upload_id,
                                                            std::string winner_pool_hash,
                                                            bool store_data_map = false);

private:
    Client client_;
};

}  // namespace antd
