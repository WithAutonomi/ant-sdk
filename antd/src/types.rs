use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
    /// Opaque token to pass back to finalize.
    pub upload_id: String,
    /// "wave_batch" or "merkle" — determines which fields are present and
    /// which contract call the external signer must make.
    pub payment_type: String,

    // --- Wave-batch fields (present when payment_type == "wave_batch") ---
    /// Per-quote payment entries for `payForQuotes()`.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub payments: Vec<PaymentEntry>,

    // --- Merkle fields (present when payment_type == "merkle") ---
    /// Merkle tree depth (1-8).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub depth: Option<u8>,
    /// Pool commitments for `payForMerkleTree2()`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pool_commitments: Option<Vec<PoolCommitmentEntry>>,
    /// Timestamp for the merkle payment (unix seconds).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub merkle_payment_timestamp: Option<u64>,

    // --- Common fields (always present) ---
    /// Total amount to pay (atto tokens as decimal string).
    /// For merkle this is "0" since cost is determined on-chain.
    pub total_amount: String,
    /// Unified payment vault contract address (hex with 0x prefix).
    pub payment_vault_address: String,
    /// Payment token contract address (hex with 0x prefix).
    pub payment_token_address: String,
    /// EVM RPC URL for submitting transactions.
    pub rpc_url: String,
}

/// A pool commitment entry for the merkle payment contract.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PoolCommitmentEntry {
    /// Pool hash (hex, 32 bytes with 0x prefix).
    pub pool_hash: String,
    /// Exactly 16 candidate nodes.
    pub candidates: Vec<CandidateNodeEntry>,
}

/// A candidate node: rewards address + price (amount).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CandidateNodeEntry {
    /// Node's rewards address (hex with 0x prefix, 20 bytes).
    pub rewards_address: String,
    /// Node's price / amount (decimal string, maps to contract's `amount` field).
    pub amount: String,
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
    /// Wave-batch: map of quote_hash (hex) → tx_hash (hex) from on-chain payment.
    #[serde(default)]
    pub tx_hashes: Option<HashMap<String, String>>,
    /// Merkle: winner pool hash (hex, 32 bytes) from `MerklePaymentMade` event.
    #[serde(default)]
    pub winner_pool_hash: Option<String>,
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
    pub address: String,
    /// Total storage cost paid in token units (atto). "0" if all chunks already existed.
    pub storage_cost_atto: String,
    /// Total gas cost paid in wei, as a decimal string (u128 exceeds JSON safe-integer range).
    /// "0" if no on-chain transactions were made.
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used ("auto", "merkle", or "single").
    pub payment_mode_used: String,
}

#[derive(Deserialize)]
pub struct FileDownloadRequest {
    pub address: String,
    pub dest_path: String,
}

#[derive(Serialize)]
pub struct DirUploadPublicResponse {
    pub address: String,
    /// Total storage cost paid in token units (atto). "0" if all chunks already existed.
    pub storage_cost_atto: String,
    /// Total gas cost paid in wei, as a decimal string.
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used ("auto", "merkle", or "single").
    pub payment_mode_used: String,
}

// ── Cost ──

#[derive(Serialize)]
pub struct CostResponse {
    /// Storage cost in atto tokens as a string.
    pub cost: String,
    /// Original file size in bytes.
    pub file_size: u64,
    /// Number of data chunks the file would split into.
    pub chunk_count: usize,
    /// Estimated gas cost in wei as a string (advisory heuristic, not a
    /// live gas-oracle query). String shape matches `cost` to avoid JS
    /// integer overflow.
    pub estimated_gas_cost_wei: String,
    /// Payment mode that would be used: `"auto" | "merkle" | "single"`.
    pub payment_mode: String,
}

