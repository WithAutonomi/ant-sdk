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

public final class NetworkError: AntdError {
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
/// daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED).
/// The on-chain payment persists and the stored chunks stay on the network.
/// How to finish the upload depends on ``retryable``:
///
/// - `retryable == true`: the daemon kept the paid attempt (payment proofs +
///   unstored chunks) under the same `upload_id`. Call the **same** finalize
///   method again with the same arguments to store the remainder against the
///   same payment — no re-prepare, no second signature, no double payment.
///   Bound the loop: a persistent failure throws this error on every call, so
///   cap the attempts and treat a ``chunksFailed`` that stops shrinking as
///   stuck. The retained attempt expires with the daemon's pending-upload TTL.
///   (antd >= 0.14.0; older daemons never send the flag, so `retryable` reads
///   `false` and the re-prepare path applies.)
/// - `retryable == false`: nothing was retained (a merkle finalize with
///   deliberately unpaid batches, or an older daemon). Re-preparing the same
///   content skips already-stored chunks, so a retry pays only for the
///   missing remainder.
///
/// Over REST the counts and `retryable` come from the structured error body.
/// The counts must be JSON non-negative integers that fit in `UInt64` and
/// `retryable` a JSON boolean; a body where any of those (or `error` /
/// `code`) carries another JSON type, such as a quoted `"1"` or `"true"`,
/// does not decode and keeps the status-based mapping (a 502 stays a
/// ``NetworkError``). Absent counts read zero and an absent `retryable`
/// reads `false`.
///
/// Over gRPC they are parsed from the status message (`Partial upload: S/T
/// chunks stored, F failed ...`, with a `paid attempt retained` hint when
/// retryable). Only an ABORTED whose message **starts with** the daemon's
/// fixed `Partial upload:` prefix maps here; any other ABORTED, including one
/// that merely mentions the prefix later in its text, keeps the
/// ``ForkError`` mapping. `retryable` is `true` only when the counts pattern
/// matched, all three counts converted to `UInt64`, and the hint is present;
/// on a pattern miss or a failed conversion the counts read zero and
/// `retryable` is `false`, so a garbled message never enables the
/// same-`upload_id` retry. See `docs/external-signer-flow.md` §6.
///
/// This is a sibling of ``NetworkError`` (not a subclass) so that a
/// `catch let e as NetworkError` clause never swallows a paid, partly stored
/// upload as a plain transport failure.
public final class PartialUploadError: AntdError {
    public let chunksStored: UInt64
    public let chunksFailed: UInt64
    public let totalChunks: UInt64
    public let retryable: Bool

    public init(
        _ message: String,
        chunksStored: UInt64,
        chunksFailed: UInt64,
        totalChunks: UInt64,
        retryable: Bool,
        statusCode: Int = 502
    ) {
        self.chunksStored = chunksStored
        self.chunksFailed = chunksFailed
        self.totalChunks = totalChunks
        self.retryable = retryable
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
    /// are surfaced as a ``PartialUploadError`` (absent counts read zero and
    /// an absent `retryable` reads `false`). Every other body, including an
    /// envelope whose fields carry the wrong JSON types (see
    /// ``ErrorBodyDTO``), keeps the status-based mapping, so a malformed
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
    /// `UInt64.max` does not). Only then are the counts returned, and only
    /// then can `retryable` be `true`, which additionally needs the `paid
    /// attempt retained` hint. On a pattern miss or any failed conversion
    /// every count is zero and `retryable` is `false`, even when the hint is
    /// present, so a garbled message never enables the same-`upload_id`
    /// retry. Callers decide whether the message is a partial upload at all
    /// (see ``partialUploadMessagePrefix``); this parser does not.
    static func parsePartialUploadMessage(
        _ message: String
    ) -> (chunksStored: UInt64, chunksFailed: UInt64, totalChunks: UInt64, retryable: Bool) {
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
            return (0, 0, 0, false)
        }
        return (stored, failed, total, message.contains(partialUploadRetainedHint))
    }
}
