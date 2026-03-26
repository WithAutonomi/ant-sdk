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

    #[error("Not implemented: {0}")]
    NotImplemented(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl AntdError {
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
            other => AntdError::Internal(other.to_string()),
        }
    }
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
            AntdError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AntdError::Payment(_) => StatusCode::PAYMENT_REQUIRED,
            AntdError::Network(_) => StatusCode::BAD_GATEWAY,
            AntdError::TooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            AntdError::Timeout(_) => StatusCode::GATEWAY_TIMEOUT,
            AntdError::NotImplemented(_) => StatusCode::NOT_IMPLEMENTED,
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
            AntdError::BadRequest(msg) => tonic::Status::invalid_argument(msg),
            AntdError::Payment(msg) => tonic::Status::failed_precondition(msg),
            AntdError::Network(msg) => tonic::Status::unavailable(msg),
            AntdError::TooLarge => tonic::Status::resource_exhausted("too large for memory"),
            AntdError::Timeout(msg) => tonic::Status::deadline_exceeded(msg),
            AntdError::NotImplemented(msg) => tonic::Status::unimplemented(msg),
            AntdError::Internal(msg) => tonic::Status::internal(msg),
        }
    }
}
