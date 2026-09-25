#pragma once

#include <charconv>
#include <cstdint>
#include <regex>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>

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
/// How to finish the upload depends on `retryable` and `retention_known`
/// (`retryable` implies `retention_known`):
///
///   1. `retryable`: the daemon kept the paid attempt (payment proofs +
///      unstored chunks) under the same `upload_id`. Call the same finalize
///      method again with the same `upload_id` and payment artefacts to store
///      the remainder against the same payment — no re-prepare, no second
///      signature, no double payment. Bound the loop: a persistent failure
///      throws this on every call, so cap the attempts and treat a
///      `chunks_failed` that stops shrinking as stuck. The retained attempt
///      expires with the daemon's pending-upload TTL.
///   2. `retention_known && !retryable`: the daemon confirmed nothing was
///      retained (e.g. a merkle finalize with deliberately unpaid batches).
///      Re-prepare the same content: already-stored chunks are skipped, so
///      the retry pays only for the remainder.
///   3. `!retention_known`: retention is unknown. The daemon may still hold
///      the paid attempt (it records the resume handle before it returns the
///      error). Stop automatic recovery, keep the `upload_id` and the
///      original payment artefacts, and reconcile before re-preparing or
///      paying again; never pay again on this signal alone. Daemons older
///      than 0.14.0 never send `retryable`, so their REST partials read as
///      unknown.
///
/// Over REST the counts come from the structured error body (a missing or
/// mistyped count reads as zero), and `retention_known` is true only when the
/// body's `retryable` is present and a JSON boolean, which then sets
/// `retryable`. Over gRPC only an ABORTED whose message starts with the
/// daemon's fixed `Partial upload:` prefix becomes this type (see
/// is_partial_upload_message); any other ABORTED, including one that quotes
/// the prefix further into its message, keeps the generic AntdError mapping.
/// The fields are then parsed from the message (see
/// parse_partial_upload_message): `retention_known` is true only when the
/// counts right after the prefix match, all three convert, and the message
/// ends with one of the daemon's two closing hints, "(paid attempt
/// retained...)" (which sets `retryable`) or "(stored chunks persist;
/// re-prepare the same content...)" (the daemon confirmed nothing was
/// retained). Counts that do not parse read as zero with retention unknown.
/// Readable counts with a missing, truncated or unrecognised hint keep the
/// counts, but retention is unknown too: stop and reconcile, never read it as
/// "nothing retained". See docs/external-signer-flow.md §6.
class PartialUploadError : public NetworkError {
public:
    std::uint64_t chunks_stored;
    std::uint64_t chunks_failed;
    std::uint64_t total_chunks;
    /// The daemon kept the paid attempt: repeat the same finalize call.
    bool retryable;
    /// Whether the daemon's answer about retention could be read. When false,
    /// `retryable` is false because retention is unknown, not because the
    /// daemon said nothing was kept. Always true when `retryable` is.
    bool retention_known;

    /// `retryable` implies `retention_known`, so a retryable error is always
    /// reported as known.
    PartialUploadError(const std::string& msg,
                       std::uint64_t chunks_stored,
                       std::uint64_t chunks_failed,
                       std::uint64_t total_chunks,
                       bool retryable,
                       bool retention_known)
        : NetworkError(msg),
          chunks_stored(chunks_stored),
          chunks_failed(chunks_failed),
          total_chunks(total_chunks),
          retryable(retryable),
          retention_known(retention_known || retryable) {}

    /// The constructor from before `retention_known` existed, kept for source
    /// compatibility: a retryable error is known, and anything else reads as
    /// unknown (the conservative reading: never pay again on it alone).
    PartialUploadError(const std::string& msg,
                       std::uint64_t chunks_stored,
                       std::uint64_t chunks_failed,
                       std::uint64_t total_chunks,
                       bool retryable)
        : PartialUploadError(msg, chunks_stored, chunks_failed, total_chunks, retryable,
                             retryable) {}
};

/// Counts, retry hint and retention status recovered from a PARTIAL_UPLOAD
/// message.
struct PartialUploadCounts {
    std::uint64_t chunks_stored{0};
    std::uint64_t chunks_failed{0};
    std::uint64_t total_chunks{0};
    bool retryable{false};
    /// True only when the counts parsed and the message ends with one of the
    /// daemon's two retention hints; see parse_partial_upload_message.
    bool retention_known{false};
};

/// The fixed text every PARTIAL_UPLOAD message from the daemon opens with
/// (antd's `Error::PartialUpload` Display impl). gRPC ABORTED is a generic
/// code, so this prefix is what identifies a partial store there.
inline constexpr std::string_view kPartialUploadPrefix = "Partial upload:";

/// Whether a gRPC ABORTED status message is the daemon's PARTIAL_UPLOAD
/// report: true only when the message starts with kPartialUploadPrefix.
/// Pass the raw grpc::Status::error_message().
///
/// Anchored at the start of the message, not a containment check (matching
/// antd-rust). The daemon opens every PARTIAL_UPLOAD message with the prefix
/// and never wraps it, so an ABORTED that merely quotes "Partial upload:"
/// further into its text is some other failure. Treating it as a partial
/// store would report counts read out of unrelated text and possibly
/// `retryable == true`, steering the caller into paid-attempt recovery for an
/// upload the daemon never retained.
inline bool is_partial_upload_message(std::string_view message) {
    return message.substr(0, kPartialUploadPrefix.size()) == kPartialUploadPrefix;
}

