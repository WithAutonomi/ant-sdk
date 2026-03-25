#pragma once

#include <cstdint>
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
    PutResult data_put_public(const std::vector<uint8_t>& data);

    /// Retrieve public data by address.
    std::vector<uint8_t> data_get_public(std::string_view address);

    /// Store private encrypted data on the network.
    PutResult data_put_private(const std::vector<uint8_t>& data);

    /// Retrieve private data using a data map.
    std::vector<uint8_t> data_get_private(std::string_view data_map);

    /// Estimate the cost of storing data.
    std::string data_cost(const std::vector<uint8_t>& data);

    // --- Chunks ---

    /// Store a raw chunk on the network.
    PutResult chunk_put(const std::vector<uint8_t>& data);

    /// Retrieve a chunk by address.
    std::vector<uint8_t> chunk_get(std::string_view address);

    // --- Graph Entries (DAG Nodes) ---

    /// Create a new graph entry.
    PutResult graph_entry_put(std::string_view owner_secret_key,
                              const std::vector<std::string>& parents,
                              std::string_view content,
                              const std::vector<GraphDescendant>& descendants);

    /// Retrieve a graph entry by address.
    GraphEntry graph_entry_get(std::string_view address);

    /// Check if a graph entry exists at the given address.
    bool graph_entry_exists(std::string_view address);

    /// Estimate the cost of creating a graph entry.
    std::string graph_entry_cost(std::string_view public_key);

    // --- Files & Directories ---

    /// Upload a local file to the network.
    PutResult file_upload_public(std::string_view path);

    /// Download a file from the network to a local path.
    void file_download_public(std::string_view address, std::string_view dest_path);

    /// Upload a local directory to the network.
    PutResult dir_upload_public(std::string_view path);

    /// Download a directory from the network to a local path.
    void dir_download_public(std::string_view address, std::string_view dest_path);

    /// Retrieve an archive manifest by address.
    Archive archive_get_public(std::string_view address);

    /// Create an archive manifest on the network.
    PutResult archive_put_public(const Archive& archive);

    /// Estimate the cost of uploading a file.
    std::string file_cost(std::string_view path, bool is_public, bool include_archive);

    // --- Wallet ---

    /// Get the wallet address configured on the daemon.
    WalletAddress wallet_address();

    /// Get the wallet balance (tokens and gas).
    WalletBalance wallet_balance();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace antd
