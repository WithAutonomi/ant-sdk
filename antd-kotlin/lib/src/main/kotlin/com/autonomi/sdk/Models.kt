package com.autonomi.sdk

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Health check result from the antd daemon. */
data class HealthStatus(val ok: Boolean, val network: String)

/** Result of a put/create operation that stores data on the network. */
data class PutResult(val cost: String, val address: String)

/** A single entry in an archive manifest. */
data class ArchiveEntry(val path: String, val address: String, val created: ULong, val modified: ULong, val size: ULong)

/** An archive manifest containing file entries. */
data class Archive(val entries: List<ArchiveEntry>)

/** Wallet address response. */
data class WalletAddress(val address: String)

/** Wallet balance response. */
data class WalletBalance(val balance: String, val gasBalance: String)

/** A single payment required for an upload. */
data class PaymentInfo(val quoteHash: String, val rewardsAddress: String, val amount: String)

/** Result of preparing an upload for external signing. */
data class PrepareUploadResult(
    val uploadId: String,
    val payments: List<PaymentInfo>,
    val totalAmount: String,
    val dataPaymentsAddress: String,
    val paymentTokenAddress: String,
    val rpcUrl: String,
)

/** Result of finalizing an externally-signed upload. */
data class FinalizeUploadResult(val address: String, val chunksStored: Long)

// ── Internal DTOs for JSON deserialization ──

@Serializable
internal data class HealthResponseDto(
    val status: String? = null,
    val network: String? = null,
)

@Serializable
internal data class DataPutPublicDto(
    val cost: String,
    val address: String,
)

@Serializable
internal data class DataPutPrivateDto(
    val cost: String,
    @SerialName("data_map") val dataMap: String,
)

@Serializable
internal data class DataGetDto(
    val data: String,
)

@Serializable
internal data class CostDto(
    val cost: String,
)

@Serializable
internal data class ArchiveEntryDto(
    val path: String,
    val address: String,
    val created: ULong,
    val modified: ULong,
    val size: ULong,
)

@Serializable
internal data class ArchiveDto(
    val entries: List<ArchiveEntryDto>? = null,
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
internal data class PrepareUploadDto(
    @SerialName("upload_id") val uploadId: String,
    val payments: List<PaymentInfoDto>? = null,
    @SerialName("total_amount") val totalAmount: String,
    @SerialName("data_payments_address") val dataPaymentsAddress: String,
    @SerialName("payment_token_address") val paymentTokenAddress: String,
    @SerialName("rpc_url") val rpcUrl: String,
)

@Serializable
internal data class FinalizeUploadDto(
    val address: String,
    @SerialName("chunks_stored") val chunksStored: Long,
)
