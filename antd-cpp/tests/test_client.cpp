#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <thread>

#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/models.hpp"
#include "base64.hpp"

using json = nlohmann::json;

// ---------------------------------------------------------------------------
// Base64 encode / decode
// ---------------------------------------------------------------------------

TEST_CASE("base64 encode empty") {
    std::vector<uint8_t> data;
    CHECK(antd::detail::base64_encode(data).empty());
}

TEST_CASE("base64 round-trip") {
    std::string original = "Hello, Autonomi!";
    std::vector<uint8_t> data(original.begin(), original.end());

    auto encoded = antd::detail::base64_encode(data);
    CHECK(encoded == "SGVsbG8sIEF1dG9ub21pIQ==");

    auto decoded = antd::detail::base64_decode(encoded);
    std::string result(decoded.begin(), decoded.end());
    CHECK(result == original);
}

TEST_CASE("base64 round-trip various lengths") {
    // Test padding cases: length % 3 == 0, 1, 2
    for (size_t len : {0, 1, 2, 3, 4, 5, 6, 100, 255}) {
        std::vector<uint8_t> data(len);
        for (size_t i = 0; i < len; ++i) {
            data[i] = static_cast<uint8_t>(i & 0xFF);
        }
        auto encoded = antd::detail::base64_encode(data);
        auto decoded = antd::detail::base64_decode(encoded);
        CHECK(decoded == data);
    }
}

// ---------------------------------------------------------------------------
// PaymentMode wire serialization
// ---------------------------------------------------------------------------

TEST_CASE("payment_mode_wire serializes enum values") {
    CHECK(antd::payment_mode_wire(antd::PaymentMode::Auto) == "auto");
    CHECK(antd::payment_mode_wire(antd::PaymentMode::Merkle) == "merkle");
    CHECK(antd::payment_mode_wire(antd::PaymentMode::Single) == "single");
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

TEST_CASE("error_for_status throws correct types") {
    CHECK_THROWS_AS(antd::error_for_status(400, "bad"), antd::BadRequestError);
    CHECK_THROWS_AS(antd::error_for_status(402, "pay"), antd::PaymentError);
    CHECK_THROWS_AS(antd::error_for_status(404, "missing"), antd::NotFoundError);
    CHECK_THROWS_AS(antd::error_for_status(409, "exists"), antd::AlreadyExistsError);
    CHECK_THROWS_AS(antd::error_for_status(413, "big"), antd::TooLargeError);
    CHECK_THROWS_AS(antd::error_for_status(500, "oops"), antd::InternalError);
    CHECK_THROWS_AS(antd::error_for_status(502, "net"), antd::NetworkError);
    CHECK_THROWS_AS(antd::error_for_status(503, "unknown"), antd::AntdError);
}

TEST_CASE("error status_code is preserved") {
    try {
        antd::error_for_status(404, "not found");
        FAIL("should have thrown");
    } catch (const antd::NotFoundError& e) {
        CHECK(e.status_code == 404);
        CHECK(std::string(e.what()).find("not found") != std::string::npos);
    }
}

TEST_CASE("AntdError subtypes are catchable as AntdError") {
    try {
        antd::error_for_status(500, "boom");
        FAIL("should have thrown");
    } catch (const antd::AntdError& e) {
        CHECK(e.status_code == 500);
    }
}

// ---------------------------------------------------------------------------
// Model JSON parsing (manual, mirrors what client.cpp does)
// ---------------------------------------------------------------------------

TEST_CASE("HealthStatus from JSON") {
    auto j = json::parse(R"({
        "status":"ok",
        "network":"local",
        "version":"0.4.0",
        "evm_network":"local",
        "uptime_seconds":42,
        "build_commit":"abcdef123456",
        "payment_token_address":"0xtoken",
        "payment_vault_address":"0xvault"
    })");
    antd::HealthStatus h{
        .ok = j.value("status", "") == "ok",
        .network = j.value("network", ""),
        .version = j.value("version", ""),
        .evm_network = j.value("evm_network", ""),
        .uptime_seconds = j.value<std::uint64_t>("uptime_seconds", 0),
        .build_commit = j.value("build_commit", ""),
        .payment_token_address = j.value("payment_token_address", ""),
        .payment_vault_address = j.value("payment_vault_address", ""),
    };

    CHECK(h.ok);
    CHECK(h.network == "local");
    CHECK(h.version == "0.4.0");
    CHECK(h.evm_network == "local");
    CHECK(h.uptime_seconds == 42);
    CHECK(h.build_commit == "abcdef123456");
    CHECK(h.payment_token_address == "0xtoken");
    CHECK(h.payment_vault_address == "0xvault");
}

