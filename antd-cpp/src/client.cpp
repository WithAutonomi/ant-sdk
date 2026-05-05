#include "antd/client.hpp"

#include <nlohmann/json.hpp>
#include <httplib.h>

#include "base64.hpp"

namespace antd {

using json = nlohmann::json;

// ---------------------------------------------------------------------------
// Impl (pimpl hides httplib from the public header)
// ---------------------------------------------------------------------------

struct Client::Impl {
    httplib::Client http;
    std::string base_url;

    Impl(const std::string& base_url, int timeout_seconds)
        : http(base_url), base_url(base_url) {
        http.set_connection_timeout(timeout_seconds);
        http.set_read_timeout(timeout_seconds);
        http.set_write_timeout(timeout_seconds);
    }

    // --- internal helpers ---

    /// Perform a JSON request. Returns parsed JSON and the status code.
    /// Throws on HTTP error status codes.
    json do_json(const std::string& method, const std::string& path,
                 const json& body = json()) {
        httplib::Result res{nullptr, httplib::Error::Unknown};
        std::string body_str;
        std::string content_type = "application/json";

        if (!body.is_null()) {
            body_str = body.dump();
        }

        if (method == "GET") {
            res = http.Get(path);
        } else if (method == "POST") {
            res = http.Post(path, body_str, content_type);
        } else if (method == "PUT") {
            res = http.Put(path, body_str, content_type);
        }

        if (!res) {
            throw AntdError(0, "HTTP request failed: connection error");
        }

        if (res->status < 200 || res->status >= 300) {
            std::string msg = res->body;
            try {
                auto err_json = json::parse(res->body);
                if (err_json.contains("error") && err_json["error"].is_string()) {
                    msg = err_json["error"].get<std::string>();
                }
            } catch (...) {
                // Use raw body as message.
            }
            error_for_status(res->status, msg);
        }

        if (res->body.empty()) {
            return json::object();
        }

        return json::parse(res->body);
    }

    /// Perform a HEAD request, returning the status code.
    int do_head(const std::string& path) {
        auto res = http.Head(path);
        if (!res) {
            throw AntdError(0, "HTTP HEAD request failed: connection error");
        }
        return res->status;
    }
};

// ---------------------------------------------------------------------------
// Client lifetime
// ---------------------------------------------------------------------------

Client::Client(const std::string& base_url, int timeout_seconds)
    : impl_(std::make_unique<Impl>(base_url, timeout_seconds)) {}

Client::~Client() = default;
Client::Client(Client&&) noexcept = default;
Client& Client::operator=(Client&&) noexcept = default;

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

HealthStatus Client::health() {
    auto j = impl_->do_json("GET", "/health");
    return HealthStatus{
        .ok = j.value("status", "") == "ok",
        .network = j.value("network", ""),
        .version = j.value("version", ""),
        .evm_network = j.value("evm_network", ""),
        .uptime_seconds = j.value<std::uint64_t>("uptime_seconds", 0),
        .build_commit = j.value("build_commit", ""),
        .payment_token_address = j.value("payment_token_address", ""),
        .payment_vault_address = j.value("payment_vault_address", ""),
    };
}

// ---------------------------------------------------------------------------
// Data (Immutable)
// ---------------------------------------------------------------------------

PutResult Client::data_put_public(const std::vector<uint8_t>& data, const std::string& payment_mode) {
    json body = {{"data", detail::base64_encode(data)}};
    if (!payment_mode.empty()) {
        body["payment_mode"] = payment_mode;
    }
    auto j = impl_->do_json("POST", "/v1/data/public", body);
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

std::vector<uint8_t> Client::data_get_public(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/data/public/" + std::string(address));
    return detail::base64_decode(j.value("data", ""));
}

PutResult Client::data_put_private(const std::vector<uint8_t>& data, const std::string& payment_mode) {
    json body = {{"data", detail::base64_encode(data)}};
    if (!payment_mode.empty()) {
        body["payment_mode"] = payment_mode;
    }
    auto j = impl_->do_json("POST", "/v1/data/private", body);
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("data_map", ""),
    };
}

static std::string url_encode(std::string_view value) {
    std::string encoded;
    encoded.reserve(value.size());
    for (unsigned char c : value) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            encoded += static_cast<char>(c);
        } else {
            char buf[4];
            std::snprintf(buf, sizeof(buf), "%%%02X", c);
            encoded += buf;
        }
    }
    return encoded;
}

