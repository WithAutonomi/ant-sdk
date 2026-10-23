use serde::{Deserialize, Serialize};

/// Payment-batching strategy for uploads.
///
/// Passed as a required parameter to every put/cost method; the client
/// serializes the variant to the wire string at the request boundary.
///
/// - `Auto`   — server picks (merkle for 64+ chunks, single otherwise).
/// - `Merkle` — force merkle-batch (saves gas, min 2 chunks).
/// - `Single` — force per-chunk payments (works for any chunk count).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaymentMode {
    Auto,
    Merkle,
    Single,
}

impl PaymentMode {
    /// Serialize to the wire string the daemon expects.
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Merkle => "merkle",
            Self::Single => "single",
        }
    }
}

/// Result of a health check against the antd daemon.
///
/// The diagnostic fields (`version`, `evm_network`, `uptime_seconds`,
/// `build_commit`, `payment_token_address`, `payment_vault_address`) were
/// added in antd 0.4.0. They default to empty / 0 via `#[serde(default)]`,
/// so deserialization tolerates pre-0.4.0 daemon responses.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HealthStatus {
    pub ok: bool,
    pub network: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub evm_network: String,
    #[serde(default)]
    pub uptime_seconds: u64,
    #[serde(default)]
    pub build_commit: String,
    #[serde(default)]
    pub payment_token_address: String,
    #[serde(default)]
    pub payment_vault_address: String,
    /// Best-effort write-path signal (antd 0.12.1+):
    /// `max(routing_table_size, connected_peers)` at or above the DHT
    /// re-bootstrap threshold. `false` on pre-0.12.1 daemons (which don't
    /// report it) and on degraded nodes — pair with `routing_table_size` to
    /// tell the two apart.
    #[serde(default)]
    pub write_ready: bool,
    /// Live transport-level connection count (antd 0.12.1+).
    #[serde(default)]
    pub connected_peers: u32,
    /// DHT routing-table entries (antd 0.12.1+).
    #[serde(default)]
    pub routing_table_size: u32,
    /// Routing-table floor below which the DHT auto-re-bootstraps
    /// (antd 0.12.1+; 0 on older daemons).
    #[serde(default)]
    pub rebootstrap_threshold: u32,
    /// Seconds since the daemon's last successful store-type operation, or
    /// `None` if none has succeeded this process (or pre-0.12.1 daemon).
    #[serde(default)]
    pub last_store_ok_secs_ago: Option<u64>,
}

/// Result of a single-chunk put (used by `chunk_put`). Data and file puts
/// return richer types — see [`DataPutResult`], [`DataPutPublicResult`],
/// [`FilePutResult`], [`FilePutPublicResult`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PutResult {
    /// Cost in atto tokens as a string.
    pub cost: String,
    /// Hex-encoded address.
    pub address: String,
}

/// Result of a private data put. The DataMap is returned to the caller; it
/// is NOT stored on-network. The REST transport populates `chunks_stored`
/// and `payment_mode_used`; the gRPC transport currently leaves them empty
/// because the proto `PutDataResponse` only carries `data_map`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DataPutResult {
    /// Hex-encoded caller-held DataMap.
    pub data_map: String,
    #[serde(default)]
    pub chunks_stored: u64,
    #[serde(default)]
    pub payment_mode_used: String,
    /// The plaintext's SHA-256 (lowercase hex). `None` from a daemon older
    /// than antd 0.17.0, which does not send it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

/// Result of a public data put. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DataPutPublicResult {
    /// Hex-encoded on-network DataMap address.
    pub address: String,
    #[serde(default)]
    pub chunks_stored: u64,
    #[serde(default)]
    pub payment_mode_used: String,
    /// The plaintext's SHA-256 (lowercase hex). `None` from a daemon older
    /// than antd 0.17.0, which does not send it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

/// Result of a private file upload. The DataMap is returned to the caller;
/// it is NOT stored on-network.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePutResult {
    /// Hex-encoded caller-held DataMap.
    pub data_map: String,
    /// Storage cost paid in atto tokens. `"0"` if all chunks already existed.
    pub storage_cost_atto: String,
    /// Gas cost paid in wei as a decimal string.
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used (`"auto"`, `"merkle"`, or `"single"`).
    pub payment_mode_used: String,
    /// The plaintext's SHA-256 (lowercase hex). `None` from a daemon older
    /// than antd 0.17.0, which does not send it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

