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

    /// The pointer is at its final state, transferred or frozen: nothing can
    /// update it or hand it over again (HTTP 409 with
    /// `code: "POINTER_FINAL"`; gRPC `FAILED_PRECONDITION` with
    /// `x-antd-error-code: POINTER_FINAL`). Usually refused before anything
    /// is paid: the daemon reads the pointer first. A write that was already
    /// paid for when the network refused it (the pointer became final while
    /// the write was in flight) keeps that payment, so read the pointer before
    /// paying again.
    #[error("antd error 409 (pointer final): {0}")]
    PointerFinal(String),

    /// The pointer's owner signed two different final states and no one of
    /// them is held by a majority of the close group, so there is no answer
    /// to give (HTTP 409 with `code: "POINTER_FORKED"`; gRPC
    /// `FAILED_PRECONDITION` with `x-antd-error-code: POINTER_FORKED`).
    #[error("antd error 409 (pointer forked): {0}")]
    PointerForked(String),

    /// The request conflicts with the resource's current state (HTTP 409 with
    /// `code: "CONFLICT"`; gRPC `ABORTED` with `x-antd-error-code: CONFLICT`).
    /// For pointers, two cases share this code, and it does not say which one
    /// happened or whether anything was paid: a write while a prepared write
    /// to the same pointer awaits payment is refused before paying (finalize
    /// the prepared write, or wait for it to expire); an update that lost to a
    /// newer state while it was in flight may already have been paid for.
    /// Read the pointer again and check what was paid before submitting
    /// another paid write.
    #[error("antd error 409 (conflict): {0}")]
    Conflict(String),

    /// Too few of an address's close group answered, or took a write, for
    /// the result to be the network's (HTTP 503 with
    /// `code: "CLOSE_GROUP_SHORTFALL"`; gRPC `UNAVAILABLE` with
    /// `x-antd-error-code: CLOSE_GROUP_SHORTFALL`). Reads are free to retry.
    /// A paid write is not, unless `retryable` is `true`: a pointer finalize
    /// then kept the paid state under the same `upload_id`, and repeating
    /// that finalize stores it against the same payment.
    #[error("antd error 503 (close group shortfall): {message}")]
    CloseGroupShortfall {
        /// `true` when a pointer finalize kept the paid state for a repeat
        /// with the same `upload_id`. `false` otherwise, including every read
        /// and every daemon-wallet write.
        retryable: bool,
        /// The daemon's error message.
        message: String,
    },

    /// A finalize stored some chunks while others stayed unstored after the
    /// daemon's own retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC
    /// `ABORTED` whose message starts with `Partial upload:`). The on-chain
    /// payment persists and the stored chunks stay on the network. How to
    /// finish the upload depends on `retryable` and `retention_known`
    /// (`retryable` implies `retention_known`):
    ///
    /// - `retryable` — the daemon kept the paid attempt (payment proofs +
    ///   unstored chunks) under the same `upload_id`. Call the **same**
    ///   finalize method again with the same `upload_id` and the same payment
    ///   artefacts (`tx_hashes`, or the winning pool hash of a merkle upload)
    ///   to store the remainder against the same payment: no re-prepare, no
    ///   second signature, no double payment. Bound the loop: a persistent
    ///   failure returns this error on every call, so cap the attempts and
    ///   treat a `chunks_failed` that stops shrinking as stuck. The retained
    ///   attempt expires with the daemon's pending-upload TTL.
    /// - `retention_known && !retryable` — the daemon confirmed it kept
    ///   nothing (for example a merkle finalize with deliberately unpaid
    ///   batches). Re-prepare the same content: already-stored chunks are
    ///   skipped, so the new payment covers only the remainder.
    /// - `!retention_known` — retention is unknown: the reply did not
    ///   establish whether the daemon kept the paid attempt (antd older than
    ///   0.14.0 never sends `retryable` over REST; a gRPC message whose counts
    ///   do not parse, or that does not end with one of the daemon's two
    ///   retention hints). The daemon may still hold the attempt, so this
    ///   does **not** mean nothing was retained. Stop automatic recovery, keep
    ///   the `upload_id` and the original payment artefacts, and reconcile the
    ///   retained attempt before deciding to re-prepare or pay again. Never
    ///   pay again on this signal alone: re-preparing skips already-stored
    ///   chunks, but it can still pay a second time for chunks that were paid
    ///   for and not stored.
    ///
    /// Over REST the fields come from the structured error body: a count is
    /// a JSON non-negative integer (anything else reads as 0), and
    /// `retention_known` is `true` only when the body carries `retryable` as a
    /// JSON bool. Over gRPC they are parsed from the status message, which
    /// the daemon writes as
    /// `Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)`.
    /// The closing hint starts `paid attempt retained` when the daemon kept
    /// the attempt and `stored chunks persist; re-prepare the same content`
    /// when it did not (daemons older than 0.14.0 write only the second).
    /// `retention_known` is `true` only when the message starts with the
    /// counts, all three convert to `u64`, and the message ends with one of
    /// the two hints; `retryable` is then `true` only for the first. A message
    /// that starts with the `Partial upload:` prefix but whose counts are
    /// garbled or overflow `u64` reads as zero counts with both flags `false`,
    /// hint or not. Readable counts with a missing, truncated or unrecognised
    /// hint, or text after it, keep the counts but also leave both flags
    /// `false`: retention unknown (stop and reconcile), not "nothing
    /// retained". An `ABORTED` status that does not start with that prefix is
    /// not a partial store and stays [`AntdError::Grpc`].
    ///
    /// New in 0.2.0: earlier releases surfaced a partial store as
    /// [`AntdError::Network`] over REST and [`AntdError::Grpc`] over gRPC.
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
        /// `true` when the daemon kept the paid attempt: the same finalize
        /// call (same `upload_id`, same payment artefacts) stores the
        /// remainder against the same payment. Implies `retention_known`.
        retryable: bool,
        /// `true` when the daemon's reply established whether it kept the
        /// paid attempt, so `retryable == false` means nothing was retained
        /// and re-preparing is the way to finish. `false` means retention is
        /// unknown: stop, keep the `upload_id` and payment artefacts, and
        /// reconcile before re-preparing or paying again.
        retention_known: bool,
        /// The daemon's error message.
        message: String,
    },

    /// A byte-range download started at or past the end of the object: HTTP
    /// 416, or gRPC `OUT_OF_RANGE` from a range method's call. Any REST 416
    /// maps here, but only the range methods send a `Range` header, so only
    /// they get one. (Other gRPC calls keep `OUT_OF_RANGE` as
    /// [`AntdError::Grpc`], since tonic also uses that code for a local
    /// message-size error.)
    #[error("antd error 416: {message}")]
    RangeNotSatisfiable {
        /// The object's plaintext size, when the daemon reported it: from the
        /// 416's `Content-Range: bytes */size` over REST, or the
        /// `x-content-range` metadata over gRPC. `None` when the daemon sent
        /// neither (older daemons' gRPC errors carry no size).
        size: Option<u64>,
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
        if let Some(e) = typed_status_error(&status) {
            return e;
        }
        match status.code() {
            // INVALID_ARGUMENT is the REST 400, on every call. Reached only
            // when no `x-antd-error-code` tag took the status above.
            tonic::Code::InvalidArgument => AntdError::BadRequest(status.message().to_string()),
            // PARTIAL_UPLOAD: some chunks stored, some still unstored after
            // retries. The daemon opens every such message with the fixed
            // `Partial upload:` prefix, so gate on it: any other ABORTED keeps
            // the generic mapping rather than being misreported as a partial
            // store. The counts and the retention hint ride the message text
            // over gRPC (no structured detail yet), so parse them to match
            // the REST client's typed error; retention is known only when the
            // counts parse and the message ends with one of the daemon's two
            // retention hints, and only the "paid attempt retained" hint
            // enables retry.
            // Anchored at the start of the message, matching the count parser:
            // a `Partial upload:` marker embedded in some other ABORTED text
            // must not select paid-attempt recovery with zero counts.
            tonic::Code::Aborted if status.message().starts_with(PARTIAL_UPLOAD_PREFIX) => {
                let message = status.message().to_string();
                let (chunks_stored, chunks_failed, total_chunks, retryable, retention_known) =
                    parse_partial_upload_message(&message);
                AntdError::PartialUpload {
                    chunks_stored,
                    chunks_failed,
                    total_chunks,
                    retryable,
                    retention_known,
                    message,
                }
            }
            // OUT_OF_RANGE is not mapped here: tonic also uses it for a local
            // "decoded message length too large" error. The range methods map
            // it to RangeNotSatisfiable themselves (see
            // `crate::range::range_call_error`).
            _ => AntdError::Grpc(Box::new(status)),
        }
    }
}

