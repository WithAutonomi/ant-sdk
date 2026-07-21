use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use bytes::Bytes;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use zeroize::Zeroize;

use ant_core::data::{
    Client as CoreClient, ClientConfig, CoreNodeConfig, DevnetManifest, DownloadEvent, EvmNetwork,
    ExternalPaymentInfo, FileUploadResult, MultiAddr, NodeMode, P2PNode, PreparedUpload,
    UploadEvent, Wallet as CoreWallet, MAX_WIRE_MESSAGE_SIZE,
};
use ant_protocol::evm::{QuoteHash, TxHash};

use crate::data::{
    from_core_confidence, from_core_payment_mode, to_core_payment_mode, to_core_visibility,
};
use crate::wallet::build_custom_network;
use crate::{
    CandidateNodeEntry, ChunkPutResult, ClientError, CostEstimate, DataPutPrivateResult,
    DataPutPublicResult, ExternalUploadResult, FilePutPrivateResult, FilePutPublicResult,
    PaymentEntry, PaymentMode, PaymentType, PoolCommitmentEntry, PreparedUploadInfo,
    ProgressListener, ProgressPhase, ProgressUpdate, TxRequest, Visibility,
};

/// Mainnet bootstrap peers vendored from ant-client's
/// `resources/bootstrap_peers.toml` at the pinned ant-core tag, so the
/// `connect_default*` constructors can reach the production network with zero
/// configuration — the same last-resort pattern as antd's compiled-in copy.
/// Re-copy from the pinned checkout whenever the ant-core pin is bumped.
const COMPILED_IN_BOOTSTRAP_PEERS_TOML: &str = include_str!("../resources/bootstrap_peers.toml");

#[derive(serde::Deserialize)]
struct BootstrapConfig {
    peers: Vec<String>,
}

/// Parse the vendored peer list ("ip:port" socket addresses) into the
/// `/ip4/<ip>/udp/<port>/quic` multiaddr strings [`Client::connect`] expects.
/// Errors instead of silently returning an empty list — a malformed vendored
/// file is a build-time regression, not a runtime condition.
fn default_bootstrap_peer_strings() -> Result<Vec<String>, ClientError> {
    let cfg: BootstrapConfig = toml::from_str(COMPILED_IN_BOOTSTRAP_PEERS_TOML).map_err(|e| {
        ClientError::InternalError {
            reason: format!("vendored bootstrap_peers.toml is malformed: {e}"),
        }
    })?;
    let peers: Vec<String> = cfg
        .peers
        .iter()
        .filter_map(|s| s.parse::<std::net::SocketAddr>().ok())
        .map(|sa| {
            let ip_tag = if sa.is_ipv4() { "ip4" } else { "ip6" };
            format!("/{}/{}/udp/{}/quic", ip_tag, sa.ip(), sa.port())
        })
        .collect();
    if peers.is_empty() {
        return Err(ClientError::InternalError {
            reason: "vendored bootstrap_peers.toml contains no usable peers".into(),
        });
    }
    Ok(peers)
}

/// Plant the directory Autonomi derives its local state paths from (bootstrap
/// cache, config). At the pinned ant-core those paths come from the `HOME`
/// env var; Android app processes have no `HOME`, so `connect*` fails with
/// `HomeDirNotFound` unless one is planted — previously done app-side via a
/// libc `setenv` shim (the demos' `AntFfiBootstrap.kt`). Passing `data_dir`
/// does the planting SDK-side. No-op when `None`.
fn apply_data_dir(data_dir: Option<&str>) {
    if let Some(dir) = data_dir {
        // Must run before any core call that reads HOME (`P2PNode::new` reads
        // the saorsa bootstrap cache under it).
        std::env::set_var("HOME", dir);
    }
}

/// Map an ant-core [`UploadEvent`] to the FFI [`ProgressUpdate`] shape.
fn map_upload_event(ev: UploadEvent) -> ProgressUpdate {
    match ev {
        UploadEvent::Encrypting { chunks_done } => ProgressUpdate {
            phase: ProgressPhase::Encrypting,
            done: chunks_done as u64,
            total: 0,
        },
        UploadEvent::Encrypted { total_chunks } => ProgressUpdate {
            phase: ProgressPhase::Encrypting,
            done: total_chunks as u64,
            total: total_chunks as u64,
        },
        UploadEvent::QuotingChunks { .. } => ProgressUpdate {
            phase: ProgressPhase::Quoting,
            done: 0,
            total: 0,
        },
        UploadEvent::ChunkQuoted { quoted, total } => ProgressUpdate {
            phase: ProgressPhase::Quoting,
            done: quoted as u64,
            total: total as u64,
        },
        UploadEvent::ChunkStored { stored, total } => ProgressUpdate {
            phase: ProgressPhase::Storing,
            done: stored as u64,
            total: total as u64,
        },
        // ant-core 0.3.0 removed `UploadEvent::WaveComplete`; per-chunk
        // `ChunkStored` already carries the running total.
    }
}

/// Map an ant-core [`DownloadEvent`] to the FFI [`ProgressUpdate`] shape.
fn map_download_event(ev: DownloadEvent) -> ProgressUpdate {
    match ev {
        DownloadEvent::ResolvingDataMap { total_map_chunks } => ProgressUpdate {
            phase: ProgressPhase::Resolving,
            done: 0,
            total: total_map_chunks as u64,
        },
        DownloadEvent::MapChunkFetched { fetched } => ProgressUpdate {
            phase: ProgressPhase::Resolving,
            done: fetched as u64,
            total: 0,
        },
        DownloadEvent::DataMapResolved { total_chunks } => ProgressUpdate {
            phase: ProgressPhase::Downloading,
            done: 0,
            total: total_chunks as u64,
        },
        DownloadEvent::ChunksFetched { fetched, total } => ProgressUpdate {
            phase: ProgressPhase::Downloading,
            done: fetched as u64,
            total: total as u64,
        },
    }
}

/// Spin up a channel + reader task that forwards ant-core upload events to a
/// foreign [`ProgressListener`]. The returned sender is handed to ant-core;
/// when it drops (the operation finishes) the task ends. Await the handle after
/// the operation to flush the last events.
fn upload_progress_bridge(
    listener: Box<dyn ProgressListener>,
) -> (mpsc::Sender<UploadEvent>, JoinHandle<()>) {
    let (tx, mut rx) = mpsc::channel::<UploadEvent>(64);
    let handle = tokio::spawn(async move {
        while let Some(ev) = rx.recv().await {
            listener.on_progress(map_upload_event(ev));
        }
    });
    (tx, handle)
}