/// Result of a public file upload. The DataMap is stored on-network as an
/// extra chunk; `address` is the shareable retrieval handle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePutPublicResult {
    /// Hex-encoded on-network DataMap address.
    pub address: String,
    /// Storage cost paid in atto tokens. `"0"` if all chunks already existed.
    pub storage_cost_atto: String,
    /// Gas cost paid in wei as a decimal string.
    pub gas_cost_wei: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: u64,
    /// Which payment mode was actually used.
    pub payment_mode_used: String,
    /// The plaintext's SHA-256 (lowercase hex). `None` from a daemon older
    /// than antd 0.17.0, which does not send it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

/// Wallet address from the antd daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletAddress {
    /// Hex-encoded address, e.g. "0x...".
    pub address: String,
}

/// Wallet balance from the antd daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletBalance {
    /// Balance in atto tokens as a string.
    pub balance: String,
    /// Gas balance in atto tokens as a string.
    pub gas_balance: String,
}

/// A single payment required for an upload.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PaymentInfo {
    /// Hex-encoded quote hash.
    pub quote_hash: String,
    /// Hex-encoded rewards address.
    pub rewards_address: String,
    /// Amount in atto tokens as a string.
    pub amount: String,
}

/// A candidate node entry within a merkle batch payment pool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateNodeEntry {
    pub rewards_address: String,
    pub amount: String,
}

/// A pool commitment entry for merkle batch payments.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolCommitmentEntry {
    pub pool_hash: String,
    pub candidates: Vec<CandidateNodeEntry>,
}

/// Options for the external-signer prepare calls (file, data, chunk) on
/// both transports.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PrepareOptions {
    /// `Some("public")` bundles the serialized DataMap chunk into the same
    /// external-signer payment batch so finalize can publish it on-network;
    /// `None` / `Some("private")` keep the DataMap caller-held. Ignored by
    /// the single-chunk prepare.
    pub visibility: Option<String>,
    /// Ask the daemon to carry the full signed quotes plus ADR-0004
    /// commitment sidecars (`signed_quotes`, wave-batch only) for offline
    /// verification via `verify_quotes`. Requires antd >= 0.13.0; older
    /// daemons ignore the flag and `signed_quotes` stays empty.
    pub include_signed_quotes: bool,
}

/// One signed wave-batch quote from a prepare response, as opaque
/// base64(msgpack) blobs — identical on REST and gRPC, so an entry obtained
/// over either transport feeds `verify_quotes` on either transport.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignedQuoteEntry {
    /// Quote hash (hex with 0x prefix) — matches the `payments[]` entry.
    pub quote_hash: String,
    /// base64(msgpack) signed `PaymentQuote`. Opaque.
    pub quote: String,
    /// base64(msgpack) `StorageCommitment` sidecar the quote's commitment
    /// pin resolves to. `None` for baseline quotes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commitment_sidecar: Option<String>,
}

/// One entry for `verify_quotes`: the payment triple the caller was asked
/// to pay plus the opaque signed artifacts from the prepare response's
/// `signed_quotes`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VerifyQuoteEntry {
    /// Quote hash the payer was asked to pay (hex, 32 bytes).
    pub quote_hash: String,
    /// Rewards address the payer was asked to pay (hex with 0x prefix).
    pub rewards_address: String,
    /// Amount the payer was asked to pay (atto tokens, decimal string).
    pub amount: String,
    /// `SignedQuoteEntry::quote`, opaque.
    pub signed_quote: String,
    /// `SignedQuoteEntry::commitment_sidecar`, opaque. Required when the
    /// quote is commitment-bound.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commitment_sidecar: Option<String>,
}

/// Per-entry verdict from `verify_quotes`. The extracted fields are `Some`
/// as soon as the signed quote deserialized — even when a later check
/// failed — so policy layers can see what the quote claimed.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VerifyQuoteVerdict {
    /// Echo of the request entry's `quote_hash`.
    pub quote_hash: String,
    /// True when every check passed: hash recomputation, ML-DSA-65
    /// signature, paid-fields equality, and the ADR-0004 commitment binding
    /// with exact on-curve pricing.
    pub valid: bool,
    /// The first failing rule, by name. `None` when valid.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// Quote timestamp (unix seconds) — for the caller's expiry policy.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timestamp_unix_secs: Option<u64>,
    /// The chunk address the quote covers (hex, 32 bytes).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    /// The signed price (atto tokens, decimal string).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price: Option<String>,
    /// The signed rewards address (hex with 0x prefix).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rewards_address: Option<String>,
    /// Claimed ADR-0004 storage-commitment key count (0 = baseline quote).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub committed_key_count: Option<u32>,
    /// Whether the quote pins a storage commitment.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pinned: Option<bool>,
}

