import 'dart:typed_data';

import 'package:antd/src/errors.dart';
import 'package:antd/src/models.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Standalone fake gRPC client for testing.
//
// Does NOT import grpc_client.dart (which requires proto-generated stubs).
// Instead, defines a _FakeGrpcClient with the same method surface that
// returns canned responses or throws fake gRPC-like errors for error mapping
// tests.
// ---------------------------------------------------------------------------

/// Simulates a gRPC error with a status code and message.
class FakeGrpcError implements Exception {
  final int code;
  final String message;
  FakeGrpcError(this.code, this.message);
}

/// Maps a fake gRPC status code to the SDK error types (mirrors the real
/// GrpcAntdClient._handleError logic).
Exception mapGrpcError(FakeGrpcError e) {
  switch (e.code) {
    case 3: return BadRequestError(e.message);
    case 5: return NotFoundError(e.message);
    case 6: return AlreadyExistsError(e.message);
    case 8: return TooLargeError(e.message);
    case 9: return PaymentError(e.message);
    case 13: return InternalError(e.message);
    case 14: return NetworkError(e.message);
    default: return AntdError(e.code, e.message);
  }
}

/// Fake gRPC client returning canned responses for all methods.
class _FakeGrpcClient {
  final FakeGrpcError? errorToThrow;

  _FakeGrpcClient({this.errorToThrow});

  Future<T> _maybeThrow<T>(T value) async {
    if (errorToThrow != null) throw mapGrpcError(errorToThrow!);
    return value;
  }

  Future<HealthStatus> health() =>
      _maybeThrow(const HealthStatus(ok: true, network: 'local'));

  Future<DataPutPublicResult> dataPutPublic(Uint8List data,
          {PaymentMode paymentMode = PaymentMode.auto}) =>
      _maybeThrow(const DataPutPublicResult(address: 'abc123'));

  Future<Uint8List> dataGetPublic(String address) =>
      _maybeThrow(Uint8List.fromList([104, 101, 108, 108, 111])); // "hello"

  Future<DataPutResult> dataPut(Uint8List data,
          {PaymentMode paymentMode = PaymentMode.auto}) =>
      _maybeThrow(const DataPutResult(dataMap: 'dm123'));

  Future<Uint8List> dataGet(String dataMap) =>
      _maybeThrow(Uint8List.fromList([115, 101, 99, 114, 101, 116])); // "secret"

  // Server-streams the payload in two chunks so the caller's chunk-by-chunk
  // consumption is exercised, not just a single message.
  Stream<List<int>> dataStream(String dataMap) async* {
    if (errorToThrow != null) throw mapGrpcError(errorToThrow!);
    yield [115, 101, 99]; // "sec"
    yield [114, 101, 116]; // "ret"
  }

  Stream<List<int>> dataStreamPublic(String address) async* {
    if (errorToThrow != null) throw mapGrpcError(errorToThrow!);
    yield [104, 101, 108]; // "hel"
    yield [108, 111]; // "lo"
  }

  // Mirrors GrpcAntdClient.dataStreamWithProgress: the byte total arrives first
  // (from the x-content-length header, surfaced as a meta frame), then when
  // include_progress is set the daemon interleaves DownloadProgress frames with
  // the data frames. Emits meta, a progress frame, then the data in two chunks.
  Stream<DownloadFrame> dataStreamWithProgress(String dataMap) async* {
    if (errorToThrow != null) throw mapGrpcError(errorToThrow!);
    yield const DownloadFrame.meta(6); // "secret"
    yield const DownloadFrame.progress(
        DownloadProgress(phase: 'fetching', fetched: 1, total: 2));
    yield DownloadFrame.data([115, 101, 99]); // "sec"
    yield DownloadFrame.data([114, 101, 116]); // "ret"
  }

  Stream<DownloadFrame> dataStreamPublicWithProgress(String address) async* {
    if (errorToThrow != null) throw mapGrpcError(errorToThrow!);
    yield const DownloadFrame.meta(5); // "hello"
    yield const DownloadFrame.progress(
        DownloadProgress(phase: 'resolving_map', fetched: 0, total: 0));
    yield DownloadFrame.data([104, 101, 108]); // "hel"
    yield DownloadFrame.data([108, 111]); // "lo"
  }

  Future<String> dataCost(Uint8List data,
          {PaymentMode paymentMode = PaymentMode.auto}) =>
      _maybeThrow('50');

