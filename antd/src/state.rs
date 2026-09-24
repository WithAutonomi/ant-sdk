use std::collections::HashMap;
use std::sync::Arc;

use ant_core::data::{Client, FinalizeResume, MultiAddr, PreparedChunk, PreparedUpload};
use tokio::sync::Mutex;

/// Which external-signer payment shape a pending upload carries. Drives the
/// finalize routing (`tx_hashes` for wave-batch, winner pool hashes for
/// merkle) and the wrong-shape request checks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PaymentKind {
    WaveBatch,
    Merkle,
}

/// The state an external-signer upload is in while it sits in
/// [`AppState::pending_uploads`] under its `upload_id`.
///
/// - **Prepared** — quotes collected, chunks (or their on-disk spill) held,
///   nothing paid yet. Created by the prepare handlers.
/// - **Resume** — the signer paid and a finalize stored *some* chunks but not
///   all after retries. The entry now owns the resume handle ant-core handed
///   back: the paid proofs plus the still-unstored chunks. A repeat finalize
///   with the same `upload_id` drives that handle against the **same**
///   on-chain payment — no re-prepare, no second signature, no double payment.
///
/// Before the resumable finalize (ant-core `FinalizeOutcome`), a post-payment
/// storage shortfall consumed the session and left the caller with a paid
/// but unfinishable upload; re-preparing produced fresh quote hashes that the
/// already-paid transaction could not satisfy.
// `PreparedUpload` is boxed so the enum stays small (the resume handle is
// already boxed inside ant-core) — the map holds one entry per pending
// upload, and the hot path moves entries in and out under the lock.
#[derive(Debug)]
pub enum UploadSession {
    Prepared(Box<PreparedUpload>),
    Resume(FinalizeResume),
}

impl UploadSession {
    /// The payment shape this session belongs to, or `None` for a shape this
    /// daemon has no finalize route for (ant-core's enums are
    /// `#[non_exhaustive]`, so a future variant must not be silently
    /// mis-routed).
    pub fn payment_kind(&self) -> Option<PaymentKind> {
        match self {
            UploadSession::Prepared(prepared) => match &prepared.payment_info {
                ant_core::data::ExternalPaymentInfo::WaveBatch { .. } => {
                    Some(PaymentKind::WaveBatch)
                }
                ant_core::data::ExternalPaymentInfo::Merkle { .. } => Some(PaymentKind::Merkle),
                #[allow(unreachable_patterns)]
                _ => None,
            },
            UploadSession::Resume(resume) => match resume {
                FinalizeResume::Wave(_) => Some(PaymentKind::WaveBatch),
                FinalizeResume::Merkle(_) => Some(PaymentKind::Merkle),
                #[allow(unreachable_patterns)]
                _ => None,
            },
        }
    }
}

/// A pending upload session with a creation timestamp for TTL-based cleanup.
pub struct TimestampedUpload {
    pub session: UploadSession,
    pub created_at: std::time::Instant,
}

impl TimestampedUpload {
    /// A freshly prepared, not-yet-paid upload.
    pub fn prepared(prepared: PreparedUpload) -> Self {
        Self {
            session: UploadSession::Prepared(Box::new(prepared)),
            created_at: std::time::Instant::now(),
        }
    }

    /// A paid, partly-stored upload retained for a repeat finalize. The
    /// timestamp restarts so the caller gets a full TTL window to retry
    /// from the moment the shortfall was reported, not from the original
    /// prepare.
    pub fn resume(resume: FinalizeResume) -> Self {
        Self {
            session: UploadSession::Resume(resume),
            created_at: std::time::Instant::now(),
        }
    }
}

/// A prepared single-chunk publish with a creation timestamp for TTL-based
/// cleanup. Mirrors [`TimestampedUpload`] but for the `/v1/chunks/prepare` flow.
pub struct TimestampedChunk {
    pub prepared: PreparedChunk,
    pub created_at: std::time::Instant,
}

/// Daemon-local record of the last successful store-type operation
/// (data/file/chunk put, external-signer finalize). `None` until the first
/// success in this process. Feeds /health `last_store_ok_secs_ago`.
#[derive(Clone, Default)]
pub struct StoreMarker(Arc<std::sync::RwLock<Option<std::time::Instant>>>);

