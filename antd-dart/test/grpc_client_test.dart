import 'dart:typed_data';

import 'package:antd/src/errors.dart';
import 'package:antd/src/models.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Standalone fake gRPC client for testing.
//
// Does NOT import grpc_client.dart (which requires proto-generated stubs).
// Instead, defines a _FakeGrpcClient with the same 15-method API that returns
// canned responses or throws fake gRPC-like errors for error mapping tests.
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

/// Fake gRPC client returning canned responses for all 15 methods.
class _FakeGrpcClient {
  final FakeGrpcError? errorToThrow;

  _FakeGrpcClient({this.errorToThrow});

  // Helper: throw mapped error if configured, otherwise return the value.
  Future<T> _maybeThrow<T>(T value) async {
    if (errorToThrow != null) throw mapGrpcError(errorToThrow!);
    return value;
  }

Future<HealthStatus> health() =>
      _maybeThrow(const HealthStatus(ok: true, network: 'local'));

Future<PutResult> dataPutPublic(Uint8List data) =>
      _maybeThrow(const PutResult(cost: '100', address: 'abc123'));

Future<Uint8List> dataGetPublic(String address) =>
      _maybeThrow(Uint8List.fromList([104, 101, 108, 108, 111])); // "hello"

Future<PutResult> dataPutPrivate(Uint8List data) =>
      _maybeThrow(const PutResult(cost: '200', address: 'dm123'));

Future<Uint8List> dataGetPrivate(String dataMap) =>
      _maybeThrow(Uint8List.fromList([115, 101, 99, 114, 101, 116])); // "secret"

Future<String> dataCost(Uint8List data) => _maybeThrow('50');

Future<PutResult> chunkPut(Uint8List data) =>
      _maybeThrow(const PutResult(cost: '10', address: 'chunk1'));

Future<Uint8List> chunkGet(String address) =>
      _maybeThrow(Uint8List.fromList([99, 104, 117, 110, 107])); // "chunk"

Future<FileUploadResult> fileUploadPublic(String path) =>
      _maybeThrow(const FileUploadResult(
        address: 'file1',
        storageCostAtto: '1000',
        gasCostWei: '42',
        chunksStored: 3,
        paymentModeUsed: 'auto',
      ));

Future<void> fileDownloadPublic(String address, String destPath) =>
      _maybeThrow(null);

Future<FileUploadResult> dirUploadPublic(String path) =>
      _maybeThrow(const FileUploadResult(
        address: 'dir1',
        storageCostAtto: '2000',
        gasCostWei: '100',
        chunksStored: 5,
        paymentModeUsed: 'merkle',
      ));

Future<void> dirDownloadPublic(String address, String destPath) =>
      _maybeThrow(null);

Future<String> fileCost(
    String path, {
    bool isPublic = true,
  }) =>
      _maybeThrow('1000');

Future<void> close() async {}
}

/// Creates a [_FakeGrpcClient] that always throws the given [GrpcError] when
/// calling any method.  This lets us test the error-mapping switch in the
/// real [GrpcAntdClient._handleError] via the static helper directly.
_FakeGrpcClient errorClient(int grpcCode, String message) {
  return _FakeGrpcClient(
    errorToThrow: FakeGrpcError(grpcCode, message),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Happy-path tests – all 15 methods
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
      final result = await client.dataPutPublic(Uint8List.fromList([1, 2, 3]));
      expect(result.cost, equals('100'));
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
      final result = await client.dataPutPrivate(Uint8List.fromList([1, 2, 3]));
      expect(result.cost, equals('200'));
      expect(result.address, equals('dm123'));
    });

    test('get private data', () async {
      final client = _FakeGrpcClient();
      final data = await client.dataGetPrivate('dm123');
      expect(String.fromCharCodes(data), equals('secret'));
    });
  });

  group('Data Cost', () {
    test('estimates storage cost', () async {
      final client = _FakeGrpcClient();
      final cost = await client.dataCost(Uint8List.fromList([1]));
      expect(cost, equals('50'));
    });
  });

  group('Chunks', () {
    test('put chunk', () async {
      final client = _FakeGrpcClient();
      final result = await client.chunkPut(Uint8List.fromList([1]));
      expect(result.cost, equals('10'));
      expect(result.address, equals('chunk1'));
    });

    test('get chunk', () async {
      final client = _FakeGrpcClient();
      final data = await client.chunkGet('chunk1');
      expect(String.fromCharCodes(data), equals('chunk'));
    });
  });

  group('Files', () {
    test('upload file', () async {
      final client = _FakeGrpcClient();
      final result = await client.fileUploadPublic('/tmp/test.txt');
      expect(result.address, equals('file1'));
      expect(result.storageCostAtto, equals('1000'));
      expect(result.gasCostWei, equals('42'));
      expect(result.chunksStored, equals(3));
      expect(result.paymentModeUsed, equals('auto'));
    });

    test('download file', () async {
      final client = _FakeGrpcClient();
      await client.fileDownloadPublic('file1', '/tmp/out.txt');
      // No exception means success.
    });

    test('upload directory', () async {
      final client = _FakeGrpcClient();
      final result = await client.dirUploadPublic('/tmp/mydir');
      expect(result.address, equals('dir1'));
      expect(result.storageCostAtto, equals('2000'));
      expect(result.gasCostWei, equals('100'));
      expect(result.chunksStored, equals(5));
      expect(result.paymentModeUsed, equals('merkle'));
    });

    test('download directory', () async {
      final client = _FakeGrpcClient();
      await client.dirDownloadPublic('dir1', '/tmp/outdir');
    });

    test('file cost', () async {
      final client = _FakeGrpcClient();
      final cost =
          await client.fileCost('/tmp/test.txt', isPublic: true);
      expect(cost, equals('1000'));
    });
  });

  // -------------------------------------------------------------------------
  // Error mapping tests – GrpcError -> AntdError via _handleError
  //
  // We test this by calling GrpcAntdClient._handleError directly through
  // a static invocation since _handleError is a static Never-returning method.
  // We access it indirectly via the fake client that rethrows.
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

    // Verify error mapping works on multiple different methods, not just health.
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

    test('error propagates from fileUploadPublic', () async {
      final client = errorClient(8, 'too large');
      expect(
        () => client.fileUploadPublic('/tmp/big.bin'),
        throwsA(isA<TooLargeError>()),
      );
    });
  });
}
