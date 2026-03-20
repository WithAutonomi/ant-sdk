use std::sync::Arc;

use clap::Parser;
use tracing_subscriber::EnvFilter;

use saorsa_node::core::{CoreNodeConfig, MultiAddr, NodeMode, P2PNode};

mod config;
mod error;
mod grpc;
mod rest;
mod state;
mod types;

use config::Config;
use state::AppState;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse().unwrap()))
        .init();

    let config = Config::parse();

    // Banner
    println!();
    println!("  antd — Saorsa REST + gRPC Gateway");
    println!("  ==================================");
    println!("  REST:    http://{}", config.rest_addr);
    println!("  gRPC:    {}", config.grpc_addr);
    println!("  Network: {}", config.network);
    println!("  CORS:    {}", if config.cors { "enabled" } else { "disabled" });
    println!();

    // Parse bootstrap peers
    let bootstrap_peers: Vec<MultiAddr> = config
        .peers
        .as_ref()
        .map(|peers| {
            peers
                .iter()
                .filter_map(|p| {
                    match p.parse::<MultiAddr>() {
                        Ok(addr) => {
                            tracing::info!(raw = %p, "parsed bootstrap peer");
                            Some(addr)
                        }
                        Err(e) => {
                            tracing::warn!(raw = %p, error = %e, "failed to parse bootstrap peer multiaddr");
                            None
                        }
                    }
                })
                .collect()
        })
        .unwrap_or_default();

    if bootstrap_peers.is_empty() {
        tracing::warn!("no bootstrap peers configured — set ANTD_PEERS or --peers");
        if let Some(raw) = &config.peers {
            tracing::warn!(raw_peers = ?raw, "raw peer strings from config");
        }
    }

    // Init saorsa P2P node in client mode
    tracing::info!(network = %config.network, "connecting to Saorsa network...");

    let mut builder = CoreNodeConfig::builder()
        .mode(NodeMode::Client)
        .port(0); // OS assigns ephemeral port

    if config.network == "local" {
        builder = builder.local(true).allow_loopback(true).ipv6(false);
    }

    for peer in &bootstrap_peers {
        builder = builder.bootstrap_peer(peer.clone());
    }

    let node_config = builder.build()
        .map_err(|e| format!("failed to build node config: {e}"))?;

    let node = P2PNode::new(node_config).await
        .map_err(|e| format!("failed to create P2P node: {e}"))?;

    node.start().await
        .map_err(|e| format!("failed to start P2P node: {e}"))?;

    tracing::info!("P2P node started in client mode");

    // Wait for bootstrap connections to establish
    for i in 0..30 {
        let peer_count = node.connected_peers().await.len();
        if peer_count > 0 {
            tracing::info!(peer_count, "connected to Saorsa network");
            break;
        }
        if i == 29 {
            tracing::warn!("no peers connected after 15s — chunk operations will fail");
        }
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    let peers = node.connected_peers().await;
    tracing::info!(count = peers.len(), peers = ?peers, "peer status at startup");

    // Load EVM wallet if configured
    let wallet = match std::env::var("AUTONOMI_WALLET_KEY") {
        Ok(wallet_key) => {
            let rpc_url = std::env::var("EVM_RPC_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:8545".to_string());
            let token_addr = std::env::var("EVM_PAYMENT_TOKEN_ADDRESS")
                .unwrap_or_default();
            let payments_addr = std::env::var("EVM_DATA_PAYMENTS_ADDRESS")
                .unwrap_or_default();
            tracing::info!(%rpc_url, "loading EVM wallet...");
            let network = evmlib::Network::new_custom(
                &rpc_url,
                &token_addr,
                &payments_addr,
                None,
            );
            match evmlib::wallet::Wallet::new_from_private_key(network, &wallet_key) {
                Ok(w) => {
                    tracing::info!(address = %w.address(), "EVM wallet loaded");
                    Some(w)
                }
                Err(e) => {
                    tracing::warn!("failed to load EVM wallet: {e}");
                    None
                }
            }
        }
        Err(_) => {
            tracing::info!("no AUTONOMI_WALLET_KEY set — write operations will fail");
            None
        }
    };

    let state = Arc::new(AppState {
        node: Arc::new(node),
        network: config.network.clone(),
        bootstrap_peers,
        wallet,
    });

    // Parse addresses
    let rest_addr: std::net::SocketAddr = config
        .rest_addr
        .parse()
        .map_err(|e| format!("invalid REST address: {e}"))?;
    let grpc_addr: std::net::SocketAddr = config
        .grpc_addr
        .parse()
        .map_err(|e| format!("invalid gRPC address: {e}"))?;

    // Build REST router
    let app = rest::router(state.clone(), config.cors);

    // Spawn both servers
    let grpc_state = state.clone();
    let grpc_handle = tokio::spawn(async move {
        if let Err(e) = grpc::serve(grpc_addr, grpc_state).await {
            tracing::error!("gRPC server error: {e}");
        }
    });

    let rest_handle = tokio::spawn(async move {
        tracing::info!("REST server listening on {rest_addr}");
        let listener = tokio::net::TcpListener::bind(rest_addr).await.unwrap();
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
            .unwrap();
    });

    tokio::select! {
        _ = rest_handle => tracing::info!("REST server shut down"),
        _ = grpc_handle => tracing::info!("gRPC server shut down"),
    }

    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("failed to install Ctrl+C handler");
    tracing::info!("shutdown signal received");
}
