use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum AntdError {
    #[error("Record not found: {0}")]
    NotFound(String),

    #[error("Already exists: {0}")]
    AlreadyExists(String),

    #[error("Fork detected: {0}")]
    Fork(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Payment error: {0}")]
    Payment(String),

    #[error("Network error: {0}")]
    Network(String),

    #[error("Too large for memory")]
    TooLarge,

    #[error("Internal error: {0}")]
    Internal(String),
}

#[derive(Serialize)]
struct ErrorBody {
    error: String,
}

impl IntoResponse for AntdError {
    fn into_response(self) -> Response {
        let status = match &self {
            AntdError::NotFound(_) => StatusCode::NOT_FOUND,
            AntdError::AlreadyExists(_) => StatusCode::CONFLICT,
            AntdError::Fork(_) => StatusCode::CONFLICT,
            AntdError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AntdError::Payment(_) => StatusCode::PAYMENT_REQUIRED,
            AntdError::Network(_) => StatusCode::BAD_GATEWAY,
            AntdError::TooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            AntdError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        };
        let body = serde_json::to_string(&ErrorBody {
            error: self.to_string(),
        })
        .unwrap_or_else(|_| r#"{"error":"internal error"}"#.to_string());
        (status, [(axum::http::header::CONTENT_TYPE, "application/json")], body).into_response()
    }
}

impl From<AntdError> for tonic::Status {
    fn from(e: AntdError) -> tonic::Status {
        match e {
            AntdError::NotFound(msg) => tonic::Status::not_found(msg),
            AntdError::AlreadyExists(msg) => tonic::Status::already_exists(msg),
            AntdError::Fork(msg) => tonic::Status::aborted(msg),
            AntdError::BadRequest(msg) => tonic::Status::invalid_argument(msg),
            AntdError::Payment(msg) => tonic::Status::failed_precondition(msg),
            AntdError::Network(msg) => tonic::Status::unavailable(msg),
            AntdError::TooLarge => tonic::Status::resource_exhausted("too large for memory"),
            AntdError::Internal(msg) => tonic::Status::internal(msg),
        }
    }
}

// Conversion helpers from autonomi error types

impl From<autonomi::client::GetError> for AntdError {
    fn from(e: autonomi::client::GetError) -> Self {
        match e {
            autonomi::client::GetError::RecordNotFound => {
                AntdError::NotFound("record not found".into())
            }
            autonomi::client::GetError::TooLargeForMemory(_) => AntdError::TooLarge,
            autonomi::client::GetError::Network(ne) => {
                AntdError::Network(format!("network error: {ne}"))
            }
            other => AntdError::Internal(other.to_string()),
        }
    }
}

impl From<autonomi::client::PutError> for AntdError {
    fn from(e: autonomi::client::PutError) -> Self {
        match e {
            autonomi::client::PutError::Wallet(we) => {
                AntdError::Payment(format!("wallet error: {we}"))
            }
            autonomi::client::PutError::Network { network_error, .. } => {
                AntdError::Network(format!("network error: {network_error}"))
            }
            autonomi::client::PutError::CostError(ce) => {
                AntdError::Payment(format!("cost error: {ce}"))
            }
            autonomi::client::PutError::PayError(pe) => {
                AntdError::Payment(format!("payment error: {pe}"))
            }
            other => AntdError::Internal(other.to_string()),
        }
    }
}

impl From<autonomi::graph::GraphError> for AntdError {
    fn from(e: autonomi::graph::GraphError) -> Self {
        use autonomi::graph::GraphError;
        match e {
            GraphError::GetError(ge) => ge.into(),
            GraphError::PutError(pe) => pe.into(),
            GraphError::Cost(ce) => ce.into(),
            GraphError::AlreadyExists(addr) => {
                AntdError::AlreadyExists(format!("graph entry exists: {}", addr.to_hex()))
            }
            GraphError::Fork(entries) => {
                AntdError::Fork(format!("graph fork: {} versions", entries.len()))
            }
            GraphError::FailedVerification => {
                AntdError::BadRequest("graph entry verification failed".into())
            }
            GraphError::Pay(pe) => AntdError::Payment(format!("payment error: {pe}")),
            GraphError::Wallet(we) => AntdError::Payment(format!("wallet error: {we}")),
            other => AntdError::Internal(other.to_string()),
        }
    }
}

impl From<autonomi::client::quote::CostError> for AntdError {
    fn from(e: autonomi::client::quote::CostError) -> Self {
        AntdError::Payment(format!("cost error: {e}"))
    }
}

impl From<autonomi::files::UploadError> for AntdError {
    fn from(e: autonomi::files::UploadError) -> Self {
        AntdError::Internal(format!("upload error: {e}"))
    }
}

impl From<autonomi::files::DownloadError> for AntdError {
    fn from(e: autonomi::files::DownloadError) -> Self {
        match e {
            autonomi::files::DownloadError::GetError(ge) => ge.into(),
            other => AntdError::Internal(other.to_string()),
        }
    }
}
