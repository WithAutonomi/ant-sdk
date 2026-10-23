"""Dataclass models for antd SDK request/response types."""

from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum


class PaymentMode(str, Enum):
    """Payment-batching strategy for uploads.

    The mode controls how on-chain chunk payments are bundled:

    - ``AUTO``    -- server picks (merkle for 64+ chunks, single otherwise).
    - ``MERKLE``  -- force merkle-batch (saves gas, min 2 chunks).
    - ``SINGLE``  -- force per-chunk payments (works for any chunk count).
    """

    AUTO = "auto"
    MERKLE = "merkle"
    SINGLE = "single"


@dataclass(frozen=True)
class HealthStatus:
    """Health check result from the antd daemon.

    The diagnostic fields (version, evm_network, uptime_seconds, build_commit,
    payment_token_address, payment_vault_address) were added in antd 0.4.0.
    They default to empty/zero so the dataclass remains constructable when
    talking to an older daemon that doesn't report them.
    """
    ok: bool
    network: str    # "default", "local", "alpha"
    version: str = ""                  # antd crate version, e.g. "0.4.0"
    evm_network: str = ""              # "arbitrum-one", "arbitrum-sepolia", "local", "custom"
    uptime_seconds: int = 0            # seconds since the daemon process started
    build_commit: str = ""             # short git SHA, "" if unknown
    payment_token_address: str = ""    # "" if unconfigured
    payment_vault_address: str = ""    # "" if unconfigured


@dataclass(frozen=True)
class PutResult:
    """Result of a single-chunk put (used by ``chunk_put``).

    Data and file puts return richer types (``DataPutResult`` /
    ``DataPutPublicResult`` / ``FilePutResult`` / ``FilePutPublicResult``).
    """
    cost: str       # atto tokens as string
    address: str    # hex


@dataclass(frozen=True)
class DataPutResult:
    """Result of a private data put.

    The DataMap is returned to the caller; it is NOT stored on-network. The
    REST transport populates ``chunks_stored`` and ``payment_mode_used``; the
    gRPC transport currently leaves them empty (proto ``PutDataResponse``
    only carries ``data_map``).
    """
    data_map: str           # hex
    chunks_stored: int = 0
    payment_mode_used: str = ""    # "auto", "merkle", or "single"
    sha256: str | None = None      # the plaintext's SHA-256 (hex); None on antd < 0.17.0


@dataclass(frozen=True)
class DataPutPublicResult:
    """Result of a public data put.

    The DataMap is stored on-network as an additional chunk; ``address`` is
    the shareable retrieval handle. REST populates ``chunks_stored`` and
    ``payment_mode_used``; gRPC currently leaves them empty.
    """
    address: str            # hex
    chunks_stored: int = 0
    payment_mode_used: str = ""
    sha256: str | None = None      # the plaintext's SHA-256 (hex); None on antd < 0.17.0


@dataclass(frozen=True)
class FilePutResult:
    """Result of a private file upload.

    The DataMap is returned to the caller; it is NOT stored on-network.
    """
    data_map: str              # hex-encoded msgpack DataMap
    storage_cost_atto: str     # "0" if all chunks already existed
    gas_cost_wei: str          # decimal string
    chunks_stored: int         # number of chunks stored on the network
    payment_mode_used: str     # "auto", "merkle", or "single"
    sha256: str | None = None  # the plaintext's SHA-256 (hex); None on antd < 0.17.0


@dataclass(frozen=True)
class FilePutPublicResult:
    """Result of a public file upload.

    The DataMap is stored on-network as an additional chunk; ``address`` is
    the shareable retrieval handle.
    """
    address: str               # hex network address of the stored DataMap
    storage_cost_atto: str     # "0" if all chunks already existed
    gas_cost_wei: str          # decimal string
    chunks_stored: int         # number of chunks stored on the network
    payment_mode_used: str     # "auto", "merkle", or "single"
    sha256: str | None = None  # the plaintext's SHA-256 (hex); None on antd < 0.17.0


@dataclass(frozen=True)
class WalletAddress:
    """Wallet address from the antd daemon."""
    address: str    # hex, e.g. "0x..."


