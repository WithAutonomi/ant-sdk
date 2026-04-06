use std::time::Duration;

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use reqwest;
use serde_json::{json, Value};

use crate::discover::discover_daemon_url;
use crate::errors::{error_for_status, AntdError};
use crate::models::*;

/// Percent-encode a string for use in a URL query parameter.
fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push_str(&format!("%{:02X}", b));
            }
        }
    }
    out
}

/// Default base URL of the antd daemon.
pub const DEFAULT_BASE_URL: &str = "http://localhost:8082";

/// Default request timeout (5 minutes).
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(300);

/// REST client for the antd daemon.
#[derive(Debug, Clone)]
pub struct Client {
    base_url: String,
    http: reqwest::Client,
}

impl Client {
    /// Creates a new client with the given base URL and default timeout.
    pub fn new(base_url: &str) -> Self {
        Self::with_timeout(base_url, DEFAULT_TIMEOUT)
    }

    /// Creates a client by auto-discovering the daemon port file, falling back
    /// to [`DEFAULT_BASE_URL`] if discovery fails.
    pub fn auto_discover() -> Self {
        let url = discover_daemon_url()
            .unwrap_or_else(|| DEFAULT_BASE_URL.to_string());
        Self::new(&url)
    }

    /// Like [`auto_discover`](Self::auto_discover) but with a custom request
    /// timeout.
    pub fn auto_discover_with_timeout(timeout: Duration) -> Self {
        let url = discover_daemon_url()
            .unwrap_or_else(|| DEFAULT_BASE_URL.to_string());
        Self::with_timeout(&url, timeout)
    }

