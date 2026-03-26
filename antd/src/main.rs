use std::sync::Arc;

use clap::Parser;
use tracing_subscriber::EnvFilter;

use ant_core::data::{
    Client, ClientConfig, CoreNodeConfig, MultiAddr, NodeMode, P2PNode, Wallet,
};

mod config;
mod error;
mod grpc;
mod port_file;
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

    // Resolve listen addresses (applying --rest-port / --grpc-port overrides)
    let rest_addr = config.resolved_rest_addr()?;
    let grpc_addr = config.resolved_grpc_addr()?;

    // Bind listeners early to capture actual ports (important for port 0)
    let rest_listener = tokio::net::TcpListener::bind(rest_addr).await
        .map_err(|e| format!("failed to bind REST listener on {rest_addr}: {e}"))?;
    let grpc_listener = tokio::net::TcpListener::bind(grpc_addr).await
        .map_err(|e| format!("failed to bind gRPC listener on {grpc_addr}: {e}"))?;

    let actual_rest_addr = rest_listener.local_addr()?;
    let actual_grpc_addr = grpc_listener.local_addr()?;

    // Banner
    println!();
    println!("  antd — Autonomi REST + gRPC Gateway");
    println!("  ==================================");
    println!("  REST:    http://{}", actual_rest_addr);
    println!("  gRPC:    {}", actual_grpc_addr);
    println!("  Network: {}", config.network);
    println!("  CORS:    {}", if config.cors { "enabled" } else { "disabled" });
    println!();

    // Write port file for SDK discovery
    let port_file_path = port_file::write(actual_rest_addr.port(), actual_grpc_addr.port());
    match &port_file_path {
        Some(p) => tracing::info!(path = %p.display(), "port file written"),
        None => tracing::warn!("could not determine data directory — port file not written"),
    }

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

    // Init P2P node in client mode
    tracing::info!(network = %config.network, "connecting to Autonomi network...");

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
            tracing::info!(peer_count, "connected to Autonomi network");
            break;
        }
        if i == 29 {
            tracing::warn!("no peers connected after 15s — chunk operations will fail");
        }
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    let peers = node.connected_peers().await;
    tracing::info!(count = peers.len(), peers = ?peers, "peer status at startup");

    // Build ant-core Client from the P2P node
    let node = Arc::new(node);
    let mut client = Client::from_node(node, ClientConfig::default());

    // Load EVM wallet if configured
    if let Ok(wallet_key) = std::env::var("AUTONOMI_WALLET_KEY") {
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
        match Wallet::new_from_private_key(network, &wallet_key) {
            Ok(w) => {
                tracing::info!(address = %w.address(), "EVM wallet loaded");
                client = client.with_wallet(w);
            }
            Err(e) => {
                tracing::warn!("failed to load EVM wallet: {e}");
            }
        }
    } else {
        tracing::info!("no AUTONOMI_WALLET_KEY set — write operations will fail");
    }

    let state = Arc::new(AppState {
        client,
        network: config.network.clone(),
        bootstrap_peers,
    });

    // Build REST router
    let app = rest::router(state.clone(), config.cors, actual_rest_addr.port());

    // Spawn both servers
    let grpc_state = state.clone();
    let grpc_handle = tokio::spawn(async move {
        if let Err(e) = grpc::serve(grpc_listener, grpc_state).await {
            tracing::error!("gRPC server error: {e}");
        }
    });

    let rest_handle = tokio::spawn(async move {
        tracing::info!("REST server listening on {actual_rest_addr}");
        axum::serve(rest_listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
            .unwrap();
    });

    tokio::select! {
        _ = rest_handle => tracing::info!("REST server shut down"),
        _ = grpc_handle => tracing::info!("gRPC server shut down"),
    }

    // Cleanup port file on shutdown
    port_file::remove();
    tracing::info!("port file removed");

    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("failed to install Ctrl+C handler");
    tracing::info!("shutdown signal received");
}
