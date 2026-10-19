import Foundation

/// Base error for all Autonomi SDK operations.
public class AntdError: Error, CustomStringConvertible {
    public let message: String
    public let statusCode: Int

    public init(_ message: String, statusCode: Int = 0) {
        self.message = message
        self.statusCode = statusCode
    }

    public var description: String { "AntdError(\(statusCode)): \(message)" }
}

public final class NotFoundError: AntdError {
    public override init(_ message: String, statusCode: Int = 404) {
        super.init(message, statusCode: statusCode)
    }
}

public final class AlreadyExistsError: AntdError {
    public override init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

/// A version conflict or fork was detected (HTTP 409; gRPC ABORTED that is not
/// a partial upload or a tagged ``ConflictError``).
///
/// Not `final`: ``PointerForkedError`` subclasses it, so a
/// `catch let e as ForkError` also catches a forked pointer.
public class ForkError: AntdError {
    public override init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

/// The pointer is at its final state, transferred or frozen: nothing can
/// update it or hand it over again (HTTP 409 with `code: "POINTER_FINAL"`;
/// gRPC FAILED_PRECONDITION with `x-antd-error-code: POINTER_FINAL`). Refused
/// before anything is paid.
public final class PointerFinalError: AntdError {
    public override init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

/// The pointer's owner signed two different final states and no one of them
/// is held by a majority of the close group, so there is no answer to give
/// (HTTP 409 with `code: "POINTER_FORKED"`; gRPC FAILED_PRECONDITION with
/// `x-antd-error-code: POINTER_FORKED`). A ``ForkError`` subclass.
public final class PointerForkedError: ForkError {
    public override init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

/// The request conflicts with the resource's current state (HTTP 409 with
/// `code: "CONFLICT"`; gRPC ABORTED with `x-antd-error-code: CONFLICT`). For
/// pointers: a write while a prepared write to the same pointer awaits
/// payment (finalize it, or wait for it to expire), or an update that lost to
/// a newer state while it was in flight.
public final class ConflictError: AntdError {
    public override init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

/// Too few of an address's close group answered, or took a write, for the
/// result to be the network's (HTTP 503 with `code: "CLOSE_GROUP_SHORTFALL"`;
/// gRPC UNAVAILABLE with `x-antd-error-code: CLOSE_GROUP_SHORTFALL`).
///
/// Reads are free to retry. A paid write is not, unless ``retryable`` is
/// `true`: a pointer finalize then kept the paid state under the same
/// `upload_id`, and repeating that finalize stores it against the same
/// payment. Over REST ``retryable`` is the body's `retryable` field; over
/// gRPC it is set when the status message closes with the daemon's
/// `(paid attempt retained...)` hint.
///
/// A direct ``AntdError`` subclass, not a ``ServiceUnavailableError`` or
/// ``NetworkError``: catch it by name.
public final class CloseGroupShortfallError: AntdError {
    /// `true` when a pointer finalize kept the paid state for a repeat with
    /// the same `upload_id`. `false` otherwise, including every read and every
    /// daemon-wallet write.
    public let retryable: Bool