TEST_CASE("HealthStatus defaults populate when pre-0.4.0 daemon omits diagnostics") {
    auto j = json::parse(R"({"status":"ok","network":"default"})");
    antd::HealthStatus h{
        .ok = j.value("status", "") == "ok",
        .network = j.value("network", ""),
        .version = j.value("version", ""),
        .evm_network = j.value("evm_network", ""),
        .uptime_seconds = j.value<std::uint64_t>("uptime_seconds", 0),
        .build_commit = j.value("build_commit", ""),
        .payment_token_address = j.value("payment_token_address", ""),
        .payment_vault_address = j.value("payment_vault_address", ""),
    };

    CHECK(h.ok);
    CHECK(h.network == "default");
    CHECK(h.version.empty());
    CHECK(h.evm_network.empty());
    CHECK(h.uptime_seconds == 0);
    CHECK(h.build_commit.empty());
}

TEST_CASE("PutResult from JSON") {
    auto j = json::parse(R"({"cost":"100","address":"abc123"})");
    antd::PutResult r;
    r.cost = j.value("cost", "");
    r.address = j.value("address", "");

    CHECK(r.cost == "100");
    CHECK(r.address == "abc123");
}

// ---------------------------------------------------------------------------
// PrepareUploadResult: merkle payment parsing
// ---------------------------------------------------------------------------

TEST_CASE("PrepareUploadResult merkle from JSON") {
    auto j = json::parse(R"({
        "upload_id": "mup1",
        "payment_type": "merkle",
        "depth": 5,
        "merkle_payment_timestamp": 1712150400,
        "total_amount": "0",
        "payment_vault_address": "0xvault",
        "payment_token_address": "0xtoken",
        "rpc_url": "http://rpc.example.com",
        "total_chunks": 128,
        "already_stored_count": 4,
        "pool_commitments": [
            {
                "pool_hash": "0xaabbccdd",
                "candidates": [
                    {"rewards_address": "0x1111", "amount": "500"},
                    {"rewards_address": "0x2222", "amount": "600"}
                ]
            }
        ]
    })");

    // Simulate what parse_prepare_response does (mirrors client.cpp logic)
    antd::PrepareUploadResult r;
    r.upload_id = j.value("upload_id", "");
    r.payment_type = j.value("payment_type", "");
    r.total_amount = j.value("total_amount", "");
    r.payment_vault_address = j.value("payment_vault_address", "");
    r.payment_token_address = j.value("payment_token_address", "");
    r.rpc_url = j.value("rpc_url", "");
    r.total_chunks = j.value("total_chunks", uint64_t{0});
    r.already_stored_count = j.value("already_stored_count", uint64_t{0});

    if (r.payment_type.empty()) {
        r.payment_type = "wave_batch";
    }

    if (j.contains("payments") && j["payments"].is_array()) {
        for (const auto& p : j["payments"]) {
            if (p.is_object()) {
                r.payments.push_back(antd::PaymentInfo{
                    p.value("quote_hash", ""),
                    p.value("rewards_address", ""),
                    p.value("amount", ""),
                });
            }
        }
    }

    if (r.payment_type == "merkle") {
        r.depth = j.value("depth", 0);
        r.merkle_payment_timestamp = j.value("merkle_payment_timestamp", uint64_t{0});

        if (j.contains("pool_commitments") && j["pool_commitments"].is_array()) {
            for (const auto& pc : j["pool_commitments"]) {
                if (!pc.is_object()) continue;
                antd::PoolCommitmentEntry entry;
                entry.pool_hash = pc.value("pool_hash", "");
                if (pc.contains("candidates") && pc["candidates"].is_array()) {
                    for (const auto& c : pc["candidates"]) {
                        if (c.is_object()) {
                            entry.candidates.push_back(antd::CandidateNodeEntry{
                                c.value("rewards_address", ""),
                                c.value("amount", ""),
                            });
                        }
                    }
                }
                r.pool_commitments.push_back(std::move(entry));
            }
        }
    }

    CHECK(r.upload_id == "mup1");
    CHECK(r.payment_type == "merkle");
    CHECK(r.depth == 5);
    CHECK(r.merkle_payment_timestamp == 1712150400);
    CHECK(r.total_amount == "0");
    CHECK(r.payment_vault_address == "0xvault");
    CHECK(r.payment_token_address == "0xtoken");
    CHECK(r.rpc_url == "http://rpc.example.com");
    CHECK(r.payments.empty());
    // already-stored preflight (added in antd 0.10.0)
    CHECK(r.total_chunks == 128);
    CHECK(r.already_stored_count == 4);

    REQUIRE(r.pool_commitments.size() == 1);
    CHECK(r.pool_commitments[0].pool_hash == "0xaabbccdd");
    REQUIRE(r.pool_commitments[0].candidates.size() == 2);
    CHECK(r.pool_commitments[0].candidates[0].rewards_address == "0x1111");
    CHECK(r.pool_commitments[0].candidates[0].amount == "500");
    CHECK(r.pool_commitments[0].candidates[1].rewards_address == "0x2222");
    CHECK(r.pool_commitments[0].candidates[1].amount == "600");
}

