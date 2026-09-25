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

public final class ForkError: AntdError {
    public override init(_ message: String, statusCode: Int = 409) {
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
///   `retryable`, so their REST partial uploads read as unknown.
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
/// chunks stored, F failed ...`, with a `paid attempt retained` hint when
/// retryable). Only an ABORTED whose message **starts with** the daemon's
/// fixed `Partial upload:` prefix maps here; any other ABORTED, including one
/// that merely mentions the prefix later in its text, keeps the
/// ``ForkError`` mapping. ``retentionKnown`` is `true` only when the counts
/// pattern matched and all three counts converted to `UInt64`; the hint then
/// decides ``retryable``. On a pattern miss or a failed conversion the
/// counts read zero, retention is unknown and ``retryable`` is `false`, so a
/// garbled message neither enables the same-`upload_id` retry nor reads as
/// a confirmed "nothing retained". SDK releases up to 0.13.x mapped every
/// gRPC ABORTED to ``ForkError``; a partial-upload ABORTED now maps here
/// (the daemon emits ABORTED only for `PARTIAL_UPLOAD`). See
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

    /// Fixed opening text of every `PARTIAL_UPLOAD` message the daemon emits.
    /// Over gRPC (where the status carries no structured `code`) this is what
    /// distinguishes a partial upload from any other ABORTED.
    static let partialUploadMessagePrefix = "Partial upload:"

    /// Message tail the daemon appends when it kept the paid attempt for a
    /// same-`upload_id` retry.
    static let partialUploadRetainedHint = "paid attempt retained"

    /// Fixed prefix of the daemon's `PARTIAL_UPLOAD` message:
    /// `Partial upload: <stored>/<total> chunks stored, <failed> failed`.
    /// Matched only at the start of the message (see
    /// ``parsePartialUploadMessage(_:)``).
    private static let partialUploadCountsPattern =
        #"Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed"#

    /// Shape of the daemon's `{"error": ..., "code": ...}` envelope. The
    /// count fields and `retryable` are only present for `PARTIAL_UPLOAD`;
    /// `retryable` is also absent on daemons older than 0.14.0.
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
    /// 0.14.0) reads as unknown retention and not retryable. Every other
    /// body, including an envelope whose fields carry the wrong JSON types
    /// (see ``ErrorBodyDTO``), keeps the status-based mapping, so a malformed
    /// body always yields a typed ``AntdError`` and no decoding error
    /// reaches the caller.
    static func fromHTTPStatus(_ statusCode: Int, body: String) -> AntdError {
        if let envelope = try? JSONDecoder().decode(ErrorBodyDTO.self, from: Data(body.utf8)),
           envelope.code == partialUploadCode {
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

    static func fromGRPCStatus(code: Int, detail: String) -> AntdError {
        // gRPC status codes: 5=NOT_FOUND, 6=ALREADY_EXISTS, 10=ABORTED,
        // 3=INVALID_ARGUMENT, 9=FAILED_PRECONDITION, 14=UNAVAILABLE,
        // 8=RESOURCE_EXHAUSTED, 13=INTERNAL
        switch code {
        case 5: return NotFoundError(detail)
        case 6: return AlreadyExistsError(detail)
        case 10:
            // The daemon's PARTIAL_UPLOAD rides gRPC as ABORTED: some chunks
            // stored, some still unstored after retries. The counts and the
            // "paid attempt retained" hint ride the message text (no
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

    /// Recovers the chunk counts and the retryable hint from a
    /// `PARTIAL_UPLOAD` message. Used for gRPC, where the status carries no
    /// structured detail; REST callers get the body fields instead.
    ///
    /// All or nothing: the counts pattern must match at the start of the
    /// message and all three counts must convert to `UInt64` (a value past
    /// `UInt64.max` does not). Only then are the counts returned and
    /// `retentionKnown` `true`, and the `paid attempt retained` hint then
    /// decides `retryable`. On a pattern miss or any failed conversion every
    /// count is zero, `retentionKnown` is `false` and `retryable` is `false`,
    /// even when the hint is present, so a garbled message never enables the
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
        return (stored, failed, total, message.contains(partialUploadRetainedHint), true)
    }
}