    public init(_ message: String, retryable: Bool = false, statusCode: Int = 503) {
        self.retryable = retryable
        super.init(message, statusCode: statusCode)
    }
}

public final class BadRequestError: AntdError {
    public override init(_ message: String, statusCode: Int = 400) {
        super.init(message, statusCode: statusCode)
    }
}

public final class PaymentError: AntdError {
    public override init(_ message: String, statusCode: Int = 402) {
        super.init(message, statusCode: statusCode)
    }
}

/// A connection or upstream failure (HTTP 502, gRPC UNAVAILABLE).
///
/// Not `final`: ``PartialUploadError`` subclasses it, so a
/// `catch let e as NetworkError` written before that typed error existed
/// still catches a partial upload (which is also an HTTP 502).
public class NetworkError: AntdError {
    public override init(_ message: String, statusCode: Int = 502) {
        super.init(message, statusCode: statusCode)
    }
}

public final class TooLargeError: AntdError {
    public override init(_ message: String, statusCode: Int = 413) {
        super.init(message, statusCode: statusCode)
    }
}

public final class InternalError: AntdError {
    public override init(_ message: String, statusCode: Int = 500) {
        super.init(message, statusCode: statusCode)
    }
}

public final class ServiceUnavailableError: AntdError {
    public override init(_ message: String, statusCode: Int = 503) {
        super.init(message, statusCode: statusCode)
    }
}

/// The client does not implement the operation. Thrown on the client side,
/// never by the daemon (``statusCode`` is 0): the default implementations of
/// the pointer methods on ``AntdClientProtocol`` throw it, so a type that
/// conformed to the protocol before those methods existed keeps compiling.
/// ``AntdRestClient`` and ``AntdGrpcClient`` implement every method.
public final class NotSupportedError: AntdError {
    public override init(_ message: String, statusCode: Int = 0) {
        super.init(message, statusCode: statusCode)
    }
}

/// A finalize stored some chunks while others remained unstored after the
/// daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED
/// whose message starts with `Partial upload:`). The on-chain payment
/// persists and the stored chunks stay on the network. How to finish the
/// upload depends on ``retryable`` and ``retentionKnown``:
///
/// - ``retryable``: the daemon kept the paid attempt (payment proofs +
///   unstored chunks) under the same `upload_id`. Call the **same** finalize
///   method again with the same `upload_id` and the same payment artefacts
///   to store the remainder against the same payment — no re-prepare, no
///   second signature, no double payment. Bound the loop: a persistent
///   failure throws this error on every call, so cap the attempts and treat
///   a ``chunksFailed`` that stops shrinking as stuck. The retained attempt
///   expires with the daemon's pending-upload TTL. (antd >= 0.14.0.)
/// - ``retentionKnown`` and not ``retryable``: the daemon confirmed it kept
///   nothing (for example a merkle finalize with deliberately unpaid
///   batches). Re-preparing the same content skips already-stored chunks, so
///   a retry pays only for the missing remainder.
/// - Not ``retentionKnown``: retention is unknown, and the daemon may still
///   hold the paid attempt. Stop automatic recovery, keep the `upload_id`
///   and the original payment artefacts (transaction hashes or winner pool
///   hash), and reconcile before re-preparing or paying again. Never pay
///   again on this signal alone. Daemons older than 0.14.0 never send
///   `retryable`, so their REST partial uploads read as unknown. Over gRPC,
///   a status message without a readable closing retention hint also reads
///   as unknown.
///
/// ``retryable`` implies ``retentionKnown``.
///
/// Over REST the counts and `retryable` come from the structured error body.
/// The counts must be JSON non-negative integers that fit in `UInt64` and
/// `retryable` a JSON boolean; a body where any of those (or `error` /
/// `code`) carries another JSON type, such as a quoted `"1"` or `"true"`,
/// does not decode and keeps the status-based mapping (a 502 stays a plain
/// ``NetworkError``). Absent or `null` counts read zero. ``retentionKnown``
/// is `true` only when the body carries `retryable` as a JSON boolean; an
/// absent or `null` `retryable` reads as unknown retention, not retryable.
///
/// Over gRPC they are parsed from the status message (`Partial upload: S/T
/// chunks stored, F failed after retries: <reason> (<hint>)`). The daemon
/// closes the message with one of two hints: `(paid attempt retained...)`
/// when it kept the paid attempt, `(stored chunks persist; re-prepare the
/// same content...)` when it did not (daemons older than 0.14.0 write only
/// the second). Only an ABORTED whose message **starts with** the daemon's
/// fixed `Partial upload:` prefix maps here; any other ABORTED, including one
/// that merely mentions the prefix later in its text, keeps the
/// ``ForkError`` mapping. ``retentionKnown`` is `true` only when the counts
/// pattern matched at the start of the message, all three counts converted
/// to `UInt64`, and the message ends with one of the two hints; the hint
/// then decides ``retryable``. On a pattern miss or a failed conversion the
/// counts read zero, retention is unknown and ``retryable`` is `false`.
/// Readable counts with a missing, truncated or unrecognised hint, or with
/// text after it, keep the counts, but retention is still unknown and
/// ``retryable`` is `false`: the daemon's answer was not read, so stop and
/// reconcile rather than re-prepare. A garbled message therefore neither
/// enables the same-`upload_id` retry nor reads as a confirmed "nothing
/// retained". SDK releases up to 0.13.x mapped every
/// gRPC ABORTED to ``ForkError``; a partial-upload ABORTED now maps here
/// (besides `PARTIAL_UPLOAD`, the daemon emits ABORTED only for `CONFLICT`,
/// tagged with `x-antd-error-code`, which maps to ``ConflictError``). See
/// `docs/external-signer-flow.md` §6.
///
/// A subclass of ``NetworkError``, the type a REST partial upload mapped to
/// before this error existed, so an existing `catch let e as NetworkError`
/// still catches it. Catch `PartialUploadError` *before* `NetworkError` to
/// act on the flags above: a paid, partly stored upload is not a plain
/// transport failure.
public final class PartialUploadError: NetworkError {
    /// Chunks the daemon confirmed stored.
    public let chunksStored: UInt64
    /// Chunks still unstored after the daemon's retries.
    public let chunksFailed: UInt64
    /// Chunks in the upload.
    public let totalChunks: UInt64
    /// The daemon kept the paid attempt under the same `upload_id`: repeat
    /// the same finalize call, bounded. Implies ``retentionKnown``.
    public let retryable: Bool
    /// Whether the daemon's answer on retention is known. `true`: it either
    /// kept the paid attempt (``retryable``) or confirmed it kept nothing
    /// (re-prepare). `false`: unknown, and the daemon may still hold the paid
    /// attempt; stop automatic recovery, keep the `upload_id` and payment
    /// artefacts, and reconcile before re-preparing or paying again.
    public let retentionKnown: Bool

