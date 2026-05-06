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
        body = {
          'status': 'ok',
          'network': 'local',
          'version': '0.4.0',
          'evm_network': 'local',
          'uptime_seconds': 42,
          'build_commit': 'abcdef123456',
          'payment_token_address': '0xtoken',
          'payment_vault_address': '0xvault',
        };
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
        body = {
          'cost': '50',
          'file_size': 4,
          'chunk_count': 3,
          'estimated_gas_cost_wei': '150000000000000',
          'payment_mode': 'single',
        };
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
      case 'POST /v1/files/cost':
        body = {
          'cost': '1000',
          'file_size': 4096,
          'chunk_count': 3,
          'estimated_gas_cost_wei': '150000000000000',
          'payment_mode': 'auto',
        };
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
    test('returns health status with all diagnostic fields', () async {
      final client = AntdClient(httpClient: mockDaemon());
      final health = await client.health();
      expect(health.ok, isTrue);
      expect(health.network, equals('local'));
      expect(health.version, equals('0.4.0'));
      expect(health.evmNetwork, equals('local'));
      expect(health.uptimeSeconds, equals(42));
      expect(health.buildCommit, equals('abcdef123456'));
      expect(health.paymentTokenAddress, equals('0xtoken'));
      expect(health.paymentVaultAddress, equals('0xvault'));
      client.close();
    });

    test('HealthStatus.fromJson defaults diagnostics for pre-0.4.0 daemon', () {
      // Older daemons reply with just status + network; the factory defaults
      // populate the diagnostic fields with empty / 0.
      final h = HealthStatus.fromJson({'status': 'ok', 'network': 'default'});
      expect(h.ok, isTrue);
      expect(h.network, equals('default'));
      expect(h.version, equals(''));
      expect(h.evmNetwork, equals(''));
      expect(h.uptimeSeconds, equals(0));
      expect(h.buildCommit, equals(''));
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
    test('returns full breakdown', () async {
      final client = AntdClient(httpClient: mockDaemon());
      final est = await client.dataCost(Uint8List.fromList(utf8.encode('test')));
      expect(est.cost, equals('50'));
      expect(est.fileSize, equals(4));
      expect(est.chunkCount, equals(3));
      expect(est.estimatedGasCostWei, equals('150000000000000'));
      expect(est.paymentMode, equals('single'));
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

    test('returns full breakdown', () async {
      final client = AntdClient(httpClient: mockDaemon());
      final est = await client.fileCost('/tmp/test.txt', isPublic: true);
      expect(est.cost, equals('1000'));
      expect(est.fileSize, equals(4096));
      expect(est.chunkCount, equals(3));
      expect(est.estimatedGasCostWei, equals('150000000000000'));
      expect(est.paymentMode, equals('auto'));
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
