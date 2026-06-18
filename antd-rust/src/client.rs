use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bytes::Bytes;
use futures_core::Stream;
use reqwest;
use serde_json::{json, Value};

use crate::discover::discover_daemon_url;
use crate::errors::{error_for_status, AntdError};
use crate::models::*;

/// Default base URL of the antd daemon.
pub const DEFAULT_BASE_URL: &str = "http://localhost:8082";

/// Media type that opts the stream endpoints into NDJSON progress framing.
const NDJSON_CONTENT_TYPE: &str = "application/x-ndjson";

/// Parse one NDJSON line into a [`DownloadFrame`]. Returns `Ok(None)` for the
/// leading `meta` frame, blank lines, and unknown frame types (forward-compat);
/// maps an `error` frame to a stream error.
fn parse_ndjson_frame(line: &[u8]) -> Result<Option<DownloadFrame>, AntdError> {
    let line = line.strip_suffix(b"\r").unwrap_or(line);
    if line.is_empty() {
        return Ok(None);
    }
    let v: Value = serde_json::from_slice(line)
        .map_err(|e| AntdError::Internal(format!("invalid NDJSON frame: {e}")))?;
    match v.get("type").and_then(Value::as_str) {
        Some("data") => {
            let b64 = v.get("chunk").and_then(Value::as_str).unwrap_or_default();
            let bytes = BASE64
                .decode(b64)
                .map_err(|e| AntdError::Internal(format!("base64 decode: {e}")))?;
            Ok(Some(DownloadFrame::Data(Bytes::from(bytes))))
        }
        Some("progress") => Ok(Some(DownloadFrame::Progress(DownloadProgress {
            phase: v
                .get("phase")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            fetched: v.get("fetched").and_then(Value::as_u64).unwrap_or(0),
            total: v.get("total").and_then(Value::as_u64).unwrap_or(0),
        }))),
        Some("error") => Err(AntdError::Internal(
            v.get("message")
                .and_then(Value::as_str)
                .unwrap_or("download failed")
                .to_string(),
        )),
        // "meta" carries the byte denominator; surface it as a Meta frame.
        Some("meta") => Ok(Some(DownloadFrame::Meta(
            v.get("total_size").and_then(Value::as_u64).unwrap_or(0),
        ))),
        // Unknown types are ignored for forward compatibility.
        _ => Ok(None),
    }
}

/// [`Stream`] adapter that parses an NDJSON download body into
/// [`DownloadFrame`]s, buffering partial lines across byte-chunk boundaries.
struct NdjsonFrames {
    inner: Pin<Box<dyn Stream<Item = Result<Bytes, reqwest::Error>> + Send>>,
    buf: Vec<u8>,
    done: bool,
}

impl NdjsonFrames {
    fn new<S>(inner: S) -> Self
    where
        S: Stream<Item = Result<Bytes, reqwest::Error>> + Send + 'static,
    {
        Self {
            inner: Box::pin(inner),
            buf: Vec::new(),
            done: false,
        }
    }
}

