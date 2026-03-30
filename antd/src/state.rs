use std::collections::HashMap;
use std::sync::Arc;

use ant_core::data::{Client, MultiAddr, PreparedUpload};
use tokio::sync::Mutex;

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
    pub pending_uploads: Arc<Mutex<HashMap<String, PreparedUpload>>>,
}
