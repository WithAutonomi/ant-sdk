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
    auto j = json::parse(R"({"status":"ok","network":"local"})");
    antd::HealthStatus h;
    h.ok = j.value("status", "") == "ok";
    h.network = j.value("network", "");

    CHECK(h.ok);
    CHECK(h.network == "local");
}

TEST_CASE("PutResult from JSON") {
    auto j = json::parse(R"({"cost":"100","address":"abc123"})");
    antd::PutResult r;
    r.cost = j.value("cost", "");
    r.address = j.value("address", "");

    CHECK(r.cost == "100");
    CHECK(r.address == "abc123");
}

TEST_CASE("GraphEntry from JSON") {
    auto j = json::parse(R"({
        "owner":"owner1",
        "parents":["p1","p2"],
        "content":"abc",
        "descendants":[{"public_key":"pk1","content":"desc1"}]
    })");

    antd::GraphEntry entry;
    entry.owner = j.value("owner", "");
    entry.content = j.value("content", "");
    for (const auto& p : j["parents"]) {
        entry.parents.push_back(p.get<std::string>());
    }
    for (const auto& d : j["descendants"]) {
        entry.descendants.push_back(antd::GraphDescendant{
            d.value("public_key", ""),
            d.value("content", ""),
        });
    }

    CHECK(entry.owner == "owner1");
    CHECK(entry.parents.size() == 2);
    CHECK(entry.parents[0] == "p1");
    CHECK(entry.content == "abc");
    CHECK(entry.descendants.size() == 1);
    CHECK(entry.descendants[0].public_key == "pk1");
}

TEST_CASE("Archive from JSON") {
    auto j = json::parse(R"({
        "entries":[{
            "path":"test.txt","address":"abc",
            "created":1000,"modified":2000,"size":42
        }]
    })");

    antd::Archive archive;
    for (const auto& e : j["entries"]) {
        archive.entries.push_back(antd::ArchiveEntry{
            e.value("path", ""),
            e.value("address", ""),
            e.value("created", int64_t{0}),
            e.value("modified", int64_t{0}),
            e.value("size", int64_t{0}),
        });
    }

    CHECK(archive.entries.size() == 1);
    CHECK(archive.entries[0].path == "test.txt");
    CHECK(archive.entries[0].created == 1000);
    CHECK(archive.entries[0].size == 42);
}

// ---------------------------------------------------------------------------
// NOTE: Full integration tests require a running antd daemon.
// The tests above validate JSON parsing, base64, and error mapping
// without network access.
// ---------------------------------------------------------------------------
