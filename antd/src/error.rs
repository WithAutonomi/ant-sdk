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

    /// Upload partially succeeded: some chunks stored, some failed quorum
    /// after all retries. The payment was made and the stored chunks persist —
    /// re-preparing the same content skips already-stored chunks, so a retry
    /// only pays for and stores the missing remainder.
    #[error(
        "Partial upload: {stored}/{total} chunks stored, {failed} failed after retries: {reason} \
         (stored chunks persist; re-prepare the same content to retry only the remainder)"
    )]
    PartialUpload {
        stored: u64,
        failed: u64,
        total: u64,
        reason: String,
    },
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
            AntdError::PartialUpload { .. } => "PARTIAL_UPLOAD",
        }
    }

    /// Convert an ant-core error into an AntdError.
    pub fn from_core(e: ant_core::data::Error) -> Self {
        use ant_core::data::Error;
        match e {
            Error::AlreadyStored => AntdError::AlreadyExists("already stored".into()),
            Error::InvalidData(msg) => AntdError::BadRequest(msg),
            Error::Payment(msg) => AntdError::Payment(msg),
            Error::Network(msg) => AntdError::Network(msg),
            Error::Timeout(msg) => AntdError::Timeout(msg),
            Error::InsufficientPeers(msg) => AntdError::Network(msg),
            Error::Protocol(msg) => AntdError::Internal(msg),
            Error::Encryption(msg) => AntdError::Internal(msg),
            Error::Serialization(msg) => AntdError::Internal(msg),
            // Both finalize paths (wave and, since ant-core 0.6.0, merkle)
            // raise this when chunks miss quorum after retries. Keep the counts
            // structured so clients can drive a retry instead of parsing text.
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
            // The upstream network failed to store part of the file; the
            // request itself was valid, so this is a gateway-side failure.
            AntdError::PartialUpload { .. } => StatusCode::BAD_GATEWAY,
        };
        let (chunks_stored, chunks_failed, total_chunks) = match &self {
            AntdError::PartialUpload {
                stored,
                failed,
                total,
                ..
            } => (Some(*stored), Some(*failed), Some(*total)),
            _ => (None, None, None),
        };
        let body = serde_json::to_string(&ErrorBody {
            error: self.to_string(),
            code: self.code().to_string(),
            chunks_stored,
            chunks_failed,
            total_chunks,
        })
        .unwrap_or_else(|_| r#"{"error":"internal error","code":"INTERNAL_ERROR"}"#.to_string());
        (
            status,
            [(axum::http::header::CONTENT_TYPE, "application/json")],
            body,
        )
            .into_response()
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
            // ABORTED: the operation stopped partway and the retry lives at
            // the application level (re-prepare, then finalize the remainder),
            // not a blind replay of the same call. Counts stay in the message
            // until the proto grows structured detail fields.
            e @ AntdError::PartialUpload { .. } => tonic::Status::aborted(e.to_string()),
        }
    }
}
