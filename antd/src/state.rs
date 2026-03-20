use std::sync::Arc;

use saorsa_node::core::P2PNode;

/// Shared application state passed to all handlers.
#[derive(Clone)]
pub struct AppState {
    /// The saorsa P2P node in client mode.
    pub node: Arc<P2PNode>,
    /// Network mode label ("local", "default", etc.)
    pub network: String,
    /// Bootstrap peer addresses for chunk routing.
    pub bootstrap_peers: Vec<saorsa_node::core::MultiAddr>,
    /// EVM wallet for paying storage quotes (optional — not needed for reads).
    pub wallet: Option<evmlib::wallet::Wallet>,
}
