// Bounded retry around AntdClient.finalizeUpload for a partial store that the
// daemon kept. Used by 07_external_signer.dart and covered by
// test/finalize_with_retry_test.dart. It lives under example/ rather than
// lib/ because it is a pattern to copy, not SDK API.

import 'package:antd_client/antd_client.dart';

/// Finalizes a wave-batch upload, resuming a partial store against the same
/// payment when the daemon kept the paid attempt.
///
/// A [PartialUploadError] with `retryable == true` (antd >= 0.14.0) means the
/// daemon retained the payment proofs and the unstored chunks under the same
/// upload_id, so calling finalize again with the same arguments stores the
/// remainder: no re-prepare, no second signature, no double payment.
///
/// The loop is bounded: at most [maxAttempts] finalize calls, [backoff]
/// between them (linear by default), and a `chunksFailed` that does not
/// shrink from one attempt to the next counts as stuck. When the attempts
/// run out or progress stalls, the last [PartialUploadError] is rethrown
/// unchanged, with its original stack trace, so the caller still has the
/// counts and `retryable` when deciding how to resume. The paid attempt stays
/// retained until the daemon's pending-upload TTL expires.
///
/// A partial with `retryable == false`, and every other error, is rethrown
/// untouched after the first call. `false` means the daemon did not report
/// the attempt as retained, and re-preparing the same content pays only for
/// the remainder. When that `false` is the SDK's fallback for an error it
/// could not read (a gRPC message whose counts did not parse), retention is
/// unconfirmed rather than ruled out: do not treat it alone as permission to
/// pay again.
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
