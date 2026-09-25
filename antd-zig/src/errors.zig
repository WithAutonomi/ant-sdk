const std = @import("std");

/// Error set for antd client operations.
pub const AntdError = error{
    BadRequest,
    Payment,
    NotFound,
    AlreadyExists,
    Fork,
    TooLarge,
    Internal,
    Network,
    ServiceUnavailable,
    /// A finalize stored some chunks while others remained unstored after
    /// the daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`). The
    /// on-chain payment persists and the stored chunks stay on the network.
    /// `Client.getLastError()` carries the counts and the `retryable` /
    /// `retention_known` flags; see `ErrorInfo` for how to finish the upload.
    /// Earlier SDK versions surfaced this 502 as `error.Network`; error sets
    /// have no subtyping, so an `error.Network` prong does not see it.
    PartialUpload,
    UnexpectedStatus,
    HttpError,
    JsonError,
};

/// Carries HTTP status code and message alongside an AntdError.
///
/// The partial-upload fields are populated only for `error.PartialUpload`
/// and read zero / false for every other error. How to finish a partial
/// upload depends on `retryable` and `retention_known`:
///
///   - `retryable`: the daemon kept the paid attempt (payment proofs +
///     unstored chunks) under the same `upload_id`. Call the same finalize
///     function again with the same arguments to store the remainder against
///     the same payment — no re-prepare, no second signature, no double
///     payment. Bound the loop: a persistent failure returns
///     `error.PartialUpload` on every call, so cap the attempts and treat a
///     `chunks_failed` that stops shrinking as stuck. The retained attempt
///     expires with the daemon's pending-upload TTL.
///   - `retention_known and !retryable`: the daemon confirmed nothing was
///     retained (e.g. a merkle finalize with deliberately unpaid batches).
///     Re-preparing the same content skips already-stored chunks, so a
///     retry pays only for the missing remainder.
///   - `!retention_known`: retention is unknown. The flag was missing (every
///     daemon older than 0.14.0 omits it), null or not a boolean. The daemon
///     records the resume handle before it returns the error, so it may
///     still hold the paid attempt. Stop automatic recovery, keep the
///     `upload_id` and the original payment artefacts, and reconcile before
///     re-preparing or paying again. Never pay again on this signal alone.
///
/// See docs/external-signer-flow.md, section 6 ("Retry a partial store").
pub const ErrorInfo = struct {
    status_code: u16,
    message: []const u8,
    /// Chunks the daemon stored before giving up (`PartialUpload` only).
    chunks_stored: u64 = 0,
    /// Chunks still unstored after the daemon's retries (`PartialUpload` only).
    chunks_failed: u64 = 0,
    /// Chunks in the upload (`PartialUpload` only).
    total_chunks: u64 = 0,
    /// `true` when the paid attempt was retained and the same finalize call
    /// stores the remainder against the same payment (`PartialUpload` only).
    retryable: bool = false,
    /// `true` when the daemon stated whether it retained the paid attempt:
    /// the body carried `retryable` as a JSON boolean. `false` when the flag
    /// was missing (antd < 0.14.0), null or not a boolean; `retryable` then
    /// reads false, but retention is unknown, not ruled out. Always `true`
    /// when `retryable` is (`PartialUpload` only).
    retention_known: bool = false,
};

/// Machine-readable `code` the daemon sends for a partial upload.
pub const partial_upload_code = "PARTIAL_UPLOAD";

/// Maps a REST error response onto an AntdError, preferring the body's
/// machine-readable `code` over the bare HTTP status where they diverge
/// (`PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a generic
/// `error.Network`). `code` is empty when the body carried none; every other
/// code keeps the status-based mapping of `errorForStatus`.
pub fn errorForResponse(status_code: u16, code: []const u8) AntdError {
    if (std.mem.eql(u8, code, partial_upload_code)) return error.PartialUpload;
    return errorForStatus(status_code);
}

/// Maps an HTTP status code to the corresponding AntdError.
pub fn errorForStatus(code: u16) AntdError {
    return switch (code) {
        400 => error.BadRequest,
        402 => error.Payment,
        404 => error.NotFound,
        409 => error.AlreadyExists,
        413 => error.TooLarge,
        500 => error.Internal,
        502 => error.Network,
        503 => error.ServiceUnavailable,
        else => error.UnexpectedStatus,
    };
}
