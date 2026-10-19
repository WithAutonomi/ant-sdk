use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum AntdError {
    #[error("Record not found: {0}")]
    NotFound(String),

    #[error("Already exists: {0}")]
    AlreadyExists(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Payment error: {0}")]
    Payment(String),

    #[error("Network error: {0}")]
    Network(String),

    #[error("Too large for memory")]
    TooLarge,

    #[error("Timeout: {0}")]
    Timeout(String),

    #[error("Service unavailable: {0}")]
    ServiceUnavailable(String),

    #[error("Not implemented: {0}")]
    NotImplemented(String),

    #[error("Internal error: {0}")]
    Internal(String),

    /// Too few of an address's close group answered, or took a write, for the
    /// result to be the network's. Reads are free to retry; a paid write is
    /// not, except where `retryable` says the paid attempt was kept (a pointer
    /// finalize repeated with the same `upload_id`).
    #[error("Close group shortfall: {message}")]
    CloseGroupShortfall {
        message: String,
        retryable: Option<bool>,
    },

    /// The pointer is at its final state (transferred or frozen): nothing can
    /// update it or hand it over again.
    #[error("Pointer is final: {0}")]
    PointerFinal(String),

    /// The pointer's owner signed two different final states, and no one of
    /// them is held by a majority of the close group.
    #[error("Pointer is forked: {0}")]
    PointerForked(String),

    /// The request conflicts with the resource's current state, such as a
    /// pointer write while a prepared write to it awaits payment.
    #[error("Conflict: {0}")]
    Conflict(String),

    /// A byte-range download (V2-1425) that starts at or past the end of the
    /// object. `size` is the object's plaintext size, reported back so the
    /// caller can re-issue a satisfiable range.
    #[error("Range not satisfiable: the object is {size} bytes")]
    RangeNotSatisfiable { size: u64 },

    /// Upload partially succeeded: some chunks stored, some failed quorum
    /// after all retries. The payment was made and the stored chunks persist.
    ///
    /// `retryable` says how to finish the upload:
    ///
    /// - `true` — an external-signer finalize kept the paid attempt (payment
    ///   proofs + unstored chunks) under the same `upload_id`. Call the same
    ///   finalize endpoint again with that `upload_id` to store the remainder
    ///   against the **same** on-chain payment — no re-prepare, no second
    ///   signature, no double payment. Bound the retry loop: a persistent
    ///   failure comes back as `PARTIAL_UPLOAD` on every call.
    /// - `false` — nothing was retained (daemon-wallet uploads, or a merkle
    ///   finalize that deliberately left some sub-batches unpaid).
    ///   Re-preparing the same content skips already-stored chunks, so a
    ///   retry only pays for and stores the missing remainder.
    #[error(
        "Partial upload: {stored}/{total} chunks stored, {failed} failed after retries: {reason} \
         ({})",
        partial_upload_hint(.retryable)
    )]
    PartialUpload {
        stored: u64,
        failed: u64,
        total: u64,
        reason: String,
        retryable: bool,
    },
}

/// Tail of the `PARTIAL_UPLOAD` message: how the caller finishes the upload.
fn partial_upload_hint(retryable: &bool) -> &'static str {
    if *retryable {
        "paid attempt retained: call finalize again with the same upload_id to store the \
         remainder against the same payment"
    } else {
        "stored chunks persist; re-prepare the same content to retry only the remainder"
    }
}

impl AntdError {
    /// Returns a machine-readable error code string for JSON responses.
    pub fn code(&self) -> &str {
        match self {
            AntdError::NotFound(_) => "NOT_FOUND",
            AntdError::AlreadyExists(_) => "ALREADY_EXISTS",
            AntdError::BadRequest(_) => "BAD_REQUEST",
            AntdError::Payment(_) => "PAYMENT_REQUIRED",
            AntdError::Network(_) => "NETWORK_ERROR",
            AntdError::TooLarge => "TOO_LARGE",
            AntdError::Timeout(_) => "TIMEOUT",
            AntdError::ServiceUnavailable(_) => "SERVICE_UNAVAILABLE",
            AntdError::NotImplemented(_) => "NOT_IMPLEMENTED",
            AntdError::Internal(_) => "INTERNAL_ERROR",
            AntdError::RangeNotSatisfiable { .. } => "RANGE_NOT_SATISFIABLE",
            AntdError::PartialUpload { .. } => "PARTIAL_UPLOAD",
            AntdError::CloseGroupShortfall { .. } => "CLOSE_GROUP_SHORTFALL",
            AntdError::PointerFinal(_) => "POINTER_FINAL",
            AntdError::PointerForked(_) => "POINTER_FORKED",
            AntdError::Conflict(_) => "CONFLICT",
        }
    }

