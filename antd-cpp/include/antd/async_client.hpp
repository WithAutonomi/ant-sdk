#pragma once

/// @file async_client.hpp
/// Asynchronous wrapper around antd::Client using std::future.

#include "client.hpp"

#include <future>
#include <map>
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
    std::future<PutResult> data_put_public(const std::vector<uint8_t>& data);

    /// Retrieve public data by address.
    std::future<std::vector<uint8_t>> data_get_public(std::string address);

    /// Store private encrypted data on the network.
    std::future<PutResult> data_put_private(const std::vector<uint8_t>& data);

    /// Retrieve private data using a data map.
    std::future<std::vector<uint8_t>> data_get_private(std::string data_map);

    /// Pre-upload cost breakdown for the given bytes.
    std::future<UploadCostEstimate> data_cost(const std::vector<uint8_t>& data);

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

    // --- Files & Directories ---

    /// Upload a local file to the network.
    std::future<FileUploadResult> file_upload_public(std::string path);

    /// Download a file from the network to a local path.
    std::future<void> file_download_public(std::string address, std::string dest_path);

    /// Upload a local directory to the network.
    std::future<FileUploadResult> dir_upload_public(std::string path);

    /// Download a directory from the network to a local path.
    std::future<void> dir_download_public(std::string address, std::string dest_path);

    /// Pre-upload cost breakdown for the file at `path`.
    std::future<UploadCostEstimate> file_cost(std::string path, bool is_public);

private:
    Client client_;
};

}  // namespace antd