@dataclass(frozen=True)
class WalletBalance:
    """Wallet balance from the antd daemon."""
    balance: str        # atto tokens as string
    gas_balance: str    # atto gas tokens as string


@dataclass(frozen=True)
class PaymentInfo:
    """A single payment required for an upload."""
    quote_hash: str      # hex
    rewards_address: str # hex
    amount: str          # atto tokens as string


@dataclass(frozen=True)
class CandidateNodeEntry:
    """A candidate node within a merkle payment pool."""
    rewards_address: str = ""
    amount: str = ""


@dataclass(frozen=True)
class PoolCommitmentEntry:
    """A pool commitment containing candidate nodes for merkle batch payment."""
    pool_hash: str = ""
    candidates: list[CandidateNodeEntry] = field(default_factory=list)


@dataclass(frozen=True)
class PrepareUploadResult:
    """Result of preparing an upload for external signing."""
    upload_id: str                    # hex identifier
    payments: list[PaymentInfo] = field(default_factory=list)
    total_amount: str = ""
    payment_vault_address: str = ""   # payment vault contract address
    payment_token_address: str = ""   # token contract address
    rpc_url: str = ""                 # EVM RPC URL
    payment_type: str = ""            # "wave_batch" or "merkle_batch"
    depth: int = 0                    # merkle tree depth
    pool_commitments: list[PoolCommitmentEntry] = field(default_factory=list)
    merkle_payment_timestamp: int = 0
    # Already-stored preflight (added in antd 0.10.0). Older daemons omit these
    # and they default to 0. total_chunks includes already-stored chunks; the
    # external signer pays for (total_chunks - already_stored_count) chunks.
    total_chunks: int = 0
    already_stored_count: int = 0


@dataclass(frozen=True)
class FinalizeUploadResult:
    """Result of finalizing an externally-signed upload."""
    address: str         # hex address of stored data
    chunks_stored: int = 0
    data_map: str = ""           # hex-encoded msgpack DataMap (always returned)
    data_map_address: str = ""   # set when prepare used visibility="public" (the DataMap chunk was paid + stored in the same external-signer batch)
    sha256: str | None = None    # the plaintext's SHA-256 (hex); None on antd < 0.17.0


@dataclass(frozen=True)
class PrepareChunkResult:
    """Result of preparing a single-chunk external-signer publish.

    When `already_stored` is True the chunk is already on-network and no
    payment / finalize step is needed — `upload_id` and the payment fields
    are empty.
    """
    address: str
    already_stored: bool = False
    upload_id: str = ""
    payment_type: str = ""            # "wave_batch" (only mode for single chunks)
    payments: list[PaymentInfo] = field(default_factory=list)
    total_amount: str = ""
    payment_vault_address: str = ""
    payment_token_address: str = ""
    rpc_url: str = ""


@dataclass(frozen=True)
class UploadCostEstimate:
    """Pre-upload cost breakdown returned by estimate_data_cost / estimate_file_cost.

    The server samples up to 5 chunk addresses and extrapolates the storage
    cost. Gas is an advisory heuristic, not a live gas-oracle query.
    """
    cost: str                     # storage cost in atto tokens
    file_size: int                # original file size in bytes
    chunk_count: int              # number of data chunks
    estimated_gas_cost_wei: str   # advisory gas heuristic in wei
    payment_mode: str             # "auto" | "merkle" | "single"


# --- Manifests (ADR-0006 `.ant` files and `ant://` links) ---
#
# Sizes are Python ints, and an unset size is None, never 0: 0 is the size
# of an empty file. The same goes for every optional field below, on both
# transports (REST omits it, gRPC leaves a proto3 optional unset or sends an
# empty string).


@dataclass(frozen=True, kw_only=True)
class ManifestEntryInput:
    """One file for ``build_manifest``. Set exactly one of ``data_map`` or
    ``address``; the client refuses both or neither before sending.

    - ``data_map``: a hex DataMap, as the upload methods return it. The entry
      embeds it, so the manifest is the key to the file.
    - ``address``: a public file's DataMap address (hex, 32 bytes).
    - ``path``: the relative path the entry extracts under, subject to the
      portable path rules. ``None``: it extracts under its content address.
    - ``size``: the plaintext size to record, as given (the creator's claim).
      ``None``: none is recorded; readers take the exact size from an
      embedded root DataMap.
    - ``sha256``: the plaintext's SHA-256 (hex) to record, passed through as
      given (the daemon validates it and answers 400 for a malformed one).
      ``None`` or ``""``: none is recorded. Needs antd 0.17.0 or later.
    """
    data_map: str | None = None
    address: str | None = None
    path: str | None = None
    size: int | None = None
    sha256: str | None = None


