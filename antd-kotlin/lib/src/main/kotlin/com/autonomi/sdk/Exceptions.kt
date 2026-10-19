package com.autonomi.sdk

import io.grpc.Metadata
import io.grpc.StatusRuntimeException
import io.grpc.Status
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

open class AntdException(message: String, val statusCode: Int = 0) : Exception(message)

class NotFoundException(message: String, statusCode: Int = 404) : AntdException(message, statusCode)
class AlreadyExistsException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)

/**
 * A version conflict or fork (HTTP 409; gRPC ABORTED that is not a partial
 * upload). Open so [PointerForkedException] can narrow it.
 */
open class ForkException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)
class BadRequestException(message: String, statusCode: Int = 400) : AntdException(message, statusCode)
class PaymentException(message: String, statusCode: Int = 402) : AntdException(message, statusCode)
open class NetworkException(message: String, statusCode: Int = 502) : AntdException(message, statusCode)
class TooLargeException(message: String, statusCode: Int = 413) : AntdException(message, statusCode)
class InternalException(message: String, statusCode: Int = 500) : AntdException(message, statusCode)
class ServiceUnavailableException(message: String, statusCode: Int = 503) : AntdException(message, statusCode)

/**
 * The pointer is at its final state, transferred or frozen: nothing can update
 * it or hand it over again (HTTP 409 with `code: "POINTER_FINAL"`; gRPC
 * FAILED_PRECONDITION with `x-antd-error-code: POINTER_FINAL`). Refused
 * before anything is paid.
 */
class PointerFinalException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)

/**
 * The pointer's owner signed two different final states and no one of them
 * is held by a majority of the close group, so there is no answer to give
 * (HTTP 409 with `code: "POINTER_FORKED"`; gRPC FAILED_PRECONDITION with
 * `x-antd-error-code: POINTER_FORKED`). A [ForkException], so existing
 * `catch (e: ForkException)` blocks see it too.
 */
class PointerForkedException(message: String, statusCode: Int = 409) : ForkException(message, statusCode)

/**
 * The request conflicts with the resource's current state (HTTP 409 with
 * `code: "CONFLICT"`; gRPC ABORTED with `x-antd-error-code: CONFLICT`). For
 * pointers: a write while a prepared write to the same pointer awaits payment
 * (finalize it, or wait for it to expire), or an update that lost to a newer
 * state while it was in flight.
 */
class ConflictException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)

/**
 * Too few of an address's close group answered, or took a write, for the
 * result to be the network's (HTTP 503 with `code: "CLOSE_GROUP_SHORTFALL"`;
 * gRPC UNAVAILABLE with `x-antd-error-code: CLOSE_GROUP_SHORTFALL`). It can
 * come from any call, not only pointers; daemons before the pointer API
 * reported it as a 500.
 *
 * Reads are free to retry. A paid write is not, unless [retryable] is true: a
 * pointer finalize then kept the paid state under the same `upload_id`, and
 * repeating that finalize stores it against the same payment. Bound that loop.
 *
 * Over REST [retryable] is the body's `retryable` when it is the JSON literal
 * `true`; over gRPC, whether the message closes with the daemon's
 * "(paid attempt retained...)" hint. Anything else reads as false.
 */
class CloseGroupShortfallException(
    message: String,
    val retryable: Boolean = false,
    statusCode: Int = 503,
) : AntdException(message, statusCode)

