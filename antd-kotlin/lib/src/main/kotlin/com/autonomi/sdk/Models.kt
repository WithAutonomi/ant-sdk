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
)

@Serializable
internal data class DataPutDto(
    @SerialName("data_map") val dataMap: String,
    @SerialName("chunks_stored") val chunksStored: ULong = 0u,
    @SerialName("payment_mode_used") val paymentModeUsed: String = "",
)

@Serializable
internal data class FilePutPublicDto(
    val address: String,
    @SerialName("storage_cost_atto") val storageCostAtto: String,
    @SerialName("gas_cost_wei") val gasCostWei: String,
    @SerialName("chunks_stored") val chunksStored: ULong,
    @SerialName("payment_mode_used") val paymentModeUsed: String,
)

@Serializable
internal data class FilePutDto(
    @SerialName("data_map") val dataMap: String,
    @SerialName("storage_cost_atto") val storageCostAtto: String,
    @SerialName("gas_cost_wei") val gasCostWei: String,
    @SerialName("chunks_stored") val chunksStored: ULong,
    @SerialName("payment_mode_used") val paymentModeUsed: String,
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