    /// Creates a new client with the given base URL and custom timeout.
    pub fn with_timeout(base_url: &str, timeout: Duration) -> Self {
        let http = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .expect("failed to build reqwest client");
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http,
        }
    }

    // --- internal helpers ---

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    async fn do_json(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<(Option<Value>, u16), AntdError> {
        let mut req = self.http.request(method, self.url(path));
        if let Some(b) = body {
            req = req.json(&b);
        }

        let resp = req.send().await?;
        let status = resp.status().as_u16();
        let bytes = resp.bytes().await?;

        if status < 200 || status >= 300 {
            let msg = if let Ok(parsed) = serde_json::from_slice::<Value>(&bytes) {
                parsed
                    .get("error")
                    .and_then(|e| e.as_str())
                    .unwrap_or_default()
                    .to_string()
            } else {
                String::from_utf8_lossy(&bytes).to_string()
            };
            return Err(error_for_status(status, msg));
        }

        if bytes.is_empty() {
            return Ok((None, status));
        }

        let result: Value = serde_json::from_slice(&bytes)?;
        Ok((Some(result), status))
    }

    async fn do_head(&self, path: &str) -> Result<u16, AntdError> {
        let resp = self
            .http
            .head(self.url(path))
            .send()
            .await?;
        Ok(resp.status().as_u16())
    }

    fn b64_encode(data: &[u8]) -> String {
        BASE64.encode(data)
    }

    fn b64_decode(s: &str) -> Result<Vec<u8>, AntdError> {
        BASE64
            .decode(s)
            .map_err(|e| AntdError::Internal(format!("base64 decode: {e}")))
    }

    fn str_field(v: &Value, key: &str) -> String {
        v.get(key)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    }

    fn i64_field(v: &Value, key: &str) -> i64 {
        v.get(key)
            .and_then(|v| v.as_f64())
            .map(|f| f as i64)
            .unwrap_or_default()
    }

    // --- Health ---

    /// Checks the antd daemon status.
    pub async fn health(&self) -> Result<HealthStatus, AntdError> {
        let (j, _) = self.do_json(reqwest::Method::GET, "/health", None).await?;
        let j = j.unwrap_or_default();
        Ok(HealthStatus {
            ok: Self::str_field(&j, "status") == "ok",
            network: Self::str_field(&j, "network"),
        })
    }

    // --- Data ---

    /// Stores public immutable data on the network.
    pub async fn data_put_public(&self, data: &[u8], payment_mode: Option<&str>) -> Result<PutResult, AntdError> {
        let mut body = json!({ "data": Self::b64_encode(data) });
        if let Some(mode) = payment_mode {
            body["payment_mode"] = json!(mode);
        }
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/public",
                Some(body),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "address"),
        })
    }

    /// Retrieves public data by address.
    pub async fn data_get_public(&self, address: &str) -> Result<Vec<u8>, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::GET,
                &format!("/v1/data/public/{address}"),
                None,
            )
            .await?;
        let j = j.unwrap_or_default();
        Self::b64_decode(&Self::str_field(&j, "data"))
    }

    /// Stores private encrypted data on the network.
    pub async fn data_put_private(&self, data: &[u8], payment_mode: Option<&str>) -> Result<PutResult, AntdError> {
        let mut body = json!({ "data": Self::b64_encode(data) });
        if let Some(mode) = payment_mode {
            body["payment_mode"] = json!(mode);
        }
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/private",
                Some(body),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "data_map"),
        })
    }

    /// Retrieves private data using a data map.
    pub async fn data_get_private(&self, data_map: &str) -> Result<Vec<u8>, AntdError> {
        let encoded = url_encode(data_map);
        let (j, _) = self
            .do_json(
                reqwest::Method::GET,
                &format!("/v1/data/private?data_map={encoded}"),
                None,
            )
            .await?;
        let j = j.unwrap_or_default();
        Self::b64_decode(&Self::str_field(&j, "data"))
    }

    /// Estimates the cost of storing data.
    pub async fn data_cost(&self, data: &[u8]) -> Result<String, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/cost",
                Some(json!({ "data": Self::b64_encode(data) })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::str_field(&j, "cost"))
    }

    // --- Chunks ---

    /// Stores a raw chunk on the network.
    pub async fn chunk_put(&self, data: &[u8]) -> Result<PutResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/chunks",
                Some(json!({ "data": Self::b64_encode(data) })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "address"),
        })
    }

    /// Retrieves a chunk by address.
    pub async fn chunk_get(&self, address: &str) -> Result<Vec<u8>, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::GET,
                &format!("/v1/chunks/{address}"),
                None,
            )
            .await?;
        let j = j.unwrap_or_default();
        Self::b64_decode(&Self::str_field(&j, "data"))
    }

    // --- Files ---

    /// Uploads a local file to the network.
    pub async fn file_upload_public(&self, path: &str, payment_mode: Option<&str>) -> Result<PutResult, AntdError> {
        let mut body = json!({ "path": path });
        if let Some(mode) = payment_mode {
            body["payment_mode"] = json!(mode);
        }
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/files/upload/public",
                Some(body),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "address"),
        })
    }

    /// Downloads a file from the network to a local path.
    pub async fn file_download_public(
        &self,
        address: &str,
        dest_path: &str,
    ) -> Result<(), AntdError> {
        self.do_json(
            reqwest::Method::POST,
            "/v1/files/download/public",
            Some(json!({ "address": address, "dest_path": dest_path })),
        )
        .await?;
        Ok(())
    }

    /// Uploads a local directory to the network.
    pub async fn dir_upload_public(&self, path: &str, payment_mode: Option<&str>) -> Result<PutResult, AntdError> {
        let mut body = json!({ "path": path });
        if let Some(mode) = payment_mode {
            body["payment_mode"] = json!(mode);
        }
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/dirs/upload/public",
                Some(body),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "address"),
        })
    }

    /// Downloads a directory from the network to a local path.
    pub async fn dir_download_public(
        &self,
        address: &str,
        dest_path: &str,
    ) -> Result<(), AntdError> {
        self.do_json(
            reqwest::Method::POST,
            "/v1/dirs/download/public",
            Some(json!({ "address": address, "dest_path": dest_path })),
        )
        .await?;
        Ok(())
    }

    /// Estimates the cost of uploading a file.
    pub async fn file_cost(
        &self,
        path: &str,
        is_public: bool,
    ) -> Result<String, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/cost/file",
                Some(json!({
                    "path": path,
                    "is_public": is_public,
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::str_field(&j, "cost"))
    }

    // --- Wallet ---

    /// Returns the wallet address configured in the daemon.
    pub async fn wallet_address(&self) -> Result<WalletAddress, AntdError> {
        let (j, _) = self
            .do_json(reqwest::Method::GET, "/v1/wallet/address", None)
            .await?;
        let j = j.unwrap_or_default();
        Ok(WalletAddress {
            address: Self::str_field(&j, "address"),
        })
    }

    /// Returns the wallet balance from the daemon.
    pub async fn wallet_balance(&self) -> Result<WalletBalance, AntdError> {
        let (j, _) = self
            .do_json(reqwest::Method::GET, "/v1/wallet/balance", None)
            .await?;
        let j = j.unwrap_or_default();
        Ok(WalletBalance {
            balance: Self::str_field(&j, "balance"),
            gas_balance: Self::str_field(&j, "gas_balance"),
        })
    }

    /// Approves the wallet to spend tokens on payment contracts.
    /// This is a one-time operation required before any storage operations.
    pub async fn wallet_approve(&self) -> Result<bool, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/wallet/approve",
                Some(json!({})),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(j.get("approved").and_then(|v| v.as_bool()).unwrap_or(false))
    }

    // --- External Signer (Two-Phase Upload) ---

    /// Prepares a file upload for external signing.
    /// Returns payment details that an external signer must process before calling
    /// [`finalize_upload`](Self::finalize_upload).
    pub async fn prepare_upload(&self, path: &str) -> Result<PrepareUploadResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/upload/prepare",
                Some(json!({ "path": path })),
            )
            .await?;
        let j = j.unwrap_or_default();
        let payments = j
            .get("payments")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|p| PaymentInfo {
                        quote_hash: Self::str_field(p, "quote_hash"),
                        rewards_address: Self::str_field(p, "rewards_address"),
                        amount: Self::str_field(p, "amount"),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(PrepareUploadResult {
            upload_id: Self::str_field(&j, "upload_id"),
            payments,
            total_amount: Self::str_field(&j, "total_amount"),
            data_payments_address: Self::str_field(&j, "data_payments_address"),
            payment_token_address: Self::str_field(&j, "payment_token_address"),
            rpc_url: Self::str_field(&j, "rpc_url"),
            payment_type: Self::str_field(&j, "payment_type"),
            depth: j.get("depth").and_then(|v| v.as_u64()).map(|v| v as u8),
            pool_commitments: j.get("pool_commitments").and_then(|v| v.as_array()).map(|arr| {
                arr.iter()
                    .map(|p| PoolCommitmentEntry {
                        pool_hash: Self::str_field(p, "pool_hash"),
                        candidates: p
                            .get("candidates")
                            .and_then(|c| c.as_array())
                            .map(|ca| {
                                ca.iter()
                                    .map(|c| CandidateNodeEntry {
                                        rewards_address: Self::str_field(c, "rewards_address"),
                                        amount: Self::str_field(c, "amount"),
                                    })
                                    .collect()
                            })
                            .unwrap_or_default(),
                    })
                    .collect()
            }),
            merkle_payment_timestamp: j.get("merkle_payment_timestamp").and_then(|v| v.as_u64()),
            merkle_payments_address: j.get("merkle_payments_address").and_then(|v| v.as_str()).map(|s| s.to_string()),
        })
    }

    /// Prepares a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    /// Returns payment details that an external signer must process before calling
    /// [`finalize_upload`](Self::finalize_upload).
    pub async fn prepare_data_upload(&self, data: &[u8]) -> Result<PrepareUploadResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/prepare",
                Some(json!({ "data": Self::b64_encode(data) })),
            )
            .await?;
        let j = j.unwrap_or_default();
        let payments = j
            .get("payments")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|p| PaymentInfo {
                        quote_hash: Self::str_field(p, "quote_hash"),
                        rewards_address: Self::str_field(p, "rewards_address"),
                        amount: Self::str_field(p, "amount"),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(PrepareUploadResult {
            upload_id: Self::str_field(&j, "upload_id"),
            payments,
            total_amount: Self::str_field(&j, "total_amount"),
            data_payments_address: Self::str_field(&j, "data_payments_address"),
            payment_token_address: Self::str_field(&j, "payment_token_address"),
            rpc_url: Self::str_field(&j, "rpc_url"),
            payment_type: Self::str_field(&j, "payment_type"),
            depth: j.get("depth").and_then(|v| v.as_u64()).map(|v| v as u8),
            pool_commitments: j.get("pool_commitments").and_then(|v| v.as_array()).map(|arr| {
                arr.iter()
                    .map(|p| PoolCommitmentEntry {
                        pool_hash: Self::str_field(p, "pool_hash"),
                        candidates: p
                            .get("candidates")
                            .and_then(|c| c.as_array())
                            .map(|ca| {
                                ca.iter()
                                    .map(|c| CandidateNodeEntry {
                                        rewards_address: Self::str_field(c, "rewards_address"),
                                        amount: Self::str_field(c, "amount"),
                                    })
                                    .collect()
                            })
                            .unwrap_or_default(),
                    })
                    .collect()
            }),
            merkle_payment_timestamp: j.get("merkle_payment_timestamp").and_then(|v| v.as_u64()),
            merkle_payments_address: j.get("merkle_payments_address").and_then(|v| v.as_str()).map(|s| s.to_string()),
        })
    }

    /// Finalizes an upload after an external signer has submitted payment transactions.
    pub async fn finalize_upload(
        &self,
        upload_id: &str,
        tx_hashes: &std::collections::HashMap<String, String>,
    ) -> Result<FinalizeUploadResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/upload/finalize",
                Some(json!({
                    "upload_id": upload_id,
                    "tx_hashes": tx_hashes,
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(FinalizeUploadResult {
            address: Self::str_field(&j, "address"),
            chunks_stored: Self::i64_field(&j, "chunks_stored"),
        })
    }

    /// Finalizes a merkle batch upload after the winning pool has been determined.
    pub async fn finalize_merkle_upload(
        &self,
        upload_id: &str,
        winner_pool_hash: &str,
        store_data_map: bool,
    ) -> Result<FinalizeUploadResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/upload/finalize",
                Some(json!({
                    "upload_id": upload_id,
                    "winner_pool_hash": winner_pool_hash,
                    "store_data_map": store_data_map,
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(FinalizeUploadResult {
            address: Self::str_field(&j, "address"),
            chunks_stored: Self::i64_field(&j, "chunks_stored"),
        })
    }
}
