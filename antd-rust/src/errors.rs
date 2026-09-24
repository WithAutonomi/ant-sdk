use serde_json::Value;
use thiserror::Error;

/// Error types returned by the antd REST client.
#[derive(Error, Debug)]
pub enum AntdError {
    /// Invalid request parameters (HTTP 400).
    #[error("antd error 400: {0}")]
    BadRequest(String),

    /// Insufficient funds or payment failure (HTTP 402).
    #[error("antd error 402: {0}")]
    Payment(String),

    /// Resource not found on the network (HTTP 404).
    #[error("antd error 404: {0}")]
    NotFound(String),

    /// Resource already exists (HTTP 409).
    #[error("antd error 409: {0}")]
    AlreadyExists(String),

    /// Version conflict or fork detected (HTTP 409).
    #[error("antd error 409 (fork): {0}")]
    Fork(String),

    /// Payload too large (HTTP 413).
    #[error("antd error 413: {0}")]
    TooLarge(String),

    /// Internal server error (HTTP 500).
    #[error("antd error 500: {0}")]
    Internal(String),

    /// Daemon cannot reach the network (HTTP 502).
    #[error("antd error 502: {0}")]
    Network(String),

    /// Service unavailable, e.g. wallet not configured (HTTP 503).
    #[error("antd error 503: {0}")]
    ServiceUnavailable(String),

    /// A finalize stored some chunks while others stayed unstored after the
    /// daemon's own retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC
    /// `ABORTED` whose message starts with `Partial upload:`). The on-chain
    /// payment persists and the stored chunks stay on the network. How to
    /// finish the upload depends on `retryable`:
    ///
    /// - `true` — the daemon kept the paid attempt (payment proofs + unstored
    ///   chunks) under the same `upload_id`. Call the **same** finalize method
    ///   again with the same arguments to store the remainder against the
    ///   same payment: no re-prepare, no second signature, no double payment.
    ///   Bound the loop: a persistent failure returns this error on every
    ///   call, so cap the attempts and treat a `chunks_failed` that stops
    ///   shrinking as stuck. The retained attempt expires with the daemon's
    ///   pending-upload TTL. Sent by antd >= 0.14.0; older daemons never set
    ///   the flag, so it reads `false` and the re-prepare path applies.
    /// - `false` — nothing was retained (a merkle finalize with deliberately
    ///   unpaid batches, or an older daemon). Re-preparing the same content
    ///   skips already-stored chunks, so a retry pays only for the remainder.
    ///
    /// Over REST the counts and `retryable` come from the structured error
    /// body. Over gRPC they are parsed best-effort from the status message
    /// (`Partial upload: S/T chunks stored, F failed ...`, with a
    /// `paid attempt retained` hint when retryable); a message that carries
    /// the `Partial upload:` prefix but garbled counts leaves the counts zero
    /// and `retryable` false. An `ABORTED` status without that prefix is not
    /// a partial store and stays [`AntdError::Grpc`].
    ///
    /// See `docs/external-signer-flow.md` §6 ("Retry a partial store") in the
    /// [ant-sdk repository](https://github.com/WithAutonomi/ant-sdk/blob/main/docs/external-signer-flow.md).
    #[error("antd error 502 (partial upload): {message}")]
    PartialUpload {
        /// Chunks the daemon confirmed stored at quorum.
        chunks_stored: u64,
        /// Chunks still unstored after the daemon's retries.
        chunks_failed: u64,
        /// Chunks in the upload (`chunks_stored + chunks_failed`).
        total_chunks: u64,
        /// `true` when the same finalize call (same `upload_id`) stores the
        /// remainder against the same payment; `false` when the retry is a
        /// re-prepare.
        retryable: bool,
        /// The daemon's error message.
        message: String,
    },

    /// HTTP transport error from reqwest.
    #[error("http error: {0}")]
    Http(#[from] reqwest::Error),

    /// JSON serialization/deserialization error.
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),

    /// gRPC transport or status error.
    ///
    /// Boxed because `tonic::Status` is ~176 bytes — keeping it inline would
    /// blow up every `Result<T, AntdError>` return site (clippy::result_large_err).
    #[error("grpc error: {0}")]
    Grpc(Box<tonic::Status>),
}

