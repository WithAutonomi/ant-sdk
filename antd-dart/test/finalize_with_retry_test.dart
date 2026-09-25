import 'dart:convert';

import 'package:antd_client/antd_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../example/finalize_with_retry.dart';

/// Leaves `retryable` out of the body, as an antd < 0.14.0 daemon does.
const _absent = Object();

/// The daemon's structured `PARTIAL_UPLOAD` 502 body for a 312-chunk upload
/// with [failed] chunks still unstored. [retryable] is written as given (any
/// JSON value, null included), or left out when it is [_absent].
http.Response _partial(int failed, {Object? retryable = true}) {
  final stored = 312 - failed;
  return http.Response(
    jsonEncode({
      'error': 'Partial upload: $stored/312 chunks stored, $failed failed '
          'after retries',
      'code': 'PARTIAL_UPLOAD',
      'chunks_stored': stored,
      'chunks_failed': failed,
      'total_chunks': 312,
      if (!identical(retryable, _absent)) 'retryable': retryable,
    }),
    502,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _finalized() => http.Response(
      jsonEncode({
        'data_map': 'dm',
        'data_map_address': 'dm-addr',
        'chunks_stored': 312,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _error(int status, String message) => http.Response(
      jsonEncode({'error': message}),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Answers `POST /v1/upload/finalize` from [responses] in order, repeating
/// the last one, and counts the finalize calls. Errors go through the real
/// REST error mapping in [AntdClient].
class _FinalizeDaemon {
  _FinalizeDaemon(this.responses);

  final List<http.Response Function()> responses;
  final backoffs = <int>[];
  final logs = <String>[];
  var calls = 0;

  Future<FinalizeUploadResult> run({int maxAttempts = 5}) {
    final client = AntdClient(httpClient: MockClient((request) async {
      expect('${request.method} ${request.url.path}',
          equals('POST /v1/upload/finalize'));
      expect(jsonDecode(request.body)['upload_id'], equals('up-1'));
      final i = calls < responses.length ? calls : responses.length - 1;
      calls++;
      return responses[i]();
    }));
    addTearDown(client.close);
    return finalizeWithRetry(
      client,
      'up-1',
      {'0xq': '0xt'},
      maxAttempts: maxAttempts,
      backoff: (attempt) {
        backoffs.add(attempt);
        return Duration.zero;
      },
      log: logs.add,
    );
  }
}

/// Runs [daemon] and returns what it threw, with the stack trace.
Future<(Object, StackTrace)> _thrown(_FinalizeDaemon daemon,
    {int maxAttempts = 5}) async {
  try {
    await daemon.run(maxAttempts: maxAttempts);
  } catch (e, st) {
    return (e, st);
  }
  throw TestFailure('finalizeWithRetry returned instead of throwing');
}

/// Throws, from every finalizeUpload call, the [PartialUploadError] the gRPC
/// client builds from an ABORTED status [message], and counts the calls. The
/// SDK's gRPC parser, not a hand-set flag, decides what the helper sees.
class _GrpcMessageClient extends AntdClient {
  _GrpcMessageClient(this.message)
      : super(
            httpClient: MockClient((_) async =>
                throw StateError('finalizeUpload is overridden')));

  final String message;
  var calls = 0;

  @override
  Future<FinalizeUploadResult> finalizeUpload(
    String uploadId,
    Map<String, String> txHashes,
  ) async {
    calls++;
    throw PartialUploadError.fromMessage(message);
  }
}

/// Counts prefix of a gRPC PARTIAL_UPLOAD message for a 312-chunk upload
/// with 12 chunks still unstored.
const _grpcCounts =
    'Partial upload: 300/312 chunks stored, 12 failed after retries: quorum';

Matcher _partialError({
  required int failed,
  required bool retryable,
  bool retentionKnown = true,
}) =>
    isA<PartialUploadError>()
        .having((e) => e.statusCode, 'statusCode', 502)
        .having((e) => e.chunksStored, 'chunksStored', 312 - failed)
        .having((e) => e.chunksFailed, 'chunksFailed', failed)
        .having((e) => e.totalChunks, 'totalChunks', 312)
        .having((e) => e.retryable, 'retryable', retryable)
        .having((e) => e.retentionKnown, 'retentionKnown', retentionKnown);

void main() {
  group('finalizeWithRetry', () {
    test('returns the result when a retry stores the remainder', () async {
      final daemon = _FinalizeDaemon([() => _partial(12), _finalized]);
      final result = await daemon.run();
      expect(result.chunksStored, equals(312));
      expect(result.dataMapAddress, equals('dm-addr'));
      expect(daemon.calls, equals(2));
      expect(daemon.backoffs, equals([1]));
    });

    test('a first-call success makes one call', () async {
      final daemon = _FinalizeDaemon([_finalized]);
      expect((await daemon.run()).dataMap, equals('dm'));
      expect(daemon.calls, equals(1));
      expect(daemon.backoffs, isEmpty);
    });

    test('attempt exhaustion rethrows the last PartialUploadError unchanged',
        () async {
      // chunksFailed keeps shrinking, so only maxAttempts stops the loop.
      final daemon = _FinalizeDaemon(
          [() => _partial(12), () => _partial(8), () => _partial(4)]);
      final (error, stack) = await _thrown(daemon, maxAttempts: 3);
      expect(error, _partialError(failed: 4, retryable: true));
      // Catchable by `on PartialUploadError`, `on NetworkError` and
      // `on Exception` alike; a StateError would escape all three.
      expect(error, isA<NetworkError>());
      expect(error, isA<Exception>());
      expect(error, isNot(isA<Error>()));
      // Rethrown, not rewrapped: the trace still starts in the client's
      // error mapping rather than in the retry helper.
      expect(stack.toString(), contains('package:antd_client/src/client.dart'));
      expect(daemon.calls, equals(3));
      expect(daemon.backoffs, equals([1, 2]));
    });

    test('maxAttempts: 1 makes one call and rethrows the partial error',
        () async {
      final daemon = _FinalizeDaemon([() => _partial(12)]);
      final (error, _) = await _thrown(daemon, maxAttempts: 1);
      expect(error, _partialError(failed: 12, retryable: true));
      expect(error, isA<Exception>());
      expect(daemon.calls, equals(1));
      expect(daemon.backoffs, isEmpty);
    });

    test('an unchanged chunksFailed stops early and rethrows', () async {
      final daemon =
          _FinalizeDaemon([() => _partial(12), () => _partial(12), _finalized]);
      final (error, _) = await _thrown(daemon);
      expect(error, _partialError(failed: 12, retryable: true));
      expect(error, isA<Exception>());
      expect(daemon.calls, equals(2));
      expect(daemon.backoffs, equals([1]));
    });

    test('a growing chunksFailed stops early and rethrows', () async {
      final daemon = _FinalizeDaemon(
          [() => _partial(8), () => _partial(4), () => _partial(6)]);
      final (error, _) = await _thrown(daemon);
      expect(error, _partialError(failed: 6, retryable: true));
      expect(daemon.calls, equals(3));
      expect(daemon.backoffs, equals([1, 2]));
    });

    test('nothing retained (retryable false) is rethrown after one call',
        () async {
      // The daemon confirmed it kept nothing: the caller re-prepares.
      final daemon = _FinalizeDaemon([() => _partial(12, retryable: false)]);
      final (error, _) = await _thrown(daemon);
      expect(error, _partialError(failed: 12, retryable: false));
      expect(daemon.calls, equals(1));
      expect(daemon.backoffs, isEmpty);
    });

    test('retention unknown stops at once and rethrows the typed error',
        () async {
      // No boolean retryable (a daemon before 0.14.0, or a mistyped flag):
      // the daemon may still hold the paid attempt, so the helper makes one
      // finalize call and hands the typed error back without retrying,
      // re-preparing or paying.
      for (final retryable in [_absent, null, 'true', 1]) {
        final label = identical(retryable, _absent) ? 'absent' : '$retryable';
        final daemon =
            _FinalizeDaemon([() => _partial(12, retryable: retryable)]);
        final (error, _) = await _thrown(daemon);
        expect(error,
            _partialError(failed: 12, retryable: false, retentionKnown: false),
            reason: label);
        expect(error, isA<Exception>(), reason: label);
        expect(daemon.calls, equals(1), reason: label);
        expect(daemon.backoffs, isEmpty, reason: label);
        expect(daemon.logs.single, contains('retention is unknown'),
            reason: label);
      }
    });

    // End to end from the gRPC status text: whenever the daemon's closing
    // retention hint cannot be read, the helper must stop at once with the
    // reconcile advice, never retry, re-prepare or pay.
    const unreadable = {
      'no hint': _grpcCounts,
      // The review's reproducer: the retained hint cut short.
      'a truncated retained hint': '$_grpcCounts (paid attempt retai',
      'an unclosed retained hint':
          '$_grpcCounts (paid attempt retained: call finalize again',
      'a truncated not-retained hint':
          '$_grpcCounts (stored chunks persist; re-prepare the same con',
    };
    unreadable.forEach((label, message) {
      test('gRPC message with $label stops at once to reconcile', () async {
        final client = _GrpcMessageClient(message);
        addTearDown(client.close);
        final logs = <String>[];
        final backoffs = <int>[];
        Object? error;
        try {
          await finalizeWithRetry(
            client,
            'up-1',
            {'0xq': '0xt'},
            backoff: (attempt) {
              backoffs.add(attempt);
              return Duration.zero;
            },
            log: logs.add,
          );
        } catch (e) {
          error = e;
        }
        expect(error,
            _partialError(failed: 12, retryable: false, retentionKnown: false));
        expect(client.calls, equals(1));
        expect(backoffs, isEmpty);
        expect(logs.single,
            allOf(contains('retention is unknown'), contains('reconcile')));
      });
    });

    test('gRPC message with the not-retained hint is rethrown as known',
        () async {
      // Only the daemon's explicit not-retained hint means "nothing
      // retained": the error reaches the caller as known, not retryable,
      // and the helper does not log the unknown-retention advice.
      final client = _GrpcMessageClient('$_grpcCounts (stored chunks '
          'persist; re-prepare the same content to retry only the remainder)');
      addTearDown(client.close);
      final logs = <String>[];
      Object? error;
      try {
        await finalizeWithRetry(client, 'up-1', {'0xq': '0xt'},
            backoff: (_) => Duration.zero, log: logs.add);
      } catch (e) {
        error = e;
      }
      expect(error, _partialError(failed: 12, retryable: false));
      expect(client.calls, equals(1));
      expect(logs, isEmpty);
    });

    test('other errors are rethrown after one call', () async {
      final network = _FinalizeDaemon([() => _error(502, 'unreachable')]);
      final (networkError, _) = await _thrown(network);
      expect(networkError, isA<NetworkError>());
      expect(networkError, isNot(isA<PartialUploadError>()));
      expect(network.calls, equals(1));

      final bad = _FinalizeDaemon([() => _error(400, 'unknown upload_id')]);
      final (badError, _) = await _thrown(bad);
      expect(badError, isA<BadRequestError>());
      expect(bad.calls, equals(1));
    });

    test('maxAttempts below 1 is rejected before any call', () async {
      final daemon = _FinalizeDaemon([_finalized]);
      final (error, _) = await _thrown(daemon, maxAttempts: 0);
      expect(error, isA<ArgumentError>());
      expect(daemon.calls, equals(0));
    });
  });
}