/// Metadata key the daemon (with the pointer API, after 0.15.0) sets on statuses whose gRPC code
/// is shared with older errors, carrying the REST `code` string.
const ANTD_ERROR_CODE_METADATA: &str = "x-antd-error-code";

/// The typed error for a status the daemon tagged with `x-antd-error-code`,
/// when the tag and the gRPC code agree. Anything else (an untagged status, a
/// tag this SDK does not know, or a tag on an unexpected code) is `None` and
/// keeps the code-based mapping.
fn typed_status_error(status: &tonic::Status) -> Option<AntdError> {
    let tag = status
        .metadata()
        .get(ANTD_ERROR_CODE_METADATA)?
        .to_str()
        .ok()?;
    let message = status.message().to_string();
    Some(match (status.code(), tag) {
        (tonic::Code::FailedPrecondition, "POINTER_FINAL") => AntdError::PointerFinal(message),
        (tonic::Code::FailedPrecondition, "POINTER_FORKED") => AntdError::PointerForked(message),
        (tonic::Code::Aborted, "CONFLICT") => AntdError::Conflict(message),
        (tonic::Code::Unavailable, "CLOSE_GROUP_SHORTFALL") => AntdError::CloseGroupShortfall {
            // gRPC carries no structured detail: a retained pointer finalize
            // closes its message with the same "(paid attempt retained...)"
            // hint a retained partial upload does.
            retryable: closing_retention_hint(&message) == Some(true),
            message,
        },
        _ => return None,
    })
}

