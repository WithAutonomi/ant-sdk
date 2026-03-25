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
    pub async fn data_put_public(&self, data: &[u8]) -> Result<PutResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/public",
                Some(json!({ "data": Self::b64_encode(data) })),
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
    pub async fn data_put_private(&self, data: &[u8]) -> Result<PutResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/data/private",
                Some(json!({ "data": Self::b64_encode(data) })),
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

    // --- Graph ---

    /// Creates a new graph entry (DAG node).
    pub async fn graph_entry_put(
        &self,
        owner_secret_key: &str,
        parents: &[String],
        content: &str,
        descendants: &[GraphDescendant],
    ) -> Result<PutResult, AntdError> {
        let descs: Vec<Value> = descendants
            .iter()
            .map(|d| json!({ "public_key": d.public_key, "content": d.content }))
            .collect();
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/graph",
                Some(json!({
                    "owner_secret_key": owner_secret_key,
                    "parents": parents,
                    "content": content,
                    "descendants": descs,
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "address"),
        })
    }

    /// Retrieves a graph entry by address.
    pub async fn graph_entry_get(&self, address: &str) -> Result<GraphEntry, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::GET,
                &format!("/v1/graph/{address}"),
                None,
            )
            .await?;
        let j = j.unwrap_or_default();
        let descendants = j
            .get("descendants")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|d| GraphDescendant {
                        public_key: Self::str_field(d, "public_key"),
                        content: Self::str_field(d, "content"),
                    })
                    .collect()
            })
            .unwrap_or_default();
        let parents = j
            .get("parents")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        Ok(GraphEntry {
            owner: Self::str_field(&j, "owner"),
            parents,
            content: Self::str_field(&j, "content"),
            descendants,
        })
    }

    /// Checks if a graph entry exists at the given address.
    pub async fn graph_entry_exists(&self, address: &str) -> Result<bool, AntdError> {
        let code = self.do_head(&format!("/v1/graph/{address}")).await?;
        if code == 404 {
            return Ok(false);
        }
        if code >= 300 {
            return Err(error_for_status(
                code,
                "graph entry exists check failed".to_string(),
            ));
        }
        Ok(true)
    }

    /// Estimates the cost of creating a graph entry.
    pub async fn graph_entry_cost(&self, public_key: &str) -> Result<String, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/graph/cost",
                Some(json!({ "public_key": public_key })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::str_field(&j, "cost"))
    }

    // --- Files ---

    /// Uploads a local file to the network.
    pub async fn file_upload_public(&self, path: &str) -> Result<PutResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/files/upload/public",
                Some(json!({ "path": path })),
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
    pub async fn dir_upload_public(&self, path: &str) -> Result<PutResult, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/dirs/upload/public",
                Some(json!({ "path": path })),
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

    /// Retrieves an archive manifest by address.
    pub async fn archive_get_public(&self, address: &str) -> Result<Archive, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::GET,
                &format!("/v1/archives/public/{address}"),
                None,
            )
            .await?;
        let j = j.unwrap_or_default();
        let entries = j
            .get("entries")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|e| ArchiveEntry {
                        path: Self::str_field(e, "path"),
                        address: Self::str_field(e, "address"),
                        created: Self::i64_field(e, "created"),
                        modified: Self::i64_field(e, "modified"),
                        size: Self::i64_field(e, "size"),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(Archive { entries })
    }

    /// Creates an archive manifest on the network.
    pub async fn archive_put_public(&self, archive: &Archive) -> Result<PutResult, AntdError> {
        let entries: Vec<Value> = archive
            .entries
            .iter()
            .map(|e| {
                json!({
                    "path": e.path,
                    "address": e.address,
                    "created": e.created,
                    "modified": e.modified,
                    "size": e.size,
                })
            })
            .collect();
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/archives/public",
                Some(json!({ "entries": entries })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(PutResult {
            cost: Self::str_field(&j, "cost"),
            address: Self::str_field(&j, "address"),
        })
    }

    /// Estimates the cost of uploading a file.
    pub async fn file_cost(
        &self,
        path: &str,
        is_public: bool,
        include_archive: bool,
    ) -> Result<String, AntdError> {
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/cost/file",
                Some(json!({
                    "path": path,
                    "is_public": is_public,
                    "include_archive": include_archive,
                })),
            )
            .await?;
        let j = j.unwrap_or_default();
        Ok(Self::str_field(&j, "cost"))
    }
}