/// Download counterpart of [`upload_progress_bridge`].
fn download_progress_bridge(
    listener: Box<dyn ProgressListener>,
) -> (mpsc::Sender<DownloadEvent>, JoinHandle<()>) {
    let (tx, mut rx) = mpsc::channel::<DownloadEvent>(64);
    let handle = tokio::spawn(async move {
        while let Some(ev) = rx.recv().await {
            listener.on_progress(map_download_event(ev));
        }
    });
    (tx, handle)
}

/// Autonomi network client (wraps ant-core Client).
///
/// Provides direct access to the Autonomi network without needing
/// an antd daemon. Suitable for mobile apps (Android/iOS).
#[derive(uniffi::Object)]
pub struct Client {
    inner: CoreClient,
    /// External-signer prepared uploads awaiting finalize, keyed by upload_id.
    ///
    /// Each `PreparedUpload` holds the upload's chunk content **in memory** so
    /// finalize can store it after the external wallet pays. Lifecycle &
    /// memory cost the caller must know:
    ///   - An entry is created by every successful `prepare_*` call and removed
    ///     only by a successful `finalize_upload*` or an explicit
    ///     `cancel_upload`. There is no TTL or automatic eviction.
    ///   - So a caller that prepares repeatedly without finalizing (e.g. the
    ///     user backs out of the confirm sheet) retains one payload-sized buffer
    ///     per abandoned upload for the life of the `Client`. Call
    ///     `cancel_upload` to release one, or drop the whole `Client`.
    ///
    /// A bounded cache / TTL is a possible follow-up if this proves a problem.
    sessions: Mutex<HashMap<String, PreparedUpload>>,
    /// Monotonic source of unique upload_ids for this client instance.
    next_id: AtomicU64,
    /// EVM network this client pays on, retained for the external-signer path so
    /// [`Self::payment_transactions`] can build calldata (token/vault + RPC).
    /// `Some` only for the `connect_for_external_signer` constructors.
    evm_network: Option<EvmNetwork>,
}

impl Client {
    /// Wrap a core client with fresh external-signer session state.
    fn wrap(inner: CoreClient) -> Arc<Self> {
        Self::wrap_with_network(inner, None)
    }

    /// Wrap a core client, retaining its EVM network for the external-signer
    /// calldata path.
    fn wrap_with_network(inner: CoreClient, evm_network: Option<EvmNetwork>) -> Arc<Self> {
        Arc::new(Self {
            inner,
            sessions: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            evm_network,
        })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl Client {
    /// Connect to a local test network.
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_local(data_dir: Option<String>) -> Result<Arc<Self>, ClientError> {
        apply_data_dir(data_dir.as_deref());
        let builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(true)
            .allow_loopback(true)
            .ipv6(false)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);

        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default());

        Ok(Self::wrap(client))
    }

    /// Connect to the network using explicit bootstrap peers
    /// (`/ip4/<ip>/udp/<port>/quic` multiaddr strings).
    ///
    /// `data_dir` overrides the directory Autonomi's local state (bootstrap
    /// cache, config) lives under. **Required on Android** — pass the app's
    /// files directory (`context.filesDir`); Android processes have no
    /// `HOME`, so connecting without it fails with `InitializationFailed`
    /// (`HomeDirNotFound`). Leave `None` on iOS / desktop to use the
    /// platform default.
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect(
        peers: Vec<String>,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        apply_data_dir(data_dir.as_deref());
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);

        for peer_str in &peers {
            let addr: MultiAddr =
                peer_str
                    .parse()
                    .map_err(|e| ClientError::InitializationFailed {
                        reason: format!("invalid peer address {peer_str}: {e}"),
                    })?;
            builder = builder.bootstrap_peer(addr);
        }

        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        // Wait briefly for peer connections
        for _ in 0..20 {
            if !node.connected_peers().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default());

