use std::sync::Arc;

use ant_core::data::{Client, MultiAddr};

/// Shared application state passed to all handlers.
#[derive(Clone)]
pub struct AppState {
    /// High-level Autonomi client (wraps P2P node, wallet, cache).
    pub client: Arc<Client>,
    /// Network mode label ("local", "default", etc.)
    pub network: String,
    /// Bootstrap peer addresses.
    pub bootstrap_peers: Vec<MultiAddr>,
}
