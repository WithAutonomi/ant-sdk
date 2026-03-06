package com.autonomi.sdk

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Health check result from the antd daemon. */
data class HealthStatus(val ok: Boolean, val network: String)

/** Result of a put/create operation that stores data on the network. */
data class PutResult(val cost: String, val address: String)

/** Target of a pointer — identifies both the kind and address of the target. */
data class PointerTarget(val kind: String, val address: String)

/** A pointer record retrieved from the network. */
data class Pointer(val address: String, val owner: String, val counter: ULong, val target: PointerTarget)

/** A scratchpad record retrieved from the network. */
data class ScratchpadRecord(val address: String, val dataEncoding: ULong, val data: ByteArray, val counter: ULong) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ScratchpadRecord) return false
        return address == other.address && dataEncoding == other.dataEncoding &&
            data.contentEquals(other.data) && counter == other.counter
    }
    override fun hashCode(): Int = address.hashCode()
}

/** A descendant entry in a graph node. */
data class GraphDescendant(val publicKey: String, val content: String)

/** A graph entry retrieved from the network. */
data class GraphEntry(val owner: String, val parents: List<String>, val content: String, val descendants: List<GraphDescendant>)

/** A register value retrieved from the network. */
data class Register(val value: String)

/** A vault record retrieved from the network. */
data class Vault(val data: ByteArray, val contentType: ULong) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Vault) return false
        return data.contentEquals(other.data) && contentType == other.contentType
    }
    override fun hashCode(): Int = data.contentHashCode()
}

/** A single entry in an archive manifest. */
data class ArchiveEntry(val path: String, val address: String, val created: ULong, val modified: ULong, val size: ULong)

/** An archive manifest containing file entries. */
data class Archive(val entries: List<ArchiveEntry>)

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
internal data class PointerTargetDto(
    val kind: String,
    val address: String,
)

@Serializable
internal data class PointerDto(
    val address: String,
    val owner: String,
    val counter: ULong,
    val target: PointerTargetDto,
)

@Serializable
internal data class ScratchpadDto(
    val address: String,
    @SerialName("data_encoding") val dataEncoding: ULong,
    val data: String,
    val counter: ULong,
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
internal data class RegisterDto(
    val value: String,
)

@Serializable
internal data class RegisterUpdateDto(
    val cost: String,
)

@Serializable
internal data class VaultDto(
    val data: String,
    @SerialName("content_type") val contentType: ULong,
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