    /// `retryable` holds only together with `retentionKnown`: an attempt the
    /// daemon is not known to hold is never marked retryable.
    public init(
        _ message: String,
        chunksStored: UInt64,
        chunksFailed: UInt64,
        totalChunks: UInt64,
        retryable: Bool,
        retentionKnown: Bool,
        statusCode: Int = 502
    ) {
        self.chunksStored = chunksStored
        self.chunksFailed = chunksFailed
        self.totalChunks = totalChunks
        self.retryable = retryable && retentionKnown
        self.retentionKnown = retentionKnown
        super.init(message, statusCode: statusCode)
    }
}

enum ErrorMapping {

    /// Machine-readable `code` the daemon sends for a partial store.
    static let partialUploadCode = "PARTIAL_UPLOAD"

    /// Codes the daemon sends for errors that share a status with older ones.
    /// REST carries them in the body's `code`; gRPC in the
    /// ``antdErrorCodeMetadataKey`` trailer.
    static let pointerFinalCode = "POINTER_FINAL"
    static let pointerForkedCode = "POINTER_FORKED"
    static let conflictCode = "CONFLICT"
    static let closeGroupShortfallCode = "CLOSE_GROUP_SHORTFALL"

    /// gRPC metadata key the daemon sets on statuses whose code is shared with
    /// older errors, carrying the REST `code` string.
    static let antdErrorCodeMetadataKey = "x-antd-error-code"

    /// Fixed opening text of every `PARTIAL_UPLOAD` message the daemon emits.
    /// Over gRPC (where the status carries no structured `code`) this is what
    /// distinguishes a partial upload from any other ABORTED.
    static let partialUploadMessagePrefix = "Partial upload:"

    /// The daemon closes every `PARTIAL_UPLOAD` message with one of two
    /// parenthesised hints (`partial_upload_hint` in antd/src/error.rs): the
    /// retained hint when it kept the paid attempt for a same-`upload_id`
    /// retry, the not-retained hint when it did not. Daemons older than
    /// 0.14.0 write only the not-retained hint.
    static let partialUploadRetainedHint = "paid attempt retained"
    static let partialUploadNotRetainedHint = "stored chunks persist; re-prepare the same content"