    /// Whether the paid attempt was retained, so the same finalize (same
    /// `upload_id`) may be repeated against the same payment. `None` where
    /// that is unknown or does not apply.
    pub fn retryable(&self) -> Option<bool> {
        match self {
            AntdError::PartialUpload { retryable, .. } => Some(*retryable),
            AntdError::CloseGroupShortfall { retryable, .. } => *retryable,
            _ => None,
        }
    }

    /// Convert an ant-core error into an AntdError.
    pub fn from_core(e: ant_core::data::Error) -> Self {
        use ant_core::data::Error;
        match e {
            Error::AlreadyStored => AntdError::AlreadyExists("already stored".into()),
            // e.g. `data_map_fetch` on an address nothing was ever stored at:
            // a 404 / NOT_FOUND for the caller, not a daemon-internal error.
            Error::NotFound(msg) => AntdError::NotFound(msg),
            Error::InvalidData(msg) => AntdError::BadRequest(msg),
            Error::Payment(msg) => AntdError::Payment(msg),
            Error::Network(msg) => AntdError::Network(msg),
            Error::Timeout(msg) => AntdError::Timeout(msg),
            Error::InsufficientPeers(msg) => AntdError::Network(msg),
            Error::Protocol(msg) => AntdError::Internal(msg),
            Error::Encryption(msg) => AntdError::Internal(msg),
            Error::Serialization(msg) => AntdError::Internal(msg),
            // Too few of a close group answered or stored: a gateway-side
            // condition the caller can wait out, not a daemon fault.
            Error::CloseGroupShortfall(message) => AntdError::CloseGroupShortfall {
                message,
                retryable: None,
            },
            Error::PointerFinal(msg) => AntdError::PointerFinal(msg),
            Error::PointerForked(msg) => AntdError::PointerForked(msg),
            // The daemon-wallet upload paths and the non-resumable external
            // finalize raise this when chunks miss quorum after retries;
            // nothing is retained on this path, so the retry is a re-prepare.
            // (The resumable external finalize never returns this error — it
            // reports a shortfall through `FinalizeOutcome::Partial`, which
            // the upload handlers turn into a `retryable: true` error after
            // retaining the resume handle.) Keep the counts structured so
            // clients can drive a retry instead of parsing text.
            Error::PartialUpload {
                stored_count,
                failed_count,
                total_chunks,
                reason,
                ..
            } => AntdError::PartialUpload {
                stored: stored_count as u64,
                failed: failed_count as u64,
                total: total_chunks as u64,
                reason,
                retryable: false,
            },
            other => AntdError::Internal(other.to_string()),
        }
    }
}

#[derive(Serialize)]
struct ErrorBody {
    error: String,
    code: String,
    // Populated only for `PARTIAL_UPLOAD` so clients get machine-readable
    // counts (additive fields — absent for every other code).
    #[serde(skip_serializing_if = "Option::is_none")]
    chunks_stored: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    chunks_failed: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    total_chunks: Option<u64>,
    /// `PARTIAL_UPLOAD`: `true` when the paid attempt was retained and the
    /// same finalize call (same `upload_id`) stores the remainder against the
    /// same payment; `false` when the retry is a re-prepare.
    /// `CLOSE_GROUP_SHORTFALL`: `true` from a pointer finalize that kept the
    /// paid state for a repeat with the same `upload_id`; absent elsewhere.
    #[serde(skip_serializing_if = "Option::is_none")]
    retryable: Option<bool>,
}

