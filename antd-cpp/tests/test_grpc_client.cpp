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
    ABORTED             = 10,
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
        case ABORTED: {
            // Same gate as grpc_client.cpp: only a message that starts with
            // the daemon's "Partial upload:" prefix turns ABORTED into
            // PartialUploadError.
            if (!antd::is_partial_upload_message(message)) {
                throw antd::AntdError(static_cast<int>(code), message);
            }
            const auto counts = antd::parse_partial_upload_message(message);
            throw antd::PartialUploadError(message,
                                           counts.chunks_stored,
                                           counts.chunks_failed,
                                           counts.total_chunks,
                                           counts.retryable,
                                           counts.retention_known);
        }
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

// ---------------------------------------------------------------------------
// PARTIAL_UPLOAD rides gRPC ABORTED, gated on the message starting with the
// daemon's fixed "Partial upload:" prefix (is_partial_upload_message). The
// status carries no structured detail, so the counts and the retention hint
// that closes the message are parsed from its text
// (parse_partial_upload_message) to match the REST client's typed error. Any
// other ABORTED keeps the generic mapping.
// ---------------------------------------------------------------------------

TEST_CASE("grpc ABORTED -> PartialUploadError with counts and retryable from the retained hint") {
    const std::string msg =
        "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum "
        "(paid attempt retained: call finalize again with the same upload_id to "
        "store the remainder against the same payment)";
    try {
        test_grpc::check_status(test_grpc::ABORTED, msg);
        FAIL("should have thrown");
    } catch (const antd::PartialUploadError& e) {
        CHECK(e.status_code == 502);
        CHECK(e.chunks_stored == 300);
        CHECK(e.chunks_failed == 12);
        CHECK(e.total_chunks == 312);
        CHECK(e.retryable);
        CHECK(e.retention_known);
        CHECK(std::string(e.what()).find("Partial upload") != std::string::npos);
    }
}

TEST_CASE("grpc ABORTED with the not-retained hint reads as retention known, not retryable") {
    const std::string msg =
        "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum "
        "(stored chunks persist; re-prepare the same content to retry only the remainder)";
    try {
        test_grpc::check_status(test_grpc::ABORTED, msg);
        FAIL("should have thrown");
    } catch (const antd::PartialUploadError& e) {
        CHECK(e.chunks_stored == 300);
        CHECK(e.chunks_failed == 12);
        CHECK(e.total_chunks == 312);
        CHECK_FALSE(e.retryable);
        CHECK(e.retention_known);
    }
}

TEST_CASE("grpc ABORTED with readable counts but no readable retention hint -> counts kept, retention unknown") {
    // The daemon's answer on retention was not read, so this is "stop and
    // reconcile", never "nothing retained" (re-prepare).
    const std::string msgs[] = {
        "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum",
        "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retai",
    };
    for (const auto& msg : msgs) {
        CAPTURE(msg);
        try {
            test_grpc::check_status(test_grpc::ABORTED, msg);
            FAIL("should have thrown");
        } catch (const antd::PartialUploadError& e) {
            CHECK(e.status_code == 502);
            CHECK(e.chunks_stored == 1);
            CHECK(e.chunks_failed == 2);
            CHECK(e.total_chunks == 3);
            CHECK_FALSE(e.retryable);
            CHECK_FALSE(e.retention_known);
        }
    }
}

TEST_CASE("grpc ABORTED is still catchable as NetworkError and AntdError") {
    // A 502 mapped to NetworkError before PartialUploadError existed, so
    // existing catch blocks must keep working.
    CHECK_THROWS_AS(test_grpc::check_status(test_grpc::ABORTED, "Partial upload: 1/2 chunks stored, 1 failed"),
                    antd::NetworkError);
    CHECK_THROWS_AS(test_grpc::check_status(test_grpc::ABORTED, "Partial upload: 1/2 chunks stored, 1 failed"),
                    antd::AntdError);
}

TEST_CASE("grpc ABORTED without the Partial upload prefix keeps the generic AntdError mapping") {
    // ABORTED is a generic gRPC code; only a message that opens with the
    // daemon's fixed prefix marks a partial store. Anything else must map
    // exactly as before this type existed: AntdError with the raw code
    // preserved.
    const std::string msg = "transaction aborted: something else entirely";
    try {
        test_grpc::check_status(test_grpc::ABORTED, msg);
        FAIL("should have thrown");
    } catch (const antd::PartialUploadError&) {
        FAIL("an ABORTED without the prefix must not become PartialUploadError");
    } catch (const antd::NetworkError&) {
        FAIL("an ABORTED without the prefix must not become NetworkError");
    } catch (const antd::AntdError& e) {
        CHECK(e.status_code == static_cast<int>(test_grpc::ABORTED));
        CHECK(std::string(e.what()).find(msg) != std::string::npos);
    }
}

