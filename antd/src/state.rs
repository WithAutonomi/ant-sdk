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
    /// Bootstrap peer addresses.
    pub bootstrap_peers: Vec<MultiAddr>,
    /// Pending prepared uploads awaiting external payment (upload_id → state).
    pub pending_uploads: Arc<Mutex<HashMap<String, TimestampedUpload>>>,
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
