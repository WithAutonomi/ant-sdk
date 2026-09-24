#pragma once

#include <cstdint>
#include <regex>
#include <stdexcept>
#include <string>
#include <string_view>

namespace antd {

/// Base error type for all antd errors.
class AntdError : public std::runtime_error {
public:
    int status_code;

    AntdError(int status_code, const std::string& message)
        : std::runtime_error("antd error " + std::to_string(status_code) + ": " + message),
          status_code(status_code) {}
};

/// Invalid request parameters (HTTP 400).
class BadRequestError : public AntdError {
public:
    BadRequestError(const std::string& msg) : AntdError(400, msg) {}
};

/// Insufficient funds or payment failure (HTTP 402).
class PaymentError : public AntdError {
public:
    PaymentError(const std::string& msg) : AntdError(402, msg) {}
};

/// Resource not found on the network (HTTP 404).
class NotFoundError : public AntdError {
public:
    NotFoundError(const std::string& msg) : AntdError(404, msg) {}
};

/// Resource already exists (HTTP 409).
class AlreadyExistsError : public AntdError {
public:
    AlreadyExistsError(const std::string& msg) : AntdError(409, msg) {}
};

/// Version conflict or fork detected (HTTP 409).
class ForkError : public AntdError {
public:
    ForkError(const std::string& msg) : AntdError(409, msg) {}
};

/// Payload too large (HTTP 413).
class TooLargeError : public AntdError {
public:
    TooLargeError(const std::string& msg) : AntdError(413, msg) {}
};

/// Internal server error (HTTP 500).
class InternalError : public AntdError {
public:
    InternalError(const std::string& msg) : AntdError(500, msg) {}
};

/// Daemon cannot reach the network (HTTP 502).
class NetworkError : public AntdError {
public:
    NetworkError(const std::string& msg) : AntdError(502, msg) {}
};

/// Service unavailable, e.g. wallet not configured (HTTP 503).
class ServiceUnavailableError : public AntdError {
public:
    ServiceUnavailableError(const std::string& msg) : AntdError(503, msg) {}
};

/// A finalize stored some chunks while others remained unstored after the
/// daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED
/// whose message starts with `Partial upload:`). The on-chain payment
/// persists and the stored chunks stay on the network.
///
/// Derives from NetworkError because a 502 mapped to NetworkError before this
/// type existed, so `catch (const NetworkError&)` blocks keep catching it —
/// catch PartialUploadError first to handle the partial case specifically.
///
/// How to finish the upload depends on `retryable`:
///
///   - `true`: the daemon kept the paid attempt (payment proofs + unstored
///     chunks) under the same `upload_id`. Call the same finalize method
///     again with the same arguments to store the remainder against the same
///     payment — no re-prepare, no second signature, no double payment.
///     Bound the loop: a persistent failure throws this on every call, so cap
///     the attempts and treat a `chunks_failed` that stops shrinking as
///     stuck. The retained attempt expires with the daemon's pending-upload
///     TTL. (antd >= 0.14.0; older daemons never send the flag, so it reads
///     false and the re-prepare path applies.)
///   - `false`: nothing was retained (a merkle finalize with deliberately
///     unpaid batches, or an older daemon). Re-preparing the same content
///     skips already-stored chunks, so a retry pays only for the remainder.
///
/// Over REST the counts and `retryable` come from the structured error body.
/// Over gRPC only an ABORTED whose message carries the daemon's fixed
/// `Partial upload:` prefix becomes this type (see is_partial_upload_message);
/// any other ABORTED keeps the generic AntdError mapping. The counts are then
/// parsed best-effort from the message (see parse_partial_upload_message); a
/// prefixed message with garbled counts leaves them zero and `retryable`
/// false. See docs/external-signer-flow.md §6.
class PartialUploadError : public NetworkError {
public:
    std::uint64_t chunks_stored;
    std::uint64_t chunks_failed;
    std::uint64_t total_chunks;
    bool retryable;

    PartialUploadError(const std::string& msg,
                       std::uint64_t chunks_stored,
                       std::uint64_t chunks_failed,
                       std::uint64_t total_chunks,
                       bool retryable)
        : NetworkError(msg),
          chunks_stored(chunks_stored),
          chunks_failed(chunks_failed),
          total_chunks(total_chunks),
          retryable(retryable) {}
};

/// Counts and retry hint recovered from a PARTIAL_UPLOAD message.
struct PartialUploadCounts {
    std::uint64_t chunks_stored{0};
    std::uint64_t chunks_failed{0};
    std::uint64_t total_chunks{0};
    bool retryable{false};
};

/// The fixed text every PARTIAL_UPLOAD message from the daemon opens with
/// (antd's `Error::PartialUpload` Display impl). gRPC ABORTED is a generic
/// code, so this prefix is what identifies a partial store there.
inline constexpr std::string_view kPartialUploadPrefix = "Partial upload:";

/// Whether a gRPC ABORTED status message is the daemon's PARTIAL_UPLOAD
/// report. Matched by containment rather than a strict prefix so a transport
/// or interceptor that prepends its own text does not hide the partial case.
inline bool is_partial_upload_message(std::string_view message) {
    return message.find(kPartialUploadPrefix) != std::string_view::npos;
}

/// Recover the chunk counts and the retryable hint from a PARTIAL_UPLOAD
/// message. Used for gRPC, where the status carries no structured detail;
/// REST callers get the body fields instead. Callers gate on
/// is_partial_upload_message first: this parser only reads the counts.
///
/// Matches the fixed prefix "Partial upload: <stored>/<total> chunks stored,
/// <failed> failed" and reads `retryable` from the "paid attempt retained"
/// hint the daemon appends when it kept the paid attempt. An unrecognised
/// message yields zero counts and `retryable == false`.
inline PartialUploadCounts parse_partial_upload_message(std::string_view message) {
    static const std::regex kCounts(
        R"(Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed)");
    PartialUploadCounts out;
    std::match_results<std::string_view::const_iterator> m;
    if (std::regex_search(message.begin(), message.end(), m, kCounts)) {
        out.chunks_stored = std::stoull(m[1].str());
        out.total_chunks = std::stoull(m[2].str());
        out.chunks_failed = std::stoull(m[3].str());
    }
    out.retryable = message.find("paid attempt retained") != std::string_view::npos;
    return out;
}

/// Throw the appropriate AntdError subclass for an HTTP status code.
[[noreturn]] inline void error_for_status(int code, const std::string& message) {
    switch (code) {
        case 400: throw BadRequestError(message);
        case 402: throw PaymentError(message);
        case 404: throw NotFoundError(message);
        case 409: throw AlreadyExistsError(message);
        case 413: throw TooLargeError(message);
        case 500: throw InternalError(message);
        case 502: throw NetworkError(message);
        case 503: throw ServiceUnavailableError(message);
        default:  throw AntdError(code, message);
    }
}

}  // namespace antd