impl VerifyQuoteVerdict {
    /// True once the signed quote deserialized (the extracted fields are
    /// populated). Mirrors the gRPC `quote_decoded` flag.
    pub fn quote_decoded(&self) -> bool {
        self.content.is_some()
    }
}

/// Result of `verify_quotes`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VerifyQuotesResult {
    /// True only when `entries` is non-empty and every entry verified.
    pub valid: bool,
    #[serde(default)]
    pub entries: Vec<VerifyQuoteVerdict>,
}

/// Result of preparing an upload for external signing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadResult {
    pub upload_id: String,
    pub payments: Vec<PaymentInfo>,
    pub total_amount: String,
    pub payment_vault_address: String,
    pub payment_token_address: String,
    pub rpc_url: String,
    #[serde(rename = "payment_type", default)]
    pub payment_type: String,
    #[serde(rename = "depth", default)]
    pub depth: Option<u8>,
    #[serde(rename = "pool_commitments", default)]
    pub pool_commitments: Option<Vec<PoolCommitmentEntry>>,
    #[serde(rename = "merkle_payment_timestamp", default)]
    pub merkle_payment_timestamp: Option<u64>,
    /// Total chunks in this upload, including any already on-network. Added in
    /// antd 0.10.0; older daemons omit it and it defaults to 0. The external
    /// signer pays for `total_chunks - already_stored_count` chunks.
    #[serde(default)]
    pub total_chunks: u64,
    /// Chunks already stored on-network and excluded from payment + PUT.
    /// Added in antd 0.10.0; defaults to 0 against older daemons.
    #[serde(default)]
    pub already_stored_count: u64,
    /// Populated only when the request set
    /// [`PrepareOptions::include_signed_quotes`] and the payment type is
    /// `wave_batch`: one entry per `payments[]` quote for offline
    /// verification via `verify_quotes`. Merkle prepares leave it empty.
    /// Added in antd 0.13.0.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub signed_quotes: Vec<SignedQuoteEntry>,
}

/// Result of finalizing an externally-signed upload.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FinalizeUploadResult {
    #[serde(default)]
    pub address: String,
    #[serde(default)]
    pub chunks_stored: i64,
    #[serde(default)]
    pub data_map: String,
    #[serde(default)]
    pub data_map_address: String,
    /// The plaintext's SHA-256 (lowercase hex). `None` from a daemon older
    /// than antd 0.17.0, which does not send it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

/// Result of preparing a single-chunk publish for external signing.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrepareChunkResult {
    pub address: String,
    #[serde(default)]
    pub already_stored: bool,
    #[serde(default)]
    pub upload_id: String,
    #[serde(default)]
    pub payment_type: String,
    #[serde(default)]
    pub payments: Vec<PaymentInfo>,
    #[serde(default)]
    pub total_amount: String,
    #[serde(default)]
    pub payment_vault_address: String,
    #[serde(default)]
    pub payment_token_address: String,
    #[serde(default)]
    pub rpc_url: String,
    /// Same semantics as [`PrepareUploadResult::signed_quotes`] (antd >= 0.13.0).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub signed_quotes: Vec<SignedQuoteEntry>,
}

/// Pre-upload cost breakdown returned by `data_cost` / `file_cost`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadCostEstimate {
    pub cost: String,
    pub file_size: u64,
    pub chunk_count: u32,
    pub estimated_gas_cost_wei: String,
    pub payment_mode: String,
}

/// A fetch-progress update emitted during a streaming download when progress is
/// requested. Counts are in *chunks*, not bytes — the byte denominator is the
/// download's total size (`x-content-length` over gRPC, the NDJSON `meta` frame
/// over REST). `total` is 0 while still unknown (mid DataMap-resolution).
///
/// `phase` is one of:
/// - `"resolving_map"` — walking the hierarchical DataMap to learn the chunk count
/// - `"resolved"` — DataMap resolved, `total` now holds the real chunk count
/// - `"fetching"` — fetching data chunks; `fetched`/`total` advance the bar
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DownloadProgress {
    pub phase: String,
    pub fetched: u64,
    pub total: u64,
}