        Ok(Self::wrap(client))
    }

    /// Connect to the Autonomi **production network** using the bootstrap
    /// peers vendored into the SDK — no configuration needed. Read-only
    /// client; for uploads use [`Self::connect_default_with_wallet`] or
    /// [`Self::connect_default_for_external_signer`].
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_default(data_dir: Option<String>) -> Result<Arc<Self>, ClientError> {
        Self::connect(default_bootstrap_peer_strings()?, data_dir).await
    }

    /// [`Self::connect_default`] with a wallet attached for write operations,
    /// preset for the production EVM network (same coordinates as
    /// `networkInfo("arbitrum-one")`).
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_default_with_wallet(
        private_key: String,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        let net = crate::payments::network_info("arbitrum-one".into())?;
        Self::connect_with_wallet(
            default_bootstrap_peer_strings()?,
            private_key,
            net.rpc_url,
            net.token_address,
            net.vault_address,
            data_dir,
        )
        .await
    }

    /// [`Self::connect_default`] configured for the **external-signer** flow
    /// (mobile wallets / WalletConnect): production peers + production EVM
    /// network for quotes, no wallet attached. Pay via `prepare_*` + your
    /// signer + `finalize_*`.
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_default_for_external_signer(
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        let net = crate::payments::network_info("arbitrum-one".into())?;
        Self::connect_for_external_signer(
            default_bootstrap_peer_strings()?,
            net.rpc_url,
            net.token_address,
            net.vault_address,
            data_dir,
        )
        .await
    }

    /// Connect to the network with a wallet configured for write operations.
    ///
    /// Takes the wallet private key and EVM network details directly,
    /// since the wallet must be constructed fresh for ownership transfer.
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_with_wallet(
        peers: Vec<String>,
        mut private_key: String,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        apply_data_dir(data_dir.as_deref());
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);

        for peer_str in &peers {
            let addr: MultiAddr =
                peer_str
                    .parse()
                    .map_err(|e| ClientError::InitializationFailed {
                        reason: format!("invalid peer address {peer_str}: {e}"),
                    })?;
            builder = builder.bootstrap_peer(addr);
        }

        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        for _ in 0..20 {
            if !node.connected_peers().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network =
            build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)
                .map_err(|e| ClientError::InitializationFailed {
                    reason: e.to_string(),
                })?;
        let result = CoreWallet::new_from_private_key(network, &private_key);
        // Clear the private key from memory as soon as possible
        private_key.zeroize();
        let wallet = result.map_err(|e| ClientError::InitializationFailed {
            reason: format!("failed to create wallet: {e}"),
        })?;

        let client =
            CoreClient::from_node(Arc::new(node), ClientConfig::default()).with_wallet(wallet);

        Ok(Self::wrap(client))
    }

    /// Connect to a locally running devnet using the manifest JSON file the
    /// devnet wrote on startup (`LocalDevnet::write_manifest`).
    ///
    /// Reads bootstrap peers, EVM RPC URL + contract addresses, and the
    /// funded wallet private key from the manifest, then constructs a Client
    /// with the wallet attached. Suitable for **development and testing
    /// only** — production code should provide bootstrap peers and wallet
    /// material explicitly via [`Self::connect_with_wallet`].
    ///
    /// Fails if the manifest doesn't exist, is malformed, or has no `evm`
    /// section (a devnet started without payment enforcement).
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_from_devnet_manifest(
        path: String,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        apply_data_dir(data_dir.as_deref());
        let bytes = std::fs::read(&path).map_err(|e| ClientError::InitializationFailed {
            reason: format!("failed to read manifest at {path}: {e}"),
        })?;
        let manifest: DevnetManifest =
            serde_json::from_slice(&bytes).map_err(|e| ClientError::InitializationFailed {
                reason: format!("invalid manifest JSON: {e}"),
            })?;
        let evm = manifest
            .evm
            .ok_or_else(|| ClientError::InitializationFailed {
                reason: "manifest has no `evm` section — devnet started without payments?".into(),
            })?;

        // `allow_loopback(true)` lets the client accept a loopback devnet's
        // 127.0.0.1 bootstrap peers (saorsa-core / libp2p otherwise filter
        // loopback as "non-routable" → peers never form and chunk_put fails
        // with "Found 0 peers, need 7").
        //
        // `local` (loopback bind) is auto-detected from the manifest: an
        // all-loopback devnet keeps `local(true)` (the common single-box
        // case), but a **LAN devnet** — any non-loopback bootstrap addr, e.g.
        // a node advertising 192.168.x — needs `local(false)` so the client
        // binds 0.0.0.0 and can actually send to the LAN. Devnet-only path;
        // production connects via `connect` / `connect_with_wallet`.
        let lan = manifest.bootstrap.iter().any(|a| !a.is_loopback());
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(!lan)
            .allow_loopback(true)
            .ipv6(false)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);
        for peer in &manifest.bootstrap {
            builder = builder.bootstrap_peer(peer.clone());
        }
        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        // Poll for peer connections. We need at least the close-group size
        // (~7) for chunk_put to succeed, not just "any peer" — wait up to
        // 15s for the network to stabilize.
        for _ in 0..60 {
            let count = node.connected_peers().await.len();
            if count >= 7 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network = build_custom_network(
            &evm.rpc_url,
            &evm.payment_token_address,
            &evm.payment_vault_address,
        )
        .map_err(|e| ClientError::InitializationFailed {
            reason: e.to_string(),
        })?;
        let wallet =
            CoreWallet::new_from_private_key(network, &evm.wallet_private_key).map_err(|e| {
                ClientError::InitializationFailed {
                    reason: format!("failed to create wallet from manifest: {e}"),
                }
            })?;

        let client =
            CoreClient::from_node(Arc::new(node), ClientConfig::default()).with_wallet(wallet);
        Ok(Self::wrap(client))
    }

    /// Like [`Self::connect_from_devnet_manifest`] but for the **external-signer**
    /// flow: configures the devnet's EVM network for quote/price queries but
    /// attaches **no wallet** (the manifest's `wallet_private_key` may be empty
    /// — e.g. the Sepolia devnet, which expects you to bring your own wallet).
    /// Pay via `prepare_*` + an external signer + `finalize_upload`.
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_from_devnet_manifest_external_signer(
        path: String,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        apply_data_dir(data_dir.as_deref());
        let bytes = std::fs::read(&path).map_err(|e| ClientError::InitializationFailed {
            reason: format!("failed to read manifest at {path}: {e}"),
        })?;
        let manifest: DevnetManifest =
            serde_json::from_slice(&bytes).map_err(|e| ClientError::InitializationFailed {
                reason: format!("invalid manifest JSON: {e}"),
            })?;
        let evm = manifest
            .evm
            .ok_or_else(|| ClientError::InitializationFailed {
                reason: "manifest has no `evm` section — devnet started without payments?".into(),
            })?;

        // Same devnet-tuned node config as the wallet variant: allow_loopback
        // for 127.0.0.1 devnets, and auto-detect LAN vs loopback so a LAN
        // devnet (non-loopback bootstrap addr) binds 0.0.0.0 (local=false) and
        // can actually reach the nodes. See the wallet variant for detail.
        let lan = manifest.bootstrap.iter().any(|a| !a.is_loopback());
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(!lan)
            .allow_loopback(true)
            .ipv6(false)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);
        for peer in &manifest.bootstrap {
            builder = builder.bootstrap_peer(peer.clone());
        }
        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        for _ in 0..60 {
            if node.connected_peers().await.len() >= 7 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network = build_custom_network(
            &evm.rpc_url,
            &evm.payment_token_address,
            &evm.payment_vault_address,
        )
        .map_err(|e| ClientError::InitializationFailed {
            reason: e.to_string(),
        })?;
        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default())
            .with_evm_network(network.clone());
        Ok(Self::wrap_with_network(client, Some(network)))
    }

    // ===== Chunk Operations =====

    /// Store a chunk on the network.
    pub async fn chunk_put(&self, data: Vec<u8>) -> Result<ChunkPutResult, ClientError> {
        let address = self.inner.chunk_put(Bytes::from(data)).await?;
        Ok(ChunkPutResult {
            address: hex::encode(address),
        })
    }

    /// Retrieve a chunk by hex-encoded address.
    pub async fn chunk_get(&self, address_hex: String) -> Result<Vec<u8>, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let chunk = self
            .inner
            .chunk_get(&address)
            .await?
            .ok_or_else(|| ClientError::NotFound {
                reason: format!("chunk {address_hex} not found"),
            })?;
        Ok(chunk.content.to_vec())
    }

    /// Check if a chunk exists on the network.
    pub async fn chunk_exists(&self, address_hex: String) -> Result<bool, ClientError> {
        let address = hex_to_address(&address_hex)?;
        Ok(self.inner.chunk_exists(&address).await?)
    }

    // ===== Data Operations =====

    /// Upload public data. Returns the address of the stored data map.
    pub async fn data_put_public(
        &self,
        data: Vec<u8>,
        payment_mode: PaymentMode,
    ) -> Result<DataPutPublicResult, ClientError> {
        let mode = to_core_payment_mode(payment_mode);

        let result = self
            .inner
            .data_upload_with_mode(Bytes::from(data), mode)
            .await?;

        let address = self.inner.data_map_store(&result.data_map).await?;

        Ok(DataPutPublicResult {
            address: hex::encode(address),
            chunks_stored: result.chunks_stored as u64,
            payment_mode_used: from_core_payment_mode(result.payment_mode_used),
        })
    }

    /// Retrieve public data by hex-encoded address.
    pub async fn data_get_public(&self, address_hex: String) -> Result<Vec<u8>, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        let content = self.inner.data_download(&data_map).await?;
        Ok(content.to_vec())
    }

    /// Upload private data. Returns the serialized data map (hex).
    pub async fn data_put_private(
        &self,
        data: Vec<u8>,
        payment_mode: PaymentMode,
    ) -> Result<DataPutPrivateResult, ClientError> {
        let mode = to_core_payment_mode(payment_mode);

        let result = self
            .inner
            .data_upload_with_mode(Bytes::from(data), mode)
            .await?;

        let data_map_bytes =
            rmp_serde::to_vec(&result.data_map).map_err(|e| ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
            })?;

        Ok(DataPutPrivateResult {
            data_map: hex::encode(data_map_bytes),
            chunks_stored: result.chunks_stored as u64,
            payment_mode_used: from_core_payment_mode(result.payment_mode_used),
        })
    }

    /// Retrieve private data using a hex-encoded data map.
    pub async fn data_get_private(&self, data_map_hex: String) -> Result<Vec<u8>, ClientError> {
        let data_map = decode_data_map_hex(&data_map_hex)?;
        let content = self.inner.data_download(&data_map).await?;
        Ok(content.to_vec())
    }

    // ===== File Operations =====

    /// Upload a file from disk (public). The serialized data map is stored as
    /// part of the same upload payment batch — one payment covers the file's
    /// chunks and the data-map chunk. Returns the shareable address plus
    /// chunk/cost details.
    pub async fn file_upload_public(
        &self,
        path: String,
        payment_mode: PaymentMode,
    ) -> Result<FilePutPublicResult, ClientError> {
        let mode = to_core_payment_mode(payment_mode);
        let file_path = PathBuf::from(&path);

        let result = self
            .inner
            .file_upload_public_with_mode(&file_path, mode)
            .await?;

        Self::to_file_put_public_result(result)
    }

    /// Same as [`Self::file_upload_public`] but reports live progress to
    /// `listener`: the `Encrypting`, `Quoting` and `Storing` upload phases
    /// as the file is self-encrypted, quoted and its chunks land on the network.
    /// Use this on the wallet-backed (built-in payment) path to drive a progress
    /// bar; the external-signer path uses the `prepare`/`finalize_*_with_progress`
    /// pair instead.
    pub async fn file_upload_public_with_progress(
        &self,
        path: String,
        payment_mode: PaymentMode,
        listener: Box<dyn ProgressListener>,
    ) -> Result<FilePutPublicResult, ClientError> {
        let mode = to_core_payment_mode(payment_mode);
        let file_path = PathBuf::from(&path);

        let (sender, handle) = upload_progress_bridge(listener);
        let result = self
            .inner
            .file_upload_public_with_progress(&file_path, mode, Some(sender))
            .await;
        // Drop of `sender` inside the call ends the bridge; await it to flush
        // any queued progress events before returning either way.
        let _ = handle.await;
        let result = result?;

        Self::to_file_put_public_result(result)
    }

    /// Upload a file from disk privately. Returns the serialized data map (hex)
    /// rather than publishing it — the caller must keep it to retrieve the file
    /// later via `dataGetPrivate`. This is the private counterpart of
    /// `fileUploadPublic`, and the file-based analog of `dataPutPrivate`.
    pub async fn file_upload_private(
        &self,
        path: String,
        payment_mode: PaymentMode,
    ) -> Result<FilePutPrivateResult, ClientError> {
        let mode = to_core_payment_mode(payment_mode);
        let file_path = PathBuf::from(&path);

        let result = self.inner.file_upload_with_mode(&file_path, mode).await?;

        Self::to_file_put_private_result(result)
    }

    /// Same as [`Self::file_upload_private`] but reports live progress to
    /// `listener` (the `Encrypting`, `Quoting` and `Storing` upload
    /// phases). See [`Self::file_upload_public_with_progress`].
    pub async fn file_upload_private_with_progress(
        &self,
        path: String,
        payment_mode: PaymentMode,
        listener: Box<dyn ProgressListener>,
    ) -> Result<FilePutPrivateResult, ClientError> {
        let mode = to_core_payment_mode(payment_mode);
        let file_path = PathBuf::from(&path);

        let (sender, handle) = upload_progress_bridge(listener);
        let result = self
            .inner
            .file_upload_with_progress(&file_path, mode, Some(sender))
            .await;
        let _ = handle.await;
        let result = result?;

        Self::to_file_put_private_result(result)
    }

    /// Publish an existing private data map as a public network chunk, returning
    /// its hex address. Lets a caller turn a previously-private upload (a hex
    /// data map from `dataPutPrivate` / `fileUploadPrivate`) into a shareable
    /// public address **without re-uploading the underlying file data**.
    ///
    /// Note: the file's data chunks are not re-stored, but the serialized data
    /// map is itself stored as one small public chunk — so this may store and
    /// pay for that single chunk (unless it is already on the network). On a
    /// client with no wallet (external-signer mode) storing an unpaid chunk
    /// will fail; use it on a wallet-backed client, or on data maps whose chunk
    /// is already stored.
    pub async fn data_map_store(&self, data_map_hex: String) -> Result<String, ClientError> {
        let data_map = decode_data_map_hex(&data_map_hex)?;
        let address = self.inner.data_map_store(&data_map).await?;
        Ok(hex::encode(address))
    }

    /// Fetch a public data map by hex address and return it serialized (hex) —
    /// the inverse of `dataMapStore`. Returns just the data map, not the file
    /// content; use `dataGetPublic` to fetch the bytes.
    pub async fn data_map_fetch(&self, address_hex: String) -> Result<String, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        let data_map_bytes =
            rmp_serde::to_vec(&data_map).map_err(|e| ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
            })?;
        Ok(hex::encode(data_map_bytes))
    }

    /// Estimate the cost of uploading a file *before* preparing or paying for
    /// it. Samples a few of the file's chunk addresses and extrapolates, so it
    /// is fast (~seconds) and needs **no wallet** — safe to call in the
    /// external-signer flow to preview cost before `prepareFileUpload`.
    ///
    /// Check `CostEstimate.confidence` before treating a `"0"` storage cost
    /// as free.
    ///
    /// This prices the file's data chunks only. A *public* upload additionally
    /// stores the serialized data map as one extra chunk, which is not included
    /// here — so treat the result as the data-storage estimate, not the exact
    /// guaranteed total of a public publish.
    pub async fn estimate_file_cost(
        &self,
        path: String,
        payment_mode: PaymentMode,
    ) -> Result<CostEstimate, ClientError> {
        let mode = to_core_payment_mode(payment_mode);
        let file_path = PathBuf::from(&path);

        let estimate = self
            .inner
            .estimate_upload_cost(&file_path, mode, None)
            .await?;

        Ok(CostEstimate {
            file_size: estimate.file_size,
            chunk_count: estimate.chunk_count as u64,
            storage_cost_atto: estimate.storage_cost_atto,
            estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
            payment_mode: from_core_payment_mode(estimate.payment_mode),
            confidence: from_core_confidence(estimate.confidence),
        })
    }

    /// Same as [`Self::estimate_file_cost`] but reports live progress to
    /// `listener` (the `Encrypting` phase). Estimating requires
    /// self-encrypting the whole file to derive chunk addresses, which takes
    /// real time for large files — without progress, a multi-GB estimate looks
    /// like a hang.
    pub async fn estimate_file_cost_with_progress(
        &self,
        path: String,
        payment_mode: PaymentMode,
        listener: Box<dyn ProgressListener>,
    ) -> Result<CostEstimate, ClientError> {
        let mode = to_core_payment_mode(payment_mode);
        let file_path = PathBuf::from(&path);

        let (sender, handle) = upload_progress_bridge(listener);
        let estimate = self
            .inner
            .estimate_upload_cost(&file_path, mode, Some(sender))
            .await;
        let _ = handle.await;
        let estimate = estimate?;

        Ok(CostEstimate {
            file_size: estimate.file_size,
            chunk_count: estimate.chunk_count as u64,
            storage_cost_atto: estimate.storage_cost_atto,
            estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
            payment_mode: from_core_payment_mode(estimate.payment_mode),
            confidence: from_core_confidence(estimate.confidence),
        })
    }

    /// Download a file to disk by hex-encoded address.
    pub async fn file_download_public(
        &self,
        address_hex: String,
        dest_path: String,
    ) -> Result<(), ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        let dest = PathBuf::from(&dest_path);
        // Propagate the real error via the `From<ant_core::data::Error>` mapping
        // instead of flattening everything into `NetworkError` — a timeout or an
        // out-of-disk-space failure now surfaces as its own `ClientError`
        // variant rather than a misleading "network error".
        self.inner.file_download(&data_map, &dest).await?;
        Ok(())
    }

    /// Download a private file to disk by hex-encoded data map, without a
    /// progress listener — the no-progress counterpart of
    /// [`Self::download_private_to_file`], mirroring how
    /// [`Self::file_download_public`] pairs with
    /// [`Self::download_public_to_file`].
    pub async fn file_download_private(
        &self,
        data_map_hex: String,
        dest_path: String,
    ) -> Result<(), ClientError> {
        let data_map = decode_data_map_hex(&data_map_hex)?;
        let dest = PathBuf::from(&dest_path);
        self.inner.file_download(&data_map, &dest).await?;
        Ok(())
    }

    // ===== Wallet Operations =====

    /// Approve token spend for storage payments (one-time).
    pub async fn wallet_approve(&self) -> Result<(), ClientError> {
        self.inner
            .approve_token_spend()
            .await
            .map_err(|e| ClientError::PaymentError {
                reason: e.to_string(),
            })?;
        Ok(())
    }

    // ===== External-signer (WalletConnect) operations =====

    /// Connect with an EVM network configured but **no wallet / private key**.
    ///
    /// This is the external-signer entry point: quote collection and price
    /// queries work (they need the network), but payment is signed off-device
    /// by an external wallet (e.g. WalletConnect). Use [`Self::prepare_data_upload`]
    /// / [`Self::prepare_file_upload`] then [`Self::finalize_upload`].
    ///
    /// `data_dir`: see [`Self::connect`].
    #[uniffi::constructor(default(data_dir = None))]
    pub async fn connect_for_external_signer(
        peers: Vec<String>,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        apply_data_dir(data_dir.as_deref());
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);
        for peer_str in &peers {
            let addr: MultiAddr =
                peer_str
                    .parse()
                    .map_err(|e| ClientError::InitializationFailed {
                        reason: format!("invalid peer address {peer_str}: {e}"),
                    })?;
            builder = builder.bootstrap_peer(addr);
        }
        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;
        for _ in 0..20 {
            if !node.connected_peers().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network =
            build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)
                .map_err(|e| ClientError::InitializationFailed {
                    reason: e.to_string(),
                })?;
        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default())
            .with_evm_network(network.clone());
        Ok(Self::wrap_with_network(client, Some(network)))
    }

    /// Phase 1 (external signer): encrypt `data`, collect quotes, and return
    /// the payment summary. The
    /// prepared state is retained under the returned `upload_id` until
    /// [`Self::finalize_upload`].
    pub async fn prepare_data_upload(
        &self,
        data: Vec<u8>,
        visibility: Visibility,
    ) -> Result<PreparedUploadInfo, ClientError> {
        let vis = to_core_visibility(visibility);
        let prepared = self
            .inner
            .data_prepare_upload_with_visibility(Bytes::from(data), vis)
            .await?;
        self.stash_prepared(prepared)
    }

    /// Phase 1 (external signer): same as [`Self::prepare_data_upload`] but for
    /// a file on disk.
    pub async fn prepare_file_upload(
        &self,
        path: String,
        visibility: Visibility,
    ) -> Result<PreparedUploadInfo, ClientError> {
        let vis = to_core_visibility(visibility);
        let prepared = self
            .inner
            .file_prepare_upload_with_visibility(&PathBuf::from(path), vis)
            .await?;
        self.stash_prepared(prepared)
    }

    /// Phase 1 (external signer): same as `prepareFileUpload` but reports
    /// encryption/quoting progress to `listener`. Encrypting a large file to
    /// spill can take seconds, so this surfaces the `Encrypting` and
    /// `Quoting` phases the plain `prepareFileUpload` runs silently. (Only
    /// files support prepare progress; ant-core has no in-memory data variant.)
    pub async fn prepare_file_upload_with_progress(
        &self,
        path: String,
        visibility: Visibility,
        listener: Box<dyn ProgressListener>,
    ) -> Result<PreparedUploadInfo, ClientError> {
        let vis = to_core_visibility(visibility);
        let (sender, handle) = upload_progress_bridge(listener);
        let result = self
            .inner
            .file_prepare_upload_with_progress(&PathBuf::from(path), vis, Some(sender))
            .await;
        // Drop of `sender` inside the call ends the bridge; await it to flush
        // any queued progress events before returning either way.
        let _ = handle.await;
        self.stash_prepared(result?)
    }

    /// Phase 1.5 (external signer): build the ordered transactions the external
    /// wallet must sign to pay for a prepared upload — an ERC-20 `approve`
    /// followed by the vault payment call(s). This replaces the hand-rolled ABI
    /// encoding + hardcoded selectors that consumers used to carry.
    ///
    /// Sign each [`TxRequest`] in the returned order, waiting for each receipt,
    /// then finalize:
    ///   - **wave-batch**: for each `"pay"` tx, map every entry in its
    ///     `quote_hashes` to that tx's hash, then call [`Self::finalize_upload`];
    ///   - **merkle**: read the winner pool hash from the `"pay"` receipt's
    ///     `MerklePaymentMade` event and call [`Self::finalize_upload_merkle`].
    ///
    /// Returns an empty list when everything was already stored (nothing to
    /// pay). Only valid on a client built with `connect_for_external_signer` /
    /// `connect_from_devnet_manifest_external_signer`; other clients return
    /// [`ClientError::WalletNotConfigured`].
    pub async fn payment_transactions(
        &self,
        upload_id: String,
    ) -> Result<Vec<TxRequest>, ClientError> {
        let network = self
            .evm_network
            .as_ref()
            .ok_or(ClientError::WalletNotConfigured)?;
        let map = self.sessions.lock().expect("sessions mutex poisoned");
        let prepared = map
            .get(&upload_id)
            .ok_or_else(|| ClientError::InvalidInput {
                reason: format!("unknown or already-finalized upload_id: {upload_id}"),
            })?;
        crate::payments::build_payment_transactions(network, prepared)
    }

    /// Phase 2 (external signer): after the external wallet has paid
    /// (`payForQuotes`), finalize the upload by supplying the resulting
    /// `quote_hash -> tx_hash` map (both 0x-prefixed hex). Stores the chunks
    /// and returns the data map / address. `upload_id` comes from a prior
    /// `prepare_*` call. If everything was already stored, pass an empty map.
    ///
    /// # Retry / failure contract (IMPORTANT for paid uploads)
    ///
    /// - **Bad input** (a malformed `quote_hash`/`tx_hash`) is validated before
    ///   any state is touched, so it errors with the upload left intact — safe
    ///   to call again with a corrected map.
    /// - **A storage/network failure *after* payment is currently NOT
    ///   retryable.** ant-core consumes the prepared upload (and the paid
    ///   proofs) by value, so on such a failure the paid attempt is stranded:
    ///   a fresh `prepare_*` collects new quotes with different quote hashes
    ///   that will not match the already-paid tx map. Do not tell the user the
    ///   payment can simply be reused. Fixing this needs an ant-core retry-state
    ///   API — tracked in WithAutonomi/ant-client#140 (core) and
    ///   WithAutonomi/ant-sdk#201 (this surface).
    pub async fn finalize_upload(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_inner(upload_id, tx_hashes, None).await
    }

    /// Same as [`Self::finalize_upload`] but reports live storing progress:
    /// `listener` gets `Storing` updates (`done`/`total` chunks) as chunks
    /// land on the network.
    pub async fn finalize_upload_with_progress(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
        listener: Box<dyn ProgressListener>,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_inner(upload_id, tx_hashes, Some(listener))
            .await
    }

    /// Phase 2 (external signer, MERKLE): after the wallet has paid via
    /// `payForMerkleTree`, finalize by supplying the `winner_pool_hash`
    /// (0x-prefixed hex, 32 bytes) read from the `MerklePaymentMade` event in
    /// the payment receipt. Use this for uploads whose
    /// `PreparedUploadInfo.payment_type` is [`crate::PaymentType::Merkle`];
    /// wave-batch uploads must
    /// use [`Self::finalize_upload`] (this rejects them with a clear error, and
    /// vice versa, without consuming the prepared upload).
    ///
    /// The same retry/failure contract as [`Self::finalize_upload`] applies: a
    /// storage failure after payment is currently not retryable
    /// (WithAutonomi/ant-client#140).
    pub async fn finalize_upload_merkle(
        &self,
        upload_id: String,
        winner_pool_hash: String,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_merkle_inner(upload_id, winner_pool_hash, None)
            .await
    }

    /// Same as [`Self::finalize_upload_merkle`] but reports live storing
    /// progress via `listener` (the `Storing` phase).
    pub async fn finalize_upload_merkle_with_progress(
        &self,
        upload_id: String,
        winner_pool_hash: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_merkle_inner(upload_id, winner_pool_hash, Some(listener))
            .await
    }

    /// Discard a prepared upload that will not be finalized, freeing the chunk
    /// content it holds in memory (see the `sessions` field docs on lifecycle).
    /// Returns `true` if an upload with this id was present. Safe to call with
    /// an unknown or already-finalized id — it simply returns `false`.
    pub fn cancel_upload(&self, upload_id: String) -> bool {
        self.sessions
            .lock()
            .expect("sessions mutex poisoned")
            .remove(&upload_id)
            .is_some()
    }

    /// Download public data by address straight to a file on disk, reporting
    /// live progress (`Resolving` then `Downloading` phases). Returns bytes
    /// written.
    pub async fn download_public_to_file(
        &self,
        address_hex: String,
        dest_path: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<u64, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        self.download_to_file(data_map, dest_path, listener).await
    }

    /// Download private data by hex-encoded data map straight to a file on
    /// disk, reporting live progress. Returns bytes written.
    pub async fn download_private_to_file(
        &self,
        data_map_hex: String,
        dest_path: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<u64, ClientError> {
        let data_map = decode_data_map_hex(&data_map_hex)?;
        self.download_to_file(data_map, dest_path, listener).await
    }
}