TEST_CASE("PrepareUploadResult merkle finalize JSON") {
    // Verify finalize_merkle_upload request body structure
    json body = {
        {"upload_id", "mup1"},
        {"winner_pool_hash", "0xwinnerhash"},
        {"store_data_map", true},
    };

    CHECK(body["upload_id"] == "mup1");
    CHECK(body["winner_pool_hash"] == "0xwinnerhash");
    CHECK(body["store_data_map"] == true);

    // Verify response parsing
    auto resp = json::parse(R"({
        "data_map": "dm_merkle",
        "address": "0xaddr",
        "chunks_stored": 100
    })");

    antd::FinalizeUploadResult fr;
    fr.data_map = resp.value("data_map", "");
    fr.address = resp.value("address", "");
    fr.chunks_stored = resp.value("chunks_stored", int64_t{0});

    CHECK(fr.data_map == "dm_merkle");
    CHECK(fr.address == "0xaddr");
    CHECK(fr.chunks_stored == 100);
}

TEST_CASE("PrepareUploadResult backward compat - no payment_type defaults to wave_batch") {
    // Older daemons do not return payment_type; should default to wave_batch
    auto j = json::parse(R"({
        "upload_id": "up_old",
        "total_amount": "5000",
        "payment_vault_address": "0xvault",
        "payment_token_address": "0xtoken",
        "rpc_url": "http://rpc.old.com",
        "payments": [
            {"quote_hash": "qh1", "rewards_address": "0xr1", "amount": "2500"},
            {"quote_hash": "qh2", "rewards_address": "0xr2", "amount": "2500"}
        ]
    })");

    antd::PrepareUploadResult r;
    r.upload_id = j.value("upload_id", "");
    r.payment_type = j.value("payment_type", "");
    r.total_amount = j.value("total_amount", "");
    r.payment_vault_address = j.value("payment_vault_address", "");
    r.payment_token_address = j.value("payment_token_address", "");
    r.rpc_url = j.value("rpc_url", "");
    r.total_chunks = j.value("total_chunks", uint64_t{0});
    r.already_stored_count = j.value("already_stored_count", uint64_t{0});

    if (r.payment_type.empty()) {
        r.payment_type = "wave_batch";
    }

    if (j.contains("payments") && j["payments"].is_array()) {
        for (const auto& p : j["payments"]) {
            if (p.is_object()) {
                r.payments.push_back(antd::PaymentInfo{
                    p.value("quote_hash", ""),
                    p.value("rewards_address", ""),
                    p.value("amount", ""),
                });
            }
        }
    }

    CHECK(r.payment_type == "wave_batch");
    CHECK(r.upload_id == "up_old");
    CHECK(r.total_amount == "5000");
    CHECK(r.payment_vault_address == "0xvault");
    REQUIRE(r.payments.size() == 2);
    CHECK(r.payments[0].quote_hash == "qh1");
    CHECK(r.payments[1].quote_hash == "qh2");

    // Merkle fields should be at defaults
    CHECK(r.depth == 0);
    CHECK(r.merkle_payment_timestamp == 0);
    CHECK(r.pool_commitments.empty());
}

TEST_CASE("FinalizeUploadResult data_map field") {
    // Verify the data_map field is present on FinalizeUploadResult
    antd::FinalizeUploadResult fr;
    fr.data_map = "0xdeadbeef";
    fr.address = "";
    fr.chunks_stored = 42;

    CHECK(fr.data_map == "0xdeadbeef");
    CHECK(fr.address.empty());
    CHECK(fr.chunks_stored == 42);
}

// ---------------------------------------------------------------------------
// Stub-server end-to-end tests
//
// Spin up an in-process httplib::Server on an ephemeral port and drive the
// real antd::Client against it. This exercises both the request-body shape
// (e.g. visibility forwarding, payment_mode propagation) and the
// response-parsing path (e.g. data_map_address surfacing,
// prepare_chunk_upload's two branches).
// ---------------------------------------------------------------------------

