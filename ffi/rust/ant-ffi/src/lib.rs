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

// ===== External-signer (WalletConnect) upload types =====

/// A single on-chain payment the external wallet must settle: one entry of the
/// `payForQuotes((address,uint256,bytes32)[])` call.
#[derive(uniffi::Record)]
pub struct PaymentEntry {
    /// 0x-prefixed quote hash (32 bytes) — the key in the tx-hash map at finalize.
    pub quote_hash: String,
    /// 0x-prefixed EVM rewards address to pay.
    pub rewards_address: String,
    /// Amount to pay in atto-tokens (base-10 string; exceeds u64).
    pub amount: String,
}

/// Summary of a prepared external-signer upload. The heavy prepared-chunk
/// state stays in Rust, referenced by `upload_id` until `finalize_upload`.
/// The caller uses `payments` to build ERC-20 `approve` + `payForQuotes`,
/// has the external wallet sign them, then calls `finalize_upload` with the
/// resulting `quote_hash -> tx_hash` map.
#[derive(uniffi::Record)]
pub struct PreparedUploadInfo {
    /// Opaque handle for this prepared upload; pass to `finalize_upload`.
    pub upload_id: String,
    /// Payment shape. Currently always `"wave_batch"` (merkle not yet exposed).
    pub payment_type: String,
    /// Per-quote payments to settle on-chain. Empty if everything was already stored.
    pub payments: Vec<PaymentEntry>,
    /// Total across all payments (atto-tokens, base-10).
    pub total_amount: String,
    /// For public uploads: hex address the data is retrievable from after
    /// finalize. `None` for private uploads.
    pub data_map_address: Option<String>,
    /// True if every chunk already existed on the network — `payments` is
    /// empty and `finalize_upload` may be called with an empty map.
    pub already_stored: bool,
}

/// Result of finalizing an external-signer upload.
#[derive(uniffi::Record)]
pub struct ExternalUploadResult {
    /// Hex-encoded serialized data map (for private retrieval; always present).
    pub data_map: String,
    /// For public uploads: hex data-map address (shareable). `None` if private.
    pub address: Option<String>,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Total storage cost paid, in atto-tokens (base-10). "0" if all pre-existed.
    pub storage_cost_atto: String,
    /// Total gas cost in wei (base-10).
    pub gas_cost_wei: String,
}

// ===== Progress reporting =====

/// A progress update for a long-running upload or download, delivered to a
/// [`ProgressListener`]. `phase` is one of:
///   - upload:   `"encrypting"`, `"quoting"`, `"storing"`
///   - download: `"resolving"`, `"downloading"`
/// `total` is 0 when the total isn't known yet (show an indeterminate bar);
/// otherwise `done / total` is a 0..1 fraction of the current phase.
#[derive(uniffi::Record)]
pub struct ProgressUpdate {
    pub phase: String,
    pub done: u64,
    pub total: u64,
}

/// Foreign callback invoked as an upload/download progresses. Implement it on
/// the Swift/Kotlin side and pass it to the `*_with_progress` client methods.
/// Calls arrive on a background thread — marshal to the UI thread before
/// touching UI state.
#[uniffi::export(callback_interface)]
pub trait ProgressListener: Send + Sync {
    fn on_progress(&self, update: ProgressUpdate);
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