  Future<PutResult> chunkPut(Uint8List data) =>
      _maybeThrow(const PutResult(cost: '10', address: 'chunk1'));

  Future<Uint8List> chunkGet(String address) =>
      _maybeThrow(Uint8List.fromList([99, 104, 117, 110, 107])); // "chunk"

  Future<FilePutResult> filePut(String path,
          {PaymentMode paymentMode = PaymentMode.auto}) =>
      _maybeThrow(const FilePutResult(
        dataMap: 'private_dm',
        storageCostAtto: '500',
        gasCostWei: '21',
        chunksStored: 2,
        paymentModeUsed: 'single',
      ));

  Future<void> fileGet(String dataMap, String destPath) => _maybeThrow(null);

  Future<FilePutPublicResult> filePutPublic(String path,
          {PaymentMode paymentMode = PaymentMode.auto}) =>
      _maybeThrow(const FilePutPublicResult(
        address: 'file1',
        storageCostAtto: '1000',
        gasCostWei: '42',
        chunksStored: 3,
        paymentModeUsed: 'auto',
      ));

  Future<void> fileGetPublic(String address, String destPath) =>
      _maybeThrow(null);

  Future<String> fileCost(
    String path, {
    bool isPublic = true,
    PaymentMode paymentMode = PaymentMode.auto,
  }) =>
      _maybeThrow('1000');

  Future<void> close() async {}
}