impl From<tonic::Status> for AntdError {
    fn from(status: tonic::Status) -> Self {
        match status.code() {
            // PARTIAL_UPLOAD: some chunks stored, some still unstored after
            // retries. The daemon opens every such message with the fixed
            // `Partial upload:` prefix, so gate on it: any other ABORTED keeps
            // the generic mapping rather than being misreported as a partial
            // store. The counts and the "paid attempt retained" hint ride the
            // message text over gRPC (no structured detail yet), so parse
            // them best-effort to match the REST client's typed error.
            tonic::Code::Aborted if status.message().contains(PARTIAL_UPLOAD_PREFIX) => {
                let message = status.message().to_string();
                let (chunks_stored, chunks_failed, total_chunks, retryable) =
                    parse_partial_upload_message(&message);
                AntdError::PartialUpload {
                    chunks_stored,
                    chunks_failed,
                    total_chunks,
                    retryable,
                    message,
                }
            }
            _ => AntdError::Grpc(Box::new(status)),
        }
    }
}

/// Fixed text the daemon opens every `PARTIAL_UPLOAD` message with; a gRPC
/// `ABORTED` status is a partial store only when its message carries it.
const PARTIAL_UPLOAD_PREFIX: &str = "Partial upload:";

/// Message tail the daemon appends when it kept the paid attempt for a
/// same-`upload_id` retry.
const PARTIAL_UPLOAD_RETAINED_HINT: &str = "paid attempt retained";

/// Recovers `(stored, failed, total, retryable)` from a `PARTIAL_UPLOAD`
/// message. Used for gRPC, where the status carries no structured detail;
/// REST callers get the body fields instead.
///
/// Matches the fixed prefix `Partial upload: <stored>/<total> chunks stored,
/// <failed> failed`; anything else yields zero counts. `retryable` is the
/// presence of the retained hint anywhere in the message.
pub(crate) fn parse_partial_upload_message(msg: &str) -> (u64, u64, u64, bool) {
    let retryable = msg.contains(PARTIAL_UPLOAD_RETAINED_HINT);
    let counts = (|| {
        let rest = msg.strip_prefix(PARTIAL_UPLOAD_PREFIX)?.strip_prefix(' ')?;
        let (stored, rest) = take_u64(rest)?;
        let (total, rest) = take_u64(rest.strip_prefix('/')?)?;
        let (failed, _) = take_u64(rest.strip_prefix(" chunks stored, ")?)?;
        Some((stored, failed, total))
    })();
    let (stored, failed, total) = counts.unwrap_or((0, 0, 0));
    (stored, failed, total, retryable)
}

/// Splits a leading run of ASCII digits off `s` as a `u64`.
fn take_u64(s: &str) -> Option<(u64, &str)> {
    let end = s.bytes().take_while(u8::is_ascii_digit).count();
    let n = s[..end].parse().ok()?;
    Some((n, &s[end..]))
}

/// Maps a non-2xx REST response onto an [`AntdError`], preferring the
/// machine-readable `code` over the bare HTTP status where they diverge:
/// `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a generic
/// [`AntdError::Network`]. Every other code keeps the status-based mapping
/// of [`error_for_status`]. A body that is not JSON is used verbatim as the
/// message.
pub fn error_for_body(code: u16, bytes: &[u8]) -> AntdError {
    let Ok(body) = serde_json::from_slice::<Value>(bytes) else {
        return error_for_status(code, String::from_utf8_lossy(bytes).to_string());
    };
    let message = body
        .get("error")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    if body.get("code").and_then(Value::as_str) == Some("PARTIAL_UPLOAD") {
        let count = |k: &str| body.get(k).and_then(Value::as_u64).unwrap_or(0);
        return AntdError::PartialUpload {
            chunks_stored: count("chunks_stored"),
            chunks_failed: count("chunks_failed"),
            total_chunks: count("total_chunks"),
            // Absent on antd < 0.14.0: the daemon dropped the upload_id, so
            // the caller must take the re-prepare path.
            retryable: body
                .get("retryable")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            message,
        };
    }
    error_for_status(code, message)
}

/// Maps an HTTP status code and message to the appropriate [`AntdError`] variant.
pub fn error_for_status(code: u16, message: String) -> AntdError {
    match code {
        400 => AntdError::BadRequest(message),
        402 => AntdError::Payment(message),
        404 => AntdError::NotFound(message),
        409 => AntdError::AlreadyExists(message),
        413 => AntdError::TooLarge(message),
        500 => AntdError::Internal(message),
        502 => AntdError::Network(message),
        503 => AntdError::ServiceUnavailable(message),
        _ => AntdError::Internal(format!("unexpected status {code}: {message}")),
    }
}