    /// The hint that closes the message: `(<hint>...)` at the very end. The
    /// end anchor is `\z`, not `$`, which in ICU also matches before a
    /// trailing line terminator. A hint quoted inside the failure reason, a
    /// truncated or unclosed tail, or text after the hint does not match.
    private static let partialUploadRetentionTailPattern =
        #"\(("#
        + NSRegularExpression.escapedPattern(for: partialUploadRetainedHint)
        + "|"
        + NSRegularExpression.escapedPattern(for: partialUploadNotRetainedHint)
        + #")[^()]*\)\z"#

    /// Fixed prefix of the daemon's `PARTIAL_UPLOAD` message:
    /// `Partial upload: <stored>/<total> chunks stored, <failed> failed`.
    /// Matched only at the start of the message (see
    /// ``parsePartialUploadMessage(_:)``).
    private static let partialUploadCountsPattern =
        #"Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed"#

    /// Shape of the daemon's `{"error": ..., "code": ...}` envelope. The
    /// count fields are only present for `PARTIAL_UPLOAD`, and `retryable`
    /// only for `PARTIAL_UPLOAD` and a `CLOSE_GROUP_SHORTFALL` from a pointer
    /// finalize; `retryable` is also absent on daemons older than 0.14.0.
    ///
    /// The fields are typed, so the envelope enforces the wire contract: a
    /// count that is not a JSON non-negative integer within `UInt64` (a
    /// string, a boolean, a negative number, an array, an out-of-range
    /// value), a `retryable` that is not a JSON boolean, or an `error` /
    /// `code` that is not a JSON string fails the whole decode. The caller
    /// then keeps the status-based mapping instead of trusting the field.
    private struct ErrorBodyDTO: Decodable {
        let error: String?
        let code: String?
        let chunksStored: UInt64?
        let chunksFailed: UInt64?
        let totalChunks: UInt64?
        let retryable: Bool?

        enum CodingKeys: String, CodingKey {
            case error
            case code
            case chunksStored = "chunks_stored"
            case chunksFailed = "chunks_failed"
            case totalChunks = "total_chunks"
            case retryable
        }
    }

    /// Maps a non-2xx REST response to an ``AntdError``. `body` is the raw
    /// response body. When it is the daemon's JSON envelope with
    /// `code == "PARTIAL_UPLOAD"` the structured counts and `retryable` flag
    /// are surfaced as a ``PartialUploadError``. Absent or `null` counts read
    /// zero. `retentionKnown` is `true` only when `retryable` is present as a
    /// JSON boolean, so an absent or `null` `retryable` (daemons older than
    /// 0.14.0) reads as unknown retention and not retryable. The codes that
    /// share a status with older errors map to their own types:
    /// `POINTER_FINAL` → ``PointerFinalError``, `POINTER_FORKED` →
    /// ``PointerForkedError``, `CONFLICT` → ``ConflictError`` (all 409s, never
    /// ``AlreadyExistsError``), and `CLOSE_GROUP_SHORTFALL` →
    /// ``CloseGroupShortfallError`` (a 503, with `retryable` only when the
    /// body says `true`). Their message is the body's `error` text. Every other
    /// body, including an envelope whose fields carry the wrong JSON types
    /// (see ``ErrorBodyDTO``), keeps the status-based mapping, so a malformed
    /// body always yields a typed ``AntdError`` and no decoding error
    /// reaches the caller.
    static func fromHTTPStatus(_ statusCode: Int, body: String) -> AntdError {
        if let envelope = try? JSONDecoder().decode(ErrorBodyDTO.self, from: Data(body.utf8)) {
            if envelope.code == partialUploadCode {
                return PartialUploadError(
                    envelope.error ?? body,
                    chunksStored: envelope.chunksStored ?? 0,
                    chunksFailed: envelope.chunksFailed ?? 0,
                    totalChunks: envelope.totalChunks ?? 0,
                    retryable: envelope.retryable ?? false,
                    retentionKnown: envelope.retryable != nil,
                    statusCode: statusCode
                )
            }
            // The codes that share an HTTP status with older errors: the 409s
            // must not read as AlreadyExistsError, nor the shortfall's 503 as
            // ServiceUnavailableError.
            let message = envelope.error ?? body
            switch envelope.code {
            case pointerFinalCode:
                return PointerFinalError(message, statusCode: statusCode)
            case pointerForkedCode:
                return PointerForkedError(message, statusCode: statusCode)
            case conflictCode:
                return ConflictError(message, statusCode: statusCode)
            case closeGroupShortfallCode:
                // Present, and true, only on a pointer finalize that kept the
                // paid state; anything else reads as not retained.
                return CloseGroupShortfallError(
                    message,
                    retryable: envelope.retryable == true,
                    statusCode: statusCode
                )
            default:
                break
            }
        }
        switch statusCode {
        case 400: return BadRequestError(body, statusCode: statusCode)
        case 402: return PaymentError(body, statusCode: statusCode)
        case 404: return NotFoundError(body, statusCode: statusCode)
        case 409: return AlreadyExistsError(body, statusCode: statusCode)
        case 413: return TooLargeError(body, statusCode: statusCode)
        case 500: return InternalError(body, statusCode: statusCode)
        case 502: return NetworkError(body, statusCode: statusCode)
        case 503: return ServiceUnavailableError(body, statusCode: statusCode)
        default: return AntdError(body, statusCode: statusCode)
        }
    }

