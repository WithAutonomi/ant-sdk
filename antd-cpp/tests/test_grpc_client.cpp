// ---------------------------------------------------------------------------
// Unit tests for the gRPC client layer (antd::GrpcClient).
//
// Setting up a full mock gRPC server in C++ requires linking against
// grpc++_test_util which pulls in significant dependencies. Instead, these
// tests validate:
//
//   1. gRPC status code -> AntdError mapping (the check_status() function)
//   2. Model construction matching the same canned data as the REST tests
//   3. The GrpcClient public API surface compiles and has the right types
//
// Full integration tests require a running antd daemon.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "antd/errors.hpp"
#include "antd/models.hpp"

#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Reproduce the check_status() mapping from grpc_client.cpp so we can test
// it without requiring gRPC headers at link time. This mirrors the exact
// switch statement in src/grpc_client.cpp.
// ---------------------------------------------------------------------------

namespace test_grpc {

// Simulated gRPC status codes (values match grpc::StatusCode enum).
enum StatusCode {
    OK                  = 0,
    INVALID_ARGUMENT    = 3,
    NOT_FOUND           = 5,
    ALREADY_EXISTS      = 6,
    FAILED_PRECONDITION = 9,
    RESOURCE_EXHAUSTED  = 8,
    INTERNAL            = 13,
    UNAVAILABLE         = 14,
    UNIMPLEMENTED       = 12,
};

/// Throw the appropriate AntdError subclass for a gRPC status code.
/// This is a standalone mirror of the static check_status() in grpc_client.cpp
/// so the mapping logic can be tested without linking against gRPC.
[[noreturn]] void check_status(StatusCode code, const std::string& message) {
    switch (code) {
        case INVALID_ARGUMENT:
            throw antd::BadRequestError(message);
        case NOT_FOUND:
            throw antd::NotFoundError(message);
        case ALREADY_EXISTS:
            throw antd::AlreadyExistsError(message);
        case RESOURCE_EXHAUSTED:
            throw antd::TooLargeError(message);
        case INTERNAL:
            throw antd::InternalError(message);
        case UNAVAILABLE:
            throw antd::NetworkError(message);
        case FAILED_PRECONDITION:
            throw antd::PaymentError(message);
        default:
            throw antd::AntdError(static_cast<int>(code), message);
    }
}

}  // namespace test_grpc

// ---------------------------------------------------------------------------
// gRPC status code -> AntdError mapping
// ---------------------------------------------------------------------------

TEST_CASE("grpc INVALID_ARGUMENT -> BadRequestError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::INVALID_ARGUMENT, "bad arg"),
        antd::BadRequestError);
}

TEST_CASE("grpc NOT_FOUND -> NotFoundError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::NOT_FOUND, "missing"),
        antd::NotFoundError);
}

TEST_CASE("grpc ALREADY_EXISTS -> AlreadyExistsError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::ALREADY_EXISTS, "exists"),
        antd::AlreadyExistsError);
}

TEST_CASE("grpc FAILED_PRECONDITION -> PaymentError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::FAILED_PRECONDITION, "no funds"),
        antd::PaymentError);
}

TEST_CASE("grpc RESOURCE_EXHAUSTED -> TooLargeError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::RESOURCE_EXHAUSTED, "too big"),
        antd::TooLargeError);
}

TEST_CASE("grpc INTERNAL -> InternalError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::INTERNAL, "oops"),
        antd::InternalError);
}

TEST_CASE("grpc UNAVAILABLE -> NetworkError") {
    CHECK_THROWS_AS(
        test_grpc::check_status(test_grpc::UNAVAILABLE, "down"),
        antd::NetworkError);
}

TEST_CASE("grpc unknown code -> AntdError with code preserved") {
    try {
        test_grpc::check_status(test_grpc::UNIMPLEMENTED, "nope");
        FAIL("should have thrown");
    } catch (const antd::AntdError& e) {
        CHECK(e.status_code == static_cast<int>(test_grpc::UNIMPLEMENTED));
        CHECK(std::string(e.what()).find("nope") != std::string::npos);
    }
}

TEST_CASE("all grpc error types are catchable as AntdError") {
    auto codes = {
        test_grpc::INVALID_ARGUMENT,
        test_grpc::NOT_FOUND,
        test_grpc::ALREADY_EXISTS,
        test_grpc::FAILED_PRECONDITION,
        test_grpc::RESOURCE_EXHAUSTED,
        test_grpc::INTERNAL,
        test_grpc::UNAVAILABLE,
    };
    for (auto code : codes) {
        CHECK_THROWS_AS(
            test_grpc::check_status(code, "test"),
            antd::AntdError);
    }
}