_FakeGrpcClient errorClient(int grpcCode, String message) {
  return _FakeGrpcClient(
    errorToThrow: FakeGrpcError(grpcCode, message),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Happy-path tests
  // -------------------------------------------------------------------------

  group('Health', () {
    test('returns health status', () async {
      final client = _FakeGrpcClient();
      final h = await client.health();
      expect(h.ok, isTrue);
      expect(h.network, equals('local'));
    });
  });

  group('Data Public', () {
    test('put public data', () async {
      final client = _FakeGrpcClient();
      final result = await client.dataPutPublic(
        Uint8List.fromList([1, 2, 3]),
        paymentMode: PaymentMode.merkle,
      );
      expect(result.address, equals('abc123'));
    });

    test('get public data', () async {
      final client = _FakeGrpcClient();
      final data = await client.dataGetPublic('abc123');
      expect(String.fromCharCodes(data), equals('hello'));
    });
  });

  group('Data Private', () {
    test('put private data', () async {
      final client = _FakeGrpcClient();
      final result = await client.dataPut(Uint8List.fromList([1]));
      expect(result.dataMap, equals('dm123'));
    });

    test('get private data', () async {
      final client = _FakeGrpcClient();
      final data = await client.dataGet('dm123');
      expect(String.fromCharCodes(data), equals('secret'));
    });

    test('stream private data', () async {
      final client = _FakeGrpcClient();
      final chunks = await client.dataStream('dm123').toList();
      final bytes = chunks.expand((c) => c).toList();
      expect(String.fromCharCodes(bytes), equals('secret'));
    });

    test('stream public data', () async {
      final client = _FakeGrpcClient();
      final chunks = await client.dataStreamPublic('abc123').toList();
      final bytes = chunks.expand((c) => c).toList();
      expect(String.fromCharCodes(bytes), equals('hello'));
    });

    test('stream private data with progress surfaces meta then progress',
        () async {
      final client = _FakeGrpcClient();
      final frames = await client.dataStreamWithProgress('dm123').toList();

      // Byte total (x-content-length) is surfaced first, before any data.
      expect(frames.first.isMeta, isTrue);
      expect(frames.first.totalBytes, equals(6));

      // Then the progress frame.
      expect(frames[1].isProgress, isTrue);
      expect(frames[1].progress!.phase, equals('fetching'));
      expect(frames[1].progress!.fetched, equals(1));
      expect(frames[1].progress!.total, equals(2));

      final bytes = frames
          .where((f) => f.data != null)
          .expand((f) => f.data!)
          .toList();
      expect(String.fromCharCodes(bytes), equals('secret'));
    });

    test('stream public data with progress surfaces meta then progress',
        () async {
      final client = _FakeGrpcClient();
      final frames =
          await client.dataStreamPublicWithProgress('abc123').toList();

      expect(frames.first.isMeta, isTrue);
      expect(frames.first.totalBytes, equals(5));

      expect(frames[1].isProgress, isTrue);
      expect(frames[1].progress!.phase, equals('resolving_map'));

      final bytes = frames
          .where((f) => f.data != null)
          .expand((f) => f.data!)
          .toList();
      expect(String.fromCharCodes(bytes), equals('hello'));
    });
  });

  group('Cost', () {
    test('data cost', () async {
      final client = _FakeGrpcClient();
      final cost = await client.dataCost(Uint8List.fromList([1, 2, 3]));
      expect(cost, equals('50'));
    });

    test('file cost', () async {
      final client = _FakeGrpcClient();
      final cost = await client.fileCost('/tmp/test.txt', isPublic: true);
      expect(cost, equals('1000'));
    });
  });

  group('Chunks', () {
    test('put chunk', () async {
      final client = _FakeGrpcClient();
      final result = await client.chunkPut(Uint8List.fromList([1, 2]));
      expect(result.cost, equals('10'));
      expect(result.address, equals('chunk1'));
    });

    test('get chunk', () async {
      final client = _FakeGrpcClient();
      final data = await client.chunkGet('chunk1');
      expect(String.fromCharCodes(data), equals('chunk'));
    });
  });

  group('Files Public', () {
    test('put public file', () async {
      final client = _FakeGrpcClient();
      final result = await client.filePutPublic('/tmp/test.txt');
      expect(result.address, equals('file1'));
      expect(result.storageCostAtto, equals('1000'));
      expect(result.gasCostWei, equals('42'));
      expect(result.chunksStored, equals(3));
      expect(result.paymentModeUsed, equals('auto'));
    });

    test('get public file', () async {
      final client = _FakeGrpcClient();
      await client.fileGetPublic('file1', '/tmp/out.txt');
      // No exception means success.
    });
  });

  group('Files Private', () {
    test('put private file', () async {
      final client = _FakeGrpcClient();
      final result = await client.filePut('/tmp/test.txt');
      expect(result.dataMap, equals('private_dm'));
      expect(result.chunksStored, equals(2));
    });

    test('get private file', () async {
      final client = _FakeGrpcClient();
      await client.fileGet('dm123', '/tmp/out.txt');
    });
  });

  // -------------------------------------------------------------------------
  // Error mapping tests
  // -------------------------------------------------------------------------

  group('Error Mapping (gRPC -> AntdError)', () {
    test('INVALID_ARGUMENT -> BadRequestError', () async {
      final client = errorClient(3, 'bad arg');
      expect(
        () => client.health(),
        throwsA(isA<BadRequestError>().having((e) => e.message, 'message', 'bad arg')),
      );
    });

    test('NOT_FOUND -> NotFoundError', () async {
      final client = errorClient(5, 'not found');
      expect(
        () => client.health(),
        throwsA(isA<NotFoundError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('ALREADY_EXISTS -> AlreadyExistsError', () async {
      final client = errorClient(6, 'exists');
      expect(
        () => client.health(),
        throwsA(isA<AlreadyExistsError>()),
      );
    });

    test('RESOURCE_EXHAUSTED -> TooLargeError', () async {
      final client = errorClient(8, 'too big');
      expect(
        () => client.health(),
        throwsA(isA<TooLargeError>()),
      );
    });

    test('INTERNAL -> InternalError', () async {
      final client = errorClient(13, 'crash');
      expect(
        () => client.health(),
        throwsA(isA<InternalError>()),
      );
    });

    test('UNAVAILABLE -> NetworkError', () async {
      final client = errorClient(14, 'down');
      expect(
        () => client.health(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('FAILED_PRECONDITION -> PaymentError', () async {
      final client = errorClient(9, 'no funds');
      expect(
        () => client.health(),
        throwsA(isA<PaymentError>()),
      );
    });

    test('unknown gRPC code -> AntdError with code', () async {
      final client = errorClient(15, 'data loss');
      expect(
        () => client.health(),
        throwsA(isA<AntdError>().having(
            (e) => e.statusCode, 'statusCode', 15)),
      );
    });

    test('error propagates from dataPutPublic', () async {
      final client = errorClient(5, 'missing data');
      expect(
        () => client.dataPutPublic(Uint8List.fromList([1])),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('error propagates from chunkGet', () async {
      final client = errorClient(13, 'boom');
      expect(
        () => client.chunkGet('addr'),
        throwsA(isA<InternalError>()),
      );
    });

    test('error propagates from filePutPublic', () async {
      final client = errorClient(8, 'too large');
      expect(
        () => client.filePutPublic('/tmp/big.bin'),
        throwsA(isA<TooLargeError>()),
      );
    });
  });
}