impl Client {
    /// Shared finalize path — optionally bridges storing progress to `listener`.
    async fn finalize_inner(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
        listener: Option<Box<dyn ProgressListener>>,
    ) -> Result<ExternalUploadResult, ClientError> {
        // Parse & validate ALL tx hashes BEFORE removing the prepared upload
        // from the session map. The caller has already paid on-chain, so a
        // malformed hash must NOT destroy the only in-memory copy of the
        // prepared chunks — with this ordering, bad input returns an error and
        // leaves the upload intact and retryable.
        let mut tx_hash_map: HashMap<QuoteHash, TxHash> = HashMap::with_capacity(tx_hashes.len());
        for (quote_hex, tx_hex) in &tx_hashes {
            let quote_bytes = decode_hash(quote_hex, "quote hash")?;
            let tx_bytes = decode_hash(tx_hex, "tx hash")?;
            tx_hash_map.insert(QuoteHash::from(quote_bytes), TxHash::from(tx_bytes));
        }

        // Take ownership of the prepared upload only now that the input is
        // known-good, so bad-input retries stay lossless. WARNING: ant-core's
        // `finalize_upload_with_progress` consumes the `PreparedUpload` (and the
        // paid proofs) by value and does not hand them back on error, so a
        // *network* store failure below strands the paid attempt — it is NOT
        // safely retryable, because a re-prepare yields fresh quote hashes that
        // won't match the already-paid tx map. See the `finalize_upload` docs
        // and WithAutonomi/ant-client#140 + WithAutonomi/ant-sdk#201 for the fix.
        let prepared = self.take_session(&upload_id, PaymentKind::Wave)?;

        let (sender, handle) = match listener {
            Some(l) => {
                let (tx, h) = upload_progress_bridge(l);
                (Some(tx), Some(h))
            }
            None => (None, None),
        };

        let result = self
            .inner
            .finalize_upload_with_progress(prepared, &tx_hash_map, sender)
            .await?;

        if let Some(h) = handle {
            let _ = h.await;
        }

        Self::to_external_result(result)
    }