    /// Maps a failed gRPC call to an ``AntdError``. `antdErrorCode` is the
    /// daemon's `x-antd-error-code` trailer, when it sent one.
    static func fromGRPCStatus(code: Int, detail: String, antdErrorCode: String? = nil) -> AntdError {
        if let typed = fromTaggedGRPCStatus(code: code, detail: detail, antdErrorCode: antdErrorCode) {
            return typed
        }
        // gRPC status codes: 5=NOT_FOUND, 6=ALREADY_EXISTS, 10=ABORTED,
        // 3=INVALID_ARGUMENT, 9=FAILED_PRECONDITION, 14=UNAVAILABLE,
        // 8=RESOURCE_EXHAUSTED, 13=INTERNAL
        switch code {
        case 5: return NotFoundError(detail)
        case 6: return AlreadyExistsError(detail)
        case 10:
            // The daemon's PARTIAL_UPLOAD rides gRPC as ABORTED: some chunks
            // stored, some still unstored after retries. The counts and the
            // daemon's closing retention hint ride the message text (no
            // structured detail yet), so parse them to match the REST
            // client's typed error. Status 502 mirrors the REST mapping.
            // Every such message opens with the daemon's fixed "Partial
            // upload:" prefix, so gate on the message starting with it: any
            // other ABORTED, including one that only mentions the prefix
            // further in (e.g. a wrapped upstream error), keeps the
            // pre-existing ForkError mapping rather than being misreported
            // as a partial upload. `detail` is the raw status message
            // (`RPCError.message`), not `RPCError.description`, which would
            // put the status code in front of it.
            if detail.hasPrefix(partialUploadMessagePrefix) {
                let parsed = parsePartialUploadMessage(detail)
                return PartialUploadError(
                    detail,
                    chunksStored: parsed.chunksStored,
                    chunksFailed: parsed.chunksFailed,
                    totalChunks: parsed.totalChunks,
                    retryable: parsed.retryable,
                    retentionKnown: parsed.retentionKnown,
                    statusCode: 502
                )
            }
            return ForkError(detail)
        case 3: return BadRequestError(detail)
        case 9: return PaymentError(detail)
        case 14: return NetworkError(detail)
        case 8: return TooLargeError(detail)
        case 13: return InternalError(detail)
        default: return AntdError(detail, statusCode: code)
        }
    }