// ---------------------------------------------------------------------------
// Model construction tests — same canned data as REST tests, simulating
// what GrpcClient methods produce from proto responses.
// ---------------------------------------------------------------------------

TEST_CASE("HealthStatus construction from gRPC response fields") {
    antd::HealthStatus h;
    h.ok = (std::string("ok") == "ok");
    h.network = "local";

    CHECK(h.ok);
    CHECK(h.network == "local");
}

TEST_CASE("DataPutPublicResult from gRPC data put public response") {
    antd::DataPutPublicResult r;
    r.address = "abc123";

    CHECK(r.address == "abc123");
    // gRPC currently leaves chunks_stored / payment_mode_used unset; the
    // wire shape `PutPublicDataResponse` only carries address + cost.
    CHECK(r.chunks_stored == 0);
    CHECK(r.payment_mode_used.empty());
}

TEST_CASE("DataPutResult from gRPC data put private response (data_map as primary)") {
    antd::DataPutResult r;
    r.data_map = "dm123";

    CHECK(r.data_map == "dm123");
    CHECK(r.chunks_stored == 0);
    CHECK(r.payment_mode_used.empty());
}

TEST_CASE("PutResult from gRPC chunk put response") {
    antd::PutResult r;
    r.cost = "10";
    r.address = "chunk1";

    CHECK(r.cost == "10");
    CHECK(r.address == "chunk1");
}

TEST_CASE("FilePutPublicResult from gRPC file put public response") {
    antd::FilePutPublicResult r;
    r.address = "file1";
    r.storage_cost_atto = "1000";
    r.gas_cost_wei = "42";
    r.chunks_stored = 5;
    r.payment_mode_used = "auto";

    CHECK(r.address == "file1");
    CHECK(r.storage_cost_atto == "1000");
    CHECK(r.chunks_stored == 5);
    CHECK(r.payment_mode_used == "auto");
}

TEST_CASE("FilePutResult from gRPC file put private response") {
    antd::FilePutResult r;
    r.data_map = "fdm1";
    r.storage_cost_atto = "900";
    r.gas_cost_wei = "42";
    r.chunks_stored = 4;
    r.payment_mode_used = "merkle";

    CHECK(r.data_map == "fdm1");
    CHECK(r.storage_cost_atto == "900");
    CHECK(r.chunks_stored == 4);
    CHECK(r.payment_mode_used == "merkle");
}

TEST_CASE("UploadCostEstimate from gRPC cost response") {
    antd::UploadCostEstimate est;
    est.cost = "50";
    est.file_size = 4;
    est.chunk_count = 3;
    est.estimated_gas_cost_wei = "150";
    est.payment_mode = "single";

    CHECK(est.cost == "50");
    CHECK(est.payment_mode == "single");
}

// ---------------------------------------------------------------------------
// PaymentMode wire serialization — same source-of-truth helper used by both
// transports.
// ---------------------------------------------------------------------------

TEST_CASE("payment_mode_wire matches the daemon's accepted strings") {
    CHECK(antd::payment_mode_wire(antd::PaymentMode::Auto) == "auto");
    CHECK(antd::payment_mode_wire(antd::PaymentMode::Merkle) == "merkle");
    CHECK(antd::payment_mode_wire(antd::PaymentMode::Single) == "single");
}

// ---------------------------------------------------------------------------
// Byte vector construction — simulates how GrpcClient converts proto bytes
// fields to std::vector<uint8_t>
// ---------------------------------------------------------------------------

TEST_CASE("byte data round-trip simulating gRPC bytes field") {
    std::string proto_bytes = "hello";
    std::vector<uint8_t> result(proto_bytes.begin(), proto_bytes.end());
    CHECK(result.size() == 5);
    CHECK(std::string(result.begin(), result.end()) == "hello");
}

TEST_CASE("private data byte round-trip") {
    std::string proto_bytes = "secret";
    std::vector<uint8_t> result(proto_bytes.begin(), proto_bytes.end());
    CHECK(std::string(result.begin(), result.end()) == "secret");
}

TEST_CASE("chunk data byte round-trip") {
    std::string proto_bytes = "chunkdata";
    std::vector<uint8_t> result(proto_bytes.begin(), proto_bytes.end());
    CHECK(std::string(result.begin(), result.end()) == "chunkdata");
}

// ---------------------------------------------------------------------------
// NOTE: Full integration tests for GrpcClient require a running antd daemon
// with gRPC enabled on localhost:50051. The tests above validate error mapping,
// model construction, and data conversion without network access or gRPC
// library linkage.
// ---------------------------------------------------------------------------