@dataclass(frozen=True)
class ManifestEntryInfo:
    """What a manifest says about one entry."""
    effective_name: str = ""          # path, or the content address in hex when there is none
    path: str | None = None
    size: int | None = None           # the size recorded in the manifest: the creator's claim
    kind: str = ""                    # "embedded" or "public"
    # Hex. The file's public DataMap address, whether or not it was ever made
    # public; the same for private and public uploads of one file.
    content_address: str = ""
    # The embedded DataMap in the hex form the download methods accept.
    # Decode only; None for public entries.
    data_map: str | None = None
    # Exact plaintext size: from an embedded root DataMap, or after a
    # resolving decode.
    exact_size: int | None = None
    error: str | None = None          # why a resolving decode failed for this entry
    # The plaintext's SHA-256 (hex) the manifest records for the entry; None
    # when it records none or the daemon is older than 0.17.0.
    sha256: str | None = None


@dataclass(frozen=True)
class BuiltManifest:
    """Result of ``build_manifest``."""
    manifest: bytes                   # the `.ant` bytes (raw; base64 is a REST wire detail)
    # The `ant://manifest/` link, set only when it fits the recommended
    # 1,500 bytes.
    link: str | None = None
    entries: list[ManifestEntryInfo] = field(default_factory=list)  # in encoded order (sorted by effective name)


@dataclass(frozen=True)
class DecodedManifest:
    """Result of ``decode_manifest`` and ``decode_manifest_link``."""
    # "manifest", or "file_link" for a file link or bare address (reported as
    # one public entry with no path).
    source: str
    name: str | None = None           # suggested root directory name
    torrent_info_hash_v1: str | None = None   # hex
    torrent_info_hash_v2: str | None = None   # hex
    entries: list[ManifestEntryInfo] = field(default_factory=list)


@dataclass(frozen=True)
class DownloadProgress:
    """A fetch-progress update emitted during a streaming download when progress
    is requested. Counts are in *chunks*, not bytes — the byte denominator is the
    download's total size (the x-content-length header over gRPC, the leading
    NDJSON ``meta`` frame over REST). ``total`` is 0 while still unknown (mid
    DataMap-resolution).

    ``phase`` is one of:

    - ``"resolving_map"`` — walking the hierarchical DataMap to learn the count
    - ``"resolved"`` — DataMap resolved, ``total`` now holds the real chunk count
    - ``"fetching"`` — fetching data chunks; ``fetched``/``total`` advance the bar
    """
    phase: str
    fetched: int
    total: int


@dataclass(frozen=True)
class DownloadFrame:
    """One frame of a progress-enabled streaming download: the total size, a
    plaintext data chunk, or a :class:`DownloadProgress` update. At most one of
    ``meta``, ``data``, or ``progress`` is set. Yielded by the ``*_with_progress``
    streaming methods; the plain ``data_stream`` methods stay a pure byte stream
    for callers that don't need progress.
    """
    data: bytes | None = None
    progress: DownloadProgress | None = None
    meta: int | None = None

    @property
    def is_progress(self) -> bool:
        """True if this frame carries a progress update rather than data bytes."""
        return self.progress is not None

    @property
    def is_meta(self) -> bool:
        """True if this frame carries the total-size denominator (in bytes).

        Surfaced from the gRPC ``x-content-length`` response metadata or the REST
        NDJSON ``meta`` frame. Emitted at most once, before any data.
        """
        return self.meta is not None


