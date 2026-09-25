package com.autonomi.sdk

import io.grpc.StatusException
import io.grpc.StatusRuntimeException
import io.grpc.Status
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

open class AntdException(message: String, val statusCode: Int = 0) : Exception(message)

class NotFoundException(message: String, statusCode: Int = 404) : AntdException(message, statusCode)
class AlreadyExistsException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)
class ForkException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)
class BadRequestException(message: String, statusCode: Int = 400) : AntdException(message, statusCode)
class PaymentException(message: String, statusCode: Int = 402) : AntdException(message, statusCode)
open class NetworkException(message: String, statusCode: Int = 502) : AntdException(message, statusCode)
class TooLargeException(message: String, statusCode: Int = 413) : AntdException(message, statusCode)
class InternalException(message: String, statusCode: Int = 500) : AntdException(message, statusCode)
class ServiceUnavailableException(message: String, statusCode: Int = 503) : AntdException(message, statusCode)

/**
 * A finalize stored some chunks while others remained unstored after the
 * daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED).
 * The on-chain payment persists and the stored chunks stay on the network.
 * How to finish the upload depends on [retryable]:
 *
 * - `retryable == true`: the daemon kept the paid attempt (payment proofs +
 *   unstored chunks) under the same `upload_id`. Call the **same** finalize
 *   method again with the same arguments to store the remainder against the
 *   same payment — no re-prepare, no second signature, no double payment.
 *   Bound the loop: a persistent failure throws this exception on every
 *   call, so cap the attempts and treat a [chunksFailed] that stops
 *   shrinking as stuck. The retained attempt expires with the daemon's
 *   pending-upload TTL. (Sent by antd >= 0.14.0; older daemons never send
 *   the flag, so it reads `false` and the re-prepare path applies.)
 * - `retryable == false`: nothing was retained (a merkle finalize with
 *   deliberately unpaid batches, or an older daemon). Re-preparing the same
 *   content skips already-stored chunks, so a retry pays only for the
 *   missing remainder.
 *
 * Extends [NetworkException] because a `PARTIAL_UPLOAD` arrives as a 502,
 * which this SDK has always mapped to [NetworkException]; existing
 * `catch (e: NetworkException)` blocks keep working and can narrow with
 * `is PartialUploadException` when they want the counts.
 *
 * Over REST the counts and [retryable] come from the structured error body:
 * each count only from a JSON number holding a non-negative integer, and
 * [retryable] only from a JSON boolean. Anything else (missing, a quoted
 * number or quoted `"true"`, a negative, fractional or out-of-range number,
 * an array or an object) reads as zero / `false`; the mapper never throws.
 *
 * Over gRPC they are parsed from the status description
 * (`Partial upload: S/T chunks stored, F failed ...`, with a "paid attempt
 * retained" hint when retryable). [retryable] is true only when the
 * description matches that layout, all three counts convert to a [Long],
 * and the hint is present. On a layout mismatch or a count that does not
 * convert, all three counts are zero and [retryable] is false even if the
 * hint is present, so a caller never loops on a message the SDK could not
 * read.
 *
 * See `docs/external-signer-flow.md` §6 ("Retry a partial store") for the
 * daemon-side contract.
 */
class PartialUploadException(
    message: String,
    val chunksStored: Long = 0,
    val chunksFailed: Long = 0,
    val totalChunks: Long = 0,
    val retryable: Boolean = false,
    statusCode: Int = 502,
) : NetworkException(message, statusCode)

internal object ExceptionMapping {

    /** Machine-readable `code` the daemon sets on a partial-store finalize. */
    private const val PARTIAL_UPLOAD_CODE = "PARTIAL_UPLOAD"

    /**
     * Fixed text every PARTIAL_UPLOAD message opens with (`antd/src/error.rs`).
     * Over gRPC it is the only thing that distinguishes a partial upload from
     * any other ABORTED status, so [fromGrpcStatus] gates on the description
     * starting with it (anchored, matching the antd-rust client).
     */
    private const val PARTIAL_UPLOAD_PREFIX = "Partial upload:"

    /**
     * Fixed prefix of the daemon's PARTIAL_UPLOAD message:
     * `Partial upload: <stored>/<total> chunks stored, <failed> failed`.
     */
    private val partialUploadCounts = Regex("$PARTIAL_UPLOAD_PREFIX (\\d+)/(\\d+) chunks stored, (\\d+) failed")

