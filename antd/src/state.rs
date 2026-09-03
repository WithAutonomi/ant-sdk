use std::collections::HashMap;
use std::sync::Arc;

use ant_core::data::{Client, MultiAddr, PreparedChunk, PreparedUpload};
use tokio::sync::Mutex;

/// A prepared upload with a creation timestamp for TTL-based cleanup.
pub struct TimestampedUpload {
    pub prepared: PreparedUpload,
    pub created_at: std::time::Instant,
}

/// A prepared single-chunk publish with a creation timestamp for TTL-based
/// cleanup. Mirrors [`TimestampedUpload`] but for the `/v1/chunks/prepare` flow.
pub struct TimestampedChunk {
    pub prepared: PreparedChunk,
    pub created_at: std::time::Instant,
}

/// Mirror of saorsa-core's `AUTO_REBOOTSTRAP_THRESHOLD`
/// (dht_network_manager.rs): the routing-table size below which the DHT
/// auto-re-bootstraps. v0.27.3 marked it `pub`, but its module is
/// `pub(crate)` and nothing re-exports it, so it remains unreachable for
/// consumers. Keep in sync until saorsa-core exports it at crate root.
pub const REBOOTSTRAP_THRESHOLD: usize = 3;

/// Live network-participation snapshot reported by /health (REST and gRPC).
pub struct NetworkHealth {
    pub write_ready: bool,
    pub connected_peers: u32,
    pub routing_table_size: u32,
    pub rebootstrap_threshold: u32,
    pub last_store_ok_secs_ago: Option<u64>,
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
    /// Pending prepared single-chunk publishes awaiting external payment
    /// (upload_id → state). Kept separate from [`Self::pending_uploads`]
    /// because the inner type differs and the two flows touch different
    /// ant-core surfaces.
    pub pending_chunks: Arc<Mutex<HashMap<String, TimestampedChunk>>>,
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
    /// Instant of the last store-type operation (data/file/chunk put,
    /// external-signer finalize) that completed successfully, or `None` until
    /// the first success in this process. Feeds /health `last_store_ok_secs_ago`.
    pub last_store_ok: Arc<std::sync::RwLock<Option<std::time::Instant>>>,
}

impl AppState {
    /// Record a successful store-type operation for /health reporting.
    pub fn mark_store_ok(&self) {
        if let Ok(mut guard) = self.last_store_ok.write() {
            *guard = Some(std::time::Instant::now());
        }
    }

    /// Compute the live network-participation snapshot for /health.
    ///
    /// Both node reads are in-memory, so this is cheap enough to run per
    /// request. `write_ready` is a best-effort floor keyed on
    /// `max(routing_table_size, connected_peers)`: in client mode the DHT
    /// routing table can sit below the re-bootstrap threshold while plenty of
    /// live connections exist and stores succeed (observed on a LAN devnet:
    /// rt=2, connected=10, paid upload fine), so the routing table alone
    /// would under-report. Neither signal guarantees a store will fully
    /// succeed (stores proceed with as little as one reachable node), but
    /// when both are below the threshold the node is known-degraded.
    pub async fn network_health(&self) -> NetworkHealth {
        let node = self.client.network().node();
        let connected_peers = node.peer_count().await;
        let routing_table_size = node.dht_manager().get_routing_table_size().await;
        let effective_peers = routing_table_size.max(connected_peers);
        let last_store_ok_secs_ago = self
            .last_store_ok
            .read()
            .ok()
            .and_then(|guard| *guard)
            .map(|at| at.elapsed().as_secs());
        NetworkHealth {
            write_ready: effective_peers >= REBOOTSTRAP_THRESHOLD,
            connected_peers: connected_peers.try_into().unwrap_or(u32::MAX),
            routing_table_size: routing_table_size.try_into().unwrap_or(u32::MAX),
            rebootstrap_threshold: REBOOTSTRAP_THRESHOLD as u32,
            last_store_ok_secs_ago,
        }
    }

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

    /// Remove pending single-chunk prepares older than the given duration.
    pub async fn cleanup_stale_chunks(&self, max_age: std::time::Duration) {
        let mut chunks = self.pending_chunks.lock().await;
        let before = chunks.len();
        chunks.retain(|_, v| v.created_at.elapsed() < max_age);
        let removed = before - chunks.len();
        if removed > 0 {
            tracing::info!(
                removed,
                remaining = chunks.len(),
                "cleaned up stale pending chunks"
            );
        }
    }
}