impl StoreMarker {
    /// Record a successful store-type operation.
    pub fn mark(&self) {
        if let Ok(mut guard) = self.0.write() {
            *guard = Some(std::time::Instant::now());
        }
    }

    /// Seconds since the last recorded success, or `None` if none yet.
    pub fn secs_ago(&self) -> Option<u64> {
        self.0
            .read()
            .ok()
            .and_then(|guard| *guard)
            .map(|at| at.elapsed().as_secs())
    }
}

/// Live snapshot reported by /health (REST and gRPC): ant-core's
/// [`ant_core::data::NetworkHealth`] — the one write-readiness formula shared
/// by every embedded client — plus the daemon-local `last_store_ok_secs_ago`.
pub struct NetworkHealth {
    pub write_ready: bool,
    pub connected_peers: u32,
    pub routing_table_size: u32,
    pub rebootstrap_threshold: u32,
    pub last_store_ok_secs_ago: Option<u64>,
}

impl NetworkHealth {
    /// Layer the daemon-local store marker onto ant-core's network snapshot.
    fn compose(net: ant_core::data::NetworkHealth, last_store_ok_secs_ago: Option<u64>) -> Self {
        Self {
            write_ready: net.write_ready,
            connected_peers: net.connected_peers,
            routing_table_size: net.routing_table_size,
            rebootstrap_threshold: net.rebootstrap_threshold,
            last_store_ok_secs_ago,
        }
    }
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
    /// Pending external-signer uploads (upload_id → state): prepared uploads
    /// awaiting payment, plus paid-but-partly-stored uploads retained for a
    /// repeat finalize (see [`UploadSession`]).
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
    /// Marker for the last successful store-type operation.
    pub last_store_ok: StoreMarker,
}

impl AppState {
    /// Record a successful store-type operation for /health reporting.
    pub fn mark_store_ok(&self) {
        self.last_store_ok.mark();
    }

    /// Compute the live network-participation snapshot for /health.
    ///
    /// The peer/routing snapshot and `write_ready` formula come from
    /// [`ant_core::data::Network::health`] (cheap in-memory reads, fine per
    /// request); only `last_store_ok_secs_ago` is daemon state.
    pub async fn network_health(&self) -> NetworkHealth {
        let net = self.client.network().health().await;
        NetworkHealth::compose(net, self.last_store_ok.secs_ago())
    }

    /// Remove pending uploads older than the given duration. Applies to both
    /// unpaid prepared uploads and retained resume handles; dropping a resume
    /// handle abandons the paid attempt (its on-chain payment cannot be
    /// recovered), so the TTL bounds how long a signer has to retry.
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

#[cfg(test)]
mod tests {
    use super::*;
    use ant_core::data::NetworkHealth as CoreHealth;

    #[test]
    fn store_marker_transitions_from_none_to_fresh() {
        let marker = StoreMarker::default();
        assert_eq!(marker.secs_ago(), None);
        marker.mark();
        assert!(marker.secs_ago().unwrap() <= 1);
    }

    #[test]
    fn compose_layers_store_marker_without_touching_readiness() {
        let degraded = NetworkHealth::compose(CoreHealth::from_counts(0, 0), None);
        assert!(!degraded.write_ready);
        assert_eq!(degraded.last_store_ok_secs_ago, None);

        // Client-mode shape: live connections carry readiness while the
        // routing table lags below the threshold.
        let ready = NetworkHealth::compose(CoreHealth::from_counts(10, 2), Some(5));
        assert!(ready.write_ready);
        assert_eq!(ready.connected_peers, 10);
        assert_eq!(ready.routing_table_size, 2);
        assert_eq!(
            ready.rebootstrap_threshold,
            CoreHealth::from_counts(0, 0).rebootstrap_threshold
        );
        assert_eq!(ready.last_store_ok_secs_ago, Some(5));
    }

    #[test]
    fn readiness_recovers_when_counts_recover() {
        // The degraded -> recovered transition the /health fields exist to
        // expose (write_ready must not stick false once peers return).
        let threshold = CoreHealth::from_counts(0, 0).rebootstrap_threshold as usize;
        let before = NetworkHealth::compose(CoreHealth::from_counts(1, 1), None);
        assert!(!before.write_ready);
        let after = NetworkHealth::compose(CoreHealth::from_counts(1, threshold), None);
        assert!(after.write_ready);
    }
}