impl IntoResponse for AntdError {
    fn into_response(self) -> Response {
        let status = match &self {
            AntdError::NotFound(_) => StatusCode::NOT_FOUND,
            AntdError::AlreadyExists(_) => StatusCode::CONFLICT,
            AntdError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AntdError::Payment(_) => StatusCode::PAYMENT_REQUIRED,
            AntdError::Network(_) => StatusCode::BAD_GATEWAY,
            AntdError::TooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            AntdError::Timeout(_) => StatusCode::GATEWAY_TIMEOUT,
            AntdError::ServiceUnavailable(_) => StatusCode::SERVICE_UNAVAILABLE,
            AntdError::NotImplemented(_) => StatusCode::NOT_IMPLEMENTED,
            AntdError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AntdError::RangeNotSatisfiable { .. } => StatusCode::RANGE_NOT_SATISFIABLE,
            // The upstream network failed to store part of the file; the
            // request itself was valid, so this is a gateway-side failure.
            AntdError::PartialUpload { .. } => StatusCode::BAD_GATEWAY,
            AntdError::CloseGroupShortfall { .. } => StatusCode::SERVICE_UNAVAILABLE,
            AntdError::PointerFinal(_) | AntdError::PointerForked(_) | AntdError::Conflict(_) => {
                StatusCode::CONFLICT
            }
        };
        let (chunks_stored, chunks_failed, total_chunks, retryable) = match &self {
            AntdError::PartialUpload {
                stored,
                failed,
                total,
                retryable,
                ..
            } => (Some(*stored), Some(*failed), Some(*total), Some(*retryable)),
            AntdError::CloseGroupShortfall { retryable, .. } => (None, None, None, *retryable),
            _ => (None, None, None, None),
        };
        let body = serde_json::to_string(&ErrorBody {
            error: self.to_string(),
            code: self.code().to_string(),
            chunks_stored,
            chunks_failed,
            total_chunks,
            retryable,
        })
        .unwrap_or_else(|_| r#"{"error":"internal error","code":"INTERNAL_ERROR"}"#.to_string());
        let mut response = (
            status,
            [(axum::http::header::CONTENT_TYPE, "application/json")],
            body,
        )
            .into_response();
        // RFC 9110 §15.5.17: a 416 carries the current length as `bytes */size`.
        if let AntdError::RangeNotSatisfiable { size } = self {
            response.headers_mut().insert(
                axum::http::header::CONTENT_RANGE,
                axum::http::HeaderValue::from_str(&format!("bytes */{size}"))
                    .expect("decimal digits are a valid header value"),
            );
        }
        response
    }
}

impl From<AntdError> for tonic::Status {
    fn from(e: AntdError) -> tonic::Status {
        match e {
            AntdError::NotFound(msg) => tonic::Status::not_found(msg),
            AntdError::AlreadyExists(msg) => tonic::Status::already_exists(msg),
            AntdError::BadRequest(msg) => tonic::Status::invalid_argument(msg),
            AntdError::Payment(msg) => tonic::Status::failed_precondition(msg),
            AntdError::Network(msg) => tonic::Status::unavailable(msg),
            AntdError::TooLarge => tonic::Status::resource_exhausted("too large for memory"),
            AntdError::Timeout(msg) => tonic::Status::deadline_exceeded(msg),
            AntdError::ServiceUnavailable(msg) => tonic::Status::unavailable(msg),
            AntdError::NotImplemented(msg) => tonic::Status::unimplemented(msg),
            AntdError::Internal(msg) => tonic::Status::internal(msg),
            // REST's 416 carries the size as `Content-Range: bytes */size`;
            // send the same value as metadata so gRPC clients don't have to
            // parse the message.
            e @ AntdError::RangeNotSatisfiable { size } => {
                let mut status = tonic::Status::out_of_range(e.to_string());
                status.metadata_mut().insert(
                    "x-content-range",
                    format!("bytes */{size}")
                        .parse()
                        .expect("a byte-range string is a valid ascii metadata value"),
                );
                status
            }
            // ABORTED: the operation stopped partway and the retry lives at
            // the application level — a repeat FinalizeUpload with the same
            // upload_id when the paid attempt was retained (`retryable`), or
            // a re-prepare otherwise — not a blind replay of the same call.
            // `retryable` rides along as metadata; the counts stay in the
            // message until the proto grows structured detail fields.
            e @ AntdError::PartialUpload { .. } => {
                let retryable = e.retryable();
                with_retryable(tonic::Status::aborted(e.to_string()), retryable)
            }
            // These share gRPC status codes with older errors, so the antd
            // code rides along as metadata for clients to tell them apart
            // without parsing the message.
            e @ AntdError::CloseGroupShortfall { .. } => {
                let retryable = e.retryable();
                let status = with_code(tonic::Status::unavailable(e.to_string()), e.code());
                with_retryable(status, retryable)
            }
            e @ (AntdError::PointerFinal(_) | AntdError::PointerForked(_)) => {
                with_code(tonic::Status::failed_precondition(e.to_string()), e.code())
            }
            e @ AntdError::Conflict(_) => {
                with_code(tonic::Status::aborted(e.to_string()), e.code())
            }
        }
    }
}

/// Attach antd's error code to a gRPC status as `x-antd-error-code`.
fn with_code(mut status: tonic::Status, code: &str) -> tonic::Status {
    if let Ok(value) = code.parse() {
        status.metadata_mut().insert("x-antd-error-code", value);
    }
    status
}

/// Attach whether the paid attempt was retained, the REST body's `retryable`,
/// as `x-antd-retryable: true|false`, so gRPC clients need not match the
/// message tail. Left off when unknown, as REST leaves the field out.
fn with_retryable(mut status: tonic::Status, retryable: Option<bool>) -> tonic::Status {
    if let Some(retryable) = retryable {
        let value = if retryable { "true" } else { "false" };
        status.metadata_mut().insert(
            "x-antd-retryable",
            tonic::metadata::MetadataValue::from_static(value),
        );
    }
    status
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_not_found_maps_to_not_found() {
        // A public fetch at an address nothing was stored at used to fall
        // into the catch-all `Internal` arm and surface as HTTP 500 / gRPC
        // INTERNAL, so clients raised InternalError instead of NotFoundError.
        let e = AntdError::from_core(ant_core::data::Error::NotFound(
            "DataMap chunk not found at abcd".into(),
        ));
        assert!(matches!(e, AntdError::NotFound(ref m) if m.contains("abcd")));
        assert_eq!(e.code(), "NOT_FOUND");
    }

    #[test]
    fn not_found_is_http_404() {
        let resp = AntdError::NotFound("gone".into()).into_response();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[test]
    fn range_not_satisfiable_is_http_416_with_content_range() {
        let resp = AntdError::RangeNotSatisfiable { size: 1234 }.into_response();
        assert_eq!(resp.status(), StatusCode::RANGE_NOT_SATISFIABLE);
        assert_eq!(
            resp.headers()
                .get(axum::http::header::CONTENT_RANGE)
                .unwrap(),
            "bytes */1234"
        );
    }

    #[test]
    fn range_not_satisfiable_is_grpc_out_of_range() {
        let status = tonic::Status::from(AntdError::RangeNotSatisfiable { size: 7 });
        assert_eq!(status.code(), tonic::Code::OutOfRange);
        assert!(status.message().contains("7 bytes"));
        assert_eq!(
            status
                .metadata()
                .get("x-content-range")
                .and_then(|v| v.to_str().ok()),
            Some("bytes */7")
        );
    }

    #[test]
    fn not_found_is_grpc_not_found() {
        let status = tonic::Status::from(AntdError::NotFound("gone".into()));
        assert_eq!(status.code(), tonic::Code::NotFound);
    }

    #[test]
    fn core_partial_upload_is_not_retryable_and_says_re_prepare() {
        // Nothing is retained on the non-resumable paths, so the error must
        // steer the caller to re-prepare (which skips stored chunks).
        let e = AntdError::from_core(ant_core::data::Error::PartialUpload {
            stored_count: 3,
            failed_count: 2,
            total_chunks: 5,
            reason: "quorum".into(),
            stored: vec![],
            failed: vec![],
            spend: Box::new(ant_core::data::error::PartialUploadSpend {
                storage_cost_atto: "0".into(),
                gas_cost_wei: 0,
            }),
        });
        assert!(
            matches!(
                e,
                AntdError::PartialUpload {
                    retryable: false,
                    ..
                }
            ),
            "got {e:?}"
        );
        let msg = e.to_string();
        assert!(msg.contains("3/5 chunks stored, 2 failed"), "{msg}");
        assert!(msg.contains("re-prepare"), "{msg}");
        assert!(!msg.contains("same upload_id"), "{msg}");
    }

    #[test]
    fn retryable_partial_upload_says_finalize_again() {
        let e = AntdError::PartialUpload {
            stored: 3,
            failed: 2,
            total: 5,
            reason: "2 chunk(s) short of quorum".into(),
            retryable: true,
        };
        let msg = e.to_string();
        assert!(msg.contains("same upload_id"), "{msg}");
        assert!(!msg.contains("re-prepare"), "{msg}");
        assert_eq!(e.code(), "PARTIAL_UPLOAD");

        let status = tonic::Status::from(e);
        assert_eq!(status.code(), tonic::Code::Aborted);
        assert!(status.message().contains("same upload_id"));
    }

    #[tokio::test]
    async fn partial_upload_body_carries_counts_and_retryable() {
        for retryable in [true, false] {
            let resp = AntdError::PartialUpload {
                stored: 3,
                failed: 2,
                total: 5,
                reason: "x".into(),
                retryable,
            }
            .into_response();
            assert_eq!(resp.status(), StatusCode::BAD_GATEWAY);
            let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
                .await
                .unwrap();
            let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(body["code"], "PARTIAL_UPLOAD");
            assert_eq!(body["chunks_stored"], 3);
            assert_eq!(body["chunks_failed"], 2);
            assert_eq!(body["total_chunks"], 5);
            assert_eq!(body["retryable"], retryable);
        }
        // Other codes never carry the partial-upload fields.
        let resp = AntdError::NotFound("gone".into()).into_response();
        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert!(body.get("retryable").is_none());
    }

    #[test]
    fn close_group_shortfall_is_a_503_not_an_internal_error() {
        let e = AntdError::from_core(ant_core::data::Error::CloseGroupShortfall(
            "Stored on 3 peers, need 4".into(),
        ));
        assert_eq!(e.code(), "CLOSE_GROUP_SHORTFALL");
        assert_eq!(e.into_response().status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn retained_pointer_finalize_says_retryable_in_the_body() {
        async fn body_of(e: AntdError) -> serde_json::Value {
            let resp = e.into_response();
            let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
                .await
                .unwrap();
            serde_json::from_slice(&bytes).unwrap()
        }

        let body = body_of(AntdError::CloseGroupShortfall {
            message: "stored on 4 of 5".into(),
            retryable: Some(true),
        })
        .await;
        assert_eq!(body["code"], "CLOSE_GROUP_SHORTFALL");
        assert_eq!(body["retryable"], true);
        assert!(body.get("chunks_stored").is_none());

        // A shortfall from a read carries no retryable flag at all.
        let body = body_of(AntdError::CloseGroupShortfall {
            message: "only 3 answered".into(),
            retryable: None,
        })
        .await;
        assert!(body.get("retryable").is_none());
    }

    #[test]
    fn pointer_refusals_are_409s() {
        for e in [
            AntdError::from_core(ant_core::data::Error::PointerFinal("x".into())),
            AntdError::from_core(ant_core::data::Error::PointerForked("x".into())),
            AntdError::Conflict("pending".into()),
        ] {
            assert_eq!(e.into_response().status(), StatusCode::CONFLICT);
        }
    }

    #[test]
    fn grpc_statuses_carry_the_antd_code_where_they_share_a_grpc_code() {
        let cases = [
            (
                AntdError::PointerFinal("x".into()),
                tonic::Code::FailedPrecondition,
                "POINTER_FINAL",
            ),
            (
                AntdError::PointerForked("x".into()),
                tonic::Code::FailedPrecondition,
                "POINTER_FORKED",
            ),
            (
                AntdError::Conflict("x".into()),
                tonic::Code::Aborted,
                "CONFLICT",
            ),
            (
                AntdError::CloseGroupShortfall {
                    message: "x".into(),
                    retryable: None,
                },
                tonic::Code::Unavailable,
                "CLOSE_GROUP_SHORTFALL",
            ),
        ];
        for (e, code, antd_code) in cases {
            let status = tonic::Status::from(e);
            assert_eq!(status.code(), code);
            assert_eq!(
                status
                    .metadata()
                    .get("x-antd-error-code")
                    .and_then(|v| v.to_str().ok()),
                Some(antd_code)
            );
        }
    }

    #[test]
    fn grpc_status_carries_retryable_as_metadata() {
        let retryable = |e: AntdError| {
            tonic::Status::from(e)
                .metadata()
                .get("x-antd-retryable")
                .and_then(|v| v.to_str().ok())
                .map(str::to_owned)
        };
        let partial = |retryable| AntdError::PartialUpload {
            stored: 1,
            failed: 1,
            total: 2,
            reason: "x".into(),
            retryable,
        };
        let shortfall = |retryable| AntdError::CloseGroupShortfall {
            message: "x".into(),
            retryable,
        };
        assert_eq!(retryable(partial(true)).as_deref(), Some("true"));
        assert_eq!(retryable(partial(false)).as_deref(), Some("false"));
        assert_eq!(retryable(shortfall(Some(true))).as_deref(), Some("true"));
        // Unknown retention is left off, as REST leaves `retryable` out.
        assert_eq!(retryable(shortfall(None)), None);
        assert_eq!(retryable(AntdError::Conflict("x".into())), None);

        // The shortfall keeps its code tag next to the new key.
        let status = tonic::Status::from(shortfall(Some(true)));
        assert_eq!(
            status
                .metadata()
                .get("x-antd-error-code")
                .and_then(|v| v.to_str().ok()),
            Some("CLOSE_GROUP_SHORTFALL")
        );
    }

    #[test]
    fn unknown_core_errors_still_map_to_internal() {
        let e = AntdError::from_core(ant_core::data::Error::Protocol("boom".into()));
        assert!(matches!(e, AntdError::Internal(_)));
    }
}
