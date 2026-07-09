mod client;
mod data;
mod payments;
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

/// Estimated cost of uploading a file, produced *before* any payment by
/// sampling a few of the file's chunk addresses and extrapolating. No wallet
/// is required. Use this to show the user a cost preview before preparing the
/// real upload.
#[derive(uniffi::Record)]
pub struct CostEstimate {
    /// Original file size in bytes.
    pub file_size: u64,
    /// Number of data chunks the file would split into (excludes the extra
    /// data-map chunk added for public uploads).
    pub chunk_count: u64,
    /// Estimated storage cost in atto-tokens (base-10 string; may exceed u64).
    pub storage_cost_atto: String,
    /// Rough estimated gas cost in wei (base-10 string). A heuristic based on
    /// chunk count and payment mode, NOT a live gas-price query.
    pub estimated_gas_cost_wei: String,
    /// Payment mode that would be used: "auto", "merkle", or "single".
    pub payment_mode: String,
    /// How much to trust `storage_cost_atto`:
    /// - `"priced_sample"` — extrapolated from at least one live quote (normal case).
    /// - `"verified_all_already_stored"` — every chunk was sampled and already
    ///   stored; cost is exactly `"0"` (genuinely free).
    /// - `"all_samples_already_stored_incomplete"` — every *sampled* chunk was
    ///   already stored but the tail was unsampled; `"0"` is a best-effort guess
    ///   the real upload reconciles at payment time. Render as "likely already
    ///   stored", not guaranteed-free.
    pub confidence: String,
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

// ===== External-signer payment plumbing (calldata / config) =====

/// On-chain configuration for a known Autonomi EVM network, so the app doesn't
/// have to hardcode addresses or guess a chain id from an RPC URL string.
/// Fetch with the free `network_info(name)` function.
#[derive(uniffi::Record)]
pub struct NetworkInfo {
    /// EVM chain id (e.g. 42161 Arbitrum One, 421614 Arbitrum Sepolia).
    pub chain_id: u32,
    /// 0x-prefixed ANT payment-token address.
    pub token_address: String,
    /// 0x-prefixed payment-vault address.
    pub vault_address: String,
    /// Default HTTPS RPC URL for the network.
    pub rpc_url: String,
}

/// One transaction the external wallet must sign & send, in order, to pay for a
/// prepared upload. Produced by [`Client::payment_transactions`].
///
/// The app signs each `TxRequest` in the returned order (approve first, then the
/// payment call), waiting for each receipt before the next.
#[derive(uniffi::Record)]
pub struct TxRequest {
    /// 0x-prefixed contract address to send the transaction to (token for
    /// `approve`, vault for the payment call).
    pub to: String,
    /// 0x-prefixed ABI-encoded calldata for the transaction's `data` field.
    pub data: String,
    /// `"approve"` (ERC-20 allowance) or `"pay"` (the vault payment call).
    pub kind: String,
    /// Wave-batch `"pay"` only: the 0x-prefixed quote hashes this payment
    /// settles. After signing, map each of these to the resulting tx hash to
    /// build the `finalize_upload` map. Empty for `approve` and for merkle.
    pub quote_hashes: Vec<String>,
}

/// Outcome of a settled transaction, from the `wait_for_receipt` free function.
#[derive(uniffi::Record)]
pub struct TxReceipt {
    /// `true` if the transaction succeeded (receipt status `0x1`), `false` if it
    /// reverted (`0x0`).
    pub success: bool,
    /// Gas units consumed (base-10 string).
    pub gas_used: String,
    /// Effective gas price paid in wei (base-10 string). Multiply by `gas_used`
    /// for the total gas cost.
    pub effective_gas_price: String,
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
