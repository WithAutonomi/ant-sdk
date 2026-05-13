#![deny(unsafe_code)]

use std::sync::Arc;

use clap::Parser;
use tracing_subscriber::EnvFilter;

use ant_core::data::{
    Client, ClientConfig, CoreNodeConfig, EvmNetwork, MultiAddr, NodeMode, P2PNode, Wallet,
};

mod config;
mod error;
mod evm_defaults;
mod grpc;
mod peers;
mod port_file;
mod rest;
mod state;
mod types;

use config::Config;
use state::AppState;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Parse config first so we can use --log-level for the subscriber
    let config = Config::parse();

    // Use --log-level / ANTD_LOG_LEVEL with "info" default
    let log_level = &config.log_level;
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive(
            log_level.parse().unwrap_or_else(|e| {
                eprintln!("invalid log level '{log_level}': {e}, falling back to 'info'");
                "info".parse().expect("valid default log directive")
            }),
        ))
        .init();

    tracing::info!(log_level = %log_level, "logging initialized");

    // Resolve listen addresses (applying --rest-port / --grpc-port overrides)
    let rest_addr = config.resolved_rest_addr()?;
    let grpc_addr = config.resolved_grpc_addr()?;

    // Bind listeners early to capture actual ports (important for port 0)
    let rest_listener = tokio::net::TcpListener::bind(rest_addr)
        .await
        .map_err(|e| format!("failed to bind REST listener on {rest_addr}: {e}"))?;
    let grpc_listener = tokio::net::TcpListener::bind(grpc_addr)
        .await
        .map_err(|e| format!("failed to bind gRPC listener on {grpc_addr}: {e}"))?;

    let actual_rest_addr = rest_listener.local_addr()?;
    let actual_grpc_addr = grpc_listener.local_addr()?;

    // Log the REST and gRPC addresses at startup via tracing
    tracing::info!(rest = %actual_rest_addr, grpc = %actual_grpc_addr, "server addresses resolved");

    // Banner
    println!();
    println!("  antd — Autonomi REST + gRPC Gateway");
    println!("  ==================================");
    println!("  REST:      http://{}", actual_rest_addr);
    println!("  gRPC:      {}", actual_grpc_addr);
    println!("  Network:   {}", config.network);
    println!(
        "  CORS:      {}",
        if config.cors { "enabled" } else { "disabled" }
    );
    println!("  Log level: {}", log_level);
    println!();

    // Write port file for SDK discovery
    let port_file_path = port_file::write(actual_rest_addr.port(), actual_grpc_addr.port());
    match &port_file_path {
        Some(p) => tracing::info!(path = %p.display(), "port file written"),
        None => tracing::warn!("could not determine data directory — port file not written"),
    }

    // Parse bootstrap peers from --peers / ANTD_PEERS
    let mut bootstrap_peers: Vec<MultiAddr> = config
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

    // Fallback: try ant-client's shared bootstrap_peers.toml when no peers
    // were supplied and we're not on the local devnet.
    if bootstrap_peers.is_empty() && config.network != "local" {
        let (fallback_peers, fallback_path) = peers::load_from_ant_client_config();
        if !fallback_peers.is_empty() {
            tracing::info!(
                count = fallback_peers.len(),
                path = ?fallback_path.as_ref().map(|p| p.display().to_string()),
                "loaded bootstrap peers from ant-client bootstrap_peers.toml"
            );
            bootstrap_peers = fallback_peers;
        }
    }

    // Last-resort fallback: peers vendored into the binary at compile time.
    // Lets a fresh release binary reach mainnet without any prior ant-client
    // installer step. CLI/env/file all take precedence over this.
    if bootstrap_peers.is_empty() && config.network != "local" {
        let compiled_in = peers::compiled_in_default_peers();
        if !compiled_in.is_empty() {
            tracing::info!(
                count = compiled_in.len(),
                "loaded compiled-in default bootstrap peers (no CLI/env/file peers were supplied)"
            );
            bootstrap_peers = compiled_in;
        }
    }

    if bootstrap_peers.is_empty() {
        if config.network != "local" {
            tracing::warn!(
                "no bootstrap peers configured and network is not 'local' — \
                 the daemon may not be able to reach the network. \
                 Set ANTD_PEERS or --peers, or populate \
                 %APPDATA%/ant/bootstrap_peers.toml (Linux: ~/.config/ant/)"
            );
        } else {
            tracing::warn!("no bootstrap peers configured — set ANTD_PEERS or --peers");
        }
        if let Some(raw) = &config.peers {
            tracing::warn!(raw_peers = ?raw, "raw peer strings from config");
        }
    }

    // Init P2P node in client mode
    tracing::info!(network = %config.network, "connecting to Autonomi network...");

    let mut builder = CoreNodeConfig::builder().mode(NodeMode::Client).port(0); // OS assigns ephemeral port

    if config.network == "local" {
        builder = builder.local(true).allow_loopback(true).ipv6(false);
    }

    for peer in &bootstrap_peers {
        builder = builder.bootstrap_peer(peer.clone());
    }

    let node_config = builder
        .build()
        .map_err(|e| format!("failed to build node config: {e}"))?;

    let node = P2PNode::new(node_config)
        .await
        .map_err(|e| format!("failed to create P2P node: {e}"))?;

    node.start()
        .await
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

    // Build ant-core Client from the P2P node, applying any CLI overrides
    // to ClientConfig (timeouts and concurrency).
    let mut client_config = ClientConfig::default();
    if let Some(v) = config.quote_timeout_secs {
        client_config.quote_timeout_secs = v;
    }
    if let Some(v) = config.store_timeout_secs {
        client_config.store_timeout_secs = v;
    }
    if let Some(v) = config.quote_concurrency {
        client_config.quote_concurrency = v;
    }
    if let Some(v) = config.store_concurrency {
        client_config.store_concurrency = v;
    }
    tracing::info!(
        quote_timeout_secs = client_config.quote_timeout_secs,
        store_timeout_secs = client_config.store_timeout_secs,
        quote_concurrency = client_config.quote_concurrency,
        store_concurrency = client_config.store_concurrency,
        "client config resolved"
    );

    let node = Arc::new(node);
    let mut client = Client::from_node(node, client_config);

    // Resolve EVM configuration — network-aware defaults + env overrides.
    let evm_cfg = evm_defaults::resolve(&config.network);
    tracing::info!(
        preset = %evm_cfg.preset,
        rpc_url = %evm_cfg.rpc_url,
        token = %evm_cfg.token_addr,
        vault = %evm_cfg.vault_addr,
        "EVM config resolved"
    );

    // Capture preset + addresses for /health diagnostics before evm_cfg is
    // consumed by the wallet/network setup below.
    let evm_preset = evm_cfg.preset.clone();
    let evm_token_addr = evm_cfg.token_addr.clone();
    let evm_vault_addr = evm_cfg.vault_addr.clone();

    // For known mainnet/testnet presets use the typed EvmNetwork variants
    // (ArbitrumOne / ArbitrumSepoliaTest) — they encode the chain-id and
    // pricing constants that mainnet storers' median-quote payment verifier
    // expects. evmlib::Network::new_custom builds a Custom variant whose
    // payment encoding is rejected by mainnet storers with
    // "Median quote payment verification failed", silently spending the
    // user's ANT for no actual storage. Custom is reserved for `local`
    // devnet or when individual EVM_* env vars override the canonical
    // contract addresses.
    let custom_overrides = std::env::var("EVM_RPC_URL").is_ok()
        || std::env::var("EVM_PAYMENT_TOKEN_ADDRESS").is_ok()
        || std::env::var("EVM_PAYMENT_VAULT_ADDRESS").is_ok()
        || std::env::var("EVM_DATA_PAYMENTS_ADDRESS").is_ok();
    if evm_cfg.token_addr.is_empty() || evm_cfg.vault_addr.is_empty() {
        tracing::warn!(
            token_empty = evm_cfg.token_addr.is_empty(),
            vault_empty = evm_cfg.vault_addr.is_empty(),
            "EVM token or vault address is empty — write operations will fail. \
             Set EVM_NETWORK (arbitrum-one / arbitrum-sepolia) or the individual \
             EVM_PAYMENT_TOKEN_ADDRESS / EVM_PAYMENT_VAULT_ADDRESS env vars."
        );
    } else {
        let network = match (evm_cfg.preset.as_str(), custom_overrides) {
            ("arbitrum-one", false) => EvmNetwork::ArbitrumOne,
            ("arbitrum-sepolia" | "arbitrum-sepolia-test", false) => {
                EvmNetwork::ArbitrumSepoliaTest
            }
            _ => evmlib::Network::new_custom(
                &evm_cfg.rpc_url,
                &evm_cfg.token_addr,
                &evm_cfg.vault_addr,
            ),
        };

        if let Ok(wallet_key) = std::env::var("AUTONOMI_WALLET_KEY") {
            tracing::info!(rpc_url = %evm_cfg.rpc_url, "loading EVM wallet...");
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
            // External signer mode: no wallet key, but the EVM network is
            // still configured so prepare-upload/finalize-upload can work.
            client = client.with_evm_network(network);
            tracing::info!(rpc_url = %evm_cfg.rpc_url, "EVM network configured (external signer mode)");
        }
    }

    let state = Arc::new(AppState {
        client: Arc::new(client),
        network: config.network.clone(),
        bootstrap_peers,
        pending_uploads: Arc::new(tokio::sync::Mutex::new(std::collections::HashMap::new())),
        pending_chunks: Arc::new(tokio::sync::Mutex::new(std::collections::HashMap::new())),
        started_at: std::time::Instant::now(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        build_commit: env!("ANTD_BUILD_COMMIT").to_string(),
        evm_preset,
        evm_token_addr,
        evm_vault_addr,
    });

    // Spawn background task to clean up stale pending prepares (1-hour TTL)
    let cleanup_state = state.clone();
    tokio::spawn(async move {
        let ttl = std::time::Duration::from_secs(3600);
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(300)).await;
            cleanup_state.cleanup_stale_uploads(ttl).await;
            cleanup_state.cleanup_stale_chunks(ttl).await;
        }
    });

    // Build REST router
    let app = rest::router(state.clone(), config.cors, actual_rest_addr.port());

    // Run both servers concurrently via tokio::select!.
    // If either server returns (with success or error), initiate shutdown.
    let shutdown = shutdown_signal();
    tokio::pin!(shutdown);

    let shutdown_state = state.clone();
    let server_result: Result<(), String> = tokio::select! {
        result = grpc::serve(grpc_listener, state.clone()) => {
            match result {
                Ok(()) => {
                    tracing::info!("gRPC server exited normally");
                    Ok(())
                }
                Err(e) => {
                    tracing::error!(error = %e, "gRPC server failed — initiating shutdown");
                    Err(format!("gRPC server error: {e}"))
                }
            }
        }
        result = async {
            tracing::info!("REST server listening on {actual_rest_addr}");
            axum::serve(rest_listener, app)
                .with_graceful_shutdown(async {
                    // Wait for the outer shutdown signal; when select! picks
                    // another branch first this future is dropped, which is fine.
                    std::future::pending::<()>().await
                })
                .await
        } => {
            match result {
                Ok(()) => {
                    tracing::info!("REST server exited normally");
                    Ok(())
                }
                Err(e) => {
                    tracing::error!(error = %e, "REST server failed — initiating shutdown");
                    Err(format!("REST server error: {e}"))
                }
            }
        }
        _ = &mut shutdown => {
            tracing::info!("shutdown signal received — starting graceful shutdown");

            // Log pending upload count on shutdown
            let pending_count = shutdown_state.pending_uploads.lock().await.len();
            if pending_count > 0 {
                tracing::warn!(count = pending_count, "abandoning pending uploads");
            }

            // Give servers a grace period to finish in-flight requests.
            // The REST server's graceful shutdown is triggered by dropping,
            // and gRPC server will be cancelled by select! dropping.
            tracing::info!("allowing 5s grace period for in-flight requests");
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;

            Ok(())
        }
    };

    // Cleanup port file on both normal and error shutdown paths
    port_file::remove();
    tracing::info!("port file removed");

    // Log final status
    match &server_result {
        Ok(()) => tracing::info!("daemon stopped"),
        Err(e) => tracing::error!(error = %e, "daemon stopped due to error"),
    }

    server_result.map_err(|e| e.into())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("failed to install Ctrl+C handler");
}
