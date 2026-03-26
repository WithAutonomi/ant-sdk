package com.autonomi.sdk

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Health check result from the antd daemon. */
data class HealthStatus(val ok: Boolean, val network: String)

/** Result of a put/create operation that stores data on the network. */
data class PutResult(val cost: String, val address: String)

/** A descendant entry in a graph node. */
data class GraphDescendant(val publicKey: String, val content: String)

/** A graph entry retrieved from the network. */
data class GraphEntry(val owner: String, val parents: List<String>, val content: String, val descendants: List<GraphDescendant>)

/** A single entry in an archive manifest. */
data class ArchiveEntry(val path: String, val address: String, val created: ULong, val modified: ULong, val size: ULong)

/** An archive manifest containing file entries. */
data class Archive(val entries: List<ArchiveEntry>)

/** Wallet address response. */
data class WalletAddress(val address: String)

/** Wallet balance response. */
data class WalletBalance(val balance: String, val gasBalance: String)

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
internal data class GraphDescendantDto(
    @SerialName("public_key") val publicKey: String,
    val content: String,
)

@Serializable
internal data class GraphEntryDto(
    val owner: String,
    val parents: List<String>? = null,
    val content: String,
    val descendants: List<GraphDescendantDto>? = null,
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