std::vector<uint8_t> Client::data_get_private(std::string_view data_map) {
    auto j = impl_->do_json("GET",
        "/v1/data/private?data_map=" + url_encode(data_map));
    return detail::base64_decode(j.value("data", ""));
}

UploadCostEstimate Client::data_cost(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/data/cost", json{
        {"data", detail::base64_encode(data)},
    });
    return UploadCostEstimate{
        j.value("cost", std::string{}),
        j.value("file_size", uint64_t{0}),
        j.value("chunk_count", uint32_t{0}),
        j.value("estimated_gas_cost_wei", std::string{}),
        j.value("payment_mode", std::string{}),
    };
}

// ---------------------------------------------------------------------------
// Chunks
// ---------------------------------------------------------------------------

PutResult Client::chunk_put(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/chunks", json{
        {"data", detail::base64_encode(data)},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

std::vector<uint8_t> Client::chunk_get(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/chunks/" + std::string(address));
    return detail::base64_decode(j.value("data", ""));
}

// ---------------------------------------------------------------------------
// Files & Directories
// ---------------------------------------------------------------------------

FileUploadResult Client::file_upload_public(std::string_view path, const std::string& payment_mode) {
    json body = {{"path", std::string(path)}};
    if (!payment_mode.empty()) {
        body["payment_mode"] = payment_mode;
    }
    auto j = impl_->do_json("POST", "/v1/files/upload/public", body);
    return FileUploadResult{
        .address = j.value("address", ""),
        .storage_cost_atto = j.value("storage_cost_atto", ""),
        .gas_cost_wei = j.value("gas_cost_wei", ""),
        .chunks_stored = j.value<uint64_t>("chunks_stored", 0),
        .payment_mode_used = j.value("payment_mode_used", ""),
    };
}

void Client::file_download_public(std::string_view address, std::string_view dest_path) {
    impl_->do_json("POST", "/v1/files/download/public", json{
        {"address", std::string(address)},
        {"dest_path", std::string(dest_path)},
    });
}

FileUploadResult Client::dir_upload_public(std::string_view path, const std::string& payment_mode) {
    json body = {{"path", std::string(path)}};
    if (!payment_mode.empty()) {
        body["payment_mode"] = payment_mode;
    }
    auto j = impl_->do_json("POST", "/v1/dirs/upload/public", body);
    return FileUploadResult{
        .address = j.value("address", ""),
        .storage_cost_atto = j.value("storage_cost_atto", ""),
        .gas_cost_wei = j.value("gas_cost_wei", ""),
        .chunks_stored = j.value<uint64_t>("chunks_stored", 0),
        .payment_mode_used = j.value("payment_mode_used", ""),
    };
}

void Client::dir_download_public(std::string_view address, std::string_view dest_path) {
    impl_->do_json("POST", "/v1/dirs/download/public", json{
        {"address", std::string(address)},
        {"dest_path", std::string(dest_path)},
    });
}

UploadCostEstimate Client::file_cost(std::string_view path, bool is_public) {
    auto j = impl_->do_json("POST", "/v1/files/cost", json{
        {"path", std::string(path)},
        {"is_public", is_public},
    });
    return UploadCostEstimate{
        j.value("cost", std::string{}),
        j.value("file_size", uint64_t{0}),
        j.value("chunk_count", uint32_t{0}),
        j.value("estimated_gas_cost_wei", std::string{}),
        j.value("payment_mode", std::string{}),
    };
}

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

WalletAddress Client::wallet_address() {
    auto j = impl_->do_json("GET", "/v1/wallet/address");
    return WalletAddress{
        .address = j.value("address", ""),
    };
}

WalletBalance Client::wallet_balance() {
    auto j = impl_->do_json("GET", "/v1/wallet/balance");
    return WalletBalance{
        .balance = j.value("balance", ""),
        .gas_balance = j.value("gas_balance", ""),
    };
}

bool Client::wallet_approve() {
    auto j = impl_->do_json("POST", "/v1/wallet/approve", json::object());
    return j.value("approved", false);
}

// ---------------------------------------------------------------------------
// External Signer (Two-Phase Upload)
// ---------------------------------------------------------------------------

/// Parse a prepare-upload JSON response into PrepareUploadResult.
/// Handles both wave_batch and merkle payment types.
static PrepareUploadResult parse_prepare_response(const json& j) {
    PrepareUploadResult result;
    result.upload_id = j.value("upload_id", "");
    result.payment_type = j.value("payment_type", "");
    result.total_amount = j.value("total_amount", "");
    result.payment_vault_address = j.value("payment_vault_address", "");
    result.payment_token_address = j.value("payment_token_address", "");
    result.rpc_url = j.value("rpc_url", "");

    // Default to wave_batch for backward compatibility with older daemons
    if (result.payment_type.empty()) {
        result.payment_type = "wave_batch";
    }

    // Parse wave-batch payments
    if (j.contains("payments") && j["payments"].is_array()) {
        for (const auto& p : j["payments"]) {
            if (p.is_object()) {
                result.payments.push_back(PaymentInfo{
                    .quote_hash = p.value("quote_hash", ""),
                    .rewards_address = p.value("rewards_address", ""),
                    .amount = p.value("amount", ""),
                });
            }
        }
    }

    // Parse merkle fields
    if (result.payment_type == "merkle") {
        result.depth = j.value("depth", 0);
        result.merkle_payment_timestamp = j.value("merkle_payment_timestamp", uint64_t{0});

        if (j.contains("pool_commitments") && j["pool_commitments"].is_array()) {
            for (const auto& pc : j["pool_commitments"]) {
                if (!pc.is_object()) continue;
                PoolCommitmentEntry entry;
                entry.pool_hash = pc.value("pool_hash", "");
                if (pc.contains("candidates") && pc["candidates"].is_array()) {
                    for (const auto& c : pc["candidates"]) {
                        if (c.is_object()) {
                            entry.candidates.push_back(CandidateNodeEntry{
                                .rewards_address = c.value("rewards_address", ""),
                                .amount = c.value("amount", ""),
                            });
                        }
                    }
                }
                result.pool_commitments.push_back(std::move(entry));
            }
        }
    }

    return result;
}

PrepareUploadResult Client::prepare_upload(std::string_view path) {
    auto j = impl_->do_json("POST", "/v1/upload/prepare", json{
        {"path", std::string(path)},
    });
    return parse_prepare_response(j);
}

PrepareUploadResult Client::prepare_data_upload(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/data/prepare", json{
        {"data", detail::base64_encode(data)},
    });
    return parse_prepare_response(j);
}