    /// Shared finalize path for MERKLE uploads. Validates `winner_pool_hash`
    /// before taking the session (bad input is lossless), then consumes the
    /// prepared upload via ant-core's merkle finalize. Same post-payment
    /// non-retryability caveat as [`Self::finalize_inner`] applies.
    async fn finalize_merkle_inner(
        &self,
        upload_id: String,
        winner_pool_hash: String,
        listener: Option<Box<dyn ProgressListener>>,
    ) -> Result<ExternalUploadResult, ClientError> {
        let winner = decode_hash(&winner_pool_hash, "winner pool hash")?;
        let prepared = self.take_session(&upload_id, PaymentKind::Merkle)?;

        let (sender, handle) = match listener {
            Some(l) => {
                let (tx, h) = upload_progress_bridge(l);
                (Some(tx), Some(h))
            }
            None => (None, None),
        };

        let result = self
            .inner
            .finalize_upload_merkle_with_progress(prepared, winner, sender)
            .await?;

        if let Some(h) = handle {
            let _ = h.await;
        }

        Self::to_external_result(result)
    }

    /// Remove the prepared upload for `upload_id`, but only if it matches the
    /// expected payment shape. An unknown id, or a call routed to the wrong
    /// finalize method, errors WITHOUT removing anything — so a mis-routed
    /// finalize is lossless and retryable via the correct method.
    fn take_session(
        &self,
        upload_id: &str,
        expect: PaymentKind,
    ) -> Result<PreparedUpload, ClientError> {
        let mut map = self.sessions.lock().expect("sessions mutex poisoned");
        let actual = match map.get(upload_id) {
            None => {
                return Err(ClientError::InvalidInput {
                    reason: format!("unknown or already-finalized upload_id: {upload_id}"),
                });
            }
            Some(p) => match p.payment_info {
                ExternalPaymentInfo::Merkle { .. } => PaymentKind::Merkle,
                ExternalPaymentInfo::WaveBatch { .. } => PaymentKind::Wave,
            },
        };
        if actual != expect {
            let (used, want) = match actual {
                PaymentKind::Merkle => ("merkle", "finalize_upload_merkle"),
                PaymentKind::Wave => ("wave-batch", "finalize_upload"),
            };
            return Err(ClientError::InvalidInput {
                reason: format!("upload {upload_id} used {used} payment; call {want} instead"),
            });
        }
        Ok(map
            .remove(upload_id)
            .expect("session entry present while holding the lock"))
    }

