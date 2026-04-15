import 'dart:convert';
import 'dart:typed_data';

import 'package:antd/antd.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Creates a MockClient that mimics antd REST responses.
MockClient mockDaemon() {
  return MockClient((request) async {
    final method = request.method;
    final path = request.url.path;
    final query = request.url.query;

    Map<String, dynamic>? body;
    int statusCode = 200;

    switch ('$method $path') {
      // Health
      case 'GET /health':
        body = {'status': 'ok', 'network': 'local'};
        break;

      // Data put public
      case 'POST /v1/data/public':
        body = {'cost': '100', 'address': 'abc123'};
        break;

      // Data get public
      case 'GET /v1/data/public/abc123':
        body = {'data': base64.encode(utf8.encode('hello'))};
        break;

      // Data put private
      case 'POST /v1/data/private':
        body = {'cost': '200', 'data_map': 'dm123'};
        break;

      // Data get private
      case 'GET /v1/data/private':
        if (query.contains('data_map')) {
          body = {'data': base64.encode(utf8.encode('secret'))};
        }
        break;

      // Data cost
      case 'POST /v1/data/cost':
        body = {'cost': '50'};
        break;

      // Chunks
      case 'POST /v1/chunks':
        body = {'cost': '10', 'address': 'chunk1'};
        break;
      case 'GET /v1/chunks/chunk1':
        body = {'data': base64.encode(utf8.encode('chunkdata'))};
        break;

      // Files
      case 'POST /v1/files/upload/public':
        body = {
          'address': 'file1',
          'storage_cost_atto': '1000',
          'gas_cost_wei': '42',
          'chunks_stored': 3,
          'payment_mode_used': 'auto',
        };
        break;
      case 'POST /v1/files/download/public':
        return http.Response('', 200);
      case 'POST /v1/dirs/upload/public':
        body = {
          'address': 'dir1',
          'storage_cost_atto': '2000',
          'gas_cost_wei': '100',
          'chunks_stored': 5,
          'payment_mode_used': 'merkle',
        };
        break;
      case 'POST /v1/dirs/download/public':
        return http.Response('', 200);
      case 'POST /v1/cost/file':
        body = {'cost': '1000'};
        break;

      // 404 for anything else
      default:
        statusCode = 404;
        body = {'error': 'not found'};
    }

    return http.Response(
      body != null ? jsonEncode(body) : '',
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
}

/// Creates a MockClient that always returns the given status code and error.
MockClient errorDaemon(int statusCode, String errorMessage) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({'error': errorMessage}),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('Health', () {
    test('returns health status', () async {
      final client = AntdClient(httpClient: mockDaemon());
      final health = await client.health();
      expect(health.ok, isTrue);
      expect(health.network, equals('local'));
      client.close();
    });
  });

  group('Data Public', () {
    test('put and get public data', () async {
      final client = AntdClient(httpClient: mockDaemon());

      final put = await client.dataPutPublic(Uint8List.fromList(utf8.encode('hello')));
      expect(put.address, equals('abc123'));
      expect(put.cost, equals('100'));

      final data = await client.dataGetPublic('abc123');
      expect(utf8.decode(data), equals('hello'));

      client.close();
    });
  });

  group('Data Private', () {
    test('put and get private data', () async {
      final client = AntdClient(httpClient: mockDaemon());

      final put = await client.dataPutPrivate(Uint8List.fromList(utf8.encode('secret')));
      expect(put.address, equals('dm123'));
      expect(put.cost, equals('200'));

      final data = await client.dataGetPrivate('dm123');
      expect(utf8.decode(data), equals('secret'));

      client.close();
    });
  });

  group('Data Cost', () {
    test('estimates storage cost', () async {
      final client = AntdClient(httpClient: mockDaemon());
      final cost = await client.dataCost(Uint8List.fromList(utf8.encode('test')));
      expect(cost, equals('50'));
      client.close();
    });
  });

  group('Chunks', () {
    test('put and get chunks', () async {
      final client = AntdClient(httpClient: mockDaemon());

      final put = await client.chunkPut(Uint8List.fromList(utf8.encode('chunkdata')));
      expect(put.address, equals('chunk1'));

      final data = await client.chunkGet('chunk1');
      expect(utf8.decode(data), equals('chunkdata'));

      client.close();
    });
  });

  group('Files', () {
    test('upload and download files', () async {
      final client = AntdClient(httpClient: mockDaemon());

      final put = await client.fileUploadPublic('/tmp/test.txt');
      expect(put.address, equals('file1'));
      expect(put.storageCostAtto, equals('1000'));
      expect(put.gasCostWei, equals('42'));
      expect(put.chunksStored, equals(3));
      expect(put.paymentModeUsed, equals('auto'));

      await client.fileDownloadPublic('file1', '/tmp/out.txt');

      client.close();
    });

    test('upload and download directories', () async {
      final client = AntdClient(httpClient: mockDaemon());

      final put = await client.dirUploadPublic('/tmp/mydir');
      expect(put.address, equals('dir1'));
      expect(put.storageCostAtto, equals('2000'));
      expect(put.gasCostWei, equals('100'));
      expect(put.chunksStored, equals(5));
      expect(put.paymentModeUsed, equals('merkle'));

      await client.dirDownloadPublic('dir1', '/tmp/outdir');

      client.close();
    });

    test('estimates file cost', () async {
      final client = AntdClient(httpClient: mockDaemon());
      final cost = await client.fileCost('/tmp/test.txt', isPublic: true);
      expect(cost, equals('1000'));
      client.close();
    });
  });

  group('Error Mapping', () {
    test('maps 404 to NotFoundError', () async {
      final client = AntdClient(httpClient: errorDaemon(404, 'not found'));
      expect(
        () => client.health(),
        throwsA(isA<NotFoundError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      client.close();
    });

    test('maps 400 to BadRequestError', () async {
      final client = AntdClient(httpClient: errorDaemon(400, 'bad request'));
      expect(
        () => client.health(),
        throwsA(isA<BadRequestError>()),
      );
      client.close();
    });

    test('maps 402 to PaymentError', () async {
      final client = AntdClient(httpClient: errorDaemon(402, 'insufficient funds'));
      expect(
        () => client.health(),
        throwsA(isA<PaymentError>()),
      );
      client.close();
    });

    test('maps 409 to AlreadyExistsError', () async {
      final client = AntdClient(httpClient: errorDaemon(409, 'already exists'));
      expect(
        () => client.health(),
        throwsA(isA<AlreadyExistsError>()),
      );
      client.close();
    });

    test('maps 413 to TooLargeError', () async {
      final client = AntdClient(httpClient: errorDaemon(413, 'too large'));
      expect(
        () => client.health(),
        throwsA(isA<TooLargeError>()),
      );
      client.close();
    });

    test('maps 500 to InternalError', () async {
      final client = AntdClient(httpClient: errorDaemon(500, 'server error'));
      expect(
        () => client.health(),
        throwsA(isA<InternalError>()),
      );
      client.close();
    });

    test('maps 502 to NetworkError', () async {
      final client = AntdClient(httpClient: errorDaemon(502, 'network error'));
      expect(
        () => client.health(),
        throwsA(isA<NetworkError>()),
      );
      client.close();
    });

    test('maps unknown status to AntdError', () async {
      final client = AntdClient(httpClient: errorDaemon(503, 'unavailable'));
      expect(
        () => client.health(),
        throwsA(isA<AntdError>().having((e) => e.statusCode, 'statusCode', 503)),
      );
      client.close();
    });
  });
}