namespace {

struct StubServer {
    httplib::Server svr;
    std::thread th;
    int port{0};

    // Captured request bodies, keyed by route.
    json last_prepare_body = json::object();
    json last_chunk_prepare_body = json::object();
    json last_chunk_finalize_body = json::object();
    json last_finalize_body = json::object();
    json last_data_put_body = json::object();
    json last_data_put_public_body = json::object();
    json last_data_get_body = json::object();
    json last_data_cost_body = json::object();
    json last_file_put_body = json::object();
    json last_file_put_public_body = json::object();
    json last_file_get_body = json::object();
    json last_file_get_public_body = json::object();
    json last_file_cost_body = json::object();

    StubServer() {
        // Data put public
        svr.Post("/v1/data/public", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_data_put_public_body = json::parse(req.body); } catch (...) {}
            json resp = {
                {"address", "addr_pub_abc"},
                {"chunks_stored", 3},
                {"payment_mode_used", "single"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // Data get public
        svr.Get("/v1/data/public/addr_pub_abc",
            [](const httplib::Request&, httplib::Response& res) {
                json resp = {{"data", "aGVsbG8="}}; // base64("hello")
                res.set_content(resp.dump(), "application/json");
            });

        // Data put private
        svr.Post("/v1/data", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_data_put_body = json::parse(req.body); } catch (...) {}
            json resp = {
                {"data_map", "dm_priv_xyz"},
                {"chunks_stored", 2},
                {"payment_mode_used", "merkle"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // Data get private
        svr.Post("/v1/data/get", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_data_get_body = json::parse(req.body); } catch (...) {}
            json resp = {{"data", "c2VjcmV0"}}; // base64("secret")
            res.set_content(resp.dump(), "application/json");
        });

        // Data stream public (streaming counterpart to data get public).
        // Default: raw decrypted bytes with a Content-Length. With
        // Accept: application/x-ndjson, interleaved NDJSON progress framing
        // (meta -> progress -> data, base64 under key "chunk").
        svr.Get("/v1/data/public/addr_pub_abc/stream",
            [](const httplib::Request& req, httplib::Response& res) {
                if (req.get_header_value("Accept") == "application/x-ndjson") {
                    std::string ndjson;
                    ndjson += json{{"type", "meta"}, {"total_size", 5}}.dump() + "\n";
                    ndjson += json{{"type", "progress"}, {"phase", "fetching"},
                                   {"fetched", 1}, {"total", 1}}.dump() + "\n";
                    ndjson += json{{"type", "data"}, {"chunk", "aGVsbG8="}}.dump() + "\n";
                    res.set_content(ndjson, "application/x-ndjson");
                    return;
                }
                res.set_content("hello", "application/octet-stream");
            });

        // Data stream public — missing address returns a JSON error body.
        svr.Get("/v1/data/public/addr_missing/stream",
            [](const httplib::Request&, httplib::Response& res) {
                res.status = 404;
                json err = {{"error", "record not found"}, {"code", "not_found"}};
                res.set_content(err.dump(), "application/json");
            });

        // Data stream public — NDJSON terminal error frame. A 200 stream that
        // signals failure mid-body via {"type":"error"} (raw octet-stream
        // cannot signal this once bytes have flowed).
        svr.Get("/v1/data/public/addr_errframe/stream",
            [](const httplib::Request&, httplib::Response& res) {
                std::string ndjson;
                ndjson += json{{"type", "meta"}, {"total_size", 0}}.dump() + "\n";
                ndjson += json{{"type", "error"},
                               {"message", "chunk fetch failed"}}.dump() + "\n";
                res.set_content(ndjson, "application/x-ndjson");
            });

        // Data stream private (streaming counterpart to data get). Same body
        // shape as POST /v1/data/get: {"data_map": "<hex>"}. With
        // Accept: application/x-ndjson, interleaved NDJSON progress framing.
        svr.Post("/v1/data/stream", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_data_get_body = json::parse(req.body); } catch (...) {}
            if (req.get_header_value("Accept") == "application/x-ndjson") {
                std::string ndjson;
                ndjson += json{{"type", "meta"}, {"total_size", 6}}.dump() + "\n";
                ndjson += json{{"type", "progress"}, {"phase", "resolving_map"},
                               {"fetched", 0}, {"total", 0}}.dump() + "\n";
                ndjson += json{{"type", "progress"}, {"phase", "fetching"},
                               {"fetched", 1}, {"total", 1}}.dump() + "\n";
                ndjson += json{{"type", "data"}, {"chunk", "c2VjcmV0"}}.dump() + "\n";
                res.set_content(ndjson, "application/x-ndjson");
                return;
            }
            res.set_content("secret", "application/octet-stream");
        });

        // Data cost
        svr.Post("/v1/data/cost", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_data_cost_body = json::parse(req.body); } catch (...) {}
            json resp = {
                {"cost", "50"},
                {"file_size", 4},
                {"chunk_count", 3},
                {"estimated_gas_cost_wei", "150"},
                {"payment_mode", "single"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // File put public
        svr.Post("/v1/files/public", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_file_put_public_body = json::parse(req.body); } catch (...) {}
            json resp = {
                {"address", "file_pub_addr"},
                {"storage_cost_atto", "1000"},
                {"gas_cost_wei", "42"},
                {"chunks_stored", 5},
                {"payment_mode_used", "auto"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // File get public
        svr.Post("/v1/files/public/get",
            [this](const httplib::Request& req, httplib::Response& res) {
                try { last_file_get_public_body = json::parse(req.body); } catch (...) {}
                res.set_content("{}", "application/json");
            });

        // File put private
        svr.Post("/v1/files", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_file_put_body = json::parse(req.body); } catch (...) {}
            json resp = {
                {"data_map", "fdm_xyz"},
                {"storage_cost_atto", "900"},
                {"gas_cost_wei", "42"},
                {"chunks_stored", 4},
                {"payment_mode_used", "merkle"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // File get private
        svr.Post("/v1/files/get",
            [this](const httplib::Request& req, httplib::Response& res) {
                try { last_file_get_body = json::parse(req.body); } catch (...) {}
                res.set_content("{}", "application/json");
            });

        // File cost
        svr.Post("/v1/files/cost", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_file_cost_body = json::parse(req.body); } catch (...) {}
            json resp = {
                {"cost", "1000"},
                {"file_size", 4096},
                {"chunk_count", 3},
                {"estimated_gas_cost_wei", "150"},
                {"payment_mode", "auto"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // /v1/upload/prepare — stash body so tests can assert visibility was
        // forwarded; return a wave_batch with deterministic upload_id.
        svr.Post("/v1/upload/prepare", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                last_prepare_body = json::parse(req.body);
            } catch (...) {
                last_prepare_body = json::object();
            }
            json resp = {
                {"upload_id", "up_wave_1"},
                {"payment_type", "wave_batch"},
                {"payments", json::array({{
                    {"quote_hash", "qh1"},
                    {"rewards_address", "0xR1"},
                    {"amount", "100"},
                }})},
                {"total_amount", "100"},
                {"payment_vault_address", "0xDP"},
                {"payment_token_address", "0xTK"},
                {"rpc_url", "http://rpc.local"},
            };
            res.set_content(resp.dump(), "application/json");
        });

        // /v1/upload/finalize — echo data_map_address only when the prior
        // prepare was public, mirroring the daemon's behaviour.
        svr.Post("/v1/upload/finalize", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                last_finalize_body = json::parse(req.body);
            } catch (...) {
                last_finalize_body = json::object();
            }
            json resp = {
                {"data_map", "deadbeef"},
                {"address", "0xFINAL"},
                {"chunks_stored", 42},
            };
            if (last_prepare_body.value("visibility", "") == "public") {
                resp["data_map_address"] = "0xDMAP";
            }
            res.set_content(resp.dump(), "application/json");
        });

        // /v1/chunks/prepare — branch on the decoded payload prefix so a single
        // handler exercises both already_stored and wave_batch shapes.
        svr.Post("/v1/chunks/prepare", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                last_chunk_prepare_body = json::parse(req.body);
            } catch (...) {
                last_chunk_prepare_body = json::object();
            }
            std::string data_b64 = last_chunk_prepare_body.value("data", "");
            auto decoded = antd::detail::base64_decode(data_b64);
            std::string decoded_str(decoded.begin(), decoded.end());

            json resp;
            if (decoded_str.rfind("already_", 0) == 0) {
                resp = {
                    {"address", "addr_already_stored"},
                    {"already_stored", true},
                };
            } else {
                resp = {
                    {"address", "addr_chunk_new"},
                    {"already_stored", false},
                    {"upload_id", "chunk_up_1"},
                    {"payment_type", "wave_batch"},
                    {"payments", json::array({{
                        {"quote_hash", "qhC"},
                        {"rewards_address", "0xRC"},
                        {"amount", "7"},
                    }})},
                    {"total_amount", "7"},
                    {"payment_vault_address", "0xVC"},
                    {"payment_token_address", "0xTC"},
                    {"rpc_url", "http://rpc.local"},
                };
            }
            res.set_content(resp.dump(), "application/json");
        });

        svr.Post("/v1/chunks/finalize", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                last_chunk_finalize_body = json::parse(req.body);
            } catch (...) {
                last_chunk_finalize_body = json::object();
            }
            json resp = {{"address", "addr_chunk_new"}};
            res.set_content(resp.dump(), "application/json");
        });

        port = svr.bind_to_any_port("127.0.0.1");
        th = std::thread([this] { svr.listen_after_bind(); });

        // Wait until the server is actually listening.
        for (int i = 0; i < 100; ++i) {
            if (svr.is_running()) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    ~StubServer() {
        svr.stop();
        if (th.joinable()) th.join();
    }

    std::string base_url() const {
        return "http://127.0.0.1:" + std::to_string(port);
    }
};

}  // namespace

TEST_CASE("data_put_public surfaces new result fields and forwards payment_mode") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::vector<uint8_t> data{'h','e','l','l','o'};
    auto r = c.data_put_public(data, antd::PaymentMode::Merkle);