# --- Pointers (ADR-0016 / ADR-0018 in ant-node) ---
#
# A pointer is a small, owner-signed, mutable reference. Its address is derived
# from the owner's key and never changes; its target (a chunk, such as a public
# file's data map, or another pointer) can be changed by the owner. antd signs
# with owner keys it loaded at startup (``--pointer-keys``), so a write names
# the pointer by its address (``owner``), never by a key.
#
# Every write pays, and every attempt pays again: the SDK never retries a
# create, update, transfer or finalize, and callers should not either.
#
# Counters are Python ``int``s. The daemon sends them as decimal strings
# because a final state sits at u64::MAX (POINTER_FINAL_COUNTER), past what a
# JSON number keeps exactly in several languages; anything that is not a
# decimal u64 raises InternalError rather than reading as 0.

POINTER_FINAL_COUNTER = 2**64 - 1
"""The counter of a pointer's final state, after a transfer or a freeze:
nothing can replace it."""


class PointerKind(str, Enum):
    """What a pointer's target is.

    - ``CHUNK``   -- an immutable chunk, such as a public file's data map
      (a ``data_put_public`` / ``file_put_public`` address). The default.
    - ``POINTER`` -- another pointer: a forwarding the owner can still
      change. Use ``pointer_transfer`` to hand a pointer over for good.
    """

    CHUNK = "chunk"
    POINTER = "pointer"

    @classmethod
    def from_tag(cls, tag: int) -> PointerKind | None:
        """The kind a raw target tag names, if this SDK knows it (``0`` chunk,
        ``1`` pointer); ``None`` otherwise."""
        return {0: cls.CHUNK, 1: cls.POINTER}.get(tag)


class PointerOp(str, Enum):
    """The write ``pointer_prepare`` signs for an external signer to pay."""

    CREATE = "create"      # needs ``target`` (and optionally ``kind``)
    UPDATE = "update"      # needs ``target`` (and optionally ``kind``)
    TRANSFER = "transfer"  # needs ``recipient``


class PointerFinalityStatus(str, Enum):
    """Where a pointer stands with respect to finality, as its whole close
    group reports it.

    - ``OPEN``        -- no peer that answered holds a final state: the owner
      can still move the pointer.
    - ``SETTLING``    -- one final state, not yet held by a majority.
    - ``UNCONFIRMED`` -- one final state held by a majority, but not every
      peer answered, so a rival could still be unseen. Ask again.
    - ``FINAL``       -- one final state held by a majority, every peer
      answered, no rival. The only status a recipient should rely on.
    - ``FORKED``      -- the owner signed two or more different final states.
    - ``UNKNOWN``     -- a status this SDK does not know (a newer daemon);
      :attr:`PointerFinality.raw_status` keeps the daemon's string.
    """

    OPEN = "open"
    SETTLING = "settling"
    UNCONFIRMED = "unconfirmed"
    FINAL = "final"
    FORKED = "forked"
    UNKNOWN = "unknown"

    @classmethod
    def from_wire(cls, value: object) -> PointerFinalityStatus:
        """Parse the daemon's status string. Anything unrecognised is
        :attr:`UNKNOWN`, never an error."""
        for status in cls:
            if status is not cls.UNKNOWN and status.value == value:
                return status
        return cls.UNKNOWN


@dataclass(frozen=True)
class PointerWriteResult:
    """The state a pointer write (``pointer_create`` / ``pointer_update``)
    stored."""
    address: str    # hex, 64 chars, no 0x
    state_id: str   # hex; the identifier the state was paid against
    counter: int    # 0..=POINTER_FINAL_COUNTER


@dataclass(frozen=True)
class PointerRecord:
    """A pointer's current state, as the network serves it (``pointer_get``)."""
    address: str
    owner: str      # the owner's ML-DSA-65 public key (hex, 1,952 bytes); the address derives from it
    counter: int    # POINTER_FINAL_COUNTER once transferred or frozen
    kind: str       # "chunk", "pointer", or "unknown" for a kind the daemon does not know
    kind_tag: int   # the raw target kind, whatever ``kind`` says
    target: str     # hex
    state_id: str   # hex
    is_final: bool  # at the final counter: nothing can replace this state
    transferred_to: str | None = None  # the pointer this one was handed over to, if any

    @property
    def target_kind(self) -> PointerKind | None:
        """The target's kind, if this SDK knows its tag."""
        return PointerKind.from_tag(self.kind_tag)


