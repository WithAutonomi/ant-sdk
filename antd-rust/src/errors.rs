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

    /// Feature not implemented by the daemon (HTTP 501).
    #[error("antd error 501: {0}")]
    NotImplemented(String),

    /// Daemon cannot reach the network (HTTP 502).
    #[error("antd error 502: {0}")]
    Network(String),

    /// HTTP transport error from reqwest.
    #[error("http error: {0}")]
    Http(#[from] reqwest::Error),

    /// JSON serialization/deserialization error.
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),

    /// gRPC transport or status error.
    #[error("grpc error: {0}")]
    Grpc(#[from] tonic::Status),
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
        501 => AntdError::NotImplemented(message),
        502 => AntdError::Network(message),
        _ => AntdError::Internal(format!("unexpected status {code}: {message}")),
    }
}