namespace detail {

/// Parse a run of ASCII digits as a u64 without throwing: false on overflow
/// or trailing junk. (std::stoull would throw std::out_of_range, which would
/// escape the typed AntdError contract.)
inline bool parse_decimal_u64(const std::string& digits, std::uint64_t& out) {
    const char* first = digits.data();
    const char* last = first + digits.size();
    const auto [ptr, ec] = std::from_chars(first, last, out);
    return ec == std::errc() && ptr == last;
}

/// The two parenthesised hints the daemon closes every PARTIAL_UPLOAD
/// message with (partial_upload_hint in antd/src/error.rs): the retained hint
/// when it kept the paid attempt for a same-upload_id retry, the not-retained
/// hint when it did not. Daemons older than 0.14.0 write only the
/// not-retained hint.
inline constexpr std::string_view kPartialUploadRetainedHint = "paid attempt retained";
inline constexpr std::string_view kPartialUploadNotRetainedHint =
    "stored chunks persist; re-prepare the same content";

/// What the hint that closes a PARTIAL_UPLOAD message says about retention.
enum class PartialUploadRetention { unreadable, retained, not_retained };

/// Read the hint that closes the message, "(<hint>...)" as its very last
/// text: the message ends with ')', the text between that ')' and the last
/// '(' holds no other parenthesis, and it opens with one of the two hints.
/// This is the pattern `\((hint)[^()]*\)` anchored to the end of the input,
/// done by hand so no regex `$` can match before a trailing newline. A hint
/// quoted inside the failure reason, a truncated or unclosed tail, an
/// unrecognised hint, and any text or newline after the closing ')' all read
/// as unreadable.
inline PartialUploadRetention read_partial_upload_retention(std::string_view message) {
    if (message.empty() || message.back() != ')') {
        return PartialUploadRetention::unreadable;
    }
    const auto open = message.rfind('(');
    if (open == std::string_view::npos) {
        return PartialUploadRetention::unreadable;
    }
    const auto inner = message.substr(open + 1, message.size() - open - 2);
    if (inner.find_first_of("()") != std::string_view::npos) {
        return PartialUploadRetention::unreadable;
    }
    const auto opens_with = [inner](std::string_view hint) {
        return inner.substr(0, hint.size()) == hint;
    };
    if (opens_with(kPartialUploadRetainedHint)) {
        return PartialUploadRetention::retained;
    }
    if (opens_with(kPartialUploadNotRetainedHint)) {
        return PartialUploadRetention::not_retained;
    }
    return PartialUploadRetention::unreadable;
}

}  // namespace detail

/// Recover the chunk counts and the retention flags from a PARTIAL_UPLOAD
/// message. Used for gRPC, where the status carries no structured detail;
/// REST callers get the body fields instead. Callers gate on
/// is_partial_upload_message first: this parser only reads the fields and
/// does not decide whether the message is a partial upload.
///
/// The daemon writes "Partial upload: <stored>/<total> chunks stored,
/// <failed> failed after retries: <reason> (<hint>)", where the hint is
/// "paid attempt retained..." or "stored chunks persist; re-prepare the same
/// content..." (partial_upload_hint in antd/src/error.rs). The counts must
/// open the message (the match is anchored at its start, like
/// is_partial_upload_message) and the hint must close it:
///
///   - Counts parse and the message ends with the retained hint:
///     `retention_known` and `retryable`.
///   - Counts parse and the message ends with the not-retained hint:
///     `retention_known`, not `retryable` (the daemon confirmed nothing was
///     retained).
///   - Counts parse but the closing hint is missing, truncated, unclosed,
///     unrecognised, or followed by any text or newline: the counts are kept
///     but both flags are false. The daemon's answer on retention was not
///     read, so retention is unknown (stop and reconcile), never "nothing
///     retained". A hint quoted inside the failure reason is not read as the
///     answer; only the hint that closes the message counts.
///   - A pattern miss or any conversion failure (e.g. a count that overflows
///     64 bits): all three counts are zero and both flags are false, even
///     with a hint; a bounded retry loop could not watch `chunks_failed`
///     shrink without the counts anyway.
///
/// Never throws.
inline PartialUploadCounts parse_partial_upload_message(std::string_view message) {
    static const std::regex kCounts(
        R"(Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed)");
    PartialUploadCounts out;
    std::match_results<std::string_view::const_iterator> m;
    if (!std::regex_search(message.begin(), message.end(), m, kCounts,
                           std::regex_constants::match_continuous)) {
        return out;
    }
    std::uint64_t stored = 0;
    std::uint64_t total = 0;
    std::uint64_t failed = 0;
    if (!detail::parse_decimal_u64(m[1].str(), stored) ||
        !detail::parse_decimal_u64(m[2].str(), total) ||
        !detail::parse_decimal_u64(m[3].str(), failed)) {
        return out;
    }
    out.chunks_stored = stored;
    out.total_chunks = total;
    out.chunks_failed = failed;
    switch (detail::read_partial_upload_retention(message)) {
        case detail::PartialUploadRetention::retained:
            out.retention_known = true;
            out.retryable = true;
            break;
        case detail::PartialUploadRetention::not_retained:
            out.retention_known = true;
            break;
        case detail::PartialUploadRetention::unreadable:
            break;  // counts kept, retention unknown
    }
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
