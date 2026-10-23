package com.autonomi.sdk

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Health check result from the antd daemon.
 *
 * The diagnostic fields ([version], [evmNetwork], [uptimeSeconds],
 * [buildCommit], [paymentTokenAddress], [paymentVaultAddress]) were added in
 * antd 0.4.0. They default to "" / 0 so the type stays constructable from a
 * pre-0.4.0 daemon's response.
 */
data class HealthStatus(
    val ok: Boolean,
    val network: String,
    val version: String = "",
    val evmNetwork: String = "",
    val uptimeSeconds: ULong = 0u,
    val buildCommit: String = "",
    val paymentTokenAddress: String = "",
    val paymentVaultAddress: String = "",
)

/**
 * Payment-batching strategy for uploads.
 *
 * - [AUTO]   — server picks (merkle for 64+ chunks, single otherwise).
 * - [MERKLE] — force merkle-batch (saves gas, min 2 chunks).
 * - [SINGLE] — force per-chunk payments (works for any chunk count).
 *
 * Pass as a typed parameter to put/cost methods. The client serializes the
 * enum to the wire string at the request boundary.
 */
enum class PaymentMode(val wire: String) {
    AUTO("auto"),
    MERKLE("merkle"),
    SINGLE("single"),
}

/** Result of a `chunkPut` operation. The DataMap concept doesn't apply at chunk level. */
data class PutResult(val cost: String, val address: String)

/**
 * Result of a private data put. The DataMap is returned to the caller; it is
 * NOT stored on-network. REST populates [chunksStored] / [paymentModeUsed];
 * gRPC currently leaves them at their defaults (proto `PutDataResponse`
 * only carries `data_map`).
 */
data class DataPutResult(
    val dataMap: String,
    val chunksStored: ULong = 0u,
    val paymentModeUsed: String = "",
    /**
     * The plaintext's SHA-256 (lowercase hex, 64 characters). Requires antd
     * 0.17.0 or later; null on older daemons.
     */
    val sha256: String? = null,
)

/**
 * Result of a public data put. The DataMap is stored on-network as an extra
 * chunk; [address] is the shareable retrieval handle. REST populates
 * [chunksStored] / [paymentModeUsed]; gRPC currently leaves them at their
 * defaults.
 */
data class DataPutPublicResult(
    val address: String,
    val chunksStored: ULong = 0u,
    val paymentModeUsed: String = "",
    /**
     * The plaintext's SHA-256 (lowercase hex, 64 characters). Requires antd
     * 0.17.0 or later; null on older daemons.
     */
    val sha256: String? = null,
)

/**
 * Result of a private file upload. The DataMap is returned to the caller;
 * it is NOT stored on-network.
 */
data class FilePutResult(
    val dataMap: String,
    val storageCostAtto: String,
    val gasCostWei: String,
    val chunksStored: ULong,
    val paymentModeUsed: String,
    /**
     * The plaintext's SHA-256 (lowercase hex, 64 characters). Requires antd
     * 0.17.0 or later; null on older daemons.
     */
    val sha256: String? = null,
)

/**
 * Result of a public file upload. The DataMap is stored on-network as an
 * extra chunk; [address] is the shareable retrieval handle.
 */
data class FilePutPublicResult(
    val address: String,
    val storageCostAtto: String,
    val gasCostWei: String,
    val chunksStored: ULong,
    val paymentModeUsed: String,
    /**
     * The plaintext's SHA-256 (lowercase hex, 64 characters). Requires antd
     * 0.17.0 or later; null on older daemons.
     */
    val sha256: String? = null,
)

/** Wallet address response. */
data class WalletAddress(val address: String)

/** Wallet balance response. */
data class WalletBalance(val balance: String, val gasBalance: String)

/** A single payment required for an upload. */
data class PaymentInfo(val quoteHash: String, val rewardsAddress: String, val amount: String)

