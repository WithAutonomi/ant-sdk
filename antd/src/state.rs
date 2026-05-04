use std::collections::HashMap;
use std::sync::Arc;

use ant_core::data::{Client, MultiAddr, PreparedUpload};
use tokio::sync::Mutex;

/// A prepared upload with a creation timestamp for TTL-based cleanup.
pub struct TimestampedUpload {
    pub prepared: PreparedUpload,
    pub created_at: std::time::Instant,
}

/// Shared application state passed to all handlers.
#[derive(Clone)]
pub struct AppState {
    /// High-level Autonomi client (wraps P2P node, wallet, cache).
    pub client: Arc<Client>,
    /// Network mode label ("local", "default", etc.)
    pub network: String,
    /// Bootstrap peer addresses (retained for diagnostics/logging).
    #[allow(dead_code)]
    pub bootstrap_peers: Vec<MultiAddr>,
    /// Pending prepared uploads awaiting external payment (upload_id → state).
    pub pending_uploads: Arc<Mutex<HashMap<String, TimestampedUpload>>>,
    /// Process start time, for /health uptime reporting.
    pub started_at: std::time::Instant,
    /// antd crate version (env!("CARGO_PKG_VERSION") at build time).
    pub version: String,
    /// Short git SHA captured by build.rs, or "" if unknown.
    pub build_commit: String,
    /// EVM preset name ("arbitrum-one", "arbitrum-sepolia", "local", "custom").
    pub evm_preset: String,
    /// Payment token contract address, or "" if unconfigured.
    pub evm_token_addr: String,
    /// Payment vault contract address, or "" if unconfigured.
    pub evm_vault_addr: String,
}

impl AppState {
    /// Remove pending uploads older than the given duration.
    pub async fn cleanup_stale_uploads(&self, max_age: std::time::Duration) {
        let mut uploads = self.pending_uploads.lock().await;
        let before = uploads.len();
        uploads.retain(|_, v| v.created_at.elapsed() < max_age);
        let removed = before - uploads.len();
        if removed > 0 {
            tracing::info!(
                removed,
                remaining = uploads.len(),
                "cleaned up stale pending uploads"
            );
        }
    }
}
