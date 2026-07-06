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

/// One pool commitment for the merkle payment call
/// `payForMerkleTree(uint8 depth, PoolCommitment[], uint64 timestamp)`.
/// Only populated on merkle-batched uploads (`payment_type == "merkle"`).
#[derive(uniffi::Record)]
pub struct PoolCommitmentEntry {
    /// 0x-prefixed pool hash (32 bytes).
    pub pool_hash: String,
    /// The pool's candidate nodes (exactly `CANDIDATES_PER_POOL` of them).
    pub candidates: Vec<CandidateNodeEntry>,
}

/// One candidate node inside a [`PoolCommitmentEntry`].
#[derive(uniffi::Record)]
pub struct CandidateNodeEntry {
    /// 0x-prefixed EVM rewards address (20 bytes).
    pub rewards_address: String,
    /// Node price in atto-tokens (base-10 string).
    pub amount: String,
}

/// Summary of a prepared external-signer upload. The heavy prepared-chunk
/// state stays in Rust, referenced by `upload_id` until finalize.
///
/// `payment_type` selects which fields are meaningful and which finalize call
/// to use:
///   - `"wave_batch"` — use `payments` to build ERC-20 `approve` + `payForQuotes`,
///     then call `finalize_upload(upload_id, {quote_hash: tx_hash})`. The merkle
///     fields (`depth`/`pool_commitments`/`merkle_payment_timestamp`) are empty/0.
///   - `"merkle"` — use `depth` + `pool_commitments` + `merkle_payment_timestamp`
///     to build the `payForMerkleTree` call, then call
///     `finalize_upload_merkle(upload_id, winner_pool_hash)` with the hash from
///     the `MerklePaymentMade` event. `payments` is empty and `total_amount` is
///     `"0"` (the settled cost isn't known until the winner pool is chosen
///     on-chain).
#[derive(uniffi::Record)]
pub struct PreparedUploadInfo {
    /// Opaque handle for this prepared upload; pass to the matching finalize call.
    pub upload_id: String,
    /// Payment shape: `"wave_batch"` or `"merkle"`.
    pub payment_type: String,
    /// Wave-batch only: per-quote payments to settle on-chain. Empty for merkle
    /// or if everything was already stored.
    pub payments: Vec<PaymentEntry>,
    /// Wave-batch: total across all payments (atto-tokens, base-10). `"0"` for merkle.
    pub total_amount: String,
    /// Merkle only: merkle tree depth for the `payForMerkleTree` call. 0 for wave-batch.
    pub depth: u32,
    /// Merkle only: pool commitments for the `payForMerkleTree` call. Empty for wave-batch.
    pub pool_commitments: Vec<PoolCommitmentEntry>,
    /// Merkle only: timestamp for the `payForMerkleTree` call. 0 for wave-batch.
    pub merkle_payment_timestamp: u64,
    /// For public uploads: hex address the data is retrievable from after
    /// finalize. `None` for private uploads.
    pub data_map_address: Option<String>,
    /// True if every chunk already existed on the network — nothing to pay;
    /// finalize may be called with an empty map / any winner hash.
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
/// [`ProgressListener`].
///
/// `phase` is one of the following strings. Note which methods actually emit
/// each phase today:
///
///   - **upload** — `"storing"` only, emitted by `finalize_upload_with_progress`
///     as chunks land on the network. The `"encrypting"` and `"quoting"` phases
///     exist in the enum for completeness but are **not** currently surfaced by
///     the external-signer FFI: they happen inside `prepare_*`, which does not
///     yet take a listener. (A prepare-with-progress API is a possible follow-up.)
///   - **download** — `"resolving"` then `"downloading"`, emitted by the
///     `download_*_to_file` methods.
///
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
            Error::Timeout(msg) => ClientError::NetworkError {
                reason: format!("timeout: {msg}"),
            },
            Error::InsufficientPeers(msg) => ClientError::NetworkError { reason: msg },
            other => ClientError::InternalError {
                reason: other.to_string(),
            },
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