/** A candidate node entry within a merkle pool commitment. */
data class CandidateNodeEntry(val rewardsAddress: String, val amount: String)

/** A pool commitment entry containing candidates for merkle batch payments. */
data class PoolCommitmentEntry(val poolHash: String, val candidates: List<CandidateNodeEntry>)

/**
 * Result of preparing an upload for external signing.
 * [paymentType] is "wave_batch" or "merkle" -- determines which fields are populated
 * and which contract call the external signer must make.
 */
data class PrepareUploadResult(
    val uploadId: String,
    val payments: List<PaymentInfo>,
    val totalAmount: String,
    val paymentVaultAddress: String,
    val paymentTokenAddress: String,
    val rpcUrl: String,
    val paymentType: String = "wave_batch",
    val depth: Int? = null,
    val poolCommitments: List<PoolCommitmentEntry>? = null,
    val merklePaymentTimestamp: Long? = null,
    // Already-stored preflight (added in antd 0.10.0). 0 on older daemons. The
    // external signer pays for (totalChunks - alreadyStoredCount) chunks.
    val totalChunks: Long = 0,
    val alreadyStoredCount: Long = 0,
)

/**
 * Result of finalizing an externally-signed upload.
 *
 * [dataMap] is the hex-encoded serialized DataMap (always populated).
 * [dataMapAddress] is set when prepare was called with `visibility="public"` —
 * the DataMap chunk was paid + stored in the same external-signer batch and
 * the address is the shareable retrieval handle. Empty on pre-0.6.1 daemons
 * or for private uploads.
 */
data class FinalizeUploadResult(
    @SerialName("address") val address: String,
    @SerialName("chunks_stored") val chunksStored: Long,
    @SerialName("data_map") val dataMap: String = "",
    @SerialName("data_map_address") val dataMapAddress: String = "",
    /**
     * The plaintext's SHA-256 (lowercase hex, 64 characters). Requires antd
     * 0.17.0 or later; null on older daemons.
     */
    @SerialName("sha256") val sha256: String? = null,
)

/**
 * Result of finalizing a merkle batch upload.
 *
 * See [FinalizeUploadResult] for [dataMap] / [dataMapAddress] semantics.
 */
data class FinalizeMerkleUploadResult(
    @SerialName("address") val address: String,
    @SerialName("chunks_stored") val chunksStored: Long,
    @SerialName("data_map") val dataMap: String = "",
    @SerialName("data_map_address") val dataMapAddress: String = "",
    /**
     * The plaintext's SHA-256 (lowercase hex, 64 characters). Requires antd
     * 0.17.0 or later; null on older daemons.
     */
    @SerialName("sha256") val sha256: String? = null,
)

/**
 * Result of preparing a single-chunk external-signer publish via
 * `POST /v1/chunks/prepare`.
 *
 * When [alreadyStored] is `true` the chunk is already on-network and no
 * payment / finalize step is needed — [uploadId] and the payment fields are
 * empty. Otherwise the wave-batch payment fields describe what the external
 * signer must submit before calling `finalizeChunkUpload`.
 */
data class PrepareChunkResult(
    val address: String,
    val alreadyStored: Boolean = false,
    val uploadId: String = "",
    val paymentType: String = "",
    val payments: List<PaymentInfo> = emptyList(),
    val totalAmount: String = "",
    val paymentVaultAddress: String = "",
    val paymentTokenAddress: String = "",
    val rpcUrl: String = "",
)

/**
 * A fetch-progress update emitted during a streaming download when progress is
 * requested. Counts are in *chunks*, not bytes — the byte denominator is the
 * download's total size (`x-content-length` over gRPC, the NDJSON `meta` frame
 * over REST). [total] is 0 while still unknown (mid DataMap-resolution).
 *
 * [phase] is one of:
 * - `"resolving_map"` — walking the hierarchical DataMap to learn the chunk count
 * - `"resolved"` — DataMap resolved, [total] now holds the real chunk count
 * - `"fetching"` — fetching data chunks; [fetched]/[total] advance the bar
 */
