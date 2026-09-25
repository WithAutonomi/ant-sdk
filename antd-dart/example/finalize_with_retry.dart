// Bounded retry around AntdClient.finalizeUpload for a partial store that the
// daemon kept. Used by 07_external_signer.dart and covered by
// test/finalize_with_retry_test.dart. It lives under example/ rather than
// lib/ because it is a pattern to copy, not SDK API.

import 'package:antd_client/antd_client.dart';

/// Finalizes a wave-batch upload, resuming a partial store against the same
/// payment when the daemon kept the paid attempt.
///
/// On a [PartialUploadError]:
///
///   * `retryable` (antd >= 0.14.0): the daemon retained the payment proofs
///     and the unstored chunks under the same upload_id, so finalize is
///     called again with the same arguments to store the remainder: no
///     re-prepare, no second signature, no double payment. The loop is
///     bounded: at most [maxAttempts] finalize calls, [backoff] between them
///     (linear by default), and a `chunksFailed` that does not shrink from
///     one attempt to the next counts as stuck.
///   * `retentionKnown` but not `retryable`: the daemon confirmed nothing
///     was retained. The error is rethrown after that call, and the caller
///     re-prepares the same content, paying only for the remainder.
///   * not `retentionKnown`: retention is unknown and the daemon may still
///     hold the paid attempt. The helper stops at once and rethrows; it never
///     re-prepares or pays. Keep the upload_id and the original payment
///     artefacts, and reconcile before re-preparing or paying again.
///
/// Whenever it gives up (attempts exhausted, progress stalled, or either of
/// the last two cases) the helper rethrows the [PartialUploadError]
/// unchanged, with its original stack trace, so the caller keeps the counts
/// and both flags. Every other error is rethrown untouched.
Future<FinalizeUploadResult> finalizeWithRetry(
  AntdClient client,
  String uploadId,
  Map<String, String> txHashes, {
  int maxAttempts = 5,
  Duration Function(int attempt) backoff = _linearBackoff,
  void Function(String message) log = print,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be at least 1');
  }
  int? lastFailed;
  for (var attempt = 1;; attempt++) {
    try {
      return await client.finalizeUpload(uploadId, txHashes);
    } on PartialUploadError catch (e) {
      if (!e.retentionKnown) {
        log('finalize left chunks unstored and retention is unknown; '
            'stopping without re-preparing or paying. Keep upload_id '
            '$uploadId and the payment artefacts, and reconcile before '
            're-preparing or paying again');
        rethrow;
      }
      if (!e.retryable) rethrow;
      final stalled = lastFailed != null && e.chunksFailed >= lastFailed;
      if (attempt >= maxAttempts || stalled) {
        log('finalize gave up after $attempt attempt(s) '
            '(${stalled ? 'no progress' : 'attempts exhausted'}): '
            '${e.chunksStored}/${e.totalChunks} chunks stored, '
            '${e.chunksFailed} still unstored; the paid attempt stays '
            'retained under upload_id $uploadId until its pending-upload '
            'TTL expires');
        rethrow;
      }
      lastFailed = e.chunksFailed;
      log('finalize stored ${e.chunksStored}/${e.totalChunks} chunks, '
          '${e.chunksFailed} still unstored; retrying against the same '
          'payment (attempt ${attempt + 1}/$maxAttempts)');
      await Future.delayed(backoff(attempt));
    }
  }
}

Duration _linearBackoff(int attempt) => Duration(seconds: attempt * 2);