/// One frame of a progress-enabled streaming download: the total size, a
/// plaintext data chunk, or a [`DownloadProgress`] update. Returned by the
/// `*_with_progress` streaming methods; the plain `data_stream` /
/// `data_stream_public` methods stay a pure `Stream<Bytes>` for callers that
/// don't need progress.
#[derive(Debug, Clone)]
pub enum DownloadFrame {
    /// Total download size in *bytes* — the progress *denominator*, surfaced
    /// from the gRPC `x-content-length` response metadata or the REST NDJSON
    /// `meta` frame. Emitted at most once, before any data, when the daemon
    /// reports it. Pair it with the byte count of the [`Data`](Self::Data)
    /// frames (or with [`DownloadProgress`] chunk counts) to render a
    /// byte-accurate progress bar.
    Meta(u64),
    Data(bytes::Bytes),
    Progress(DownloadProgress),
}

// ── Pointers (ADR-0016 / ADR-0018 in ant-node) ──
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; its target (a chunk, such as
// a public file's data map, or another pointer) can be changed by the owner.
// antd signs with owner keys it loaded at startup (`--pointer-keys`), so a
// write names the pointer by its address (`owner`), never by a key.
//
// Every write pays, and every attempt pays again: do not retry a create,
// update or transfer automatically.

/// What a pointer's target is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PointerKind {
    /// An immutable chunk, such as a public file's data map. The default.
    #[default]
    Chunk,
    /// Another pointer: a forwarding the owner can still change. Use a
    /// transfer to hand a pointer over for good.
    Pointer,
}

impl PointerKind {
    /// Serialize to the wire string the daemon expects.
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Chunk => "chunk",
            Self::Pointer => "pointer",
        }
    }

    /// The kind a raw target tag names, if this SDK knows it (`0` chunk,
    /// `1` pointer).
    pub fn from_tag(tag: u8) -> Option<Self> {
        match tag {
            0 => Some(Self::Chunk),
            1 => Some(Self::Pointer),
            _ => None,
        }
    }
}

/// The write a [`pointer_prepare`](crate::Client::pointer_prepare) signs for an
/// external signer to pay.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PointerOp {
    /// Create the pointer at `target`. Refused if it already exists.
    Create { target: String, kind: PointerKind },
    /// Point the pointer at `target`, creating it if it does not exist.
    Update { target: String, kind: PointerKind },
    /// Hand the pointer over for good to the pointer at `recipient`, which
    /// must already exist. Irreversible once stored.
    Transfer { recipient: String },
}

/// A pointer the daemon holds an owner key for.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerKey {
    /// The pointer's address, derived from the owner key.
    pub address: String,
}

/// The state a pointer write stored.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerWriteResult {
    pub address: String,
    pub state_id: String,
    /// The state's counter. A final state (a transfer) sits at `u64::MAX`.
    pub counter: u64,
}

/// A pointer's current state, as the network serves it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerRecord {
    pub address: String,
    /// The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
    /// derived from it, so it is the proof of who owns the pointer.
    pub owner: String,
    pub counter: u64,
    /// `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not
    /// know; [`kind_tag`](Self::kind_tag) carries the raw value either way.
    pub kind: String,
    pub kind_tag: u8,
    pub target: String,
    pub state_id: String,
    /// The state is at the final counter: nothing can replace it.
    pub is_final: bool,
    /// The pointer this one was handed over to, when its final state is a
    /// transfer.
    pub transferred_to: Option<String>,
}

impl PointerRecord {
    /// The target's kind, if this SDK knows its tag.
    pub fn target_kind(&self) -> Option<PointerKind> {
        PointerKind::from_tag(self.kind_tag)
    }
}

/// Where a chain of pointers ends.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerResolved {
    /// `"chunk"`, or `"unknown"` for a target kind the daemon does not know.
    pub kind: String,
    pub kind_tag: u8,
    pub target: String,
}

/// Where a pointer stands with respect to finality, as its whole close group
/// reports it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PointerFinalityStatus {
    /// No peer that answered holds a final state: the owner can still move
    /// the pointer. Rules a final state out only when every peer answered.
    Open,
    /// One final state, not yet held by a majority: a transfer still
    /// spreading, or a write that fell short.
    Settling,
    /// One final state held by a majority, but not every peer answered, so a
    /// rival could still be unseen. Ask again.
    Unconfirmed,
    /// One final state held by a majority, every peer answered, no rival.
    /// The only status a recipient should rely on.
    Final,
    /// The owner signed two or more different final states.
    Forked,
    /// A status this SDK does not know (a newer daemon).
    Unknown(String),
}

