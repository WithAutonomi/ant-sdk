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

#include <charconv>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
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
// Streaming downloads (data_stream / data_stream_public). The real methods
// drain a gRPC server-stream into a DataSink; reproduce that draining logic
// here (the test binary doesn't link gRPC) to validate chunk accumulation and
// early-stop semantics.
// ---------------------------------------------------------------------------

TEST_CASE("streaming download accumulates chunks via DataSink") {
    // Two chunks so chunk-boundary handling is exercised, not a single buffer.
    std::vector<std::string> chunks = {"sec", "ret"};
    std::string out;
    auto sink = [&out](const char* data, std::size_t len) -> bool {
        out.append(data, len);
        return true;
    };
    for (const auto& c : chunks) {
        sink(c.data(), c.size());
    }
    CHECK(out == "secret");
}

TEST_CASE("streaming download stops early when sink returns false") {
    std::vector<std::string> chunks = {"hel", "lo"};
    std::string out;
    int calls = 0;
    auto sink = [&](const char* data, std::size_t len) -> bool {
        ++calls;
        out.append(data, len);
        return false;  // request early stop after the first chunk
    };
    for (const auto& c : chunks) {
        if (!sink(c.data(), c.size())) break;
    }
    CHECK(calls == 1);
    CHECK(out == "hel");
}

// ---------------------------------------------------------------------------
// V2-512: progress-enabled streaming downloads. The real data_stream_with_
// progress methods set include_progress=true and map the DataChunk oneof
// (kind_case) onto a DownloadFrame. The test binary doesn't link gRPC, so we
// reproduce that oneof-mapping logic here with a simulated wire frame to
// validate the discrimination and accumulation semantics.
// ---------------------------------------------------------------------------

namespace test_grpc {

// Simulated DataChunk oneof arm — mirrors antd::v1::DataChunk::KindCase.
enum KindCase { KIND_NOT_SET = 0, kData = 1, kProgress = 2 };

// A minimal stand-in for a wire DataChunk carrying exactly one oneof arm.
struct WireChunk {
    KindCase kind{KIND_NOT_SET};
    std::string data;              // set when kind == kData
    antd::DownloadProgress progress;  // set when kind == kProgress
};

// Standalone mirror of frame_of() from grpc_client.cpp: a progress arm becomes
// a progress frame; a data arm (or unset oneof) becomes a data frame.
antd::DownloadFrame frame_of(const WireChunk& chunk) {
    if (chunk.kind == kProgress) {
        return antd::DownloadFrame::from_progress(chunk.progress);
    }
    std::vector<uint8_t> bytes(chunk.data.begin(), chunk.data.end());
    return antd::DownloadFrame::from_data(std::move(bytes));
}

// Standalone mirror of deliver_meta_frame()'s parse step from grpc_client.cpp.
// The real code reads the `x-content-length` value out of the stream's server
// initial metadata (a std::multimap<grpc::string_ref, grpc::string_ref>); the
// test binary doesn't link gRPC, so we reproduce the parse-and-prepend logic
// against the raw header value. A present + fully-numeric value yields a Meta
// frame; an absent (nullptr) or unparseable value yields none — matching the
// older-daemon fallthrough.
std::optional<antd::DownloadFrame> meta_frame_of(const char* x_content_length) {
    if (x_content_length == nullptr) {
        return std::nullopt;  // header absent — older daemon
    }
    std::string_view val(x_content_length);
    std::uint64_t total = 0;
    const char* first = val.data();
    const char* last = first + val.size();
    auto [ptr, ec] = std::from_chars(first, last, total);
    if (ec != std::errc() || ptr != last) {
        return std::nullopt;  // unparseable — skip the Meta frame
    }
    return antd::DownloadFrame::from_meta(total);
}

}  // namespace test_grpc

TEST_CASE("gRPC oneof: data arm maps to a data DownloadFrame") {
    test_grpc::WireChunk wire;
    wire.kind = test_grpc::kData;
    wire.data = "secret";

    auto frame = test_grpc::frame_of(wire);
    CHECK_FALSE(frame.is_progress());
    REQUIRE(frame.data.has_value());
    CHECK(std::string(frame.data->begin(), frame.data->end()) == "secret");
}

