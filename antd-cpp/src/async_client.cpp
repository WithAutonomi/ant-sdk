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

std::future<DataPutPublicResult> AsyncClient::data_put_public(
    const std::vector<uint8_t>& data, PaymentMode payment_mode) {
    return std::async(std::launch::async, [this, data, payment_mode] {
        return client_.data_put_public(data, payment_mode);
    });
}

std::future<std::vector<uint8_t>> AsyncClient::data_get_public(std::string address) {
    return std::async(std::launch::async, [this, addr = std::move(address)] {
        return client_.data_get_public(addr);
    });
}

std::future<DataPutResult> AsyncClient::data_put(
    const std::vector<uint8_t>& data, PaymentMode payment_mode) {
    return std::async(std::launch::async, [this, data, payment_mode] {
        return client_.data_put(data, payment_mode);
    });
}

std::future<std::vector<uint8_t>> AsyncClient::data_get(std::string data_map) {
    return std::async(std::launch::async, [this, dm = std::move(data_map)] {
        return client_.data_get(dm);
    });
}

std::future<UploadCostEstimate> AsyncClient::data_cost(
    const std::vector<uint8_t>& data, PaymentMode payment_mode) {
    return std::async(std::launch::async, [this, data, payment_mode] {
        return client_.data_cost(data, payment_mode);
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

std::future<PrepareChunkResult> AsyncClient::prepare_chunk_upload(const std::vector<uint8_t>& data) {
    return std::async(std::launch::async, [this, data] {
        return client_.prepare_chunk_upload(data);
    });
}

std::future<std::string> AsyncClient::finalize_chunk_upload(
    std::string upload_id,
    std::map<std::string, std::string> tx_hashes) {
    return std::async(std::launch::async,
        [this, uid = std::move(upload_id), th = std::move(tx_hashes)] {
            return client_.finalize_chunk_upload(uid, th);
        });
}

// ---------------------------------------------------------------------------
// Files & Directories
// ---------------------------------------------------------------------------

std::future<FilePutResult> AsyncClient::file_put(std::string path, PaymentMode payment_mode) {
    return std::async(std::launch::async, [this, p = std::move(path), payment_mode] {
        return client_.file_put(p, payment_mode);
    });
}

std::future<void> AsyncClient::file_get(std::string data_map, std::string dest_path) {
    return std::async(std::launch::async,
        [this, dm = std::move(data_map), dest = std::move(dest_path)] {
            client_.file_get(dm, dest);
        });
}

std::future<FilePutPublicResult> AsyncClient::file_put_public(std::string path, PaymentMode payment_mode) {
    return std::async(std::launch::async, [this, p = std::move(path), payment_mode] {
        return client_.file_put_public(p, payment_mode);
    });
}

std::future<void> AsyncClient::file_get_public(std::string address, std::string dest_path) {
    return std::async(std::launch::async,
        [this, addr = std::move(address), dest = std::move(dest_path)] {
            client_.file_get_public(addr, dest);
        });
}

std::future<UploadCostEstimate> AsyncClient::file_cost(std::string path, bool is_public, PaymentMode payment_mode) {
    return std::async(std::launch::async,
        [this, p = std::move(path), is_public, payment_mode] {
            return client_.file_cost(p, is_public, payment_mode);
        });
}


// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

std::future<WalletAddress> AsyncClient::wallet_address() {
    return std::async(std::launch::async, [this] { return client_.wallet_address(); });
}

std::future<WalletBalance> AsyncClient::wallet_balance() {
    return std::async(std::launch::async, [this] { return client_.wallet_balance(); });
}

std::future<bool> AsyncClient::wallet_approve() {
    return std::async(std::launch::async, [this] { return client_.wallet_approve(); });
}

// ---------------------------------------------------------------------------
// External Signer (Two-Phase Upload)
// ---------------------------------------------------------------------------

std::future<PrepareUploadResult> AsyncClient::prepare_upload(
    std::string path, std::optional<std::string> visibility) {
    return std::async(std::launch::async,
                      [this, p = std::move(path), v = std::move(visibility)] {
                          return client_.prepare_upload(p, v);
                      });
}

std::future<PrepareUploadResult> AsyncClient::prepare_upload_public(std::string path) {
    return std::async(std::launch::async, [this, p = std::move(path)] {
        return client_.prepare_upload_public(p);
    });
}

std::future<PrepareUploadResult> AsyncClient::prepare_data_upload(
    const std::vector<uint8_t>& data, std::optional<std::string> visibility) {
    return std::async(std::launch::async,
                      [this, data, v = std::move(visibility)] {
                          return client_.prepare_data_upload(data, v);
                      });
}

std::future<FinalizeUploadResult> AsyncClient::finalize_upload(
    std::string upload_id, std::map<std::string, std::string> tx_hashes,
    bool store_data_map) {
    return std::async(std::launch::async,
                      [this, uid = std::move(upload_id),
                       hashes = std::move(tx_hashes), store_data_map] {
                          return client_.finalize_upload(uid, hashes, store_data_map);
                      });
}

std::future<FinalizeUploadResult> AsyncClient::finalize_merkle_upload(
    std::string upload_id, std::string winner_pool_hash, bool store_data_map) {
    return std::async(std::launch::async,
                      [this, uid = std::move(upload_id),
                       wph = std::move(winner_pool_hash), store_data_map] {
                          return client_.finalize_merkle_upload(uid, wph, store_data_map);
                      });
}

}  // namespace antd
