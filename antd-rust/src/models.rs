use serde::{Deserialize, Serialize};

/// Payment-batching strategy for uploads.
///
/// Passed as a required parameter to every put/cost method; the client
/// serializes the variant to the wire string at the request boundary.
///
/// - `Auto`   — server picks (merkle for 64+ chunks, single otherwise).
/// - `Merkle` — force merkle-batch (saves gas, min 2 chunks).
/// - `Single` — force per-chunk payments (works for any chunk count).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaymentMode {
    Auto,
    Merkle,
    Single,
}

impl PaymentMode {
    /// Serialize to the wire string the daemon expects.
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Merkle => "merkle",
            Self::Single => "single",
        }
    }
}

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

/// Result of a single-chunk put (used by `chunk_put`). Data and file puts
/// return richer types — see [`DataPutResult`], [`DataPutPublicResult`],
/// [`FilePutResult`], [`FilePutPublicResult`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PutResult {
    /// Cost in atto tokens as a string.
    pub cost: String,
    /// Hex-encoded address.
    pub address: String,
}

/// Result of a private data put. The DataMap is returned to the caller; it
/// is NOT stored on-network. The REST transport populates `chunks_stored`
/// and `payment_mode_used`; the gRPC transport currently leaves them empty
/// because the proto `PutDataResponse` only carries `data_map`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DataPutResult {
    /// Hex-encoded caller-held DataMap.
    pub data_map: String,
    #[serde(default)]
    pub chunks_stored: u64,
    #[serde(default)]
    pub payment_mode_used: String,
}

/// Result of a public data put. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DataPutPublicResult {
    /// Hex-encoded on-network DataMap address.
    pub address: String,
    #[serde(default)]
    pub chunks_stored: u64,
    #[serde(default)]
    pub payment_mode_used: String,
}

/// Result of a private file upload. The DataMap is returned to the caller;
/// it is NOT stored on-network.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePutResult {
    /// Hex-encoded caller-held DataMap.
    pub data_map: String,
    /// Storage cost paid in atto tokens. `"0"` if all chunks already existed.
    pub storage_cost_atto: String,
    /// Gas cost paid in wei as a decimal string.
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used (`"auto"`, `"merkle"`, or `"single"`).
    pub payment_mode_used: String,
}

/// Result of a public file upload. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePutPublicResult {
    /// Hex-encoded on-network DataMap address.
    pub address: String,
    /// Storage cost paid in atto tokens. `"0"` if all chunks already existed.
    pub storage_cost_atto: String,
    /// Gas cost paid in wei as a decimal string.
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used.
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
    pub rewards_address: String,
    pub amount: String,
}

/// A pool commitment entry for merkle batch payments.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolCommitmentEntry {
    pub pool_hash: String,
    pub candidates: Vec<CandidateNodeEntry>,
}

/// Result of preparing an upload for external signing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadResult {
    pub upload_id: String,
    pub payments: Vec<PaymentInfo>,
    pub total_amount: String,
    pub payment_vault_address: String,
    pub payment_token_address: String,
    pub rpc_url: String,
    #[serde(rename = "payment_type", default)]
    pub payment_type: String,
    #[serde(rename = "depth", default)]
    pub depth: Option<u8>,
    #[serde(rename = "pool_commitments", default)]
    pub pool_commitments: Option<Vec<PoolCommitmentEntry>>,
    #[serde(rename = "merkle_payment_timestamp", default)]
    pub merkle_payment_timestamp: Option<u64>,
    /// Total chunks in this upload, including any already on-network. Added in
    /// antd 0.10.0; older daemons omit it and it defaults to 0. The external
    /// signer pays for `total_chunks - already_stored_count` chunks.
    #[serde(default)]
    pub total_chunks: u64,
    /// Chunks already stored on-network and excluded from payment + PUT.
    /// Added in antd 0.10.0; defaults to 0 against older daemons.
    #[serde(default)]
    pub already_stored_count: u64,
}

/// Result of finalizing an externally-signed upload.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FinalizeUploadResult {
    #[serde(default)]
    pub address: String,
    #[serde(default)]
    pub chunks_stored: i64,
    #[serde(default)]
    pub data_map: String,
    #[serde(default)]
    pub data_map_address: String,
}

/// Result of preparing a single-chunk publish for external signing.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrepareChunkResult {
    pub address: String,
    #[serde(default)]
    pub already_stored: bool,
    #[serde(default)]
    pub upload_id: String,
    #[serde(default)]
    pub payment_type: String,
    #[serde(default)]
    pub payments: Vec<PaymentInfo>,
    #[serde(default)]
    pub total_amount: String,
    #[serde(default)]
    pub payment_vault_address: String,
    #[serde(default)]
    pub payment_token_address: String,
    #[serde(default)]
    pub rpc_url: String,
}

/// Pre-upload cost breakdown returned by `data_cost` / `file_cost`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadCostEstimate {
    pub cost: String,
    pub file_size: u64,
    pub chunk_count: u32,
    pub estimated_gas_cost_wei: String,
    pub payment_mode: String,
}