TEST_CASE("grpc ABORTED with the prefix but garbled counts -> PartialUploadError with zeros, retention unknown") {
    const std::string msg = "Partial upload: counts unavailable";
    try {
        test_grpc::check_status(test_grpc::ABORTED, msg);
        FAIL("should have thrown");
    } catch (const antd::PartialUploadError& e) {
        CHECK(e.status_code == 502);
        CHECK(e.chunks_stored == 0);
        CHECK(e.chunks_failed == 0);
        CHECK(e.total_chunks == 0);
        CHECK_FALSE(e.retryable);
        CHECK_FALSE(e.retention_known);
        CHECK(std::string(e.what()).find(msg) != std::string::npos);
    }
}

TEST_CASE("grpc ABORTED that embeds the Partial upload marker after other text keeps the generic AntdError mapping") {
    // Anchored, not containment: an ABORTED that merely quotes the marker
    // further into its message is some other failure and must not select
    // the partial-store recovery path (least of all a retryable one).
    const std::string msgs[] = {
        "upstream error: Partial upload: 1/3 chunks stored, 2 failed",
        "wrapped (Partial upload: 0/1 chunks stored, 1 failed; paid attempt retained)",
    };
    for (const auto& msg : msgs) {
        CAPTURE(msg);
        try {
            test_grpc::check_status(test_grpc::ABORTED, msg);
            FAIL("should have thrown");
        } catch (const antd::PartialUploadError&) {
            FAIL("an embedded marker must not become PartialUploadError");
        } catch (const antd::NetworkError&) {
            FAIL("an embedded marker must not become NetworkError");
        } catch (const antd::AntdError& e) {
            CHECK(e.status_code == static_cast<int>(test_grpc::ABORTED));
            CHECK(std::string(e.what()).find(msg) != std::string::npos);
        }
    }
}

TEST_CASE("grpc ABORTED with a count that overflows 64 bits -> PartialUploadError with zeros, retention unknown, no raw exception") {
    // The retained hint is present, but the counts are unusable, so
    // retention is unknown and the error must not be retryable.
    const std::string msg =
        "Partial upload: 99999999999999999999999/312 chunks stored, 12 failed after retries: "
        "quorum (paid attempt retained: call finalize again with the same upload_id to "
        "store the remainder against the same payment)";
    try {
        test_grpc::check_status(test_grpc::ABORTED, msg);
        FAIL("should have thrown");
    } catch (const antd::PartialUploadError& e) {
        CHECK(e.chunks_stored == 0);
        CHECK(e.chunks_failed == 0);
        CHECK(e.total_chunks == 0);
        CHECK_FALSE(e.retryable);
        CHECK_FALSE(e.retention_known);
    } catch (const std::exception& e) {
        FAIL("escaped the typed error contract: " << std::string(e.what()));
    }
}

TEST_CASE("grpc ABORTED with the retained hint but unparseable counts -> PartialUploadError with zeros, retention unknown") {
    const std::string msg =
        "Partial upload: counts unavailable (paid attempt retained: call finalize again "
        "with the same upload_id to store the remainder against the same payment)";
    try {
        test_grpc::check_status(test_grpc::ABORTED, msg);
        FAIL("should have thrown");
    } catch (const antd::PartialUploadError& e) {
        CHECK(e.status_code == 502);
        CHECK(e.chunks_stored == 0);
        CHECK(e.chunks_failed == 0);
        CHECK(e.total_chunks == 0);
        CHECK_FALSE(e.retryable);
        CHECK_FALSE(e.retention_known);
    }
}

TEST_CASE("PartialUploadError: retryable implies retention_known; the 5-argument constructor stays source compatible") {
    const antd::PartialUploadError known_not_retained("m", 1, 1, 2, false, true);
    CHECK_FALSE(known_not_retained.retryable);
    CHECK(known_not_retained.retention_known);

    const antd::PartialUploadError unknown("m", 1, 1, 2, false, false);
    CHECK_FALSE(unknown.retryable);
    CHECK_FALSE(unknown.retention_known);

    // A retryable error is always known, whatever the caller passes.
    const antd::PartialUploadError forced("m", 1, 1, 2, true, false);
    CHECK(forced.retryable);
    CHECK(forced.retention_known);

    // The pre-existing 5-argument form: retryable is known, anything else
    // reads as unknown.
    const antd::PartialUploadError legacy_retryable("m", 1, 1, 2, true);
    CHECK(legacy_retryable.retention_known);
    const antd::PartialUploadError legacy_not("m", 1, 1, 2, false);
    CHECK_FALSE(legacy_not.retention_known);
}

