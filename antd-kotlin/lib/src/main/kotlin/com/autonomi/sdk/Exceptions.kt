package com.autonomi.sdk

import io.grpc.StatusException
import io.grpc.StatusRuntimeException
import io.grpc.Status
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

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
 * Over REST the counts and [retryable] come from the structured error body.
 * Over gRPC they are parsed best-effort from the status description
 * (`Partial upload: S/T chunks stored, F failed ...`, with a "paid attempt
 * retained" hint when retryable); an unrecognised description leaves the
 * counts at zero and [retryable] false.
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
     * any other ABORTED status, so [fromGrpcStatus] gates on it.
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
     * with `code == "PARTIAL_UPLOAD"`, carrying its counts; `retryable` is
     * absent on daemons < 0.14.0 and defaults to `false`. Returns null for
     * every other body (including non-JSON bodies).
     */
    private fun partialUploadFromBody(statusCode: Int, body: String): PartialUploadException? {
        val obj = try {
            json.parseToJsonElement(body) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return null
        if (obj["code"]?.jsonPrimitive?.contentOrNull != PARTIAL_UPLOAD_CODE) return null
        return PartialUploadException(
            message = obj["error"]?.jsonPrimitive?.contentOrNull ?: body,
            chunksStored = obj["chunks_stored"]?.jsonPrimitive?.longOrNull ?: 0,
            chunksFailed = obj["chunks_failed"]?.jsonPrimitive?.longOrNull ?: 0,
            totalChunks = obj["total_chunks"]?.jsonPrimitive?.longOrNull ?: 0,
            retryable = obj["retryable"]?.jsonPrimitive?.booleanOrNull ?: false,
            statusCode = statusCode,
        )
    }

    /** True when [message] carries the daemon's fixed PARTIAL_UPLOAD prefix. */
    fun isPartialUploadMessage(message: String): Boolean = message.contains(PARTIAL_UPLOAD_PREFIX)

    /**
     * Recovers the chunk counts and the retryable hint from a PARTIAL_UPLOAD
     * message. Used for gRPC, where the status carries no structured detail;
     * REST callers get the body fields instead. A message whose counts do not
     * parse yields zero counts and `retryable = false`; whether the message is
     * a partial upload at all is decided by [isPartialUploadMessage].
     */
    fun partialUploadFromMessage(message: String): PartialUploadException {
        val m = partialUploadCounts.find(message)
        return PartialUploadException(
            message = message,
            chunksStored = m?.groupValues?.get(1)?.toLongOrNull() ?: 0,
            totalChunks = m?.groupValues?.get(2)?.toLongOrNull() ?: 0,
            chunksFailed = m?.groupValues?.get(3)?.toLongOrNull() ?: 0,
            retryable = message.contains(PARTIAL_UPLOAD_RETAINED_HINT),
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
            // "Partial upload:" prefix, so gate on it; any other ABORTED keeps
            // the pre-existing conflicting-update mapping instead of being
            // misreported as a partial upload.
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
