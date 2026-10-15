package com.autonomi.sdk

import antd.v1.Manifests
import antd.v1.buildManifestRequest
import antd.v1.manifestEntryInput
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import java.util.Base64

// Manifests (ADR-0006, V2-1580): `.ant` files and `ant://` links that
// describe a set of files, each with an optional path and size and either an
// embedded DataMap or a public DataMap address. The daemon builds and decodes
// them through ant-core, so callers never re-implement the format. Nothing is
// uploaded or paid for.
//
// The public API always takes and returns the raw `.ant` bytes: REST carries
// them as base64 in JSON, gRPC as `bytes`, and both are converted here.

/**
 * One file for [IAntdClient.buildManifest]. Set exactly one of [dataMap] or
 * [address]; an empty string counts as unset. Both clients check this before
 * sending anything and throw [BadRequestException].
 */
data class ManifestEntryInput(
    /**
     * The relative path the entry extracts under, subject to the portable
     * path rules (the daemon rejects, say, `../x`). Null or empty: it
     * extracts under its content address.
     */
    val path: String? = null,
    /**
     * The plaintext size to record, as given (the creator's claim). Null:
     * none is recorded; readers take the exact size from an embedded root
     * DataMap.
     */
    val size: ULong? = null,
    /**
     * A hex DataMap, as `dataPut` / `filePut` return it. The entry embeds it:
     * the manifest is the key to the file.
     */
    val dataMap: String? = null,
    /** A public file's DataMap address (hex, 32 bytes), as `dataPutPublic` / `filePutPublic` return it. */
    val address: String? = null,
)

/** The optional parts of an [IAntdClient.buildManifest] call. */
data class BuildManifestOptions(
    /** A suggested root directory name (one portable path component). Null or empty: none. */
    val name: String? = null,
    /** BitTorrent info hashes of the same files: hex, 40 characters for v1 and/or 64 for v2. */
    val torrentInfoHashes: List<String> = emptyList(),
    /**
     * ADR-0006's embedding policy, on by default: the daemon resolves each
     * shrunk DataMap's root (fetching its wrapper records) and embeds the
     * root when it is at most 64 KiB, so recipients skip that fetch. False
     * embeds shrunk DataMaps exactly as given (antd-go's
     * `KeepShrunkDataMaps`).
     */
    val embedRoots: Boolean = true,
)

/** What a manifest says about one entry. */
data class ManifestEntryInfo(
    /** [path], or the content address in hex when there is none. */
    val effectiveName: String,
    /** "embedded" or "public". */
    val kind: String,
    /**
     * Hex. The file's public DataMap address, whether or not it was ever
     * made public; the same for private and public uploads of one file.
     */
    val contentAddress: String,
    /** The path the entry extracts under; null when it has none. */
    val path: String? = null,
    /** The size recorded in the manifest (the creator's claim); null when none was recorded. */
    val size: ULong? = null,
    /**
     * The embedded DataMap, in the hex form `dataGet` / `fileGet` accept.
     * Set by decodes only, and only for embedded entries; null otherwise.
     */
    val dataMap: String? = null,
    /**
     * The exact plaintext size, from an embedded root DataMap or after a
     * resolving decode; null when it is not known.
     */
    val exactSize: ULong? = null,
    /** Why a resolving decode failed for this entry; null when it did not. */
    val error: String? = null,
)

/** The result of [IAntdClient.buildManifest]. */
data class BuiltManifest(
    /** The `.ant` bytes. */
    val manifest: ByteArray,
    /** The `ant://manifest/` link; null when it does not fit the recommended 1,500 bytes. */
    val link: String?,
    /** In encoded order (sorted by effective name). */
    val entries: List<ManifestEntryInfo>,
) {
    // data classes with a ByteArray member need structural equals/hashCode.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is BuiltManifest) return false
        return manifest.contentEquals(other.manifest) && link == other.link && entries == other.entries
    }

    override fun hashCode(): Int {
        var result = manifest.contentHashCode()
        result = 31 * result + (link?.hashCode() ?: 0)
        result = 31 * result + entries.hashCode()
        return result
    }
}

