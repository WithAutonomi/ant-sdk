use std::sync::Arc;

use clap::Parser;
use tracing_subscriber::EnvFilter;

use autonomi::Client;
use ant_evm::EvmWallet;

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
    println!("  antd — Autonomi REST + gRPC Gateway");
    println!("  ====================================");
    println!("  REST:    http://{}", config.rest_addr);
    println!("  gRPC:    {}", config.grpc_addr);
    println!("  Network: {}", config.network);
    println!("  CORS:    {}", if config.cors { "enabled" } else { "disabled" });
    println!();

    // Init client
    tracing::info!(network = %config.network, "connecting to Autonomi network...");
    let client = match config.network.as_str() {
        "local" => Client::init_local().await?,
        "alpha" => Client::init_alpha().await?,
        _ => {
            if let Some(ref peers) = config.peers {
                let multiaddrs: Vec<_> = peers
                    .iter()
                    .map(|p| p.parse::<autonomi::Multiaddr>())
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|e| format!("invalid peer multiaddr: {e}"))?;
                Client::init_with_peers(multiaddrs).await?
            } else {
                Client::init().await?
            }
        }
    };
    tracing::info!("connected to Autonomi network");

    // Load wallet
    let wallet_key = std::env::var("AUTONOMI_WALLET_KEY")
        .map_err(|_| "AUTONOMI_WALLET_KEY env var is required")?;
    let wallet = EvmWallet::new_from_private_key(client.evm_network().clone(), &wallet_key)
        .map_err(|e| format!("failed to create wallet: {e}"))?;
    tracing::info!("wallet loaded");

    let state = Arc::new(AppState { client, wallet, network: config.network.clone() });

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
