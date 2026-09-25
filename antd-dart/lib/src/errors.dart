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
/// daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC ABORTED
/// whose message starts with the daemon's `Partial upload:` prefix).
///
/// The on-chain payment persists and the stored chunks stay on the network.
/// How to finish the upload depends on [retryable] and [retentionKnown]:
///
///   * [retryable] — the daemon kept the paid attempt (payment proofs +
///     unstored chunks) under the same `upload_id` (antd >= 0.14.0). Call
///     the **same** finalize method again with the same `upload_id` and
///     payment artefacts to store the remainder against the same payment:
///     no re-prepare, no second signature, no double payment. Bound the
///     loop: a persistent failure throws this error on every call, so cap
///     the attempts and treat a [chunksFailed] that stops shrinking as
///     stuck. The retained attempt expires with the daemon's pending-upload
///     TTL.
///   * [retentionKnown] but not [retryable] — the daemon confirmed that
///     nothing was retained (for example a merkle finalize with deliberately
///     unpaid batches). Re-prepare the same content: already-stored chunks
///     are skipped, so the retry pays only for the remainder.
///   * not [retentionKnown] — retention is unknown: the SDK could not read
///     whether the daemon kept the attempt (a REST body without a boolean
///     `retryable`, which includes every daemon before 0.14.0, or a gRPC
///     message whose counts did not parse or that does not end with one of
///     the daemon's two retention hints). The daemon may still hold the
///     paid attempt, because it records the resume handle before it returns
///     the error. Stop automatic recovery, keep the `upload_id` and the
///     original payment artefacts, and reconcile before re-preparing or
///     paying again. Never pay again on this signal alone.
///
/// Extends [NetworkError] because the daemon reports the shortfall as a 502:
/// an existing `on NetworkError` clause keeps catching it, while a dedicated
/// `on PartialUploadError` clause (listed first) gets the counts.
///
/// Over REST the fields come from the structured error body (see
/// [errorForResponse]); over gRPC they are parsed from the status message
/// (see [PartialUploadError.fromMessage]). Only an ABORTED whose message
/// starts with `Partial upload:` (see
/// [PartialUploadError.isPartialUploadMessage]) is mapped to this type; any
/// other ABORTED, including one that quotes the phrase further in, stays a
/// plain [AntdError]. See `docs/external-signer-flow.md` §6
/// ("Retry a partial store") for the daemon contract.
class PartialUploadError extends NetworkError {
  /// Chunks the daemon stored before giving up on the remainder.
  final int chunksStored;

  /// Chunks still unstored after the daemon's retries.
  final int chunksFailed;

  /// Chunks in the upload.
  final int totalChunks;

  /// `true` when the daemon retained the paid attempt under the same
  /// `upload_id`, so the same finalize call stores the remainder against the
  /// same payment. `false` both when the daemon confirmed nothing was
  /// retained and when retention is unknown; [retentionKnown] tells the two
  /// apart. Implies [retentionKnown].
  final bool retryable;

  /// `true` when the SDK read the daemon's answer on retention: over REST a
  /// JSON boolean `retryable` in the body, over gRPC a message whose counts
  /// parsed and that ends with one of the daemon's two retention hints (see
  /// [PartialUploadError.fromMessage]). `false` means retention is unknown
  /// and the daemon may still hold the paid attempt, so neither re-prepare
  /// nor pay again on this error alone (see the class doc).
  final bool retentionKnown;

  /// Passing [retryable] `true` also makes [retentionKnown] `true`: an
  /// attempt the daemon retained is by definition a known one.
  const PartialUploadError(
    String message, {
    this.chunksStored = 0,
    this.chunksFailed = 0,
    this.totalChunks = 0,
    this.retryable = false,
    bool retentionKnown = false,
  })  : retentionKnown = retentionKnown || retryable,
        super(message);

  /// Recovers the counts, [retryable] and [retentionKnown] from a
  /// `PARTIAL_UPLOAD` message. Used for gRPC, where the ABORTED status
  /// carries no structured detail; REST callers get the body fields instead.
  ///
  /// The daemon formats the message as `Partial upload: <stored>/<total>
  /// chunks stored, <failed> failed after retries: <reason> (<hint>)` and
  /// closes it with one of two hints (`partial_upload_hint` in
  /// antd/src/error.rs): `(paid attempt retained: ...)` when it kept the
  /// attempt, `(stored chunks persist; re-prepare the same content ...)`
  /// when it did not. Daemons before 0.14.0 write only the second.
  ///
  /// [retentionKnown] is `true` only when [message] starts with the counts
  /// pattern, all three counts convert to an `int`, and [message] ends with
  /// one of the two hints; [retryable] is then `true` only for the retained
  /// hint. If the pattern does not match at the start, or a count does not
  /// fit an `int` (whose Dart VM limit is 2^63 - 1), all three counts read
  /// as zero and both flags are `false`, even if a hint is present: a retry
  /// loop that cannot watch [chunksFailed] shrink cannot tell progress from
  /// a stuck upload. Readable counts with a missing, truncated or
  /// unrecognised hint, or with any text after it, keep the counts but leave
  /// both flags `false`: the daemon's answer on retention was not read, so
  /// retention is unknown (stop and reconcile), never "nothing retained". A
  /// hint quoted inside the failure reason is not the daemon's answer. Never
  /// throws. Callers gate on [isPartialUploadMessage] first so that an
  /// unrelated ABORTED is not misreported as a partial upload.
  factory PartialUploadError.fromMessage(String message) {
    final m = _partialUploadCounts.firstMatch(message);
    final stored = m == null ? null : int.tryParse(m.group(1)!);
    final total = m == null ? null : int.tryParse(m.group(2)!);
    final failed = m == null ? null : int.tryParse(m.group(3)!);
    if (stored == null || total == null || failed == null) {
      return PartialUploadError(message);
    }
    final tail = _partialUploadRetentionTail.firstMatch(message);
    return PartialUploadError(
      message,
      chunksStored: stored,
      totalChunks: total,
      chunksFailed: failed,
      retryable: tail?.group(1) == _partialUploadRetainedHint,
      retentionKnown: tail != null,
    );
  }