data class DownloadProgress(
    val phase: String,
    val fetched: ULong,
    val total: ULong,
)

/**
 * One frame of a progress-enabled streaming download: the total size
 * ([totalSize] set), a plaintext data chunk ([data] set), or a
 * [DownloadProgress] update ([progress] set). Returned by the `*WithProgress`
 * streaming methods; the plain `dataStream` / `dataStreamPublic` methods stay a
 * pure byte stream for callers that don't need progress.
 */
data class DownloadFrame(
    val data: ByteArray? = null,
    val progress: DownloadProgress? = null,
    /**
     * Total download size in *bytes* — the progress *denominator*, surfaced
     * from the gRPC `x-content-length` response metadata or the REST NDJSON
     * `meta` frame. Emitted at most once, before any data, when the daemon
     * reports it. Pair it with the byte count of the [data] frames (or with
     * [DownloadProgress] chunk counts) to render a byte-accurate progress bar.
     */
    val totalSize: ULong? = null,
) {
    /** True when this frame carries a [progress] update rather than [data]. */
    val isProgress: Boolean get() = progress != null

    /** True when this frame carries the [totalSize] byte denominator. */
    val isMeta: Boolean get() = totalSize != null

    // data classes with a ByteArray member need structural equals/hashCode.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DownloadFrame) return false
        if (data != null) {
            if (other.data == null) return false
            if (!data.contentEquals(other.data)) return false
        } else if (other.data != null) return false
        return progress == other.progress && totalSize == other.totalSize
    }

    override fun hashCode(): Int {
        var result = data?.contentHashCode() ?: 0
        result = 31 * result + (progress?.hashCode() ?: 0)
        result = 31 * result + (totalSize?.hashCode() ?: 0)
        return result
    }
}

/**
 * Pre-upload cost breakdown returned by `dataCost` and `fileCost`.
 *
 * The server samples up to 5 chunk addresses and extrapolates the storage
 * cost. Gas is an advisory heuristic, not a live gas-oracle query.
 */
data class UploadCostEstimate(
    val cost: String,
    val fileSize: ULong,
    val chunkCount: UInt,
    val estimatedGasCostWei: String,
    val paymentMode: String,
)

