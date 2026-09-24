/// Base error type for all antd errors.
class AntdError implements Exception {
  /// The HTTP status code.
  final int statusCode;

  /// The error message.
  final String message;

  const AntdError(this.statusCode, this.message);

  @override
  String toString() => 'antd error $statusCode: $message';
}

/// Invalid request parameters (HTTP 400).
class BadRequestError extends AntdError {
  const BadRequestError(String message) : super(400, message);
}

/// Insufficient funds or payment failure (HTTP 402).
class PaymentError extends AntdError {
  const PaymentError(String message) : super(402, message);
}

/// Resource not found on the network (HTTP 404).
class NotFoundError extends AntdError {
  const NotFoundError(String message) : super(404, message);
}

/// Resource already exists (HTTP 409).
class AlreadyExistsError extends AntdError {
  const AlreadyExistsError(String message) : super(409, message);
}

/// Version conflict or fork detected (HTTP 409).
class ForkError extends AntdError {
  const ForkError(String message) : super(409, message);
}

/// Payload too large (HTTP 413).
class TooLargeError extends AntdError {
  const TooLargeError(String message) : super(413, message);
}

/// Internal server error (HTTP 500).
class InternalError extends AntdError {
  const InternalError(String message) : super(500, message);
}

/// Daemon cannot reach the network (HTTP 502).
class NetworkError extends AntdError {
  const NetworkError(String message) : super(502, message);
}

/// Service unavailable, e.g. wallet not configured (HTTP 503).
class ServiceUnavailableError extends AntdError {
  const ServiceUnavailableError(String message) : super(503, message);
}

/// A finalize stored some chunks while others stayed unstored after the
/// daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED).
///
/// The on-chain payment persists and the stored chunks stay on the network.
/// How to finish the upload depends on [retryable]:
///
///   * `true` — the daemon kept the paid attempt (payment proofs + unstored
///     chunks) under the same `upload_id`. Call the **same** finalize method
///     again with the same arguments to store the remainder against the same
///     payment — no re-prepare, no second signature, no double payment.
///     Bound the loop: a persistent failure throws this error on every call,
///     so cap the attempts and treat a [chunksFailed] that stops shrinking as
///     stuck. The retained attempt expires with the daemon's pending-upload
///     TTL. Sent by antd >= 0.14.0; older daemons never send the flag, so
///     [retryable] reads `false` and the re-prepare path applies.
///   * `false` — nothing was retained (a merkle finalize with deliberately
///     unpaid batches, or an older daemon). Re-preparing the same content
///     skips already-stored chunks, so a retry pays only for the remainder.
///
/// Extends [NetworkError] because the daemon reports the shortfall as a 502:
/// an existing `on NetworkError` clause keeps catching it, while a dedicated
/// `on PartialUploadError` clause (listed first) gets the counts.
///
/// Over REST the counts and [retryable] come from the structured error body.
/// Over gRPC they are parsed best-effort from the status message by
/// [PartialUploadError.fromMessage]. See `docs/external-signer-flow.md` §6
/// ("Retry a partial store") for the daemon contract.
class PartialUploadError extends NetworkError {
  /// Chunks the daemon stored before giving up on the remainder.
  final int chunksStored;

  /// Chunks still unstored after the daemon's retries.
  final int chunksFailed;

  /// Chunks in the upload.
  final int totalChunks;

  /// `true` when the paid attempt was retained under the same `upload_id`
  /// and the same finalize call stores the remainder against the same
  /// payment; `false` when the retry is a re-prepare.
  final bool retryable;

  const PartialUploadError(
    String message, {
    this.chunksStored = 0,
    this.chunksFailed = 0,
    this.totalChunks = 0,
    this.retryable = false,
  }) : super(message);

  /// Recovers the counts and the retryable hint from a `PARTIAL_UPLOAD`
  /// message. Used for gRPC, where the ABORTED status carries no structured
  /// detail; REST callers get the body fields instead.
  ///
  /// The daemon formats the message as `Partial upload: <stored>/<total>
  /// chunks stored, <failed> failed after retries: <reason> (<hint>)`, with
  /// the hint `paid attempt retained: ...` when retryable. An unrecognised
  /// message leaves the counts zero and [retryable] false.
  factory PartialUploadError.fromMessage(String message) {
    final m = _partialUploadCounts.firstMatch(message);
    return PartialUploadError(
      message,
      chunksStored: m == null ? 0 : int.parse(m.group(1)!),
      totalChunks: m == null ? 0 : int.parse(m.group(2)!),
      chunksFailed: m == null ? 0 : int.parse(m.group(3)!),
      retryable: message.contains(_partialUploadRetainedHint),
    );
  }
}

/// Matches the fixed prefix of the daemon's `PARTIAL_UPLOAD` message:
/// `Partial upload: <stored>/<total> chunks stored, <failed> failed`.
final _partialUploadCounts =
    RegExp(r'Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed');

/// Message tail the daemon appends when it kept the paid attempt for a
/// same-`upload_id` retry.
const _partialUploadRetainedHint = 'paid attempt retained';

/// Maps a REST error response onto a typed error, preferring the
/// machine-readable `code` over the bare HTTP status where they diverge:
/// `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a generic
/// [NetworkError]. Every other code keeps the [errorForStatus] mapping.
/// [body] is `null` when the response was not JSON.
///
/// `retryable` is absent from daemons before 0.14.0 and defaults to `false`.
AntdError errorForResponse(
  int statusCode,
  String message,
  Map<String, dynamic>? body,
) {
  if (body != null && body['code'] == 'PARTIAL_UPLOAD') {
    return PartialUploadError(
      message,
      chunksStored: (body['chunks_stored'] as num?)?.toInt() ?? 0,
      chunksFailed: (body['chunks_failed'] as num?)?.toInt() ?? 0,
      totalChunks: (body['total_chunks'] as num?)?.toInt() ?? 0,
      retryable: body['retryable'] as bool? ?? false,
    );
  }
  return errorForStatus(statusCode, message);
}

/// Returns the appropriate error type for an HTTP status code.
AntdError errorForStatus(int statusCode, String message) {
  switch (statusCode) {
    case 400:
      return BadRequestError(message);
    case 402:
      return PaymentError(message);
    case 404:
      return NotFoundError(message);
    case 409:
      return AlreadyExistsError(message);
    case 413:
      return TooLargeError(message);
    case 500:
      return InternalError(message);
    case 502:
      return NetworkError(message);
    case 503:
      return ServiceUnavailableError(message);
    default:
      return AntdError(statusCode, message);
  }
}