    /// Convert ant-core's [`FileUploadResult`] into the FFI
    /// [`FilePutPublicResult`]. Public uploads always carry a data-map address.
    fn to_file_put_public_result(
        result: FileUploadResult,
    ) -> Result<FilePutPublicResult, ClientError> {
        let address = result
            .data_map_address
            .ok_or_else(|| ClientError::InternalError {
                reason: "public upload returned no data-map address".into(),
            })?;
        Ok(FilePutPublicResult {
            address: hex::encode(address),
            chunks_stored: result.chunks_stored as u64,
            storage_cost_atto: result.storage_cost_atto,
            gas_cost_wei: result.gas_cost_wei.to_string(),
            payment_mode_used: from_core_payment_mode(result.payment_mode_used),
        })
    }

    /// Convert ant-core's [`FileUploadResult`] into the FFI
    /// [`FilePutPrivateResult`] (serializes the data map for the caller).
    fn to_file_put_private_result(
        result: FileUploadResult,
    ) -> Result<FilePutPrivateResult, ClientError> {
        let data_map_bytes =
            rmp_serde::to_vec(&result.data_map).map_err(|e| ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
            })?;
        Ok(FilePutPrivateResult {
            data_map: hex::encode(data_map_bytes),
            chunks_stored: result.chunks_stored as u64,
            storage_cost_atto: result.storage_cost_atto,
            gas_cost_wei: result.gas_cost_wei.to_string(),
            payment_mode_used: from_core_payment_mode(result.payment_mode_used),
        })
    }

    /// Convert ant-core's [`FileUploadResult`] into the FFI [`ExternalUploadResult`].
    fn to_external_result(result: FileUploadResult) -> Result<ExternalUploadResult, ClientError> {
        let data_map_bytes =
            rmp_serde::to_vec(&result.data_map).map_err(|e| ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
            })?;
        Ok(ExternalUploadResult {
            data_map: hex::encode(data_map_bytes),
            address: result.data_map_address.map(hex::encode),
            chunks_stored: result.chunks_stored as u64,
            storage_cost_atto: result.storage_cost_atto,
            gas_cost_wei: result.gas_cost_wei.to_string(),
        })
    }

    /// Shared download-to-file path with progress bridging.
    async fn download_to_file(
        &self,
        data_map: ant_core::data::DataMap,
        dest_path: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<u64, ClientError> {
        let (tx, handle) = download_progress_bridge(listener);
        let written = self
            .inner
            .file_download_with_progress(&data_map, Path::new(&dest_path), Some(tx))
            .await?;
        let _ = handle.await;
        Ok(written)
    }

    /// Build the FFI summary for a prepared upload and stash the heavy state
    /// under a fresh `upload_id`. Handles both wave-batch and merkle payment.
    fn stash_prepared(&self, prepared: PreparedUpload) -> Result<PreparedUploadInfo, ClientError> {
        let data_map_address = prepared.data_map_address.map(hex::encode);
        // Everything already on the network (nothing to pay/store) when the
        // preflight found every chunk. Independent of payment shape — merkle
        // never produces per-quote `payments`, so we can't infer this from an
        // empty payments list.
        let already_stored = prepared.already_stored_addresses.len() >= prepared.total_chunks;

        // Defaults: wave leaves the merkle fields empty; merkle leaves `payments`
        // empty and `total_amount` "0".
        let mut payments = Vec::new();
        let mut total_amount = "0".to_string();
        let mut depth = 0u32;
        let mut pool_commitments = Vec::new();
        let mut merkle_payment_timestamp = 0u64;

        let payment_type = match &prepared.payment_info {
            ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
                payments = payment_intent
                    .payments
                    .iter()
                    .map(|(quote_hash, rewards_addr, amount)| PaymentEntry {
                        quote_hash: format!("0x{}", hex::encode(quote_hash)),
                        rewards_address: format!("{rewards_addr}"),
                        amount: amount.to_string(),
                    })
                    .collect::<Vec<_>>();
                total_amount = payment_intent.total_amount.to_string();
                PaymentType::WaveBatch
            }
            // Merkle: expose depth + pool commitments + timestamp so the app can
            // build the `payForMerkleTree(uint8, PoolCommitment[], uint64)` call.
            // Mirrors the antd daemon's gRPC/REST mapping.
            ExternalPaymentInfo::Merkle { prepared_batch, .. } => {
                depth = prepared_batch.depth as u32;
                merkle_payment_timestamp = prepared_batch.merkle_payment_timestamp;
                pool_commitments = prepared_batch
                    .pool_commitments
                    .iter()
                    .map(|pc| PoolCommitmentEntry {
                        pool_hash: format!("0x{}", hex::encode(pc.pool_hash)),
                        candidates: pc
                            .candidates
                            .iter()
                            .map(|c| CandidateNodeEntry {
                                rewards_address: format!("0x{}", hex::encode(c.rewards_address)),
                                amount: c.price.to_string(),
                            })
                            .collect(),
                    })
                    .collect::<Vec<_>>();
                PaymentType::Merkle
            }
        };
        let upload_id = format!("upl-{}", self.next_id.fetch_add(1, Ordering::Relaxed));
        self.sessions
            .lock()
            .expect("sessions mutex poisoned")
            .insert(upload_id.clone(), prepared);
        Ok(PreparedUploadInfo {
            upload_id,
            payment_type,
            payments,
            total_amount,
            depth,
            pool_commitments,
            merkle_payment_timestamp,
            data_map_address,
            already_stored,
        })
    }
}