    /// The typed error for a status the daemon tagged with
    /// `x-antd-error-code`, when the tag and the gRPC code agree:
    /// FAILED_PRECONDITION (9) for `POINTER_FINAL` / `POINTER_FORKED`, ABORTED
    /// (10) for `CONFLICT`, UNAVAILABLE (14) for `CLOSE_GROUP_SHORTFALL`.
    /// Anything else (no tag, a tag this SDK does not know, or a tag on an
    /// unexpected code) is `nil` and keeps the code-based mapping, so an
    /// untagged FAILED_PRECONDITION is still a ``PaymentError``.
    private static func fromTaggedGRPCStatus(code: Int, detail: String, antdErrorCode: String?) -> AntdError? {
        guard let tag = antdErrorCode else { return nil }
        switch (code, tag) {
        case (9, pointerFinalCode):
            return PointerFinalError(detail)
        case (9, pointerForkedCode):
            return PointerForkedError(detail)
        case (10, conflictCode):
            return ConflictError(detail)
        case (14, closeGroupShortfallCode):
            // gRPC carries no structured detail: a retained pointer finalize
            // closes its message with the same "(paid attempt retained...)"
            // hint a retained partial upload does.
            return CloseGroupShortfallError(detail, retryable: closingRetentionHint(detail) == true)
        default:
            return nil
        }
    }

    /// Reads the parenthesised hint that closes a daemon message (see
    /// `partialUploadRetentionTailPattern`): `true` for the retained hint,
    /// `false` for the not-retained hint, `nil` when the message does not end
    /// with either (missing, truncated, quoted mid-message, or followed by
    /// more text).
    static func closingRetentionHint(_ message: String) -> Bool? {
        guard let tailRegex = try? NSRegularExpression(pattern: partialUploadRetentionTailPattern),
              let tail = tailRegex.firstMatch(
                  in: message,
                  range: NSRange(message.startIndex..., in: message)
              ),
              let hintRange = Range(tail.range(at: 1), in: message)
        else {
            return nil
        }
        return message[hintRange] == partialUploadRetainedHint
    }

    /// Recovers the chunk counts and the retention flags from a
    /// `PARTIAL_UPLOAD` message. Used for gRPC, where the status carries no
    /// structured detail; REST callers get the body fields instead.
    ///
    /// The counts are all or nothing: the counts pattern must match at the
    /// start of the message and all three counts must convert to `UInt64` (a
    /// value past `UInt64.max` does not). On a pattern miss or any failed
    /// conversion every count is zero and both flags are `false`, even when
    /// a hint is present. With the counts read, `retentionKnown` is `true`
    /// only when the message ends with one of the daemon's two hints (see
    /// `partialUploadRetentionTailPattern`), and `retryable` only when that
    /// hint is ``partialUploadRetainedHint``. Readable counts with a missing,
    /// truncated or unrecognised tail, or text after it, keep the counts but
    /// leave both flags `false`: the daemon's answer on retention was not
    /// read, so retention is unknown, never "nothing retained". A message
    /// the SDK could not fully read therefore never enables the
    /// same-`upload_id` retry and never reads as a confirmed "nothing
    /// retained" either. Callers decide whether the message is a partial
    /// upload at all (see ``partialUploadMessagePrefix``); this parser does
    /// not.
    static func parsePartialUploadMessage(
        _ message: String
    ) -> (chunksStored: UInt64, chunksFailed: UInt64, totalChunks: UInt64, retryable: Bool, retentionKnown: Bool) {
        guard let regex = try? NSRegularExpression(pattern: partialUploadCountsPattern),
              let match = regex.firstMatch(
                  in: message,
                  options: [.anchored],
                  range: NSRange(message.startIndex..., in: message)
              ),
              match.numberOfRanges == 4,
              let storedRange = Range(match.range(at: 1), in: message),
              let totalRange = Range(match.range(at: 2), in: message),
              let failedRange = Range(match.range(at: 3), in: message),
              let stored = UInt64(message[storedRange]),
              let total = UInt64(message[totalRange]),
              let failed = UInt64(message[failedRange])
        else {
            return (0, 0, 0, false, false)
        }
        guard let retained = closingRetentionHint(message) else {
            return (stored, failed, total, false, false)
        }
        return (stored, failed, total, retained, true)
    }
}