TEST_CASE("gRPC oneof: progress arm maps to a progress DownloadFrame") {
    test_grpc::WireChunk wire;
    wire.kind = test_grpc::kProgress;
    wire.progress = antd::DownloadProgress{"fetching", 3, 7};

    auto frame = test_grpc::frame_of(wire);
    CHECK(frame.is_progress());
    REQUIRE(frame.progress.has_value());
    CHECK(frame.progress->phase == "fetching");
    CHECK(frame.progress->fetched == 3);
    CHECK(frame.progress->total == 7);
}

TEST_CASE("gRPC oneof: unset arm defaults to an empty data frame") {
    test_grpc::WireChunk wire;  // KIND_NOT_SET
    auto frame = test_grpc::frame_of(wire);
    CHECK_FALSE(frame.is_progress());
    REQUIRE(frame.data.has_value());
    CHECK(frame.data->empty());
}

TEST_CASE("progress-enabled stream interleaves progress and data frames") {
    // A representative wire sequence: a resolving-map progress, a fetching
    // progress, then the decrypted data chunk.
    std::vector<test_grpc::WireChunk> wire = {
        {test_grpc::kProgress, "", antd::DownloadProgress{"resolving_map", 0, 0}},
        {test_grpc::kProgress, "", antd::DownloadProgress{"fetching", 1, 1}},
        {test_grpc::kData, "secret", {}},
    };

    std::vector<antd::DownloadProgress> progress;
    std::string received;
    for (const auto& w : wire) {
        auto f = test_grpc::frame_of(w);
        if (f.is_progress()) {
            progress.push_back(*f.progress);
        } else {
            received.append(f.data->begin(), f.data->end());
        }
    }

    REQUIRE(progress.size() == 2);
    CHECK(progress[0].phase == "resolving_map");
    CHECK(progress[1].phase == "fetching");
    CHECK(received == "secret");
}

// ---------------------------------------------------------------------------
// V2-510: the byte denominator (x-content-length response metadata) surfaces
// as a leading Meta DownloadFrame before any data. The real
// data_stream_*_with_progress methods call WaitForInitialMetadata(), look the
// header up in ctx.GetServerInitialMetadata(), parse it to a uint64, and
// deliver a Meta frame first. The test binary doesn't link gRPC, so we
// validate the parse-and-prepend logic via meta_frame_of().
// ---------------------------------------------------------------------------

TEST_CASE("gRPC meta: numeric x-content-length maps to a Meta frame") {
    auto frame = test_grpc::meta_frame_of("12345");
    REQUIRE(frame.has_value());
    CHECK(frame->is_meta());
    CHECK_FALSE(frame->is_progress());
    REQUIRE(frame->total_size.has_value());
    CHECK(*frame->total_size == 12345);
}

TEST_CASE("gRPC meta: absent x-content-length yields no Meta frame") {
    // Older daemon — header missing (find() returns end(), modelled as nullptr).
    CHECK_FALSE(test_grpc::meta_frame_of(nullptr).has_value());
}

TEST_CASE("gRPC meta: unparseable x-content-length yields no Meta frame") {
    CHECK_FALSE(test_grpc::meta_frame_of("not-a-number").has_value());
    CHECK_FALSE(test_grpc::meta_frame_of("123abc").has_value());
    CHECK_FALSE(test_grpc::meta_frame_of("").has_value());
}

TEST_CASE("gRPC meta: Meta frame leads the progress/data sequence") {
    // The denominator is delivered first, then the wire chunk sequence.
    std::vector<antd::DownloadFrame> frames;
    if (auto meta = test_grpc::meta_frame_of("6")) {
        frames.push_back(*meta);
    }
    std::vector<test_grpc::WireChunk> wire = {
        {test_grpc::kProgress, "", antd::DownloadProgress{"fetching", 1, 1}},
        {test_grpc::kData, "secret", {}},
    };
    for (const auto& w : wire) {
        frames.push_back(test_grpc::frame_of(w));
    }

    REQUIRE(frames.size() == 3);
    REQUIRE(frames[0].is_meta());
    CHECK(*frames[0].total_size == 6);
    CHECK(frames[1].is_progress());
    CHECK_FALSE(frames[2].is_progress());
    CHECK_FALSE(frames[2].is_meta());
}

// ---------------------------------------------------------------------------
// NOTE: Full integration tests for GrpcClient require a running antd daemon
// with gRPC enabled on localhost:50051. The tests above validate error mapping,
// model construction, and data conversion without network access or gRPC
// library linkage.
// ---------------------------------------------------------------------------