impl PointerFinalityStatus {
    /// Parse the daemon's wire string.
    pub fn from_wire(s: &str) -> Self {
        match s {
            "open" => Self::Open,
            "settling" => Self::Settling,
            "unconfirmed" => Self::Unconfirmed,
            "final" => Self::Final,
            "forked" => Self::Forked,
            other => Self::Unknown(other.to_string()),
        }
    }
}

/// One final state, as a finality check reports it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerFinalState {
    pub state_id: String,
    pub kind: String,
    pub kind_tag: u8,
    pub target: String,
    /// How many peers of the close group hold it.
    pub holders: u32,
    pub transferred_to: Option<String>,
}

/// The answer to a pointer finality check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PointerFinality {
    pub address: String,
    /// Peers in the close group.
    pub group: u32,
    /// Peers that answered.
    pub answered: u32,
    pub status: PointerFinalityStatus,
    /// [`Open`](PointerFinalityStatus::Open) only: the counter a read would
    /// return, if any state is corroborated.
    pub counter: Option<u64>,
    /// `Settling`, `Unconfirmed` and `Final`: the one final state seen.
    pub state: Option<PointerFinalState>,
    /// `Forked` only: every final state seen, most-held first.
    pub states: Vec<PointerFinalState>,
    /// `Forked` only: the state a majority holds, which reads return.
    pub majority: Option<PointerFinalState>,
    /// The pointer this one was handed over to, once that is beyond dispute
    /// (status `Final`).
    pub transferred_to: Option<String>,
}

impl PointerFinality {
    /// One final state, held by a majority, with every peer answering and no
    /// rival seen.
    pub fn is_final(&self) -> bool {
        self.status == PointerFinalityStatus::Final
    }
}

/// What a transfer stored, and where the close group says it stands.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PointerTransferResult {
    pub address: String,
    pub state_id: String,
    /// The close group's view once the write landed. `None` when that check
    /// failed (see `finality_error`), which does not undo the transfer: it is
    /// stored and final. Ask again with `pointer_finality`.
    pub finality: Option<PointerFinality>,
    pub finality_error: Option<String>,
}

/// Whose pointer decides what an address resolves to, after every transfer.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerController {
    pub pointer: String,
    /// Every pointer the address was handed over to, in order.
    pub transfers: Vec<String>,
    /// `pointer` is final without being handed over: nobody can move it.
    pub frozen: bool,
}

/// A pointer write signed by the daemon and quoted for an external signer.
/// Pay `payments` with `payForQuotes()`, then call `pointer_finalize`.
///
/// While it awaits payment, other writes to the pointer answer
/// [`AntdError::Conflict`](crate::AntdError::Conflict) until it is finalized
/// or expires.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PointerPrepareResult {
    pub upload_id: String,
    /// `"create"`, `"update"` or `"transfer"`.
    pub op: String,
    pub address: String,
    pub state_id: String,
    pub counter: u64,
    /// Always `"wave_batch"`: a pointer state is paid with one quote.
    pub payment_type: String,
    pub payments: Vec<PaymentInfo>,
    pub total_amount: String,
    pub payment_vault_address: String,
    pub payment_token_address: String,
    pub rpc_url: String,
    /// Populated when requested with
    /// [`PrepareOptions::include_signed_quotes`].
    pub signed_quotes: Vec<SignedQuoteEntry>,
}

/// The state a pointer finalize stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PointerFinalizeResult {
    pub address: String,
    pub state_id: String,
    pub counter: u64,
    /// Transfers only: where the close group says the transfer stands.
    pub finality: Option<PointerFinality>,
}

/// Parse a pointer counter. The daemon sends counters as decimal strings,
/// since a final state's `u64::MAX` is past what a JSON number keeps exactly
/// in several languages; Rust reads it into a `u64` losslessly.
pub(crate) fn parse_counter(field: &str, value: &str) -> Result<u64, crate::AntdError> {
    value.parse().map_err(|_| {
        crate::AntdError::Internal(format!(
            "invalid pointer {field} {value:?}: expected a decimal u64"
        ))
    })
}
