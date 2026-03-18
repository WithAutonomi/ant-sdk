#include "antd/async_client.hpp"

#include <future>
#include <utility>

namespace antd {

// ---------------------------------------------------------------------------
// Lifetime
// ---------------------------------------------------------------------------

AsyncClient::AsyncClient(const std::string& base_url, int timeout_seconds)
    : client_(base_url, timeout_seconds) {}

AsyncClient::~AsyncClient() = default;

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

std::future<HealthStatus> AsyncClient::health() {
    return std::async(std::launch::async, [this] {
        return client_.health();
    });
}

// ---------------------------------------------------------------------------
// Data (Immutable)
// ---------------------------------------------------------------------------

std::future<PutResult> AsyncClient::data_put_public(const std::vector<uint8_t>& data) {
    return std::async(std::launch::async, [this, data] {
        return client_.data_put_public(data);
    });
}

std::future<std::vector<uint8_t>> AsyncClient::data_get_public(std::string address) {
    return std::async(std::launch::async, [this, addr = std::move(address)] {
        return client_.data_get_public(addr);
    });
}

std::future<PutResult> AsyncClient::data_put_private(const std::vector<uint8_t>& data) {
    return std::async(std::launch::async, [this, data] {
        return client_.data_put_private(data);
    });
}

std::future<std::vector<uint8_t>> AsyncClient::data_get_private(std::string data_map) {
    return std::async(std::launch::async, [this, dm = std::move(data_map)] {
        return client_.data_get_private(dm);
    });
}

std::future<std::string> AsyncClient::data_cost(const std::vector<uint8_t>& data) {
    return std::async(std::launch::async, [this, data] {
        return client_.data_cost(data);
    });
}

// ---------------------------------------------------------------------------
// Chunks
// ---------------------------------------------------------------------------

std::future<PutResult> AsyncClient::chunk_put(const std::vector<uint8_t>& data) {
    return std::async(std::launch::async, [this, data] {
        return client_.chunk_put(data);
    });
}

std::future<std::vector<uint8_t>> AsyncClient::chunk_get(std::string address) {
    return std::async(std::launch::async, [this, addr = std::move(address)] {
        return client_.chunk_get(addr);
    });
}

// ---------------------------------------------------------------------------
// Graph Entries (DAG Nodes)
// ---------------------------------------------------------------------------

std::future<PutResult> AsyncClient::graph_entry_put(
        std::string owner_secret_key,
        std::vector<std::string> parents,
        std::string content,
        std::vector<GraphDescendant> descendants) {
    return std::async(std::launch::async,
        [this,
         osk = std::move(owner_secret_key),
         p   = std::move(parents),
         c   = std::move(content),
         d   = std::move(descendants)] {
            return client_.graph_entry_put(osk, p, c, d);
        });
}

std::future<GraphEntry> AsyncClient::graph_entry_get(std::string address) {
    return std::async(std::launch::async, [this, addr = std::move(address)] {
        return client_.graph_entry_get(addr);
    });
}

std::future<bool> AsyncClient::graph_entry_exists(std::string address) {
    return std::async(std::launch::async, [this, addr = std::move(address)] {
        return client_.graph_entry_exists(addr);
    });
}

std::future<std::string> AsyncClient::graph_entry_cost(std::string public_key) {
    return std::async(std::launch::async, [this, pk = std::move(public_key)] {
        return client_.graph_entry_cost(pk);
    });
}

// ---------------------------------------------------------------------------
// Files & Directories
// ---------------------------------------------------------------------------

std::future<PutResult> AsyncClient::file_upload_public(std::string path) {
    return std::async(std::launch::async, [this, p = std::move(path)] {
        return client_.file_upload_public(p);
    });
}

std::future<void> AsyncClient::file_download_public(std::string address, std::string dest_path) {
    return std::async(std::launch::async,
        [this, addr = std::move(address), dest = std::move(dest_path)] {
            client_.file_download_public(addr, dest);
        });
}

std::future<PutResult> AsyncClient::dir_upload_public(std::string path) {
    return std::async(std::launch::async, [this, p = std::move(path)] {
        return client_.dir_upload_public(p);
    });
}

std::future<void> AsyncClient::dir_download_public(std::string address, std::string dest_path) {
    return std::async(std::launch::async,
        [this, addr = std::move(address), dest = std::move(dest_path)] {
            client_.dir_download_public(addr, dest);
        });
}

std::future<Archive> AsyncClient::archive_get_public(std::string address) {
    return std::async(std::launch::async, [this, addr = std::move(address)] {
        return client_.archive_get_public(addr);
    });
}

std::future<PutResult> AsyncClient::archive_put_public(const Archive& archive) {
    return std::async(std::launch::async, [this, archive] {
        return client_.archive_put_public(archive);
    });
}

std::future<std::string> AsyncClient::file_cost(std::string path, bool is_public, bool include_archive) {
    return std::async(std::launch::async,
        [this, p = std::move(path), is_public, include_archive] {
            return client_.file_cost(p, is_public, include_archive);
        });
}

}  // namespace antd