  /// Whether [message] is the daemon's `PARTIAL_UPLOAD` message: every one
  /// it emits opens with the fixed text `Partial upload:`. Used to decide
  /// whether a gRPC ABORTED status is a partial upload at all.
  ///
  /// Anchored at the start of [message], matching antd-rust: the daemon
  /// never wraps its own message, so an ABORTED that merely quotes the
  /// phrase further in is something else and must not be misreported as a
  /// partial upload.
  static bool isPartialUploadMessage(String message) =>
      message.startsWith(_partialUploadPrefix);
}

/// Fixed opening text of every `PARTIAL_UPLOAD` message the daemon emits.
const _partialUploadPrefix = 'Partial upload:';

/// Matches the fixed prefix of the daemon's `PARTIAL_UPLOAD` message:
/// `Partial upload: <stored>/<total> chunks stored, <failed> failed`.
/// Anchored at the start, like [PartialUploadError.isPartialUploadMessage],
/// so counts quoted further into a message are never read.
final _partialUploadCounts =
    RegExp(r'^Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed');

/// The daemon closes every `PARTIAL_UPLOAD` message with one of two
/// parenthesised hints (`partial_upload_hint` in antd/src/error.rs): the
/// retained hint when it kept the paid attempt for a same-`upload_id` retry,
/// the not-retained hint when it did not. Daemons before 0.14.0 write only
/// the not-retained hint.
const _partialUploadRetainedHint = 'paid attempt retained';
const _partialUploadNotRetainedHint =
    'stored chunks persist; re-prepare the same content';

/// Matches the hint that closes the message: `(<hint>...)` at the very end.
/// Without `multiLine`, a Dart `$` matches only at the end of the input, not
/// before a trailing newline. A hint quoted inside the failure reason, a
/// truncated or unclosed tail, or any text after the hint does not match.
final _partialUploadRetentionTail = RegExp(
  r'\(('
  '${RegExp.escape(_partialUploadRetainedHint)}|'
  '${RegExp.escape(_partialUploadNotRetainedHint)}'
  r')[^()]*\)$',
);

/// Maps a REST error response onto a typed error, preferring the
/// machine-readable `code` over the bare HTTP status where they diverge:
/// `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a generic
/// [NetworkError]. Every other code keeps the [errorForStatus] mapping.
/// [body] is `null` when the response was not a JSON object.
///
/// Never throws: the body is input from the network. A `code` that is not
/// the string `PARTIAL_UPLOAD` (missing, another string, or an object,
/// array, number or null) keeps the [errorForStatus] mapping. In a
/// `PARTIAL_UPLOAD` body a count that is not a finite JSON number reads as
/// 0. [PartialUploadError.retentionKnown] is `true` only when `retryable` is
/// present and a JSON boolean, whose value then sets
/// [PartialUploadError.retryable]. A missing, null or mistyped `retryable`
/// (daemons before 0.14.0 never send it) means retention is unknown, and
/// `retryable` reads `false`.
AntdError errorForResponse(
  int statusCode,
  String message,
  Map<String, dynamic>? body,
) {
  final code = body?['code'];
  if (body != null && code is String && code == 'PARTIAL_UPLOAD') {
    final retryable = body['retryable'];
    return PartialUploadError(
      message,
      chunksStored: _countField(body['chunks_stored']),
      chunksFailed: _countField(body['chunks_failed']),
      totalChunks: _countField(body['total_chunks']),
      retryable: retryable == true,
      retentionKnown: retryable is bool,
    );
  }
  return errorForStatus(statusCode, message);
}

/// A `PARTIAL_UPLOAD` count field as an int: 0 unless [value] is a finite
/// JSON number. A string, object, array, boolean or null reads as absent,
/// and so does an overflowing literal such as `1e999`, which decodes to
/// infinity (`toInt()` would throw on it).
int _countField(Object? value) =>
    value is num && value.isFinite ? value.toInt() : 0;

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
