#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>

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
// NOTE: Full integration tests require a running antd daemon.
// The tests above validate JSON parsing, base64, and error mapping
// without network access.
// ---------------------------------------------------------------------------