    CHECK(r.address == "addr_pub_abc");
    CHECK(r.chunks_stored == 3);
    CHECK(r.payment_mode_used == "single");
    CHECK(stub.last_data_put_public_body.value("payment_mode", "") == "merkle");
}

TEST_CASE("data_put_public defaults to auto payment_mode") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::vector<uint8_t> data{'x'};
    c.data_put_public(data);
    CHECK(stub.last_data_put_public_body.value("payment_mode", "") == "auto");
}

TEST_CASE("data_put returns DataPutResult and forwards payment_mode") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::vector<uint8_t> data{'s','e','c','r','e','t'};
    auto r = c.data_put(data, antd::PaymentMode::Merkle);

    CHECK(r.data_map == "dm_priv_xyz");
    CHECK(r.chunks_stored == 2);
    CHECK(r.payment_mode_used == "merkle");
    CHECK(stub.last_data_put_body.value("payment_mode", "") == "merkle");
}

TEST_CASE("data_get POSTs data_map and returns bytes") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    auto bytes = c.data_get("dm_priv_xyz");
    std::string text(bytes.begin(), bytes.end());

    CHECK(text == "secret");
    CHECK(stub.last_data_get_body.value("data_map", "") == "dm_priv_xyz");
}

TEST_CASE("data_stream POSTs data_map and streams bytes to the sink") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::string received;
    c.data_stream("dm_priv_xyz", [&](const char* data, std::size_t len) {
        received.append(data, len);
        return true;
    });

    CHECK(received == "secret");
    CHECK(stub.last_data_get_body.value("data_map", "") == "dm_priv_xyz");
}