/// Which external-signer payment shape a finalize call targets. Used to route
/// `finalize_upload` (wave) vs `finalize_upload_merkle` and reject mismatches.
#[derive(Clone, Copy, PartialEq)]
enum PaymentKind {
    Wave,
    Merkle,
}

/// Decode a 0x-prefixed (or bare) hex string into a 32-byte hash.
fn decode_hash(hex_str: &str, label: &str) -> Result<[u8; 32], ClientError> {
    let bytes =
        hex::decode(hex_str.trim_start_matches("0x")).map_err(|e| ClientError::InvalidInput {
            reason: format!("invalid {label} {hex_str}: {e}"),
        })?;
    bytes.try_into().map_err(|_| ClientError::InvalidInput {
        reason: format!("{label} {hex_str} must be 32 bytes"),
    })
}

/// Parse a hex string into a 32-byte address.
fn hex_to_address(hex: &str) -> Result<[u8; 32], ClientError> {
    let bytes = hex::decode(hex).map_err(|e| ClientError::InvalidInput {
        reason: format!("invalid hex address: {e}"),
    })?;
    bytes.try_into().map_err(|_| ClientError::InvalidInput {
        reason: "address must be 32 bytes".into(),
    })
}

/// Decode a hex-encoded serialized data map, rejecting unreasonably large
/// input first (20 MB hex = 10 MB decoded) — this surface is reachable from
/// app/UI input, so guard against a decode-driven memory spike.
fn decode_data_map_hex(data_map_hex: &str) -> Result<ant_core::data::DataMap, ClientError> {
    const MAX_HEX_INPUT: usize = 20 * 1024 * 1024;
    if data_map_hex.len() > MAX_HEX_INPUT {
        return Err(ClientError::InvalidInput {
            reason: format!(
                "data map hex too large: {} bytes (max {})",
                data_map_hex.len(),
                MAX_HEX_INPUT
            ),
        });
    }
    let data_map_bytes = hex::decode(data_map_hex).map_err(|e| ClientError::InvalidInput {
        reason: format!("invalid hex: {e}"),
    })?;
    rmp_serde::from_slice(&data_map_bytes).map_err(|e| ClientError::InvalidInput {
        reason: format!("invalid data map: {e}"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_bootstrap_peers_are_valid_multiaddrs() {
        let peers = default_bootstrap_peer_strings().unwrap();
        assert_eq!(peers.len(), 7, "vendored mainnet peer count");
        for p in &peers {
            assert!(p.starts_with("/ip4/") && p.ends_with("/quic"), "shape: {p}");
            assert!(p.parse::<MultiAddr>().is_ok(), "unparseable multiaddr: {p}");
        }
    }

    #[test]
    fn decode_hash_accepts_32_bytes_with_or_without_0x() {
        let bare = "11".repeat(32);
        let prefixed = format!("0x{bare}");
        let want = [0x11u8; 32];
        assert_eq!(decode_hash(&bare, "winner pool hash").unwrap(), want);
        assert_eq!(decode_hash(&prefixed, "winner pool hash").unwrap(), want);
    }

    #[test]
    fn decode_hash_rejects_wrong_length() {
        // 31 bytes — one short of a 32-byte hash.
        let short = "ab".repeat(31);
        let err = decode_hash(&short, "winner pool hash").unwrap_err();
        assert!(
            matches!(err, ClientError::InvalidInput { reason } if reason.contains("32 bytes")),
            "expected a 32-byte length error"
        );
    }

    #[test]
    fn decode_hash_rejects_non_hex() {
        let err = decode_hash("0xzz", "winner pool hash").unwrap_err();
        assert!(matches!(err, ClientError::InvalidInput { .. }));
    }

    #[test]
    fn payment_mode_round_trips_through_core() {
        use crate::data::{from_core_payment_mode, to_core_payment_mode};
        for mode in [PaymentMode::Auto, PaymentMode::Merkle, PaymentMode::Single] {
            assert_eq!(from_core_payment_mode(to_core_payment_mode(mode)), mode);
        }
    }

    #[test]
    fn visibility_maps_to_core() {
        use crate::data::to_core_visibility;
        assert!(matches!(
            to_core_visibility(Visibility::Public),
            ant_core::data::Visibility::Public
        ));
        assert!(matches!(
            to_core_visibility(Visibility::Private),
            ant_core::data::Visibility::Private
        ));
    }

    // PaymentType, TxKind and ProgressPhase have no ant-core counterpart
    // (FFI-only vocabulary), so there is no conversion to exercise.
    #[test]
    fn cost_confidence_maps_from_core() {
        use crate::data::from_core_confidence;
        use ant_core::data::CostEstimateConfidence as Core;
        assert_eq!(
            from_core_confidence(Core::PricedSample),
            crate::CostConfidence::PricedSample
        );
        assert_eq!(
            from_core_confidence(Core::VerifiedAllAlreadyStored),
            crate::CostConfidence::VerifiedAllAlreadyStored
        );
        assert_eq!(
            from_core_confidence(Core::AllSamplesAlreadyStoredIncomplete),
            crate::CostConfidence::AllSamplesAlreadyStoredIncomplete
        );
    }
}