    /**
     * Message tail the daemon appends when it kept the paid attempt for a
     * same-upload_id retry.
     */
    private const val PARTIAL_UPLOAD_RETAINED_HINT = "paid attempt retained"

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Maps a REST error response onto a typed exception, preferring the
     * machine-readable `code` over the bare HTTP status where they diverge:
     * `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a plain
     * [NetworkException]. Every other status keeps its status-based mapping.
     */
    fun fromHttpStatus(statusCode: Int, body: String): AntdException =
        partialUploadFromBody(statusCode, body) ?: fromHttpStatusOnly(statusCode, body)

    /**
     * Returns a [PartialUploadException] when [body] is a JSON error object
     * whose `code` is the string `"PARTIAL_UPLOAD"`, carrying its counts;
     * `retryable` is absent on daemons < 0.14.0 and defaults to `false`.
     * Returns null for every other body (non-JSON, non-object, or a `code`
     * that is missing, another value, or not a string), so the caller's
     * status-based mapping applies. Counts go through [count] and
     * `retryable` through [flag]: a value of any other kind (a quoted number
     * or quoted `"true"`, a negative or fractional number, an object or an
     * array) reads as absent, zero or `false`, rather than being coerced or
     * escaping as a serialization error. The daemon's error body is input
     * from the network and must never turn a typed [AntdException] into an
     * [IllegalArgumentException].
     */
    private fun partialUploadFromBody(statusCode: Int, body: String): PartialUploadException? {
        val obj = try {
            json.parseToJsonElement(body) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return null
        val code = obj.primitive("code")
        if (code == null || !code.isString || code.content != PARTIAL_UPLOAD_CODE) return null
        return PartialUploadException(
            message = obj.primitive("error")?.takeIf { it.isString }?.content ?: body,
            chunksStored = obj.count("chunks_stored"),
            chunksFailed = obj.count("chunks_failed"),
            totalChunks = obj.count("total_chunks"),
            retryable = obj.flag("retryable"),
            statusCode = statusCode,
        )
    }

    /**
     * The value at [key] when it is a JSON primitive (string, number, boolean
     * or null); `null` when the key is absent or holds an object or array.
     * Unlike `JsonElement.jsonPrimitive`, never throws.
     */
    private fun JsonObject.primitive(key: String): JsonPrimitive? = this[key] as? JsonPrimitive

    /**
     * The chunk count at [key]: a JSON number holding a non-negative integer
     * that fits a [Long]. Anything else reads as 0: absent, a JSON string
     * (even `"12"`), a negative, fractional or out-of-range number, `null`,
     * a boolean, an object or an array.
     */
    private fun JsonObject.count(key: String): Long =
        primitive(key)?.takeUnless { it.isString }?.content?.toLongOrNull()?.takeIf { it >= 0 } ?: 0

    /**
     * The flag at [key]: true only for the JSON literal `true`. Anything
     * else reads as false: absent, the string `"true"`, a number, `null`,
     * an object or an array.
     */
    private fun JsonObject.flag(key: String): Boolean =
        primitive(key)?.takeUnless { it.isString }?.content == "true"

    /**
     * True when [message] starts with the daemon's fixed PARTIAL_UPLOAD
     * prefix. Anchored rather than a containment check so an unrelated
     * ABORTED that merely quotes the phrase is not misreported as a partial
     * upload; the daemon never wraps its own message, so the prefix is
     * always at offset zero when it is a partial upload.
     */
    fun isPartialUploadMessage(message: String): Boolean = message.startsWith(PARTIAL_UPLOAD_PREFIX)

    /**
     * Recovers the chunk counts and the retryable hint from a PARTIAL_UPLOAD
     * message. Used for gRPC, where the status carries no structured detail;
     * REST callers get the body fields instead. `retryable` is true only when
     * the message matches the count layout, all three counts convert to a
     * [Long], and the "paid attempt retained" hint is present. The layout
     * accepts any run of digits, so a count past [Long.MAX_VALUE] matches but
     * does not convert. On a layout mismatch or a failed conversion all three
     * counts are zero and `retryable` is false, even when the hint is present:
     * a retry loop that cannot see [PartialUploadException.chunksFailed]
     * shrinking has no way to tell progress from a stuck upload. Whether the
     * message is a partial upload at all is decided by [isPartialUploadMessage].
     */
    fun partialUploadFromMessage(message: String): PartialUploadException {
        val counts = partialUploadCounts.find(message)?.groupValues?.let { g ->
            val stored = g[1].toLongOrNull()
            val total = g[2].toLongOrNull()
            val failed = g[3].toLongOrNull()
            if (stored != null && total != null && failed != null) Triple(stored, total, failed) else null
        }
        return PartialUploadException(
            message = message,
            chunksStored = counts?.first ?: 0,
            totalChunks = counts?.second ?: 0,
            chunksFailed = counts?.third ?: 0,
            retryable = counts != null && message.contains(PARTIAL_UPLOAD_RETAINED_HINT),
        )
    }

    private fun fromHttpStatusOnly(statusCode: Int, body: String): AntdException = when (statusCode) {
        400 -> BadRequestException(body, statusCode)
        402 -> PaymentException(body, statusCode)
        404 -> NotFoundException(body, statusCode)
        409 -> AlreadyExistsException(body, statusCode)
        413 -> TooLargeException(body, statusCode)
        500 -> InternalException(body, statusCode)
        502 -> NetworkException(body, statusCode)
        503 -> ServiceUnavailableException(body, statusCode)
        else -> AntdException(body, statusCode)
    }

    fun fromGrpcStatus(ex: StatusRuntimeException): AntdException {
        val detail = ex.status.description ?: ex.message ?: "Unknown error"
        return when (ex.status.code) {
            Status.Code.NOT_FOUND -> NotFoundException(detail)
            Status.Code.ALREADY_EXISTS -> AlreadyExistsException(detail)
            // PARTIAL_UPLOAD: some chunks stored, some still unstored after
            // retries. The counts and the "paid attempt retained" hint ride
            // the status description over gRPC (no structured detail yet),
            // so parse them best-effort to match the REST client's typed
            // exception. The daemon's message always opens with the fixed
            // "Partial upload:" prefix, so gate on the description starting
            // with it; any other ABORTED keeps the pre-existing
            // conflicting-update mapping instead of being misreported as a
            // partial upload.
            Status.Code.ABORTED ->
                if (isPartialUploadMessage(detail)) partialUploadFromMessage(detail) else ForkException(detail)
            Status.Code.INVALID_ARGUMENT -> BadRequestException(detail)
            Status.Code.FAILED_PRECONDITION -> PaymentException(detail)
            Status.Code.UNAVAILABLE -> NetworkException(detail)
            Status.Code.RESOURCE_EXHAUSTED -> TooLargeException(detail)
            Status.Code.INTERNAL -> InternalException(detail)
            else -> AntdException(detail, ex.status.code.value())
        }
    }
}