// ── Pointers (ADR-0016 / ADR-0018 in ant-node) ──
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; its target (a chunk, such as
// a public file's data map, or another pointer) can be changed by the owner.
// antd signs with owner keys it loaded at startup (`--pointer-keys`), so a
// write names the pointer by its address (`owner`), never by a key.
//
// Every write pays, and every attempt pays again: do not retry a create,
// update, transfer or finalize automatically.
//
// Counters are [ULong]. The daemon sends them as decimal strings because a
// final state sits at 2^64-1, past what a JSON number keeps exactly in
// several languages; anything that is not a decimal u64 is an error, never 0.

/**
 * What a pointer's target is. [CHUNK] is the default for writes.
 *
 * - [CHUNK]   — an immutable chunk, such as a public file's data map.
 * - [POINTER] — another pointer: a forwarding the owner can still change.
 *   Use `pointerTransfer` to hand a pointer over for good.
 */
enum class PointerKind(val wire: String, val tag: UInt) {
    CHUNK("chunk", 0u),
    POINTER("pointer", 1u),
    ;

    companion object {
        /** The kind a raw target tag names, or null for a tag this SDK does not know. */
        fun fromTag(tag: UInt): PointerKind? = entries.firstOrNull { it.tag == tag }
    }
}

/**
 * The write `pointerPrepare` signs for an external signer to pay.
 */
sealed class PointerOp {
    /** The wire name of the operation: "create", "update" or "transfer". */
    abstract val wire: String

    /** Create the pointer at [target]. Refused if the pointer already exists. */
    data class Create(val target: String, val kind: PointerKind = PointerKind.CHUNK) : PointerOp() {
        override val wire: String get() = "create"
    }

    /** Point the pointer at [target], creating it if it does not exist. */
    data class Update(val target: String, val kind: PointerKind = PointerKind.CHUNK) : PointerOp() {
        override val wire: String get() = "update"
    }

    /**
     * Hand the pointer over for good to the pointer at [recipient], which must
     * already exist. Irreversible once stored.
     */
    data class Transfer(val recipient: String) : PointerOp() {
        override val wire: String get() = "transfer"
    }
}

/** The state a pointer write stored. */
data class PointerWriteResult(
    val address: String,
    /** The identifier the state was paid against (hex). */
    val stateId: String,
    /** The state's counter. A final state (a transfer) sits at [PointerRecord.FINAL_COUNTER]. */
    val counter: ULong,
)

/** A pointer's current state, as the network serves it. */
data class PointerRecord(
    val address: String,
    /**
     * The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
     * derived from it, so it is the proof of who owns the pointer.
     */
    val owner: String,
    val counter: ULong,
    /**
     * `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not
     * know; [kindTag] carries the raw value either way.
     */
    val kind: String,
    val kindTag: UInt,
    val target: String,
    val stateId: String,
    /** The state is at the final counter: it was handed over or frozen, and nothing can replace it. */
    val isFinal: Boolean,
    /** The pointer this one was handed over to, when its final state is a transfer; otherwise null. */
    val transferredTo: String?,
) {
    /** The target's kind, or null if this SDK does not know its tag. */
    val targetKind: PointerKind? get() = PointerKind.fromTag(kindTag)

    companion object {
        /** The counter of a pointer's final state, after a transfer or a freeze: 2^64-1. */
        val FINAL_COUNTER: ULong = ULong.MAX_VALUE
    }
}

/** Where a chain of pointers ends (`pointerResolve`). */
data class PointerTarget(
    /** `"chunk"`, or `"unknown"` for a target kind the daemon does not know. */
    val kind: String,
    val kindTag: UInt,
    val target: String,
) {
    /** The target's kind, or null if this SDK does not know its tag. */
    val targetKind: PointerKind? get() = PointerKind.fromTag(kindTag)
}

/**
 * Where a pointer stands with respect to finality, as its whole close group
 * reports it. [Unknown] carries a status a newer daemon may add, so a `when`
 * over this type stays exhaustive across daemon upgrades.
 */
sealed class PointerFinalityStatus {
    /** The daemon's wire string. */
    abstract val wire: String

    /**
     * No peer that answered holds a final state: the owner can still move the
     * pointer. Rules a final state out only when every peer answered.
     */
    data object Open : PointerFinalityStatus() {
        override val wire: String get() = "open"
    }

    /** One final state, not yet held by a majority: a transfer still spreading, or a write that fell short. */
    data object Settling : PointerFinalityStatus() {
        override val wire: String get() = "settling"
    }

    /**
     * One final state held by a majority, but not every peer answered, so a
     * rival could still be unseen. Ask again.
     */
    data object Unconfirmed : PointerFinalityStatus() {
        override val wire: String get() = "unconfirmed"
    }

    /**
     * One final state held by a majority, every peer answered, no rival. The
     * only status a recipient should rely on.
     */
    data object Final : PointerFinalityStatus() {
        override val wire: String get() = "final"
    }

    /** The owner signed two or more different final states. */
    data object Forked : PointerFinalityStatus() {
        override val wire: String get() = "forked"
    }

    /** A status this SDK does not know (a newer daemon). */
    data class Unknown(override val wire: String) : PointerFinalityStatus()

    companion object {
        /** Parses the daemon's wire string; anything unrecognised is [Unknown]. */
        fun fromWire(s: String): PointerFinalityStatus = when (s) {
            "open" -> Open
            "settling" -> Settling
            "unconfirmed" -> Unconfirmed
            "final" -> Final
            "forked" -> Forked
            else -> Unknown(s)
        }
    }
}

/** One final state, as a finality check reports it. */
data class PointerFinalState(
    val stateId: String,
    val kind: String,
    val kindTag: UInt,
    val target: String,
    /** How many peers of the close group hold it. */
    val holders: UInt,
    val transferredTo: String?,
)

/**
 * The whole close group's view of a pointer's finality (`pointerFinality`).
 * Check it before relying on a transfer: only [PointerFinalityStatus.Final]
 * means the transfer is beyond dispute.
 */
data class PointerFinality(
    val address: String,
    /** Peers in the close group. */
    val group: UInt,
    /** Peers that answered. */
    val answered: UInt,
    val status: PointerFinalityStatus,
    /** [PointerFinalityStatus.Open] only: the counter a read would return, if any state is corroborated. */
    val counter: ULong?,
    /** Settling, unconfirmed and final: the one final state seen. */
    val state: PointerFinalState?,
    /** Forked only: every final state seen, most-held first. */
    val states: List<PointerFinalState>,
    /** Forked only: the state a majority holds, which reads return. */
    val majority: PointerFinalState?,
    /** The pointer this one was handed over to, once that is beyond dispute (status final). */
    val transferredTo: String?,
) {
    /** One final state, held by a majority, with every peer answering and no rival seen. */
    val isFinal: Boolean get() = status == PointerFinalityStatus.Final
}

/** Whose pointer decides what an address resolves to, after following every transfer. */
data class PointerController(
    val pointer: String,
    /** Every pointer the address was handed over to, in order. */
    val transfers: List<String>,
    /** [pointer] is final without being handed over: nobody can move it. */
    val frozen: Boolean,
)

/**
 * What a transfer stored, and where the close group says it stands.
 * [finality] is null when that check failed ([finalityError] says why); the
 * transfer itself is stored and final either way. Ask again with
 * `pointerFinality`.
 */
data class PointerTransferResult(
    val address: String,
    val stateId: String,
    val finality: PointerFinality?,
    val finalityError: String?,
)

/**
 * One `payments[]` quote in full signed form, returned when a prepare asks
 * for `includeSignedQuotes`. Both byte fields are base64 and opaque: only
 * antd parses them.
 */
data class SignedQuoteEntry(
    /** Quote hash (hex with 0x prefix); matches the [PaymentInfo] entry. */
    val quoteHash: String,
    /** base64 of the msgpack-serialized signed PaymentQuote. */
    val quote: String,
    /** base64 of the msgpack-serialized StorageCommitment the quote pins; null for baseline quotes. */
    val commitmentSidecar: String? = null,
)

/**
 * A pointer write signed by the daemon and quoted for an external signer.
 * Pay [payments] with `payForQuotes()`, then call `pointerFinalize`.
 *
 * While it awaits payment, other writes to the pointer throw
 * [ConflictException] until it is finalized or expires (one hour).
 */
data class PointerPrepareResult(
    val uploadId: String,
    /** `"create"`, `"update"` or `"transfer"`. */
    val op: String,
    val address: String,
    val stateId: String,
    val counter: ULong,
    /** Always `"wave_batch"`: a pointer state is paid with one quote. */
    val paymentType: String,
    val payments: List<PaymentInfo>,
    val totalAmount: String,
    val paymentVaultAddress: String,
    val paymentTokenAddress: String,
    val rpcUrl: String,
    /** Populated when the prepare asked for `includeSignedQuotes`. */
    val signedQuotes: List<SignedQuoteEntry> = emptyList(),
)

/** The state a pointer finalize stored. [finality] is set for a transfer. */
data class PointerFinalizeResult(
    val address: String,
    val stateId: String,
    val counter: ULong,
    val finality: PointerFinality?,
)

/**
 * Parses a pointer counter. Strict: only ASCII decimal digits that fit a
 * u64. No sign, no whitespace, no other Unicode digits, and never a silent 0.
 */
internal fun parsePointerCounter(field: String, value: String): ULong {
    val parsed = if (value.isNotEmpty() && value.all { it in '0'..'9' }) value.toULongOrNull() else null
    return parsed ?: throw InternalException("antd: pointer $field \"$value\" is not a decimal counter")
}

/** An optional pointer counter: absent or empty (gRPC's unset) is null; anything else parses strictly. */
internal fun parseOptionalPointerCounter(field: String, value: String?): ULong? =
    if (value.isNullOrEmpty()) null else parsePointerCounter(field, value)

/** An optional address or message: REST sends null, gRPC sends ""; both are null here. */
internal fun String?.nonEmptyOrNull(): String? = if (isNullOrEmpty()) null else this

// ── Internal DTOs for JSON deserialization ──

@Serializable
internal data class HealthResponseDto(
    val status: String? = null,
    val network: String? = null,
    val version: String? = null,
    @SerialName("evm_network") val evmNetwork: String? = null,
    @SerialName("uptime_seconds") val uptimeSeconds: ULong? = null,
    @SerialName("build_commit") val buildCommit: String? = null,
    @SerialName("payment_token_address") val paymentTokenAddress: String? = null,
    @SerialName("payment_vault_address") val paymentVaultAddress: String? = null,
)

internal fun HealthResponseDto.toHealthStatus(): HealthStatus = HealthStatus(
    ok = status == "ok",
    network = network ?: "unknown",
    version = version ?: "",
    evmNetwork = evmNetwork ?: "",
    uptimeSeconds = uptimeSeconds ?: 0u,
    buildCommit = buildCommit ?: "",
    paymentTokenAddress = paymentTokenAddress ?: "",
    paymentVaultAddress = paymentVaultAddress ?: "",
)

@Serializable
internal data class DataPutPublicDto(
    val address: String,
    @SerialName("chunks_stored") val chunksStored: ULong = 0u,
    @SerialName("payment_mode_used") val paymentModeUsed: String = "",
    val sha256: String? = null,
)

@Serializable
internal data class DataPutDto(
    @SerialName("data_map") val dataMap: String,
    @SerialName("chunks_stored") val chunksStored: ULong = 0u,
    @SerialName("payment_mode_used") val paymentModeUsed: String = "",
    val sha256: String? = null,
)

@Serializable
internal data class FilePutPublicDto(
    val address: String,
    @SerialName("storage_cost_atto") val storageCostAtto: String,
    @SerialName("gas_cost_wei") val gasCostWei: String,
    @SerialName("chunks_stored") val chunksStored: ULong,
    @SerialName("payment_mode_used") val paymentModeUsed: String,
    val sha256: String? = null,
)

@Serializable
internal data class FilePutDto(
    @SerialName("data_map") val dataMap: String,
    @SerialName("storage_cost_atto") val storageCostAtto: String,
    @SerialName("gas_cost_wei") val gasCostWei: String,
    @SerialName("chunks_stored") val chunksStored: ULong,
    @SerialName("payment_mode_used") val paymentModeUsed: String,
    val sha256: String? = null,
)

@Serializable
internal data class ChunkPutDto(
    val cost: String = "",
    val address: String,
)

@Serializable
internal data class DataGetDto(
    val data: String,
)

@Serializable
internal data class CostDto(
    val cost: String,
    @SerialName("file_size") val fileSize: ULong = 0u,
    @SerialName("chunk_count") val chunkCount: UInt = 0u,
    @SerialName("estimated_gas_cost_wei") val estimatedGasCostWei: String = "",
    @SerialName("payment_mode") val paymentMode: String = "",
)

@Serializable
internal data class WalletAddressDto(
    val address: String,
)

@Serializable
internal data class WalletBalanceDto(
    val balance: String,
    @SerialName("gas_balance") val gasBalance: String,
)

@Serializable
internal data class WalletApproveDto(
    val approved: Boolean,
)

@Serializable
internal data class PaymentInfoDto(
    @SerialName("quote_hash") val quoteHash: String,
    @SerialName("rewards_address") val rewardsAddress: String,
    val amount: String,
)

@Serializable
internal data class CandidateNodeEntryDto(
    @SerialName("rewards_address") val rewardsAddress: String,
    val amount: String,
)

@Serializable
internal data class PoolCommitmentEntryDto(
    @SerialName("pool_hash") val poolHash: String,
    val candidates: List<CandidateNodeEntryDto>,
)

@Serializable
internal data class PrepareUploadDto(
    @SerialName("upload_id") val uploadId: String,
    val payments: List<PaymentInfoDto>? = null,
    @SerialName("total_amount") val totalAmount: String,
    @SerialName("payment_vault_address") val paymentVaultAddress: String,
    @SerialName("payment_token_address") val paymentTokenAddress: String,
    @SerialName("rpc_url") val rpcUrl: String,
    @SerialName("payment_type") val paymentType: String? = null,
    val depth: Int? = null,
    @SerialName("pool_commitments") val poolCommitments: List<PoolCommitmentEntryDto>? = null,
    @SerialName("merkle_payment_timestamp") val merklePaymentTimestamp: Long? = null,
    @SerialName("total_chunks") val totalChunks: Long = 0,
    @SerialName("already_stored_count") val alreadyStoredCount: Long = 0,
)

@Serializable
internal data class FinalizeUploadDto(
    val address: String = "",
    @SerialName("chunks_stored") val chunksStored: Long = 0,
    @SerialName("data_map") val dataMap: String = "",
    @SerialName("data_map_address") val dataMapAddress: String = "",
    val sha256: String? = null,
)

@Serializable
internal data class PrepareChunkDto(
    val address: String,
    @SerialName("already_stored") val alreadyStored: Boolean = false,
    @SerialName("upload_id") val uploadId: String? = null,
    @SerialName("payment_type") val paymentType: String? = null,
    val payments: List<PaymentInfoDto>? = null,
    @SerialName("total_amount") val totalAmount: String? = null,
    @SerialName("payment_vault_address") val paymentVaultAddress: String? = null,
    @SerialName("payment_token_address") val paymentTokenAddress: String? = null,
    @SerialName("rpc_url") val rpcUrl: String? = null,
)

@Serializable
internal data class FinalizeChunkDto(
    val address: String,
)

// ── Pointer DTOs ──
//
// Counters stay strings here and go through parsePointerCounter, so a
// malformed one is an error rather than a silent zero.

@Serializable
internal data class PointerKeyDto(val address: String = "")

@Serializable
internal data class PointerKeysDto(val keys: List<PointerKeyDto> = emptyList())

@Serializable
internal data class PointerWriteDto(
    val address: String = "",
    @SerialName("state_id") val stateId: String = "",
    val counter: String = "",
) {
    fun toModel() = PointerWriteResult(address, stateId, parsePointerCounter("counter", counter))
}

@Serializable
internal data class PointerRecordDto(
    val address: String = "",
    val owner: String = "",
    val counter: String = "",
    val kind: String = "",
    @SerialName("kind_tag") val kindTag: UInt = 0u,
    val target: String = "",
    @SerialName("state_id") val stateId: String = "",
    @SerialName("is_final") val isFinal: Boolean = false,
    @SerialName("transferred_to") val transferredTo: String? = null,
) {
    fun toModel() = PointerRecord(
        address = address,
        owner = owner,
        counter = parsePointerCounter("counter", counter),
        kind = kind,
        kindTag = kindTag,
        target = target,
        stateId = stateId,
        isFinal = isFinal,
        transferredTo = transferredTo.nonEmptyOrNull(),
    )
}

@Serializable
internal data class PointerTargetDto(
    val kind: String = "",
    @SerialName("kind_tag") val kindTag: UInt = 0u,
    val target: String = "",
) {
    fun toModel() = PointerTarget(kind, kindTag, target)
}

@Serializable
internal data class PointerFinalStateDto(
    @SerialName("state_id") val stateId: String = "",
    val kind: String = "",
    @SerialName("kind_tag") val kindTag: UInt = 0u,
    val target: String = "",
    val holders: UInt = 0u,
    @SerialName("transferred_to") val transferredTo: String? = null,
) {
    fun toModel() = PointerFinalState(stateId, kind, kindTag, target, holders, transferredTo.nonEmptyOrNull())
}

@Serializable
internal data class PointerFinalityDto(
    val address: String = "",
    val group: UInt = 0u,
    val answered: UInt = 0u,
    val status: String = "",
    val counter: String? = null,
    val state: PointerFinalStateDto? = null,
    val states: List<PointerFinalStateDto> = emptyList(),
    val majority: PointerFinalStateDto? = null,
    @SerialName("transferred_to") val transferredTo: String? = null,
) {
    fun toModel() = PointerFinality(
        address = address,
        group = group,
        answered = answered,
        status = PointerFinalityStatus.fromWire(status),
        counter = parseOptionalPointerCounter("counter", counter),
        state = state?.toModel(),
        states = states.map { it.toModel() },
        majority = majority?.toModel(),
        transferredTo = transferredTo.nonEmptyOrNull(),
    )
}

@Serializable
internal data class PointerControllerDto(
    val pointer: String = "",
    val transfers: List<String> = emptyList(),
    val frozen: Boolean = false,
) {
    fun toModel() = PointerController(pointer, transfers, frozen)
}

@Serializable
internal data class PointerTransferDto(
    val address: String = "",
    @SerialName("state_id") val stateId: String = "",
    val finality: PointerFinalityDto? = null,
    @SerialName("finality_error") val finalityError: String? = null,
) {
    fun toModel() = PointerTransferResult(address, stateId, finality?.toModel(), finalityError.nonEmptyOrNull())
}

@Serializable
internal data class SignedQuoteDto(
    @SerialName("quote_hash") val quoteHash: String = "",
    val quote: String = "",
    @SerialName("commitment_sidecar") val commitmentSidecar: String? = null,
)

@Serializable
internal data class PointerPrepareDto(
    @SerialName("upload_id") val uploadId: String = "",
    val op: String = "",
    val address: String = "",
    @SerialName("state_id") val stateId: String = "",
    val counter: String = "",
    @SerialName("payment_type") val paymentType: String = "",
    val payments: List<PaymentInfoDto> = emptyList(),
    @SerialName("total_amount") val totalAmount: String = "",
    @SerialName("payment_vault_address") val paymentVaultAddress: String = "",
    @SerialName("payment_token_address") val paymentTokenAddress: String = "",
    @SerialName("rpc_url") val rpcUrl: String = "",
    @SerialName("signed_quotes") val signedQuotes: List<SignedQuoteDto>? = null,
) {
    fun toModel() = PointerPrepareResult(
        uploadId = uploadId,
        op = op,
        address = address,
        stateId = stateId,
        counter = parsePointerCounter("counter", counter),
        paymentType = paymentType,
        payments = payments.map { PaymentInfo(it.quoteHash, it.rewardsAddress, it.amount) },
        totalAmount = totalAmount,
        paymentVaultAddress = paymentVaultAddress,
        paymentTokenAddress = paymentTokenAddress,
        rpcUrl = rpcUrl,
        signedQuotes = signedQuotes.orEmpty().map {
            SignedQuoteEntry(it.quoteHash, it.quote, it.commitmentSidecar.nonEmptyOrNull())
        },
    )
}

@Serializable
internal data class PointerFinalizeDto(
    val address: String = "",
    @SerialName("state_id") val stateId: String = "",
    val counter: String = "",
    val finality: PointerFinalityDto? = null,
) {
    fun toModel() = PointerFinalizeResult(address, stateId, parsePointerCounter("counter", counter), finality?.toModel())
}