@dataclass(frozen=True)
class PointerTarget:
    """Where a chain of pointers ends (``pointer_resolve``)."""
    kind: str       # "chunk", or "unknown" for a kind the daemon does not know
    kind_tag: int
    target: str     # hex

    @property
    def target_kind(self) -> PointerKind | None:
        """The target's kind, if this SDK knows its tag."""
        return PointerKind.from_tag(self.kind_tag)


@dataclass(frozen=True)
class PointerFinalState:
    """One final state, as a finality check reports it."""
    state_id: str
    kind: str
    kind_tag: int
    target: str
    holders: int    # peers of the close group that hold it
    transferred_to: str | None = None


@dataclass(frozen=True)
class PointerFinality:
    """The whole close group's view of a pointer (``pointer_finality``).

    Check it before relying on a transfer: only ``status ==
    PointerFinalityStatus.FINAL`` (:attr:`is_final`) means one final state,
    held by a majority, with every peer answering and no rival seen.
    """
    address: str
    group: int      # peers in the close group
    answered: int   # peers that answered
    status: PointerFinalityStatus
    raw_status: str  # the daemon's status string, kept for UNKNOWN
    counter: int | None = None  # OPEN only: the counter a read would return, if any state is corroborated
    state: PointerFinalState | None = None  # SETTLING / UNCONFIRMED / FINAL: the one final state seen
    states: list[PointerFinalState] = field(default_factory=list)  # FORKED: every final state seen, most-held first
    majority: PointerFinalState | None = None  # FORKED: the state a majority holds, which reads return
    transferred_to: str | None = None  # set once a transfer is beyond dispute (FINAL)

    @property
    def is_final(self) -> bool:
        """One final state, held by a majority, every peer answered, no rival."""
        return self.status is PointerFinalityStatus.FINAL


@dataclass(frozen=True)
class PointerController:
    """Whose pointer decides what an address resolves to, after following
    every transfer (``pointer_controller``)."""
    pointer: str
    transfers: list[str] = field(default_factory=list)  # every pointer handed over to, in order
    frozen: bool = False  # ``pointer`` is final without being handed over: nobody can move it


@dataclass(frozen=True)
class PointerTransferResult:
    """What a transfer stored, and where the close group says it stands.

    ``finality`` is ``None`` when that check failed (``finality_error`` says
    why), which does not undo the transfer: it is stored and final either way.
    Ask again with ``pointer_finality``.
    """
    address: str
    state_id: str
    finality: PointerFinality | None = None
    finality_error: str | None = None


@dataclass(frozen=True)
class SignedQuoteEntry:
    """One ``payments`` quote in full signed form, for offline verification.

    ``quote`` and ``commitment_sidecar`` are opaque base64 blobs (msgpack
    inside); only antd parses them. Over gRPC the raw bytes are base64-encoded
    so both transports return the same value.
    """
    quote_hash: str   # hex with 0x prefix, matches the payments entry
    quote: str        # base64(msgpack signed PaymentQuote)
    commitment_sidecar: str | None = None  # base64(msgpack StorageCommitment); None for baseline quotes


@dataclass(frozen=True)
class PointerPrepareResult:
    """A pointer write signed by the daemon and quoted for an external signer
    (``pointer_prepare``). Pay ``payments`` with ``payForQuotes()``, then call
    ``pointer_finalize``.

    While it awaits payment, other writes to the pointer raise
    :class:`~antd.exceptions.ConflictError` until it is finalized or expires
    (one hour).
    """
    upload_id: str
    op: str         # "create", "update" or "transfer"
    address: str
    state_id: str
    counter: int
    payment_type: str = ""   # always "wave_batch": a pointer state is paid with one quote
    payments: list[PaymentInfo] = field(default_factory=list)
    total_amount: str = ""   # atto tokens, decimal string
    payment_vault_address: str = ""
    payment_token_address: str = ""
    rpc_url: str = ""
    signed_quotes: list[SignedQuoteEntry] = field(default_factory=list)  # with include_signed_quotes=True


@dataclass(frozen=True)
class PointerFinalizeResult:
    """The state a pointer finalize stored. ``finality`` is set for a
    transfer."""
    address: str
    state_id: str
    counter: int
    finality: PointerFinality | None = None