/// Fixed text the daemon opens every `PARTIAL_UPLOAD` message with; a gRPC
/// `ABORTED` status is a partial store only when its message starts with it.
const PARTIAL_UPLOAD_PREFIX: &str = "Partial upload:";

/// The daemon closes every `PARTIAL_UPLOAD` message with one of two
/// parenthesised hints (`partial_upload_hint` in `antd/src/error.rs`): this
/// one when it kept the paid attempt for a same-`upload_id` retry, and
/// [`PARTIAL_UPLOAD_NOT_RETAINED_HINT`] when it did not. Daemons older than
/// 0.14.0 write only the not-retained hint.
const PARTIAL_UPLOAD_RETAINED_HINT: &str = "paid attempt retained";

/// Opening of the hint the daemon closes a `PARTIAL_UPLOAD` message with when
/// it did not keep the paid attempt (see [`PARTIAL_UPLOAD_RETAINED_HINT`]).
const PARTIAL_UPLOAD_NOT_RETAINED_HINT: &str = "stored chunks persist; re-prepare the same content";

/// Recovers `(stored, failed, total, retryable, retention_known)` from a
/// `PARTIAL_UPLOAD` message. Used for gRPC, where the status carries no
/// structured detail; REST callers get the body fields instead.
///
/// The message must start with `Partial upload: <stored>/<total> chunks
/// stored, <failed> failed`, and every count must convert to a `u64`. Any
/// miss (a message that does not fit the pattern, or a count that is not a
/// plain `u64`, such as one that overflows) yields `(0, 0, 0, false, false)`
/// even when a hint is there. Invalid fields must not enable recovery: a
/// same-`upload_id` retry acts on these counts (a bounded loop watches
/// `chunks_failed` shrink), so it is offered only for a message the client
/// fully understood.
///
/// Readable counts alone do not establish retention: `retention_known` is
/// `true` only when the message also ends with one of the daemon's two
/// hints (see [`closing_retention_hint`]), and `retryable` is then `true`
/// only for the retained one. A missing, truncated or unrecognised hint, or
/// any text after it, keeps the counts but leaves both flags `false`.
///
/// Neither kind of miss means nothing was retained: the daemon may still hold
/// the paid attempt, so retention reads as unknown and the caller reconciles
/// before re-preparing or paying again.
pub(crate) fn parse_partial_upload_message(msg: &str) -> (u64, u64, u64, bool, bool) {
    let counts = (|| {
        let rest = msg.strip_prefix(PARTIAL_UPLOAD_PREFIX)?.strip_prefix(' ')?;
        let (stored, rest) = take_u64(rest)?;
        let (total, rest) = take_u64(rest.strip_prefix('/')?)?;
        let (failed, rest) = take_u64(rest.strip_prefix(" chunks stored, ")?)?;
        rest.starts_with(" failed")
            .then_some((stored, failed, total))
    })();
    let Some((stored, failed, total)) = counts else {
        return (0, 0, 0, false, false);
    };
    match closing_retention_hint(msg) {
        Some(retryable) => (stored, failed, total, retryable, true),
        None => (stored, failed, total, false, false),
    }
}

