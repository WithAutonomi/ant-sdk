use serde::{Deserialize, Serialize};

/// Result of a health check against the antd daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub ok: bool,
    pub network: String,
}

/// Result of a put/create operation containing cost and address.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PutResult {
    /// Cost in atto tokens as a string.
    pub cost: String,
    /// Hex-encoded address.
    pub address: String,
}

/// A descendant entry in a graph node.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphDescendant {
    /// Hex-encoded public key.
    pub public_key: String,
    /// Hex-encoded content (32 bytes).
    pub content: String,
}

/// A DAG node from the network.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphEntry {
    pub owner: String,
    pub parents: Vec<String>,
    pub content: String,
    pub descendants: Vec<GraphDescendant>,
}

/// A single entry in a file archive.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArchiveEntry {
    pub path: String,
    pub address: String,
    pub created: i64,
    pub modified: i64,
    pub size: i64,
}

/// A collection of archive entries.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Archive {
    pub entries: Vec<ArchiveEntry>,
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

/// Result of preparing an upload for external signing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadResult {
    /// Hex identifier for this upload session.
    pub upload_id: String,
    /// Payments that must be signed externally.
    pub payments: Vec<PaymentInfo>,
    /// Total amount across all payments.
    pub total_amount: String,
    /// Data payments contract address.
    pub data_payments_address: String,
    /// Payment token contract address.
    pub payment_token_address: String,
    /// EVM RPC URL for submitting transactions.
    pub rpc_url: String,
}

/// Result of finalizing an externally-signed upload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FinalizeUploadResult {
    /// Hex address of the stored data.
    pub address: String,
    /// Number of chunks stored.
    pub chunks_stored: i64,
}