TEST_CASE("is_partial_upload_message matches the daemon prefix only at the start of the message") {
    CHECK(antd::is_partial_upload_message("Partial upload: 1/2 chunks stored, 1 failed"));
    CHECK(antd::is_partial_upload_message("Partial upload:"));
    CHECK_FALSE(antd::is_partial_upload_message("rpc error: Partial upload: 1/2 chunks stored, 1 failed"));
    CHECK_FALSE(antd::is_partial_upload_message("upstream error: Partial upload: 1/3 chunks stored, 2 failed"));
    CHECK_FALSE(antd::is_partial_upload_message(
        "wrapped (Partial upload: 0/1 chunks stored, 1 failed; paid attempt retained)"));
    CHECK_FALSE(antd::is_partial_upload_message(" Partial upload: 1/2 chunks stored, 1 failed"));  // leading space
    CHECK_FALSE(antd::is_partial_upload_message("Partial upload"));  // shorter than the prefix
    CHECK_FALSE(antd::is_partial_upload_message("partial upload: 1/2 chunks stored"));  // case-sensitive
    CHECK_FALSE(antd::is_partial_upload_message("Partial upload 1/2 chunks stored"));   // no colon
    CHECK_FALSE(antd::is_partial_upload_message("something else entirely"));
    CHECK_FALSE(antd::is_partial_upload_message(""));
}

TEST_CASE("parse_partial_upload_message recovers counts, retention and the retryable hint") {
    struct Case {
        const char* msg;
        std::uint64_t stored, failed, total;
        bool retryable, known;
    };
    const Case cases[] = {
        {"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum "
         "(paid attempt retained: call finalize again with the same upload_id to "
         "store the remainder against the same payment)",
         300, 12, 312, true, true},
        {"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum "
         "(stored chunks persist; re-prepare the same content to retry only the remainder)",
         300, 12, 312, false, true},
        // No closing hint: the counts are kept, but retention is unknown.
        {"Partial upload: 300/312 chunks stored, 12 failed after retries", 300, 12, 312, false, false},
        {"Partial upload: 18446744073709551615/1 chunks stored, 0 failed",  // u64 max still parses
         18446744073709551615ULL, 0, 1, false, false},
        {"Partial upload: 18446744073709551615/1 chunks stored, 0 failed after retries: quorum "
         "(stored chunks persist; re-prepare the same content to retry only the remainder)",
         18446744073709551615ULL, 0, 1, false, true},
        {"Partial upload: 18446744073709551616/1 chunks stored, 0 failed",  // overflow
         0, 0, 0, false, false},
        {"something else entirely", 0, 0, 0, false, false},
        // The counts pattern must open the message, as the gate requires.
        {"upstream error: Partial upload: 1/3 chunks stored, 2 failed", 0, 0, 0, false, false},
    };
    for (const auto& tc : cases) {
        CAPTURE(tc.msg);
        const auto c = antd::parse_partial_upload_message(tc.msg);
        CHECK(c.chunks_stored == tc.stored);
        CHECK(c.chunks_failed == tc.failed);
        CHECK(c.total_chunks == tc.total);
        CHECK(c.retryable == tc.retryable);
        CHECK(c.retention_known == tc.known);
    }
}

TEST_CASE("parse_partial_upload_message knows retention only when all three counts parse and the closing hint reads") {
    // The retained hint alone does not make an error retryable, nor does it
    // make retention known: a pattern miss or a count that fails to convert
    // (overflow in any position) zeroes all three counts and leaves both
    // flags false, hint or not. Readable counts without a closing hint keep
    // the counts but leave retention unknown.
    const std::string hint =
        " (paid attempt retained: call finalize again with the same upload_id to "
        "store the remainder against the same payment)";
    const std::string overflow = "18446744073709551616";  // u64 max + 1
    struct Case {
        std::string msg;
        std::uint64_t stored, failed, total;
        bool retryable, known;
    };
    const Case cases[] = {
        // Well-formed with the retained hint: retention known, retryable.
        {"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum" + hint,
         300, 12, 312, true, true},
        // Well-formed without a closing hint: counts kept, retention unknown.
        {"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum",
         300, 12, 312, false, false},
        // Overflow in each position, hint present: unknown.
        {"Partial upload: " + overflow + "/312 chunks stored, 12 failed" + hint,
         0, 0, 0, false, false},
        {"Partial upload: 300/" + overflow + " chunks stored, 12 failed" + hint,
         0, 0, 0, false, false},
        {"Partial upload: 300/312 chunks stored, " + overflow + " failed" + hint,
         0, 0, 0, false, false},
        // Pattern miss, hint present: unknown.
        {"Partial upload: counts unavailable" + hint, 0, 0, 0, false, false},
        {"Partial upload: 300 of 312 chunks stored, 12 failed" + hint, 0, 0, 0, false, false},
        // Garbled counts after the prefix with a well-formed pattern later in
        // the text: the pattern must open the message, so still unknown.
        {"Partial upload: see below; Partial upload: 1/2 chunks stored, 1 failed" + hint,
         0, 0, 0, false, false},
    };
    for (const auto& tc : cases) {
        CAPTURE(tc.msg);
        const auto c = antd::parse_partial_upload_message(tc.msg);
        CHECK(c.chunks_stored == tc.stored);
        CHECK(c.chunks_failed == tc.failed);
        CHECK(c.total_chunks == tc.total);
        CHECK(c.retryable == tc.retryable);
        CHECK(c.retention_known == tc.known);
        CHECK((!c.retryable || c.retention_known));  // retryable => known
    }
}