/** The result of [IAntdClient.decodeManifest] and [IAntdClient.decodeManifestLink]. */
data class DecodedManifest(
    /**
     * "manifest", or "file_link" for a file link or bare address (reported
     * as one public entry with no path).
     */
    val source: String,
    /** The suggested root directory name; null when the manifest has none. */
    val name: String?,
    /** BitTorrent v1 info hash (hex); null when absent. */
    val torrentInfoHashV1: String?,
    /** BitTorrent v2 info hash (hex); null when absent. */
    val torrentInfoHashV2: String?,
    val entries: List<ManifestEntryInfo>,
)

/**
 * The gRPC message ceiling for ManifestService, both ways. A manifest can be
 * 64 MiB, a Build or Decode response carries it (a decode also carries its
 * DataMaps in hex), and a Decode request sends it. grpc-java's default
 * receive limit is 4 MiB. Same value as antd-go's `maxManifestGrpcMessage`.
 */
internal const val MAX_MANIFEST_GRPC_MESSAGE: Int = 256 * 1024 * 1024

/** Most entry errors the daemon lists in one message; the rest are counted. */
private const val MAX_REPORTED_ENTRY_ERRORS = 20

/**
 * Rejects entries that set both or neither of `dataMap` and `address`
 * (an empty string is unset), before anything is sent. Every bad entry is
 * reported, in the daemon's own wording (`antd/src/manifests.rs`
 * `parse_entries` / `entry_errors_message`), so a client-side refusal reads
 * exactly like the daemon's 400.
 *
 * @throws BadRequestException (status 400) naming each bad entry's index.
 */
internal fun checkManifestEntries(entries: List<ManifestEntryInput>) {
    val errors = entries.mapIndexedNotNull { i, e ->
        when {
            !e.dataMap.isNullOrEmpty() && !e.address.isNullOrEmpty() -> "entries[$i]: give data_map or address, not both"
            e.dataMap.isNullOrEmpty() && e.address.isNullOrEmpty() -> "entries[$i]: needs a data_map or an address"
            else -> null
        }
    }
    if (errors.isEmpty()) return
    var message = "${errors.size} invalid entries: ${errors.take(MAX_REPORTED_ENTRY_ERRORS).joinToString("; ")}"
    if (errors.size > MAX_REPORTED_ENTRY_ERRORS) message += "; and ${errors.size - MAX_REPORTED_ENTRY_ERRORS} more"
    throw BadRequestException(message, 400)
}

private const val EMPTY_DECODE_INPUT = "needs a manifest (base64 .ant bytes) or a link"

internal fun checkManifestBytes(manifest: ByteArray) {
    if (manifest.isEmpty()) throw BadRequestException(EMPTY_DECODE_INPUT, 400)
}

internal fun checkManifestLink(link: String) {
    if (link.isEmpty()) throw BadRequestException(EMPTY_DECODE_INPUT, 400)
}

// ── REST ──

/**
 * The `POST /v1/manifests/build` body. Unset paths, sizes, an empty name and
 * empty torrent hashes are omitted; `embed_roots` is always sent.
 */
@OptIn(ExperimentalSerializationApi::class) // JsonPrimitive(ULong)
internal fun manifestBuildBody(entries: List<ManifestEntryInput>, options: BuildManifestOptions): String =
    buildJsonObject {
        putJsonArray("entries") {
            entries.forEach { e ->
                addJsonObject {
                    e.path?.takeIf { it.isNotEmpty() }?.let { put("path", it) }
                    // A ULong is not a Number; JsonPrimitive(ULong) writes the exact u64.
                    e.size?.let { put("size", JsonPrimitive(it)) }
                    if (!e.dataMap.isNullOrEmpty()) put("data_map", e.dataMap) else put("address", e.address)
                }
            }
        }
        put("embed_roots", options.embedRoots)
        options.name?.takeIf { it.isNotEmpty() }?.let { put("name", it) }
        if (options.torrentInfoHashes.isNotEmpty()) {
            putJsonArray("torrent_info_hashes") { options.torrentInfoHashes.forEach { add(it) } }
        }
    }.toString()

/** The `POST /v1/manifests/decode` body for `.ant` bytes, sent as base64. */
internal fun manifestDecodeBytesBody(manifest: ByteArray, resolve: Boolean): String = buildJsonObject {
    put("manifest", Base64.getEncoder().encodeToString(manifest))
    put("resolve", resolve)
}.toString()

/** The `POST /v1/manifests/decode` body for a link. */
internal fun manifestDecodeLinkBody(link: String, resolve: Boolean): String = buildJsonObject {
    put("link", link)
    put("resolve", resolve)
}.toString()

