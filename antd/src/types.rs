use serde::{Deserialize, Serialize};

// ── Data ──

#[derive(Deserialize)]
pub struct DataPutRequest {
    pub data: String, // base64
    /// Payment mode: "auto" (default), "merkle", or "single".
    #[serde(default)]
    pub payment_mode: Option<String>,
}

#[derive(Serialize)]
pub struct DataPutPublicResponse {
    pub address: String,
    pub chunks_stored: usize,
    pub payment_mode_used: String,
}

#[derive(Serialize)]
pub struct DataGetResponse {
    pub data: String, // base64
}

#[derive(Deserialize)]
pub struct DataCostRequest {
    pub data: String, // base64
}

#[derive(Serialize)]
pub struct DataPutPrivateResponse {
    pub data_map: String, // hex-encoded serialized data map
    pub chunks_stored: usize,
    pub payment_mode_used: String,
}

#[derive(Deserialize)]
pub struct DataGetPrivateQuery {
    pub data_map: String, // hex
}

// ── Chunks ──

#[derive(Deserialize)]
pub struct ChunkPutRequest {
    pub data: String, // base64
}

#[derive(Serialize)]
pub struct ChunkPutResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Serialize)]
pub struct ChunkGetResponse {
    pub data: String, // base64
}

// ── Graph ──

#[derive(Deserialize)]
pub struct GraphEntryPutRequest {
    pub owner_secret_key: String,              // hex
    pub parents: Vec<String>,                  // hex public keys
    pub content: String,                       // hex, 32 bytes
    pub descendants: Vec<GraphDescendantDto>,
}

#[derive(Serialize, Deserialize)]
pub struct GraphDescendantDto {
    pub public_key: String, // hex
    pub content: String,    // hex, 32 bytes
}

#[derive(Serialize)]
pub struct GraphEntryPutResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Serialize)]
pub struct GraphEntryGetResponse {
    pub owner: String,
    pub parents: Vec<String>,
    pub content: String,
    pub descendants: Vec<GraphDescendantDto>,
}

#[derive(Deserialize)]
pub struct GraphEntryCostRequest {
    pub public_key: String, // hex
}

// ── External Signer (two-phase upload) ──

#[derive(Deserialize)]
pub struct PrepareUploadRequest {
    pub path: String,
}

#[derive(Deserialize)]
pub struct PrepareDataUploadRequest {
    pub data: String, // base64
}

#[derive(Serialize)]
pub struct PrepareUploadResponse {
    /// Opaque token to pass back to finalize (hex-encoded serialized state).
    pub upload_id: String,
    /// Payment entries: each has quote_hash, rewards_address, amount.
    pub payments: Vec<PaymentEntry>,
    /// Total amount to pay (atto tokens as decimal string).
    pub total_amount: String,
    /// Data payments contract address (hex with 0x prefix).
    pub data_payments_address: String,
    /// Payment token contract address (hex with 0x prefix).
    pub payment_token_address: String,
    /// EVM RPC URL for submitting transactions.
    pub rpc_url: String,
}

#[derive(Serialize)]
pub struct PaymentEntry {
    /// Quote hash (hex, 32 bytes).
    pub quote_hash: String,
    /// Rewards address (hex with 0x prefix, 20 bytes).
    pub rewards_address: String,
    /// Amount to pay (atto tokens as decimal string).
    pub amount: String,
}

#[derive(Deserialize)]
pub struct FinalizeUploadRequest {
    /// The upload_id returned from prepare.
    pub upload_id: String,
    /// Map of quote_hash (hex) → tx_hash (hex) from on-chain payment.
    pub tx_hashes: std::collections::HashMap<String, String>,
    /// If true, store the DataMap on-network and return its address.
    /// If false (default), return the raw DataMap for caller-side storage.
    #[serde(default)]
    pub store_data_map: bool,
}

#[derive(Serialize)]
pub struct FinalizeUploadResponse {
    /// Hex-encoded serialized DataMap. Always returned.
    pub data_map: String,
    /// Network address of the stored DataMap (only set when store_data_map=true).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub address: Option<String>,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
}

// ── Files ──

#[derive(Deserialize)]
pub struct FileUploadRequest {
    pub path: String,
    /// Payment mode: "auto" (default), "merkle", or "single".
    #[serde(default)]
    pub payment_mode: Option<String>,
}

#[derive(Serialize)]
pub struct FileUploadPublicResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Deserialize)]
pub struct FileDownloadRequest {
    pub address: String,
    pub dest_path: String,
}

#[derive(Serialize)]
pub struct DirUploadPublicResponse {
    pub cost: String,
    pub address: String,
}

// ── Archives ──

#[derive(Serialize, Deserialize)]
pub struct ArchiveEntryDto {
    pub path: String,
    pub address: String,
    pub created: u64,
    pub modified: u64,
    pub size: u64,
}

#[derive(Serialize, Deserialize)]
pub struct ArchiveDto {
    pub entries: Vec<ArchiveEntryDto>,
}

#[derive(Serialize)]
pub struct ArchivePutResponse {
    pub cost: String,
    pub address: String,
}

// ── Cost ──

#[derive(Serialize)]
pub struct CostResponse {
    pub cost: String,
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub struct CostEstimateRequest {
    pub content_addrs: Vec<CostEstimateEntry>,
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub struct CostEstimateEntry {
    pub xorname: String, // hex
    pub size: usize,
}

#[derive(Deserialize)]
pub struct FileCostRequest {
    pub path: String,
    #[serde(default = "default_true")]
    pub is_public: bool,
    #[serde(default)]
    pub include_archive: bool,
}

fn default_true() -> bool {
    true
}

/// Parse a payment mode string into ant-core's PaymentMode.
pub fn parse_payment_mode(mode: Option<&str>) -> Result<ant_core::data::PaymentMode, String> {
    match mode {
        None | Some("auto") => Ok(ant_core::data::PaymentMode::Auto),
        Some("merkle") => Ok(ant_core::data::PaymentMode::Merkle),
        Some("single") => Ok(ant_core::data::PaymentMode::Single),
        Some(other) => Err(format!("invalid payment_mode: {other:?}. Use \"auto\", \"merkle\", or \"single\"")),
    }
}

/// Format a PaymentMode for JSON responses.
pub fn format_payment_mode(mode: ant_core::data::PaymentMode) -> String {
    match mode {
        ant_core::data::PaymentMode::Auto => "auto".into(),
        ant_core::data::PaymentMode::Merkle => "merkle".into(),
        ant_core::data::PaymentMode::Single => "single".into(),
    }
}

// ── Wallet ──

#[derive(Serialize)]
pub struct WalletBalanceResponse {
    /// Token balance in atto (smallest unit).
    pub balance: String,
    /// Gas token balance in wei.
    pub gas_balance: String,
}

#[derive(Serialize)]
pub struct WalletAddressResponse {
    /// The wallet's public address (hex with 0x prefix).
    pub address: String,
}

#[derive(Serialize)]
pub struct WalletApproveResponse {
    /// Whether the token spend was approved.
    pub approved: bool,
}

// ── Health ──

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub network: String,
}

// ── Events ──

#[derive(Serialize)]
#[allow(dead_code)]
pub struct ClientEventDto {
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub records_paid: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub records_already_paid: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tokens_spent: Option<String>,
}