impl Stream for NdjsonFrames {
    type Item = Result<DownloadFrame, AntdError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        loop {
            // Emit any complete line already buffered.
            if let Some(pos) = this.buf.iter().position(|&b| b == b'\n') {
                let line: Vec<u8> = this.buf.drain(..=pos).collect();
                match parse_ndjson_frame(&line[..line.len() - 1]) {
                    Ok(Some(frame)) => return Poll::Ready(Some(Ok(frame))),
                    Ok(None) => continue,
                    Err(e) => return Poll::Ready(Some(Err(e))),
                }
            }
            if this.done {
                return Poll::Ready(None);
            }
            match this.inner.as_mut().poll_next(cx) {
                Poll::Ready(Some(Ok(bytes))) => {
                    this.buf.extend_from_slice(&bytes);
                    continue;
                }
                Poll::Ready(Some(Err(e))) => return Poll::Ready(Some(Err(AntdError::from(e)))),
                Poll::Ready(None) => {
                    this.done = true;
                    // Flush a trailing line with no terminating newline.
                    if !this.buf.is_empty() {
                        let line = std::mem::take(&mut this.buf);
                        return match parse_ndjson_frame(&line) {
                            Ok(Some(frame)) => Poll::Ready(Some(Ok(frame))),
                            Ok(None) => Poll::Ready(None),
                            Err(e) => Poll::Ready(Some(Err(e))),
                        };
                    }
                    return Poll::Ready(None);
                }
                Poll::Pending => return Poll::Pending,
            }
        }
    }
}

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
        let url = discover_daemon_url().unwrap_or_else(|| DEFAULT_BASE_URL.to_string());
        Self::new(&url)
    }

    /// Like [`auto_discover`](Self::auto_discover) but with a custom request
    /// timeout.
    pub fn auto_discover_with_timeout(timeout: Duration) -> Self {
        let url = discover_daemon_url().unwrap_or_else(|| DEFAULT_BASE_URL.to_string());
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

        if !(200..300).contains(&status) {
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

    /// Sends a request and, on a 2xx response, returns the [`reqwest::Response`]
    /// for streaming consumption via [`reqwest::Response::bytes_stream`].
    ///
    /// On a non-2xx response the JSON error body (`{"error":"..."}`) is read
    /// and parsed into an [`AntdError`] — mirroring [`do_json`](Self::do_json).
    /// This lets callers consume the body incrementally (constant memory)
    /// instead of buffering the whole object.
    async fn do_stream(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<reqwest::Response, AntdError> {
        self.do_stream_with_accept(method, path, body, None).await
    }

    /// Like [`do_stream`](Self::do_stream) but optionally sets an `Accept`
    /// header — used to opt into NDJSON progress framing on the stream
    /// endpoints (`Accept: application/x-ndjson`).
    async fn do_stream_with_accept(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
        accept: Option<&str>,
    ) -> Result<reqwest::Response, AntdError> {
        let mut req = self.http.request(method, self.url(path));
        if let Some(a) = accept {
            req = req.header(reqwest::header::ACCEPT, a);
        }
        if let Some(b) = body {
            req = req.json(&b);
        }

        let resp = req.send().await?;
        let status = resp.status().as_u16();

        if !(200..300).contains(&status) {
            // Error responses are small JSON bodies sent before any stream
            // body, so it is safe to buffer them fully.
            let bytes = resp.bytes().await?;
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

        Ok(resp)
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

    fn u64_field(v: &Value, key: &str) -> u64 {
        v.get(key).and_then(|v| v.as_u64()).unwrap_or_default()
    }

    // --- Health ---

    /// Checks the antd daemon status.
    pub async fn health(&self) -> Result<HealthStatus, AntdError> {
        let (j, _) = self.do_json(reqwest::Method::GET, "/health", None).await?;
        let j = j.unwrap_or_default();
        Ok(HealthStatus {
            ok: Self::str_field(&j, "status") == "ok",
            network: Self::str_field(&j, "network"),
            version: Self::str_field(&j, "version"),
            evm_network: Self::str_field(&j, "evm_network"),
            uptime_seconds: j
                .get("uptime_seconds")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
            build_commit: Self::str_field(&j, "build_commit"),
            payment_token_address: Self::str_field(&j, "payment_token_address"),
            payment_vault_address: Self::str_field(&j, "payment_vault_address"),
        })
    }

    // --- Data ---

    /// Stores private encrypted data on the network. Returns the caller-held
    /// DataMap (hex); the DataMap is NOT stored on-network.
    pub async fn data_put(
        &self,
        data: &[u8],
        payment_mode: PaymentMode,
    ) -> Result<DataPutResult, AntdError> {
        let body = json!({
            "data": Self::b64_encode(data),
            "payment_mode": payment_mode.as_wire(),
        });
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/data", Some(body))
            .await?;
        let j = j.unwrap_or_default();
        Ok(DataPutResult {
            data_map: Self::str_field(&j, "data_map"),
            chunks_stored: Self::u64_field(&j, "chunks_stored"),
            payment_mode_used: Self::str_field(&j, "payment_mode_used"),
        })
    }

    /// Retrieves private data from a caller-held DataMap (hex).
    pub async fn data_get(&self, data_map: &str) -> Result<Vec<u8>, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/get",
                Some(json!({ "data_map": data_map })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Self::b64_decode(&Self::str_field(&j, "data"))
    }

    /// Stores public data on the network. The DataMap is stored on-network
    /// as an extra chunk; the returned address is the shareable handle.
    pub async fn data_put_public(
        &self,
        data: &[u8],
        payment_mode: PaymentMode,
    ) -> Result<DataPutPublicResult, AntdError> {
        let body = json!({
            "data": Self::b64_encode(data),
            "payment_mode": payment_mode.as_wire(),
        });
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/data/public", Some(body))
            .await?;
        let j = j.unwrap_or_default();
        Ok(DataPutPublicResult {
            address: Self::str_field(&j, "address"),
            chunks_stored: Self::u64_field(&j, "chunks_stored"),
            payment_mode_used: Self::str_field(&j, "payment_mode_used"),
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

    /// Streams private data from a caller-held DataMap (hex).
    ///
    /// The streaming counterpart to [`data_get`](Self::data_get): instead of
    /// buffering the whole decrypted object in memory, this returns an async
    /// [`Stream`] of [`Bytes`] chunks that the caller consumes incrementally
    /// (constant memory).
    ///
    /// The daemon decrypts the object and streams the raw bytes with a
    /// `Content-Length` header; a body ending short of `Content-Length`
    /// indicates a failed download. Non-2xx responses are surfaced as an
    /// [`AntdError`] before any stream item is yielded.
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// use antd_client::{Client, DEFAULT_BASE_URL};
    /// use futures_core::Stream;
    /// use tokio_stream::StreamExt;
    ///
    /// # async fn run() -> Result<(), Box<dyn std::error::Error>> {
    /// let client = Client::new(DEFAULT_BASE_URL);
    /// let mut stream = Box::pin(client.data_stream("deadbeef").await?);
    /// while let Some(chunk) = stream.next().await {
    ///     let chunk = chunk?;
    ///     // process `chunk` (Bytes) incrementally
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub async fn data_stream(
        &self,
        data_map: &str,
    ) -> Result<impl Stream<Item = Result<Bytes, reqwest::Error>>, AntdError> {
        let resp = self
            .do_stream(
                reqwest::Method::POST,
                "/v1/data/stream",
                Some(json!({ "data_map": data_map })),
            )
            .await?;
        Ok(resp.bytes_stream())
    }

    /// Streams public data by address.
    ///
    /// The streaming counterpart to [`data_get_public`](Self::data_get_public):
    /// returns an async [`Stream`] of [`Bytes`] chunks the caller consumes
    /// incrementally (constant memory) rather than buffering the whole object.
    ///
    /// Non-2xx responses are surfaced as an [`AntdError`] before any stream
    /// item is yielded.
    pub async fn data_stream_public(
        &self,
        address: &str,
    ) -> Result<impl Stream<Item = Result<Bytes, reqwest::Error>>, AntdError> {
        let resp = self
            .do_stream(
                reqwest::Method::GET,
                &format!("/v1/data/public/{address}/stream"),
                None,
            )
            .await?;
        Ok(resp.bytes_stream())
    }

    /// Like [`data_stream`](Self::data_stream) but opts into NDJSON progress
    /// framing (`Accept: application/x-ndjson`), yielding [`DownloadFrame`]s so
    /// the caller can drive a *determinate* progress bar. Data frames carry the
    /// plaintext [`Bytes`]; progress frames carry chunk-fetch counts. The byte
    /// denominator arrives as the leading NDJSON `meta` frame (parsed and
    /// dropped here); a terminal `error` frame surfaces as a stream error.
    pub async fn data_stream_with_progress(
        &self,
        data_map: &str,
    ) -> Result<impl Stream<Item = Result<DownloadFrame, AntdError>>, AntdError> {
        let resp = self
            .do_stream_with_accept(
                reqwest::Method::POST,
                "/v1/data/stream",
                Some(json!({ "data_map": data_map })),
                Some(NDJSON_CONTENT_TYPE),
            )
            .await?;
        Ok(NdjsonFrames::new(resp.bytes_stream()))
    }

    /// The public counterpart to
    /// [`data_stream_with_progress`](Self::data_stream_with_progress).
    pub async fn data_stream_public_with_progress(
        &self,
        address: &str,
    ) -> Result<impl Stream<Item = Result<DownloadFrame, AntdError>>, AntdError> {
        let resp = self
            .do_stream_with_accept(
                reqwest::Method::GET,
                &format!("/v1/data/public/{address}/stream"),
                None,
                Some(NDJSON_CONTENT_TYPE),
            )
            .await?;
        Ok(NdjsonFrames::new(resp.bytes_stream()))
    }

    /// Pre-upload cost breakdown for the given bytes.
    pub async fn data_cost(
        &self,
        data: &[u8],
        payment_mode: PaymentMode,
    ) -> Result<UploadCostEstimate, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/cost",
                Some(json!({
                    "data": Self::b64_encode(data),
                    "payment_mode": payment_mode.as_wire(),
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(UploadCostEstimate {
            cost: Self::str_field(&j, "cost"),
            file_size: Self::u64_field(&j, "file_size"),
            chunk_count: Self::u64_field(&j, "chunk_count") as u32,
            estimated_gas_cost_wei: Self::str_field(&j, "estimated_gas_cost_wei"),
            payment_mode: Self::str_field(&j, "payment_mode"),
        })
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
            .do_json(reqwest::Method::GET, &format!("/v1/chunks/{address}"), None)
            .await?;
        let j = j.unwrap_or_default();
        Self::b64_decode(&Self::str_field(&j, "data"))
    }

    // --- Files ---

    /// Uploads a file privately. Returns the caller-held DataMap (hex).
    pub async fn file_put(
        &self,
        path: &str,
        payment_mode: PaymentMode,
    ) -> Result<FilePutResult, AntdError> {
        let body = json!({
            "path": path,
            "payment_mode": payment_mode.as_wire(),
        });
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/files", Some(body))
            .await?;
        let j = j.unwrap_or_default();
        Ok(FilePutResult {
            data_map: Self::str_field(&j, "data_map"),
            storage_cost_atto: Self::str_field(&j, "storage_cost_atto"),
            gas_cost_wei: Self::str_field(&j, "gas_cost_wei"),
            chunks_stored: Self::u64_field(&j, "chunks_stored"),
            payment_mode_used: Self::str_field(&j, "payment_mode_used"),
        })
    }

    /// Downloads a private file from a caller-held DataMap into `dest_path`.
    pub async fn file_get(&self, data_map: &str, dest_path: &str) -> Result<(), AntdError> {
        self.do_json(
            reqwest::Method::POST,
            "/v1/files/get",
            Some(json!({ "data_map": data_map, "dest_path": dest_path })),
        )
        .await?;
        Ok(())
    }

    /// Uploads a file publicly. The DataMap is stored on-network as an extra
    /// chunk; the returned address is the shareable handle.
    pub async fn file_put_public(
        &self,
        path: &str,
        payment_mode: PaymentMode,
    ) -> Result<FilePutPublicResult, AntdError> {
        let body = json!({
            "path": path,
            "payment_mode": payment_mode.as_wire(),
        });
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/files/public", Some(body))
            .await?;
        let j = j.unwrap_or_default();
        Ok(FilePutPublicResult {
            address: Self::str_field(&j, "address"),
            storage_cost_atto: Self::str_field(&j, "storage_cost_atto"),
            gas_cost_wei: Self::str_field(&j, "gas_cost_wei"),
            chunks_stored: Self::u64_field(&j, "chunks_stored"),
            payment_mode_used: Self::str_field(&j, "payment_mode_used"),
        })
    }

    /// Downloads a public file from an on-network DataMap address.
    pub async fn file_get_public(&self, address: &str, dest_path: &str) -> Result<(), AntdError> {
        self.do_json(
            reqwest::Method::POST,
            "/v1/files/public/get",
            Some(json!({ "address": address, "dest_path": dest_path })),
        )
        .await?;
        Ok(())
    }

    /// Pre-upload cost breakdown for the file at `path`.
    pub async fn file_cost(
        &self,
        path: &str,
        is_public: bool,
        payment_mode: PaymentMode,
    ) -> Result<UploadCostEstimate, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/files/cost",
                Some(json!({
                    "path": path,
                    "is_public": is_public,
                    "payment_mode": payment_mode.as_wire(),
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(UploadCostEstimate {
            cost: Self::str_field(&j, "cost"),
            file_size: Self::u64_field(&j, "file_size"),
            chunk_count: Self::u64_field(&j, "chunk_count") as u32,
            estimated_gas_cost_wei: Self::str_field(&j, "estimated_gas_cost_wei"),
            payment_mode: Self::str_field(&j, "payment_mode"),
        })
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
            .do_json(reqwest::Method::POST, "/v1/wallet/approve", Some(json!({})))
            .await?;
        let j = j.unwrap_or_default();
        Ok(j.get("approved").and_then(|v| v.as_bool()).unwrap_or(false))
    }

    // --- External Signer (Two-Phase Upload) ---

    /// Parses a `/v1/upload/prepare` or `/v1/data/prepare` JSON response into
    /// a [`PrepareUploadResult`].
    fn parse_prepare_response(j: &Value) -> PrepareUploadResult {
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
        PrepareUploadResult {
            upload_id: Self::str_field(j, "upload_id"),
            payments,
            total_amount: Self::str_field(j, "total_amount"),
            payment_vault_address: Self::str_field(j, "payment_vault_address"),
            payment_token_address: Self::str_field(j, "payment_token_address"),
            rpc_url: Self::str_field(j, "rpc_url"),
            payment_type: Self::str_field(j, "payment_type"),
            depth: j.get("depth").and_then(|v| v.as_u64()).map(|v| v as u8),
            pool_commitments: j
                .get("pool_commitments")
                .and_then(|v| v.as_array())
                .map(|arr| {
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
            total_chunks: j.get("total_chunks").and_then(|v| v.as_u64()).unwrap_or(0),
            already_stored_count: j
                .get("already_stored_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
        }
    }

    /// Prepares a file upload for external signing.
    ///
    /// `visibility` controls whether the DataMap chunk is bundled into the
    /// same external-signer payment batch:
    /// - `Some("public")` — daemon includes the serialized DataMap as an
    ///   additional chunk in the payment intent, and `finalize_upload`
    ///   returns the shareable on-network handle as
    ///   [`FinalizeUploadResult::data_map_address`]. Requires antd >= 0.6.1.
    /// - `Some("private")` / `None` — preserves the pre-public daemon wire
    ///   shape: the JSON field is omitted when `None`.
    ///
    /// Returns payment details that an external signer must process before
    /// calling [`finalize_upload`](Self::finalize_upload).
    pub async fn prepare_upload(
        &self,
        path: &str,
        visibility: Option<&str>,
    ) -> Result<PrepareUploadResult, AntdError> {
        let mut body = json!({ "path": path });
        if let Some(v) = visibility {
            body["visibility"] = json!(v);
        }
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/upload/prepare", Some(body))
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::parse_prepare_response(&j))
    }

    /// Convenience wrapper: prepares a *public* file upload for external
    /// signing.
    ///
    /// Equivalent to [`prepare_upload`](Self::prepare_upload) with
    /// `visibility=Some("public")` — the daemon bundles the DataMap chunk
    /// into the same payment batch so the external signer signs ONE EVM
    /// transaction covering chunks + DataMap. After `finalize_upload`, the
    /// result's [`FinalizeUploadResult::data_map_address`] is the shareable
    /// retrieval handle.
    ///
    /// Requires antd >= 0.6.1.
    pub async fn prepare_upload_public(
        &self,
        path: &str,
    ) -> Result<PrepareUploadResult, AntdError> {
        self.prepare_upload(path, Some("public")).await
    }

    /// Prepares a data upload for external signing.
    ///
    /// Takes raw bytes, base64-encodes them, and POSTs to `/v1/data/prepare`.
    /// Returns payment details that an external signer must process before
    /// calling [`finalize_upload`](Self::finalize_upload).
    ///
    /// When `visibility="public"`, the serialized DataMap is bundled
    /// into the same external-signer payment batch and published
    /// on-network on finalize.
    pub async fn prepare_data_upload(
        &self,
        data: &[u8],
        visibility: Option<&str>,
    ) -> Result<PrepareUploadResult, AntdError> {
        let mut body = json!({ "data": Self::b64_encode(data) });
        if let Some(v) = visibility {
            body["visibility"] = json!(v);
        }
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/data/prepare", Some(body))
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::parse_prepare_response(&j))
    }

    /// Parses a `/v1/upload/finalize` JSON response into a
    /// [`FinalizeUploadResult`].
    ///
    /// `data_map_address` is populated only when prepare was called with
    /// `visibility="public"` — the DataMap chunk was bundled into the same
    /// external-signer payment batch and stored on-network.
    fn parse_finalize_response(j: &Value) -> FinalizeUploadResult {
        FinalizeUploadResult {
            address: Self::str_field(j, "address"),
            chunks_stored: Self::i64_field(j, "chunks_stored"),
            data_map: Self::str_field(j, "data_map"),
            data_map_address: Self::str_field(j, "data_map_address"),
        }
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
        Ok(Self::parse_finalize_response(&j))
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
        Ok(Self::parse_finalize_response(&j))
    }

    /// Prepares a single chunk for external-signer publish via
    /// `POST /v1/chunks/prepare`.
    ///
    /// The daemon collects storage quotes from the close group, stashes the
    /// prepared state, and returns either:
    /// - [`PrepareChunkResult::already_stored`] `= true` with
    ///   [`PrepareChunkResult::address`] set, if the chunk is already
    ///   on-network. No payment or finalize call is needed.
    /// - `already_stored = false` with `upload_id` + `payments` +
    ///   `total_amount` populated, in which case the caller signs and
    ///   submits `payForQuotes()` externally, then calls
    ///   [`finalize_chunk_upload`](Self::finalize_chunk_upload) with the
    ///   resulting tx hashes.
    ///
    /// Unlike [`chunk_put`](Self::chunk_put), this method does NOT require
    /// the daemon to have a wallet — all funds flow through the external
    /// signer.
    ///
    /// Requires antd >= 0.7.0.
    pub async fn prepare_chunk_upload(&self, data: &[u8]) -> Result<PrepareChunkResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/chunks/prepare",
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
        Ok(PrepareChunkResult {
            address: Self::str_field(&j, "address"),
            already_stored: j
                .get("already_stored")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            upload_id: Self::str_field(&j, "upload_id"),
            payment_type: Self::str_field(&j, "payment_type"),
            payments,
            total_amount: Self::str_field(&j, "total_amount"),
            payment_vault_address: Self::str_field(&j, "payment_vault_address"),
            payment_token_address: Self::str_field(&j, "payment_token_address"),
            rpc_url: Self::str_field(&j, "rpc_url"),
        })
    }

    /// Submits a prepared chunk to the network after external payment via
    /// `POST /v1/chunks/finalize`.
    ///
    /// `tx_hashes` maps each non-zero `quote_hash` from
    /// [`prepare_chunk_upload`](Self::prepare_chunk_upload)'s payments to the
    /// corresponding `tx_hash` returned by `payForQuotes()`. Returns the
    /// hex-encoded network address of the stored chunk (matches
    /// [`PrepareChunkResult::address`]).
    ///
    /// Requires antd >= 0.7.0.
    pub async fn finalize_chunk_upload(
        &self,
        upload_id: &str,
        tx_hashes: &std::collections::HashMap<String, String>,
    ) -> Result<String, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/chunks/finalize",
                Some(json!({
                    "upload_id": upload_id,
                    "tx_hashes": tx_hashes,
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::str_field(&j, "address"))
    }
}
