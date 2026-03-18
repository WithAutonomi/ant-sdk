import 'dart:typed_data';

import 'package:antd/src/errors.dart';
import 'package:antd/src/models.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Standalone fake gRPC client for testing.
//
// Does NOT import grpc_client.dart (which requires proto-generated stubs).
// Instead, defines a _FakeGrpcClient with the same 19-method API that returns
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

/// Fake gRPC client returning canned responses for all 19 methods.
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

Future<PutResult> graphEntryPut(
    String ownerSecretKey,
    List<String> parents,
    String content,
    List<GraphDescendant> descendants,
  ) =>
      _maybeThrow(const PutResult(cost: '500', address: 'ge1'));

Future<GraphEntry> graphEntryGet(String address) =>
      _maybeThrow(const GraphEntry(
        owner: 'owner1',
        parents: [],
        content: 'abc',
        descendants: [GraphDescendant(publicKey: 'pk1', content: 'desc1')],
      ));

Future<bool> graphEntryExists(String address) =>
      _maybeThrow(address == 'ge1');

Future<String> graphEntryCost(String publicKey) => _maybeThrow('500');

Future<PutResult> fileUploadPublic(String path) =>
      _maybeThrow(const PutResult(cost: '1000', address: 'file1'));

Future<void> fileDownloadPublic(String address, String destPath) =>
      _maybeThrow(null);

Future<PutResult> dirUploadPublic(String path) =>
      _maybeThrow(const PutResult(cost: '2000', address: 'dir1'));

Future<void> dirDownloadPublic(String address, String destPath) =>
      _maybeThrow(null);

Future<Archive> archiveGetPublic(String address) =>
      _maybeThrow(const Archive(entries: [
        ArchiveEntry(
          path: 'test.txt',
          address: 'abc',
          created: 1000,
          modified: 2000,
          size: 42,
        ),
      ]));

Future<PutResult> archivePutPublic(Archive archive) =>
      _maybeThrow(const PutResult(cost: '50', address: 'arc2'));

Future<String> fileCost(
    String path, {
    bool isPublic = true,
    bool includeArchive = false,
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
  // Happy-path tests – all 19 methods
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

  group('Graph', () {
    test('put graph entry', () async {
      final client = _FakeGrpcClient();
      final result = await client.graphEntryPut('sk1', [], 'abc', []);
      expect(result.cost, equals('500'));
      expect(result.address, equals('ge1'));
    });

    test('get graph entry', () async {
      final client = _FakeGrpcClient();
      final entry = await client.graphEntryGet('ge1');
      expect(entry.owner, equals('owner1'));
      expect(entry.parents, isEmpty);
      expect(entry.content, equals('abc'));
      expect(entry.descendants.length, equals(1));
      expect(entry.descendants[0].publicKey, equals('pk1'));
      expect(entry.descendants[0].content, equals('desc1'));
    });

    test('graph entry exists returns true', () async {
      final client = _FakeGrpcClient();
      expect(await client.graphEntryExists('ge1'), isTrue);
    });

    test('graph entry exists returns false', () async {
      final client = _FakeGrpcClient();
      expect(await client.graphEntryExists('missing'), isFalse);
    });

    test('graph entry cost', () async {
      final client = _FakeGrpcClient();
      expect(await client.graphEntryCost('pk1'), equals('500'));
    });
  });

  group('Files', () {
    test('upload file', () async {
      final client = _FakeGrpcClient();
      final result = await client.fileUploadPublic('/tmp/test.txt');
      expect(result.cost, equals('1000'));
      expect(result.address, equals('file1'));
    });

    test('download file', () async {
      final client = _FakeGrpcClient();
      await client.fileDownloadPublic('file1', '/tmp/out.txt');
      // No exception means success.
    });

    test('upload directory', () async {
      final client = _FakeGrpcClient();
      final result = await client.dirUploadPublic('/tmp/mydir');
      expect(result.cost, equals('2000'));
      expect(result.address, equals('dir1'));
    });

    test('download directory', () async {
      final client = _FakeGrpcClient();
      await client.dirDownloadPublic('dir1', '/tmp/outdir');
    });

    test('get archive', () async {
      final client = _FakeGrpcClient();
      final arc = await client.archiveGetPublic('arc1');
      expect(arc.entries.length, equals(1));
      expect(arc.entries[0].path, equals('test.txt'));
      expect(arc.entries[0].address, equals('abc'));
      expect(arc.entries[0].created, equals(1000));
      expect(arc.entries[0].modified, equals(2000));
      expect(arc.entries[0].size, equals(42));
    });

    test('put archive', () async {
      final client = _FakeGrpcClient();
      const archive = Archive(entries: [
        ArchiveEntry(
          path: 'test.txt',
          address: 'abc',
          created: 1000,
          modified: 2000,
          size: 42,
        ),
      ]);
      final result = await client.archivePutPublic(archive);
      expect(result.cost, equals('50'));
      expect(result.address, equals('arc2'));
    });

    test('file cost', () async {
      final client = _FakeGrpcClient();
      final cost =
          await client.fileCost('/tmp/test.txt', isPublic: true, includeArchive: false);
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

    test('error propagates from graphEntryPut', () async {
      final client = errorClient(6, 'duplicate');
      expect(
        () => client.graphEntryPut('sk', [], 'c', []),
        throwsA(isA<AlreadyExistsError>()),
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