/// Reads the hint that closes a `PARTIAL_UPLOAD` message: `Some(true)` for
/// the retained hint, `Some(false)` for the not-retained hint, `None` for
/// anything else.
///
/// Equivalent to the pattern `\((<retained>|<not retained>)[^()]*\)\z`: the
/// message must end with `)`, and the text after its last `(` must start with
/// one of the two hints and hold no other parenthesis. So a hint quoted
/// inside the failure reason, a truncated or unclosed hint, and any text
/// after the hint (a trailing newline included) are not read as the daemon's
/// answer.
fn closing_retention_hint(msg: &str) -> Option<bool> {
    let inner = msg.strip_suffix(')')?;
    let hint = &inner[inner.rfind('(')? + 1..];
    if hint.contains(')') {
        None
    } else if hint.starts_with(PARTIAL_UPLOAD_RETAINED_HINT) {
        Some(true)
    } else if hint.starts_with(PARTIAL_UPLOAD_NOT_RETAINED_HINT) {
        Some(false)
    } else {
        None
    }
}

/// Splits a leading run of ASCII digits off `s` as a `u64`; `None` when the
/// run is empty or overflows `u64`.
fn take_u64(s: &str) -> Option<(u64, &str)> {
    let end = s.bytes().take_while(u8::is_ascii_digit).count();
    let n = s[..end].parse().ok()?;
    Some((n, &s[end..]))
}

/// Maps a non-2xx REST response onto an [`AntdError`], preferring the
/// machine-readable `code` over the bare HTTP status where they diverge:
/// `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a generic
/// [`AntdError::Network`], and `POINTER_FINAL`, `POINTER_FORKED` and
/// `CONFLICT` are 409s that must not read as [`AntdError::AlreadyExists`].
/// Every other code keeps the status-based mapping of [`error_for_status`].
/// A body that is not JSON is used verbatim as the message.
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
        // Only a JSON bool `retryable` establishes retention. It is absent on
        // antd < 0.14.0; absent or any other type reads as unknown retention
        // (not "nothing retained"), so the caller stops and reconciles rather
        // than paying again.
        let retryable = body.get("retryable").and_then(Value::as_bool);
        return AntdError::PartialUpload {
            chunks_stored: count("chunks_stored"),
            chunks_failed: count("chunks_failed"),
            total_chunks: count("total_chunks"),
            retryable: retryable.unwrap_or(false),
            retention_known: retryable.is_some(),
            message,
        };
    }
    match body.get("code").and_then(Value::as_str) {
        Some("POINTER_FINAL") => AntdError::PointerFinal(message),
        Some("POINTER_FORKED") => AntdError::PointerForked(message),
        Some("CONFLICT") => AntdError::Conflict(message),
        Some("CLOSE_GROUP_SHORTFALL") => AntdError::CloseGroupShortfall {
            // Present, and true, only on a pointer finalize that kept the
            // paid state; anything else reads as not retained.
            retryable: body.get("retryable").and_then(Value::as_bool) == Some(true),
            message,
        },
        _ => error_for_status(code, message),
    }
}

/// Maps an HTTP status code and message to the appropriate [`AntdError`] variant.
pub fn error_for_status(code: u16, message: String) -> AntdError {
    match code {
        400 => AntdError::BadRequest(message),
        402 => AntdError::Payment(message),
        404 => AntdError::NotFound(message),
        409 => AntdError::AlreadyExists(message),
        413 => AntdError::TooLarge(message),
        // The size comes from the response's Content-Range header, which the
        // range methods read; a bare status carries none.
        416 => AntdError::RangeNotSatisfiable {
            size: None,
            message,
        },
        500 => AntdError::Internal(message),
        502 => AntdError::Network(message),
        503 => AntdError::ServiceUnavailable(message),
        _ => AntdError::Internal(format!("unexpected status {code}: {message}")),
    }
}