TEST_CASE("parse_partial_upload_message reads retention only from the hint that closes the message") {
    // The daemon's two closing hints (partial_upload_hint in antd/src/error.rs).
    const std::string retained_tail =
        " (paid attempt retained: call finalize again with the same upload_id to "
        "store the remainder against the same payment)";
    const std::string not_retained_tail =
        " (stored chunks persist; re-prepare the same content to retry only the remainder)";
    const std::string head = "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum";
    struct Case {
        std::string name;
        std::string msg;
        std::uint64_t stored, failed, total;
        bool retryable, known;
    };
    const Case cases[] = {
        {"retained hint", head + retained_tail, 1, 2, 3, true, true},
        {"short retained hint", head + " (paid attempt retained)", 1, 2, 3, true, true},
        {"not-retained hint", head + not_retained_tail, 1, 2, 3, false, true},
        {"parenthesised reason before the hint",
         "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (2 of 5 peers)" +
             not_retained_tail,
         1, 2, 3, false, true},
        {"retained hint quoted in the reason, not-retained tail",
         "Partial upload: 1/3 chunks stored, 2 failed after retries: peer said "
         "(paid attempt retained)" + not_retained_tail,
         1, 2, 3, false, true},
        // Readable counts but no readable answer on retention: the counts are
        // kept, retention is unknown (stop and reconcile), never "nothing
        // retained" (re-prepare).
        {"no hint", head, 1, 2, 3, false, false},
        {"truncated retained hint", head + " (paid attempt retai", 1, 2, 3, false, false},
        {"retained hint without its closing paren",
         head + " (paid attempt retained: call finalize again", 1, 2, 3, false, false},
        {"retained hint without its opening paren", head + " paid attempt retained)",
         1, 2, 3, false, false},
        {"truncated not-retained hint", head + " (stored chunks persist; re-prepare the same con",
         1, 2, 3, false, false},
        {"unrecognised hint", head + " (something else)", 1, 2, 3, false, false},
        {"empty parentheses", head + " ()", 1, 2, 3, false, false},
        {"retained hint with a nested paren", head + " (paid attempt retained (see logs))",
         1, 2, 3, false, false},
        {"text after the retained hint", head + retained_tail + " trailing", 1, 2, 3, false, false},
        {"newline after the retained hint", head + retained_tail + "\n", 1, 2, 3, false, false},
        {"newline after the not-retained hint", head + not_retained_tail + "\n",
         1, 2, 3, false, false},
        {"CRLF after the retained hint", head + retained_tail + "\r\n", 1, 2, 3, false, false},
        {"retained hint quoted in the reason only",
         "Partial upload: 1/3 chunks stored, 2 failed after retries: peer said "
         "(paid attempt retained) (connection reset)",
         1, 2, 3, false, false},
        // The counts must open the message: counts quoted later are never read.
        {"embedded counts",
         "Partial upload: garbled; was Partial upload: 1/3 chunks stored, 2 failed "
         "(paid attempt retained)",
         0, 0, 0, false, false},
    };
    for (const auto& tc : cases) {
        CAPTURE(tc.name);
        CAPTURE(tc.msg);
        const auto c = antd::parse_partial_upload_message(tc.msg);
        CHECK(c.chunks_stored == tc.stored);
        CHECK(c.chunks_failed == tc.failed);
        CHECK(c.total_chunks == tc.total);
        CHECK(c.retryable == tc.retryable);
        CHECK(c.retention_known == tc.known);
        CHECK((!c.retryable || c.retention_known));  // retryable => known

        // The same fields through the ABORTED mapping.
        try {
            test_grpc::check_status(test_grpc::ABORTED, tc.msg);
            FAIL("should have thrown");
        } catch (const antd::PartialUploadError& e) {
            CHECK(e.chunks_stored == tc.stored);
            CHECK(e.chunks_failed == tc.failed);
            CHECK(e.total_chunks == tc.total);
            CHECK(e.retryable == tc.retryable);
            CHECK(e.retention_known == tc.known);
        }
    }
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