TEST_CASE("data_stream_public GETs the /stream route and streams bytes") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::string received;
    c.data_stream_public("addr_pub_abc", [&](const char* data, std::size_t len) {
        received.append(data, len);
        return true;
    });

    CHECK(received == "hello");
}

TEST_CASE("data_stream_public parses {\"error\"} on non-2xx") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::string received;
    auto sink = [&](const char* data, std::size_t len) {
        received.append(data, len);
        return true;
    };

    CHECK_THROWS_AS(c.data_stream_public("addr_missing", sink), antd::NotFoundError);
    // The error body must not leak into the caller's sink.
    CHECK(received.empty());

    try {
        c.data_stream_public("addr_missing", sink);
    } catch (const antd::NotFoundError& e) {
        CHECK(std::string(e.what()).find("record not found") != std::string::npos);
    }
}

TEST_CASE("data_stream sink returning false aborts the download") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::string received;
    // Stop after the first chunk by returning false.
    c.data_stream("dm_priv_xyz", [&](const char* data, std::size_t len) {
        received.append(data, len);
        return false;
    });

    // No throw; we simply stopped consuming. Body is small so we still got it.
    CHECK(received == "secret");
}

// ---------------------------------------------------------------------------
// V2-512: progress-enabled streaming downloads (NDJSON framing).
// ---------------------------------------------------------------------------

