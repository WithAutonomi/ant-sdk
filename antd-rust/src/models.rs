use serde::{Deserialize, Serialize};

/// Result of a health check against the antd daemon.
///
/// The diagnostic fields (`version`, `evm_network`, `uptime_seconds`,
/// `build_commit`, `payment_token_address`, `payment_vault_address`) were
/// added in antd 0.4.0. They default to empty / 0 via `#[serde(default)]`,
/// so deserialization tolerates pre-0.4.0 daemon responses.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HealthStatus {
    pub ok: bool,
    pub network: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub evm_network: String,
    #[serde(default)]
    pub uptime_seconds: u64,
    #[serde(default)]
    pub build_commit: String,
    #[serde(default)]
    pub payment_token_address: String,
    #[serde(default)]
    pub payment_vault_address: String,
}

/// Result of a put/create operation containing cost and address.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PutResult {
    /// Cost in atto tokens as a string.
    pub cost: String,
    /// Hex-encoded address.
    pub address: String,
}

/// Result of a public file or directory upload.
///
/// Returned by [`crate::Client::file_upload_public`],
/// [`crate::Client::dir_upload_public`], and the equivalent gRPC methods.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileUploadResult {
    /// Hex-encoded network address of the uploaded file or directory.
    pub address: String,
    /// Total storage cost paid in token units (atto). `"0"` if all chunks already existed.
    pub storage_cost_atto: String,
    /// Total gas cost paid in wei as a decimal string (u128 exceeds JSON safe-integer range).
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used (`"auto"`, `"merkle"`, or `"single"`).
    pub payment_mode_used: String,
}

/// Wallet address from the antd daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletAddress {
    /// Hex-encoded address, e.g. "0x...".
    pub address: String,
}

/// Wallet balance from the antd daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletBalance {
    /// Balance in atto tokens as a string.
    pub balance: String,
    /// Gas balance in atto tokens as a string.
    pub gas_balance: String,
}

/// A single payment required for an upload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaymentInfo {
    /// Hex-encoded quote hash.
    pub quote_hash: String,
    /// Hex-encoded rewards address.
    pub rewards_address: String,
    /// Amount in atto tokens as a string.
    pub amount: String,
}

/// A candidate node entry within a merkle batch payment pool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateNodeEntry {
    /// Hex-encoded rewards address.
    pub rewards_address: String,
    /// Amount in atto tokens as a string.
    pub amount: String,
}

/// A pool commitment entry for merkle batch payments.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolCommitmentEntry {
    /// Hex-encoded pool hash.
    pub pool_hash: String,
    /// Candidate nodes in this pool.
    pub candidates: Vec<CandidateNodeEntry>,
}

/// Result of preparing an upload for external signing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadResult {
    /// Hex identifier for this upload session.
    pub upload_id: String,
    /// Payments that must be signed externally.
    pub payments: Vec<PaymentInfo>,
    /// Total amount across all payments.
    pub total_amount: String,
    /// Payment vault contract address.
    pub payment_vault_address: String,
    /// Payment token contract address.
    pub payment_token_address: String,
    /// EVM RPC URL for submitting transactions.
    pub rpc_url: String,
    /// Payment type: "direct" or "merkle". Empty for legacy responses.
    #[serde(rename = "payment_type", default)]
    pub payment_type: String,
    /// Merkle tree depth (merkle payments only).
    #[serde(rename = "depth", default)]
    pub depth: Option<u8>,
    /// Pool commitments for merkle batch payments.
    #[serde(rename = "pool_commitments", default)]
    pub pool_commitments: Option<Vec<PoolCommitmentEntry>>,
    /// Timestamp for merkle payment submission.
    #[serde(rename = "merkle_payment_timestamp", default)]
    pub merkle_payment_timestamp: Option<u64>,
}

/// Result of finalizing an externally-signed upload.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FinalizeUploadResult {
    /// Hex address of the stored data.
    #[serde(default)]
    pub address: String,
    /// Number of chunks stored.
    #[serde(default)]
    pub chunks_stored: i64,
    /// Hex-encoded serialized DataMap (always returned). Empty for legacy
    /// daemons that pre-date the field.
    #[serde(default)]
    pub data_map: String,
    /// On-network address of the DataMap chunk. Populated only when prepare
    /// was called with `visibility="public"` — the DataMap chunk was bundled
    /// into the same external-signer payment batch and stored on-network.
    /// Empty otherwise.
    #[serde(default)]
    pub data_map_address: String,
}

/// Result of preparing a single-chunk publish for external signing via
/// `POST /v1/chunks/prepare`.
///
/// When [`already_stored`](Self::already_stored) is `true`, the chunk is
/// already on-network — only [`address`](Self::address) is populated and no
/// finalize call is needed. Otherwise the wave-batch payment fields describe
/// what the external signer must submit before calling
/// [`crate::Client::finalize_chunk_upload`].
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrepareChunkResult {
    /// Content-addressed BLAKE3 of the chunk bytes (hex, 64 chars). Always set.
    pub address: String,
    /// `true` if the chunk is already stored on the network and no payment
    /// is needed.
    #[serde(default)]
    pub already_stored: bool,

    // Fields below are only populated when `already_stored == false`.

    /// Opaque identifier to pass back to `finalize_chunk_upload`.
    #[serde(default)]
    pub upload_id: String,
    /// Always `"wave_batch"` for single-chunk publishes (well below the
    /// merkle threshold).
    #[serde(default)]
    pub payment_type: String,
    /// Per-quote payment entries for `payForQuotes()`. Typically 5–7 (one
    /// per peer in the close group).
    #[serde(default)]
    pub payments: Vec<PaymentInfo>,
    /// Total amount to pay (atto tokens, decimal string).
    #[serde(default)]
    pub total_amount: String,
    /// Payment vault contract address (hex with 0x prefix).
    #[serde(default)]
    pub payment_vault_address: String,
    /// Payment token contract address (hex with 0x prefix).
    #[serde(default)]
    pub payment_token_address: String,
    /// EVM RPC URL for submitting transactions.
    #[serde(default)]
    pub rpc_url: String,
}

/// Pre-upload cost breakdown returned by `estimate_data_cost` /
/// `estimate_file_cost`.
///
/// The server samples up to 5 chunk addresses and extrapolates the storage
/// cost. Gas is an advisory heuristic, not a live gas-oracle query.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadCostEstimate {
    /// Storage cost in atto tokens as a string.
    pub cost: String,
    /// Original file size in bytes.
    pub file_size: u64,
    /// Number of data chunks the file would split into.
    pub chunk_count: u32,
    /// Advisory gas cost heuristic in wei as a string.
    pub estimated_gas_cost_wei: String,
    /// Payment mode that would be used: `"auto"`, `"merkle"`, or `"single"`.
    pub payment_mode: String,
}