FinalizeUploadResult Client::finalize_upload(std::string_view upload_id,
                                               const std::map<std::string, std::string>& tx_hashes,
                                               bool store_data_map) {
    json hashes = json::object();
    for (const auto& [k, v] : tx_hashes) {
        hashes[k] = v;
    }

    auto j = impl_->do_json("POST", "/v1/upload/finalize", json{
        {"upload_id", std::string(upload_id)},
        {"tx_hashes", hashes},
        {"store_data_map", store_data_map},
    });
    return FinalizeUploadResult{
        .data_map = j.value("data_map", ""),
        .address = j.value("address", ""),
        .chunks_stored = j.value("chunks_stored", int64_t{0}),
    };
}

FinalizeUploadResult Client::finalize_merkle_upload(std::string_view upload_id,
                                                      std::string_view winner_pool_hash,
                                                      bool store_data_map) {
    auto j = impl_->do_json("POST", "/v1/upload/finalize", json{
        {"upload_id", std::string(upload_id)},
        {"winner_pool_hash", std::string(winner_pool_hash)},
        {"store_data_map", store_data_map},
    });
    return FinalizeUploadResult{
        .data_map = j.value("data_map", ""),
        .address = j.value("address", ""),
        .chunks_stored = j.value("chunks_stored", int64_t{0}),
    };
}

}  // namespace antd