TEST_CASE("data_stream_with_progress yields progress then data frames") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::vector<antd::DownloadProgress> progress;
    std::string received;
    std::vector<std::uint64_t> meta;
    std::size_t meta_index = SIZE_MAX;  // position of the first meta frame
    std::size_t frame_index = 0;
    c.data_stream_with_progress("dm_priv_xyz", [&](const antd::DownloadFrame& f) {
        if (f.is_meta()) {
            if (meta.empty()) meta_index = frame_index;
            meta.push_back(*f.total_size);
        } else if (f.is_progress()) {
            progress.push_back(*f.progress);
        } else {
            received.append(f.data->begin(), f.data->end());
        }
        ++frame_index;
        return true;
    });

    // The byte total surfaces first, as a single leading Meta frame; then two
    // progress frames + one data frame.
    REQUIRE(meta.size() == 1);
    CHECK(meta_index == 0);
    CHECK(meta[0] == 6);
    REQUIRE(progress.size() == 2);
    CHECK(progress[0].phase == "resolving_map");
    CHECK(progress[1].phase == "fetching");
    CHECK(progress[1].fetched == 1);
    CHECK(progress[1].total == 1);
    CHECK(received == "secret");
    // Request opted into NDJSON and still carried the data_map body.
    CHECK(stub.last_data_get_body.value("data_map", "") == "dm_priv_xyz");
}

TEST_CASE("data_stream_public_with_progress yields progress then data frames") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    bool saw_progress = false;
    std::string received;
    std::optional<std::uint64_t> first_total;  // set by the first frame if Meta
    bool first_frame = true;
    c.data_stream_public_with_progress("addr_pub_abc", [&](const antd::DownloadFrame& f) {
        if (first_frame) {
            first_frame = false;
            if (f.is_meta()) first_total = *f.total_size;
        }
        if (f.is_meta()) {
            // Meta carries the byte total; nothing else to accumulate.
        } else if (f.is_progress()) {
            saw_progress = true;
            CHECK(f.progress->phase == "fetching");
        } else {
            received.append(f.data->begin(), f.data->end());
        }
        return true;
    });

    // The byte total (5) leads, before any progress/data frame.
    REQUIRE(first_total.has_value());
    CHECK(*first_total == 5);
    CHECK(saw_progress);
    CHECK(received == "hello");
}

TEST_CASE("data_stream_with_progress surfaces a terminal error frame") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    auto sink = [&](const antd::DownloadFrame&) { return true; };
    // The {"type":"error"} frame throws out of the parser as an InternalError
    // (mapped from status 500), even though the HTTP response was 200.
    CHECK_THROWS_AS(
        c.data_stream_public_with_progress("addr_errframe", sink),
        antd::InternalError);

    try {
        c.data_stream_public_with_progress("addr_errframe", sink);
    } catch (const antd::AntdError& e) {
        CHECK(std::string(e.what()).find("chunk fetch failed") != std::string::npos);
    }
}

TEST_CASE("data_stream_with_progress sink returning false aborts the download") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    int frames = 0;
    c.data_stream_with_progress("dm_priv_xyz", [&](const antd::DownloadFrame&) {
        ++frames;
        return false;  // abort after the first frame
    });

    CHECK(frames == 1);
}

TEST_CASE("data_cost forwards payment_mode") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::vector<uint8_t> data{'t','e','s','t'};
    auto est = c.data_cost(data, antd::PaymentMode::Single);

    CHECK(est.cost == "50");
    CHECK(est.chunk_count == 3);
    CHECK(est.payment_mode == "single");
    CHECK(stub.last_data_cost_body.value("payment_mode", "") == "single");
}

TEST_CASE("file_put_public surfaces new fields and forwards payment_mode") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    auto r = c.file_put_public("/tmp/x.dat");

    CHECK(r.address == "file_pub_addr");
    CHECK(r.storage_cost_atto == "1000");
    CHECK(r.chunks_stored == 5);
    CHECK(r.payment_mode_used == "auto");
    CHECK(stub.last_file_put_public_body.value("payment_mode", "") == "auto");
}

TEST_CASE("file_get_public POSTs to /v1/files/public/get") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    c.file_get_public("file_pub_addr", "/tmp/out.dat");
    CHECK(stub.last_file_get_public_body.value("address", "") == "file_pub_addr");
    CHECK(stub.last_file_get_public_body.value("dest_path", "") == "/tmp/out.dat");
}

TEST_CASE("file_put POSTs to /v1/files and returns FilePutResult") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    auto r = c.file_put("/tmp/y.dat", antd::PaymentMode::Merkle);

    CHECK(r.data_map == "fdm_xyz");
    CHECK(r.storage_cost_atto == "900");
    CHECK(r.chunks_stored == 4);
    CHECK(r.payment_mode_used == "merkle");
    CHECK(stub.last_file_put_body.value("payment_mode", "") == "merkle");
}

