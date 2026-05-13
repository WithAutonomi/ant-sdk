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

// ── External Signer (single-chunk publish) ──

/// `POST /v1/chunks/prepare` — request a quote for publishing a single chunk
/// via the external-signer flow. The daemon collects quotes from the close
/// group, returns the payment shape, and stashes server-side state keyed by
/// `upload_id` for the matching finalize call.
#[derive(Deserialize)]
pub struct PrepareChunkRequest {
    /// Raw chunk bytes, base64-encoded. Maximum one ant-protocol chunk
    /// (≤ 4 MiB before self-encryption is irrelevant here — the bytes are
    /// stored verbatim as one chunk at their BLAKE3 address).
    pub data: String,
}

/// `POST /v1/chunks/prepare` response. Mirrors [`PrepareUploadResponse`]'s
/// wave-batch shape so external signers can reuse the same `payForQuotes()`
/// path with no special-casing.
///
/// When the chunk is already on-network, `already_stored` is `true` and the
/// `upload_id` / payment fields are omitted — the caller can update their
/// records with `address` and skip the finalize step.
#[derive(Serialize)]
pub struct PrepareChunkResponse {
    /// Content-addressed BLAKE3 of the chunk bytes (hex, 32 bytes). Computed
    /// locally on the daemon; the caller can also derive it independently if
    /// needed.
    pub address: String,
    /// `true` if the chunk was already stored on the network. In that case
    /// no payment or finalize call is needed.
    pub already_stored: bool,

    /// Opaque token to pass back to finalize. Omitted when
    /// `already_stored == true`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub upload_id: Option<String>,
    /// Always `"wave_batch"` for single-chunk publishes (single chunk is well
    /// below the merkle threshold). Omitted when `already_stored == true`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payment_type: Option<String>,
    /// Per-quote payment entries for `payForQuotes()`. Typically 5–7 entries
    /// (one per peer in the close group). Empty/omitted when already stored.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub payments: Vec<PaymentEntry>,
    /// Total amount to pay (atto tokens, decimal string). Omitted when
    /// `already_stored == true`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_amount: Option<String>,
    /// EVM configuration — same source as the file/data prepare flow. Omitted
    /// when `already_stored == true`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payment_vault_address: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payment_token_address: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rpc_url: Option<String>,
}

#[derive(Deserialize)]
pub struct FinalizeChunkRequest {
    /// The `upload_id` returned from `/v1/chunks/prepare`.
    pub upload_id: String,
    /// Map of quote_hash (hex) → tx_hash (hex) from the on-chain payment.
    pub tx_hashes: HashMap<String, String>,
}

#[derive(Serialize)]
pub struct FinalizeChunkResponse {
    /// Network address of the stored chunk (hex, 32 bytes).
    pub address: String,
}

// ── External Signer (two-phase upload) ──

#[derive(Deserialize)]
pub struct PrepareUploadRequest {
    pub path: String,
    /// Upload visibility: `"private"` (default — DataMap returned to the
    /// caller) or `"public"` (DataMap chunk bundled into the same payment
    /// batch and stored on-network; its address is returned on finalize).
    /// Omitting this field is equivalent to `"private"` and preserves
    /// pre-0.6.1 behavior.
    #[serde(default)]
    pub visibility: Option<String>,
}

#[derive(Deserialize)]
pub struct PrepareDataUploadRequest {
    pub data: String, // base64
    /// Same semantics as [`PrepareUploadRequest::visibility`]. Currently
    /// only `"private"` (or omission) is accepted on this endpoint;
    /// `"public"` returns 501 until upstream `ant-core` exposes
    /// `data_prepare_upload_with_visibility` (tracked as ant-client PR #73).
    #[serde(default)]
    pub visibility: Option<String>,
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
    /// Network address of the stored DataMap, only set when the legacy
    /// `store_data_map=true` path published the DataMap via the daemon's
    /// internal wallet. New callers should prefer `visibility:"public"`
    /// on prepare and read [`Self::data_map_address`] instead.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub address: Option<String>,
    /// Network address of the bundled DataMap chunk when the upload was
    /// prepared with `visibility:"public"`. The DataMap chunk's payment
    /// is part of the same external-signer batch as the data chunks, so
    /// no separate daemon-wallet payment is required.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_map_address: Option<String>,
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
    #[serde(default = "default_true")]
    pub is_public: bool,
}

fn default_true() -> bool {
    true
}