#[derive(Deserialize)]
pub struct FileCostRequest {
    pub path: String,
    #[allow(dead_code)]
    #[serde(default = "default_true")]
    pub is_public: bool,
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
        Some(other) => Err(format!(
            "invalid payment_mode: {other:?}. Use \"auto\", \"merkle\", or \"single\""
        )),
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

// ── Tests ──

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prepare_response_wave_batch_serializes_without_merkle_fields() {
        let resp = PrepareUploadResponse {
            upload_id: "abc123".into(),
            payment_type: "wave_batch".into(),
            payments: vec![PaymentEntry {
                quote_hash: "0xaa".into(),
                rewards_address: "0xbb".into(),
                amount: "100".into(),
            }],
            depth: None,
            pool_commitments: None,
            merkle_payment_timestamp: None,
            total_amount: "100".into(),
            payment_vault_address: "0xcc".into(),
            payment_token_address: "0xdd".into(),
            rpc_url: "http://localhost:8545".into(),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["payment_type"], "wave_batch");
        assert_eq!(json["payments"][0]["quote_hash"], "0xaa");
        assert_eq!(json["payment_vault_address"], "0xcc");
        // Merkle fields must be absent
        assert!(json.get("depth").is_none());
        assert!(json.get("pool_commitments").is_none());
        assert!(json.get("merkle_payment_timestamp").is_none());
    }

    #[test]
    fn prepare_response_merkle_serializes_without_wave_fields() {
        let resp = PrepareUploadResponse {
            upload_id: "def456".into(),
            payment_type: "merkle".into(),
            payments: vec![],
            depth: Some(5),
            pool_commitments: Some(vec![PoolCommitmentEntry {
                pool_hash: "0xaabb".into(),
                candidates: vec![CandidateNodeEntry {
                    rewards_address: "0x1234".into(),
                    amount: "1000".into(),
                }],
            }]),
            merkle_payment_timestamp: Some(1712150400),
            total_amount: "0".into(),
            payment_vault_address: "0xee".into(),
            payment_token_address: "0xdd".into(),
            rpc_url: "http://localhost:8545".into(),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["payment_type"], "merkle");
        assert_eq!(json["depth"], 5);
        assert_eq!(json["merkle_payment_timestamp"], 1712150400u64);
        assert_eq!(json["pool_commitments"][0]["pool_hash"], "0xaabb");
        assert_eq!(json["payment_vault_address"], "0xee");
        // Wave fields must be absent
        assert!(json.get("payments").is_none());
    }

    #[test]
    fn finalize_request_wave_batch_deserializes() {
        let json = r#"{
            "upload_id": "up1",
            "tx_hashes": {"0xaa": "0xbb"},
            "store_data_map": false
        }"#;
        let req: FinalizeUploadRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.upload_id, "up1");
        assert!(req.tx_hashes.is_some());
        assert_eq!(req.tx_hashes.as_ref().unwrap()["0xaa"], "0xbb");
        assert!(req.winner_pool_hash.is_none());
    }

    #[test]
    fn finalize_request_merkle_deserializes() {
        let json = r#"{
            "upload_id": "up2",
            "winner_pool_hash": "0xccdd",
            "store_data_map": true
        }"#;
        let req: FinalizeUploadRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.upload_id, "up2");
        assert!(req.winner_pool_hash.is_some());
        assert_eq!(req.winner_pool_hash.unwrap(), "0xccdd");
        assert!(req.tx_hashes.is_none());
        assert!(req.store_data_map);
    }

    #[test]
    fn finalize_request_minimal_deserializes() {
        // Only upload_id required — both tx_hashes and winner_pool_hash default to None
        let json = r#"{"upload_id": "up3"}"#;
        let req: FinalizeUploadRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.upload_id, "up3");
        assert!(req.tx_hashes.is_none());
        assert!(req.winner_pool_hash.is_none());
        assert!(!req.store_data_map);
    }

    #[test]
    fn finalize_request_backward_compat_with_required_tx_hashes() {
        // Old clients send tx_hashes as a required field (not wrapped in Option)
        // Verify this still deserializes correctly
        let json = r#"{
            "upload_id": "up4",
            "tx_hashes": {}
        }"#;
        let req: FinalizeUploadRequest = serde_json::from_str(json).unwrap();
        assert!(req.tx_hashes.is_some());
        assert!(req.tx_hashes.as_ref().unwrap().is_empty());
    }
}