/** REST omits every unset field, so each optional one reads as null. */
@Serializable
internal data class ManifestEntryInfoDto(
    @SerialName("effective_name") val effectiveName: String = "",
    val path: String? = null,
    val size: ULong? = null,
    val kind: String = "",
    @SerialName("content_address") val contentAddress: String = "",
    @SerialName("data_map") val dataMap: String? = null,
    @SerialName("exact_size") val exactSize: ULong? = null,
    val error: String? = null,
)

@Serializable
internal data class ManifestBuildDto(
    /** The `.ant` bytes, base64. */
    val manifest: String = "",
    val link: String? = null,
    val entries: List<ManifestEntryInfoDto> = emptyList(),
)

@Serializable
internal data class ManifestDecodeDto(
    val source: String = "",
    val name: String? = null,
    @SerialName("torrent_info_hash_v1") val torrentInfoHashV1: String? = null,
    @SerialName("torrent_info_hash_v2") val torrentInfoHashV2: String? = null,
    val entries: List<ManifestEntryInfoDto> = emptyList(),
)

internal fun ManifestEntryInfoDto.toManifestEntryInfo() = ManifestEntryInfo(
    effectiveName = effectiveName,
    kind = kind,
    contentAddress = contentAddress,
    path = path,
    size = size,
    dataMap = dataMap?.ifEmpty { null },
    exactSize = exactSize,
    error = error?.ifEmpty { null },
)

/** @throws InternalException if the daemon's `manifest` is not valid base64. */
internal fun ManifestBuildDto.toBuiltManifest(): BuiltManifest {
    val bytes = try {
        Base64.getDecoder().decode(manifest)
    } catch (e: IllegalArgumentException) {
        throw InternalException("buildManifest: the daemon's manifest is not valid base64: ${e.message}")
    }
    return BuiltManifest(bytes, link?.ifEmpty { null }, entries.map { it.toManifestEntryInfo() })
}

internal fun ManifestDecodeDto.toDecodedManifest() = DecodedManifest(
    source = source,
    name = name,
    torrentInfoHashV1 = torrentInfoHashV1?.ifEmpty { null },
    torrentInfoHashV2 = torrentInfoHashV2?.ifEmpty { null },
    entries = entries.map { it.toManifestEntryInfo() },
)

// ── gRPC ──
//
// proto3 `optional` fields are read by presence (hasSize, hasPath, ...), never
// by their zero value. The plain strings the proto leaves empty when unset
// (link, data_map, error, the torrent hashes) read as null. uint64 is a Java
// long; toLong()/toULong() keep all 64 bits.

internal fun buildManifestRequestOf(inputs: List<ManifestEntryInput>, options: BuildManifestOptions): Manifests.BuildManifestRequest =
    buildManifestRequest {
        options.name?.takeIf { it.isNotEmpty() }?.let { name = it }
        torrentInfoHashes.addAll(options.torrentInfoHashes)
        // Always set, so the daemon sees the caller's choice rather than its default.
        embedRoots = options.embedRoots
        inputs.forEach { e ->
            entries += manifestEntryInput {
                e.path?.takeIf { it.isNotEmpty() }?.let { path = it }
                e.size?.let { size = it.toLong() }
                if (!e.dataMap.isNullOrEmpty()) dataMap = e.dataMap else address = e.address.orEmpty()
            }
        }
    }

internal fun Manifests.ManifestEntryInfo.toManifestEntryInfo() = ManifestEntryInfo(
    effectiveName = effectiveName,
    kind = kind,
    contentAddress = contentAddress,
    path = if (hasPath()) path else null,
    size = if (hasSize()) size.toULong() else null,
    dataMap = dataMap.ifEmpty { null },
    exactSize = if (hasExactSize()) exactSize.toULong() else null,
    error = error.ifEmpty { null },
)

internal fun Manifests.BuildManifestResponse.toBuiltManifest() = BuiltManifest(
    manifest = manifest.toByteArray(),
    link = link.ifEmpty { null },
    entries = entriesList.map { it.toManifestEntryInfo() },
)

internal fun Manifests.DecodeManifestResponse.toDecodedManifest() = DecodedManifest(
    source = source,
    name = if (hasName()) name else null,
    torrentInfoHashV1 = torrentInfoHashV1.ifEmpty { null },
    torrentInfoHashV2 = torrentInfoHashV2.ifEmpty { null },
    entries = entriesList.map { it.toManifestEntryInfo() },
)