TEST_CASE("file_get POSTs data_map and dest_path") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    c.file_get("fdm_xyz", "/tmp/private-out.dat");
    CHECK(stub.last_file_get_body.value("data_map", "") == "fdm_xyz");
    CHECK(stub.last_file_get_body.value("dest_path", "") == "/tmp/private-out.dat");
}

TEST_CASE("file_cost forwards payment_mode and is_public") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    auto est = c.file_cost("/tmp/z.dat", true, antd::PaymentMode::Single);
    CHECK(est.cost == "1000");
    CHECK(stub.last_file_cost_body.value("payment_mode", "") == "single");
    CHECK(stub.last_file_cost_body.value("is_public", false) == true);
}

TEST_CASE("prepare_upload_public forwards visibility=public and finalize surfaces data_map_address") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    auto prep = c.prepare_upload_public("/tmp/file.dat");
    CHECK(prep.upload_id == "up_wave_1");
    CHECK(stub.last_prepare_body.value("visibility", "") == "public");
    CHECK(stub.last_prepare_body.value("path", "") == "/tmp/file.dat");

    auto fin = c.finalize_upload("up_wave_1", {{"qh1", "tx1"}}, /*store_data_map=*/false);
    CHECK(fin.data_map == "deadbeef");
    CHECK(fin.address == "0xFINAL");
    CHECK(fin.data_map_address == "0xDMAP");
    CHECK(fin.chunks_stored == 42);
}

TEST_CASE("prepare_upload omits visibility when nullopt and finalize leaves data_map_address empty") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    c.prepare_upload("/tmp/file.dat");  // default: std::nullopt
    CHECK(stub.last_prepare_body.contains("visibility") == false);

    auto fin = c.finalize_upload("up_wave_1", {{"qh1", "tx1"}});
    CHECK(fin.data_map_address.empty());
}

TEST_CASE("prepare_upload with explicit visibility=private forwards the field") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    c.prepare_upload("/tmp/file.dat", std::string("private"));
    CHECK(stub.last_prepare_body.value("visibility", "") == "private");
}

TEST_CASE("prepare_chunk_upload already-stored branch omits payment fields") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::string payload = "already_chunk_data";
    std::vector<uint8_t> data(payload.begin(), payload.end());
    auto r = c.prepare_chunk_upload(data);

    CHECK(r.address == "addr_already_stored");
    CHECK(r.already_stored == true);
    CHECK(r.upload_id.empty());
    CHECK(r.payments.empty());
    CHECK(r.total_amount.empty());
    CHECK(r.payment_vault_address.empty());
}

TEST_CASE("prepare_chunk_upload wave_batch branch returns payment intent") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::string payload = "fresh_chunk_data";
    std::vector<uint8_t> data(payload.begin(), payload.end());
    auto r = c.prepare_chunk_upload(data);

    CHECK(r.already_stored == false);
    CHECK(r.address == "addr_chunk_new");
    CHECK(r.upload_id == "chunk_up_1");
    CHECK(r.payment_type == "wave_batch");
    REQUIRE(r.payments.size() == 1);
    CHECK(r.payments[0].quote_hash == "qhC");
    CHECK(r.payments[0].rewards_address == "0xRC");
    CHECK(r.payments[0].amount == "7");
    CHECK(r.total_amount == "7");
    CHECK(r.payment_vault_address == "0xVC");
    CHECK(r.payment_token_address == "0xTC");
    CHECK(r.rpc_url == "http://rpc.local");
}

TEST_CASE("finalize_chunk_upload forwards upload_id + tx_hashes and returns address") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    std::map<std::string, std::string> tx{{"qhC", "tx_C"}};
    auto addr = c.finalize_chunk_upload("chunk_up_1", tx);

    CHECK(addr == "addr_chunk_new");
    CHECK(stub.last_chunk_finalize_body.value("upload_id", "") == "chunk_up_1");
    REQUIRE(stub.last_chunk_finalize_body.contains("tx_hashes"));
    CHECK(stub.last_chunk_finalize_body["tx_hashes"].value("qhC", "") == "tx_C");
}

// ---------------------------------------------------------------------------
// NOTE: Full integration tests require a running antd daemon.
// The stub-server tests above exercise the actual Client request/response
// path. The pure-parse tests earlier in this file are kept for fast feedback
// when the network stack is unavailable.
// ---------------------------------------------------------------------------
