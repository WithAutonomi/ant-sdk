mod client;
mod data;
mod wallet;

pub use client::Client;
pub use data::{DataUploadResult, FileUploadResult};
pub use wallet::Wallet;

uniffi::setup_scaffolding!();

// ===== Result types =====

/// Result of storing a chunk on the network.
#[derive(uniffi::Record)]
pub struct ChunkPutResult {
    /// Hex-encoded chunk address (32 bytes).
    pub address: String,
}

/// Result of a public data upload (data map stored as public chunk).
#[derive(uniffi::Record)]
pub struct DataPutPublicResult {
    /// Hex-encoded address of the stored data map.
    pub address: String,
    /// Number of chunks stored.
    pub chunks_stored: u64,
    /// Payment mode that was used: "auto", "merkle", or "single".
    pub payment_mode_used: String,
}

/// Result of a private data upload (data map returned to caller).
#[derive(uniffi::Record)]
pub struct DataPutPrivateResult {
    /// Hex-encoded serialized data map (caller keeps this secret).
    pub data_map: String,
    /// Number of chunks stored.
    pub chunks_stored: u64,
    /// Payment mode that was used.
    pub payment_mode_used: String,
}

/// Result of uploading a file (public).
#[derive(uniffi::Record)]
pub struct FilePutPublicResult {
    /// Hex-encoded address of the stored data map.
    pub address: String,
}

/// Payment entry for external signing.
#[derive(uniffi::Record)]
pub struct PaymentEntry {
    /// Quote hash (hex, 32 bytes).
    pub quote_hash: String,
    /// Rewards address (hex with 0x prefix).
    pub rewards_address: String,
    /// Amount to pay (atto tokens as decimal string).
    pub amount: String,
}

/// Result of preparing an upload for external signing.
#[derive(uniffi::Record)]
pub struct PrepareUploadResult {
    /// Payment entries to sign externally.
    pub payments: Vec<PaymentEntry>,
    /// Total amount across all payments (atto tokens).
    pub total_amount: String,
    /// Hex-encoded serialized DataMap for later retrieval.
    pub data_map: String,
}

/// Result of finalizing an externally-signed upload.
#[derive(uniffi::Record)]
pub struct FinalizeUploadResult {
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
}

// ===== Error types =====

/// Error type for client operations.
#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum ClientError {
    #[error("Initialization failed: {reason}")]
    InitializationFailed { reason: String },
    #[error("Network error: {reason}")]
    NetworkError { reason: String },
    #[error("Payment error: {reason}")]
    PaymentError { reason: String },
    #[error("Invalid input: {reason}")]
    InvalidInput { reason: String },
    #[error("Not found: {reason}")]
    NotFound { reason: String },
    #[error("Already exists")]
    AlreadyExists,
    #[error("Wallet not configured")]
    WalletNotConfigured,
    #[error("Internal error: {reason}")]
    InternalError { reason: String },
}

/// Map ant-core errors to FFI errors.
impl From<ant_core::data::Error> for ClientError {
    fn from(e: ant_core::data::Error) -> Self {
        use ant_core::data::Error;
        match e {
            Error::AlreadyStored => ClientError::AlreadyExists,
            Error::InvalidData(msg) => ClientError::InvalidInput { reason: msg },
            Error::Payment(msg) => ClientError::PaymentError { reason: msg },
            Error::Network(msg) => ClientError::NetworkError { reason: msg },
            Error::Timeout(msg) => ClientError::NetworkError { reason: format!("timeout: {msg}") },
            Error::InsufficientPeers(msg) => ClientError::NetworkError { reason: msg },
            other => ClientError::InternalError { reason: other.to_string() },
        }
    }
}

/// Error type for wallet operations.
#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum WalletError {
    #[error("Wallet creation failed: {reason}")]
    CreationFailed { reason: String },
    #[error("Operation failed: {reason}")]
    OperationFailed { reason: String },
}