/**
 * A finalize stored some chunks while others remained unstored after the
 * daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED).
 * The on-chain payment persists and the stored chunks stay on the network.
 * How to finish the upload depends on [retryable] and [retentionKnown]
 * ([retryable] implies [retentionKnown]):
 *
 * - [retryable]: the daemon kept the paid attempt (payment proofs +
 *   unstored chunks) under the same `upload_id`. Call the **same** finalize
 *   method again with the same `upload_id` and payment artefacts to store
 *   the remainder against the same payment — no re-prepare, no second
 *   signature, no double payment. Bound the loop: a persistent failure
 *   throws this exception on every call, so cap the attempts and treat a
 *   [chunksFailed] that stops shrinking as stuck. The retained attempt
 *   expires with the daemon's pending-upload TTL.
 * - [retentionKnown] and not [retryable]: the daemon confirmed it kept
 *   nothing (e.g. a merkle finalize with deliberately unpaid batches).
 *   Re-prepare the same content; already-stored chunks are skipped, so the
 *   retry pays only for the missing remainder.
 * - not [retentionKnown]: retention is unknown, and the daemon may still
 *   hold the paid attempt (it records the resume handle before it returns
 *   the error). Stop automatic recovery, keep the `upload_id` and the
 *   original payment artefacts (tx hashes / quote data), and reconcile
 *   before re-preparing or paying again. Never pay again on this signal
 *   alone. Daemons older than 0.14.0 never send `retryable`, so their REST
 *   partial uploads always read as unknown.
 *
 * Extends [NetworkException] because a `PARTIAL_UPLOAD` arrives as a 502,
 * which this SDK has always mapped to [NetworkException]; existing
 * `catch (e: NetworkException)` blocks keep working and can narrow with
 * `is PartialUploadException` when they want the counts and flags. It is
 * not a [ForkException]: over gRPC a partial upload's ABORTED used to map
 * there, and around a finalize the daemon sends ABORTED only for
 * PARTIAL_UPLOAD (its other ABORTED, a pointer CONFLICT, is tagged and maps
 * to [ConflictException]), so code that caught [ForkException] around a gRPC
 * finalize should catch [PartialUploadException] instead.
 *
 * Over REST the counts and flags come from the structured error body. Each
 * count is read only from a JSON number holding a non-negative integer;
 * anything else (missing, a quoted number, a negative, fractional or
 * out-of-range number, an array or an object) reads as zero.
 * [retentionKnown] is true when the body's `retryable` is a JSON boolean
 * (`true` or `false`), and [retryable] when it is the literal `true`;
 * missing, `null`, a quoted `"true"`, a number, an array or an object reads
 * as unknown and not retryable. The mapper never throws.
 *
 * Over gRPC they are parsed from the status description,
 * `Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)`,
 * where the daemon's closing hint starts "paid attempt retained" when it
 * kept the paid attempt and "stored chunks persist; re-prepare the same
 * content" when it did not (daemons older than 0.14.0 write only the
 * second). [retentionKnown] is true only when the description starts with
 * that layout, all three counts convert to a [Long], and the description
 * ends with one of the two hints; the hint then decides [retryable]. On a
 * layout mismatch or a count that does not convert, all three counts are
 * zero and both flags are false even if a hint is present. Readable counts
 * with a missing, truncated or unrecognised hint, or text after it, keep
 * the counts but leave both flags false: retention unknown (stop and
 * reconcile), not "nothing retained". A caller never retries, re-prepares
 * or pays again on a message the SDK could not fully read.
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
    retentionKnown: Boolean = retryable,
    statusCode: Int = 502,
) : NetworkException(message, statusCode) {
    /**
     * Whether the daemon's answer on retaining the paid attempt was read:
     * `true` when it confirmed either way, `false` when retention is
     * unknown. Always `true` when [retryable] is.
     */
    val retentionKnown: Boolean = retentionKnown || retryable
}

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
     * Fixed prefix of the daemon's PARTIAL_UPLOAD message, anchored at the
     * start like [isPartialUploadMessage]:
     * `Partial upload: <stored>/<total> chunks stored, <failed> failed`.
     */
    private val partialUploadCounts = Regex("^$PARTIAL_UPLOAD_PREFIX (\\d+)/(\\d+) chunks stored, (\\d+) failed")

    /**
     * The daemon closes every PARTIAL_UPLOAD message with one of two
     * parenthesised hints (`partial_upload_hint` in `antd/src/error.rs`): the
     * retained hint when it kept the paid attempt for a same-upload_id retry,
     * the not-retained hint when it did not. Daemons older than 0.14.0 write
     * only the not-retained hint.
     */
    private const val PARTIAL_UPLOAD_RETAINED_HINT = "paid attempt retained"
    private const val PARTIAL_UPLOAD_NOT_RETAINED_HINT = "stored chunks persist; re-prepare the same content"

    /**
     * The hint that closes the message: `(<hint>...)` at the very end of the
     * input (`\z`, not `$`, which would also match before a trailing line
     * terminator). A hint quoted inside the failure reason, a truncated or
     * unclosed tail, or any text after the hint does not match.
     */
    private val partialUploadRetentionTail = Regex(
        "\\((" + Regex.escape(PARTIAL_UPLOAD_RETAINED_HINT) + "|" +
            Regex.escape(PARTIAL_UPLOAD_NOT_RETAINED_HINT) + ")[^()]*\\)\\z",
    )

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * gRPC metadata key the daemon (with the pointer API, after 0.15.0) sets
     * on statuses whose code is shared with older errors, carrying the REST
     * `code` string.
     */
    private val ANTD_ERROR_CODE: Metadata.Key<String> =
        Metadata.Key.of("x-antd-error-code", Metadata.ASCII_STRING_MARSHALLER)

    /**
     * Maps a REST error response onto a typed exception, preferring the
     * machine-readable `code` over the bare HTTP status where they diverge:
     * `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a plain
     * [NetworkException]; `POINTER_FINAL`, `POINTER_FORKED` and `CONFLICT`
     * are 409s that must not read as [AlreadyExistsException]; and
     * `CLOSE_GROUP_SHORTFALL` is a 503 that must not read as
     * [ServiceUnavailableException]. Every other status keeps its
     * status-based mapping.
     */
    fun fromHttpStatus(statusCode: Int, body: String): AntdException {
        val obj = errorObject(body)
        return obj?.let { partialUploadFromBody(statusCode, body, it) }
            ?: obj?.let { codedErrorFromBody(statusCode, body, it) }
            ?: fromHttpStatusOnly(statusCode, body)
    }

    /** [body] as a JSON object, or null when it is not one. Never throws. */
    private fun errorObject(body: String): JsonObject? = try {
        json.parseToJsonElement(body) as? JsonObject
    } catch (_: Exception) {
        null
    }

    /**
     * The typed exception for the daemon codes that share an HTTP status with
     * older errors (the pointer 409s and `CLOSE_GROUP_SHORTFALL`'s 503), or
     * null for any other `code`. The message is the body's `error` string,
     * falling back to the raw body. A `retryable` that is not the JSON literal
     * `true` reads as false.
     */
    private fun codedErrorFromBody(statusCode: Int, body: String, obj: JsonObject): AntdException? {
        val code = obj.primitive("code")?.takeIf { it.isString }?.content ?: return null
        val message = obj.primitive("error")?.takeIf { it.isString }?.content ?: body
        return when (code) {
            "POINTER_FINAL" -> PointerFinalException(message, statusCode)
            "POINTER_FORKED" -> PointerForkedException(message, statusCode)
            "CONFLICT" -> ConflictException(message, statusCode)
            "CLOSE_GROUP_SHORTFALL" ->
                CloseGroupShortfallException(message, retryable = obj.flag("retryable") == true, statusCode = statusCode)
            else -> null
        }
    }

    /**
     * Returns a [PartialUploadException] when [obj] is a JSON error object
     * whose `code` is the string `"PARTIAL_UPLOAD"`, carrying its counts.
     * A boolean `retryable` makes retention known and sets `retryable`;
     * daemons < 0.14.0 never send it, so their retention reads as unknown.
     * Returns null for every other body (a `code` that is missing, another
     * value, or not a string), so the caller's other mappings apply. Counts
     * go through [count] and `retryable` through [flag]: a value of any other
     * kind (a quoted number or quoted `"true"`, a negative or fractional
     * number, an object or an array) reads as absent, zero or `false`, rather
     * than being coerced or escaping as a serialization error. The daemon's
     * error body is input from the network and must never turn a typed
     * [AntdException] into an [IllegalArgumentException].
     */
    private fun partialUploadFromBody(statusCode: Int, body: String, obj: JsonObject): PartialUploadException? {
        val code = obj.primitive("code")
        if (code == null || !code.isString || code.content != PARTIAL_UPLOAD_CODE) return null
        val retained = obj.flag("retryable")
        return PartialUploadException(
            message = obj.primitive("error")?.takeIf { it.isString }?.content ?: body,
            chunksStored = obj.count("chunks_stored"),
            chunksFailed = obj.count("chunks_failed"),
            totalChunks = obj.count("total_chunks"),
            retryable = retained == true,
            retentionKnown = retained != null,
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
     * The boolean at [key]: `true` / `false` only for the JSON literals
     * `true` / `false`, and `null` for anything else: absent, `null`, the
     * string `"true"`, a number, an object or an array.
     */
    private fun JsonObject.flag(key: String): Boolean? =
        when (primitive(key)?.takeUnless { it.isString }?.content) {
            "true" -> true
            "false" -> false
            else -> null
        }

    /**
     * True when [message] starts with the daemon's fixed PARTIAL_UPLOAD
     * prefix. Anchored rather than a containment check so an unrelated
     * ABORTED that merely quotes the phrase is not misreported as a partial
     * upload; the daemon never wraps its own message, so the prefix is
     * always at offset zero when it is a partial upload.
     */
    fun isPartialUploadMessage(message: String): Boolean = message.startsWith(PARTIAL_UPLOAD_PREFIX)

    /**
     * Recovers the chunk counts and the retention flags from a PARTIAL_UPLOAD
     * message. Used for gRPC, where the status carries no structured detail;
     * REST callers get the body fields instead. `retentionKnown` is true only
     * when the message starts with the count layout, all three counts
     * convert to a [Long], and the message ends with one of the daemon's two
     * hints, "(paid attempt retained...)" or "(stored chunks persist;
     * re-prepare the same content...)"; `retryable` is then true only for
     * the first. The layout accepts any run of digits, so a count past
     * [Long.MAX_VALUE] matches but does not convert. On a layout mismatch or
     * a failed conversion all three counts are zero and both flags are false,
     * even when a hint is present: a retry loop that cannot see
     * [PartialUploadException.chunksFailed] shrinking has no way to tell
     * progress from a stuck upload. Readable counts with a missing, truncated
     * or unrecognised hint, or text after it, keep the counts but leave both
     * flags false: the daemon's answer on retention was not read, so
     * retention is unknown, never "nothing retained". Whether the message is
     * a partial upload at all is decided by [isPartialUploadMessage].
     */
    fun partialUploadFromMessage(message: String): PartialUploadException {
        val counts = partialUploadCounts.find(message)?.groupValues?.let { g ->
            val stored = g[1].toLongOrNull()
            val total = g[2].toLongOrNull()
            val failed = g[3].toLongOrNull()
            if (stored != null && total != null && failed != null) Triple(stored, total, failed) else null
        }
        // The closing hint is the daemon's answer on retention; it is read
        // only alongside counts that converted.
        val hint = counts?.let { partialUploadRetentionTail.find(message)?.groupValues?.get(1) }
        return PartialUploadException(
            message = message,
            chunksStored = counts?.first ?: 0,
            totalChunks = counts?.second ?: 0,
            chunksFailed = counts?.third ?: 0,
            retryable = hint == PARTIAL_UPLOAD_RETAINED_HINT,
            retentionKnown = hint != null,
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

    /**
     * Whether [message] closes with the daemon's "(paid attempt retained...)"
     * hint, read the way [partialUploadFromMessage] reads it: a pointer
     * finalize's CLOSE_GROUP_SHORTFALL closes its message the same way a
     * retained PARTIAL_UPLOAD does.
     */
    private fun closesWithRetainedHint(message: String): Boolean =
        partialUploadRetentionTail.find(message)?.groupValues?.get(1) == PARTIAL_UPLOAD_RETAINED_HINT

    /**
     * The typed exception for a status the daemon tagged with
     * `x-antd-error-code`, when the tag and the gRPC code agree:
     * FAILED_PRECONDITION for POINTER_FINAL / POINTER_FORKED, ABORTED for
     * CONFLICT, UNAVAILABLE for CLOSE_GROUP_SHORTFALL. Anything else (no
     * trailers, no tag, a tag this SDK does not know, or a tag on an
     * unexpected code) is null and keeps the code-based mapping, so a
     * FAILED_PRECONDITION without a tag is still a [PaymentException].
     */
    private fun taggedGrpcError(code: Status.Code, detail: String, trailers: Metadata?): AntdException? {
        val tag = trailers?.get(ANTD_ERROR_CODE) ?: return null
        return when {
            code == Status.Code.FAILED_PRECONDITION && tag == "POINTER_FINAL" -> PointerFinalException(detail)
            code == Status.Code.FAILED_PRECONDITION && tag == "POINTER_FORKED" -> PointerForkedException(detail)
            code == Status.Code.ABORTED && tag == "CONFLICT" -> ConflictException(detail)
            code == Status.Code.UNAVAILABLE && tag == "CLOSE_GROUP_SHORTFALL" ->
                // gRPC carries no structured detail: a pointer finalize that
                // kept the paid state closes its message with the same
                // "(paid attempt retained...)" hint a retained partial upload does.
                CloseGroupShortfallException(detail, retryable = closesWithRetainedHint(detail))
            else -> null
        }
    }

    fun fromGrpcStatus(ex: StatusRuntimeException): AntdException =
        fromGrpcStatus(ex.status, ex.trailers, ex.message)

    /**
     * Maps a failed gRPC [status] and the [trailers] it came with onto the
     * typed exception the REST client throws for the same daemon error. The
     * trailers carry `x-antd-error-code` for the errors that share a status
     * code with older ones; see [taggedGrpcError].
     */
    fun fromGrpcStatus(status: Status, trailers: Metadata?, fallbackMessage: String? = null): AntdException {
        val detail = status.description ?: fallbackMessage ?: "Unknown error"
        taggedGrpcError(status.code, detail, trailers)?.let { return it }
        return when (status.code) {
            Status.Code.NOT_FOUND -> NotFoundException(detail)
            Status.Code.ALREADY_EXISTS -> AlreadyExistsException(detail)
            // PARTIAL_UPLOAD: some chunks stored, some still unstored after
            // retries. The counts and the daemon's closing retention hint
            // ride the status description over gRPC (no structured detail
            // yet), so parse them to match the REST client's typed
            // exception; retention reads as known only when both parse (see
            // partialUploadFromMessage). The daemon's message always opens
            // with the fixed "Partial upload:" prefix, so gate on the
            // description starting with it; any other ABORTED keeps the
            // pre-existing conflicting-update mapping instead of being
            // misreported as a partial upload.
            Status.Code.ABORTED ->
                if (isPartialUploadMessage(detail)) partialUploadFromMessage(detail) else ForkException(detail)
            Status.Code.INVALID_ARGUMENT -> BadRequestException(detail)
            Status.Code.FAILED_PRECONDITION -> PaymentException(detail)
            Status.Code.UNAVAILABLE -> NetworkException(detail)
            Status.Code.RESOURCE_EXHAUSTED -> TooLargeException(detail)
            Status.Code.INTERNAL -> InternalException(detail)
            else -> AntdException(detail, status.code.value())
        }
    }
}
