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
        AntdError::Grpc(Box::new(status))
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
        500 => AntdError::Internal(message),
        502 => AntdError::Network(message),
        503 => AntdError::ServiceUnavailable(message),
        _ => AntdError::Internal(format!("unexpected status {code}: {message}")),
    }
}