/// Adjust a chunk count + storage cost estimate to reflect a public upload,
/// which bundles one additional DataMap chunk into the same payment batch.
///
/// Returns `(adjusted_chunk_count, adjusted_storage_cost_atto)`. If the input
/// cost cannot be parsed, only the chunk count is bumped and the cost is
/// returned unchanged.
pub fn adjust_for_public_upload(chunk_count: usize, storage_cost_atto: &str) -> (usize, String) {
    let new_chunk_count = chunk_count.saturating_add(1);
    if chunk_count == 0 {
        return (new_chunk_count, storage_cost_atto.to_string());
    }
    let total: ant_core::data::U256 = match storage_cost_atto.parse() {
        Ok(v) => v,
        Err(_) => return (new_chunk_count, storage_cost_atto.to_string()),
    };
    let divisor = ant_core::data::U256::from(chunk_count as u64);
    let per_chunk = total / divisor;
    let new_total = total + per_chunk;
    (new_chunk_count, new_total.to_string())
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

/// Parse a visibility string into ant-core's `Visibility` enum.
///
/// Accepts `"private"`, `"public"`, or absent (defaults to `Private`).
pub fn parse_visibility(s: Option<&str>) -> Result<ant_core::data::Visibility, String> {
    match s {
        None | Some("private") => Ok(ant_core::data::Visibility::Private),
        Some("public") => Ok(ant_core::data::Visibility::Public),
        Some(other) => Err(format!(
            "invalid visibility: {other:?}. Use \"private\" or \"public\""
        )),
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
    pub version: String,
    pub evm_network: String,
    pub uptime_seconds: u64,
    pub build_commit: String,
    pub payment_token_address: String,
    pub payment_vault_address: String,
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

    #[test]
    fn health_response_serializes_all_fields() {
        let resp = HealthResponse {
            status: "ok".into(),
            network: "default".into(),
            version: "0.4.0".into(),
            evm_network: "arbitrum-one".into(),
            uptime_seconds: 12345,
            build_commit: "abcdef123456".into(),
            payment_token_address: "0xtoken".into(),
            payment_vault_address: "0xvault".into(),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["status"], "ok");
        assert_eq!(json["network"], "default");
        assert_eq!(json["version"], "0.4.0");
        assert_eq!(json["evm_network"], "arbitrum-one");
        assert_eq!(json["uptime_seconds"], 12345u64);
        assert_eq!(json["build_commit"], "abcdef123456");
        assert_eq!(json["payment_token_address"], "0xtoken");
        assert_eq!(json["payment_vault_address"], "0xvault");
    }

    #[test]
    fn health_response_keeps_empty_strings_for_unconfigured_evm() {
        // Local devnet leaves token + vault empty; build_commit is empty for
        // non-git source distributions. Empty strings must round-trip rather
        // than being omitted.
        let resp = HealthResponse {
            status: "ok".into(),
            network: "local".into(),
            version: "0.4.0".into(),
            evm_network: "local".into(),
            uptime_seconds: 0,
            build_commit: String::new(),
            payment_token_address: String::new(),
            payment_vault_address: String::new(),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["build_commit"], "");
        assert_eq!(json["payment_token_address"], "");
        assert_eq!(json["payment_vault_address"], "");
    }

    #[test]
    fn adjust_for_public_upload_bumps_count_and_scales_cost() {
        // 5 chunks, 1000 atto total → per-chunk = 200 atto.
        // Public upload adds 1 chunk → 6 chunks, 1200 atto total.
        let (chunks, cost) = adjust_for_public_upload(5, "1000");
        assert_eq!(chunks, 6);
        assert_eq!(cost, "1200");
    }

    #[test]
    fn adjust_for_public_upload_handles_uneven_division() {
        // 3 chunks, 100 atto total → per-chunk = 33 atto (integer divide).
        // Result: 4 chunks, 133 atto. Slight rounding is acceptable for
        // an estimate; exact pricing is the on-chain quote.
        let (chunks, cost) = adjust_for_public_upload(3, "100");
        assert_eq!(chunks, 4);
        assert_eq!(cost, "133");
    }

    #[test]
    fn adjust_for_public_upload_handles_large_atto_values() {
        // Real-world atto costs frequently exceed u64. Verify U256 handles it.
        // 10 chunks at 1e22 atto total = 10K ANT — well above u64::MAX.
        let total = "10000000000000000000000"; // 1e22
        let (chunks, cost) = adjust_for_public_upload(10, total);
        assert_eq!(chunks, 11);
        // 1e22 + 1e21 = 1.1e22
        assert_eq!(cost, "11000000000000000000000");
    }

    #[test]
    fn adjust_for_public_upload_zero_chunks_only_bumps_count() {
        // Defensive: shouldn't happen in practice, but division-by-zero would.
        let (chunks, cost) = adjust_for_public_upload(0, "0");
        assert_eq!(chunks, 1);
        assert_eq!(cost, "0");
    }

    #[test]
    fn adjust_for_public_upload_unparseable_cost_only_bumps_count() {
        // ant-core returns "0" for already-stored chunks; a non-numeric or
        // negative value would be a contract bug, but stay graceful.
        let (chunks, cost) = adjust_for_public_upload(5, "not-a-number");
        assert_eq!(chunks, 6);
        assert_eq!(cost, "not-a-number");
    }

    #[test]
    fn adjust_for_public_upload_zero_cost_round_trips() {
        // Already-stored case: cost stays 0, count still bumps.
        let (chunks, cost) = adjust_for_public_upload(5, "0");
        assert_eq!(chunks, 6);
        assert_eq!(cost, "0");
    }

    #[test]
    fn prepare_request_visibility_defaults_to_none() {
        let req: PrepareUploadRequest = serde_json::from_str(r#"{"path":"/tmp/foo"}"#).unwrap();
        assert_eq!(req.path, "/tmp/foo");
        assert!(req.visibility.is_none());
    }

    #[test]
    fn prepare_request_visibility_round_trips_public() {
        let req: PrepareUploadRequest =
            serde_json::from_str(r#"{"path":"/tmp/foo","visibility":"public"}"#).unwrap();
        assert_eq!(req.visibility.as_deref(), Some("public"));
    }

    #[test]
    fn prepare_data_request_visibility_defaults_to_none() {
        let req: PrepareDataUploadRequest = serde_json::from_str(r#"{"data":"AAA="}"#).unwrap();
        assert!(req.visibility.is_none());
    }

    #[test]
    fn parse_visibility_accepts_known_values() {
        assert!(matches!(
            parse_visibility(None),
            Ok(ant_core::data::Visibility::Private)
        ));
        assert!(matches!(
            parse_visibility(Some("private")),
            Ok(ant_core::data::Visibility::Private)
        ));
        assert!(matches!(
            parse_visibility(Some("public")),
            Ok(ant_core::data::Visibility::Public)
        ));
    }

    #[test]
    fn parse_visibility_rejects_unknown_values() {
        let err = parse_visibility(Some("Public")).unwrap_err();
        assert!(err.contains("Public"), "err was: {err}");
        let err = parse_visibility(Some("")).unwrap_err();
        assert!(err.contains("\"\""), "err was: {err}");
    }

    #[test]
    fn finalize_response_serializes_data_map_address() {
        let resp = FinalizeUploadResponse {
            data_map: "deadbeef".into(),
            address: None,
            data_map_address: Some("cafebabe".into()),
            chunks_stored: 4,
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["data_map"], "deadbeef");
        assert_eq!(json["data_map_address"], "cafebabe");
        assert!(json.get("address").is_none());
        assert_eq!(json["chunks_stored"], 4);
    }

    #[test]
    fn finalize_response_omits_data_map_address_when_private() {
        let resp = FinalizeUploadResponse {
            data_map: "deadbeef".into(),
            address: None,
            data_map_address: None,
            chunks_stored: 4,
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert!(json.get("address").is_none());
        assert!(json.get("data_map_address").is_none());
    }

    // ── Single-chunk external-signer ──

    #[test]
    fn prepare_chunk_response_for_new_chunk_includes_payment_shape() {
        let resp = PrepareChunkResponse {
            address: "deadbeef".repeat(8),
            already_stored: false,
            upload_id: Some("abc123".into()),
            payment_type: Some("wave_batch".into()),
            payments: vec![PaymentEntry {
                quote_hash: "0xaa".into(),
                rewards_address: "0xbb".into(),
                amount: "100".into(),
            }],
            total_amount: Some("100".into()),
            payment_vault_address: Some("0xcc".into()),
            payment_token_address: Some("0xdd".into()),
            rpc_url: Some("http://localhost:8545".into()),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["already_stored"], false);
        assert_eq!(json["upload_id"], "abc123");
        assert_eq!(json["payment_type"], "wave_batch");
        assert_eq!(json["payments"][0]["quote_hash"], "0xaa");
        assert_eq!(json["total_amount"], "100");
        assert_eq!(json["payment_vault_address"], "0xcc");
        assert_eq!(json["rpc_url"], "http://localhost:8545");
    }

    #[test]
    fn prepare_chunk_response_for_already_stored_omits_payment_fields() {
        let resp = PrepareChunkResponse {
            address: "deadbeef".repeat(8),
            already_stored: true,
            upload_id: None,
            payment_type: None,
            payments: Vec::new(),
            total_amount: None,
            payment_vault_address: None,
            payment_token_address: None,
            rpc_url: None,
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["already_stored"], true);
        assert!(
            json.get("upload_id").is_none(),
            "upload_id should be skipped when already_stored"
        );
        assert!(json.get("payment_type").is_none());
        assert!(json.get("payments").is_none());
        assert!(json.get("total_amount").is_none());
        assert!(json.get("payment_vault_address").is_none());
        assert!(json.get("rpc_url").is_none());
        // address is always present so the caller can update their records
        assert_eq!(
            json["address"].as_str().unwrap().len(),
            64,
            "BLAKE3 address must be 64 hex chars"
        );
    }

    #[test]
    fn prepare_chunk_request_deserializes() {
        let req: PrepareChunkRequest =
            serde_json::from_str(r#"{"data":"SGVsbG8="}"#).unwrap();
        assert_eq!(req.data, "SGVsbG8=");
    }

    #[test]
    fn finalize_chunk_request_deserializes() {
        let json = r#"{
            "upload_id": "abc",
            "tx_hashes": {"0xaa": "0xbb", "0xcc": "0xdd"}
        }"#;
        let req: FinalizeChunkRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.upload_id, "abc");
        assert_eq!(req.tx_hashes.len(), 2);
        assert_eq!(req.tx_hashes["0xaa"], "0xbb");
    }

    #[test]
    fn finalize_chunk_response_serializes() {
        let resp = FinalizeChunkResponse {
            address: "deadbeef".repeat(8),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["address"].as_str().unwrap().len(), 64);
    }
}
