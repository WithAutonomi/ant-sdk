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
    """
    data_map: str | None = None
    address: str | None = None
    path: str | None = None
    size: int | None = None


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
