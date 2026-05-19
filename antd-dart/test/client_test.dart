import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  group('Public Prepare (V2-249 PR4)', () {
    test('prepareUploadPublic forwards visibility=public on the wire', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      final res = await client.prepareUploadPublic('/tmp/test.txt');
      expect(res.uploadId, equals('up-pub-1'));

      // Body captured by the mock server must include visibility="public".
      expect(harness.lastPrepareBody, isNotNull);
      expect(harness.lastPrepareBody!['visibility'], equals('public'));
      expect(harness.lastPrepareBody!['path'], equals('/tmp/test.txt'));
    });

    test('prepareUpload forwards explicit visibility argument', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      await client.prepareUpload('/tmp/test.txt', visibility: 'private');
      expect(harness.lastPrepareBody!['visibility'], equals('private'));
    });

    test('prepareUpload without visibility omits the JSON field', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      await client.prepareUpload('/tmp/test.txt');
      // No visibility key on the wire — preserves the pre-public daemon shape.
      expect(harness.lastPrepareBody!.containsKey('visibility'), isFalse);
    });

    test('FinalizeUploadResult surfaces data_map and data_map_address', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      // Set the server to return data_map_address (simulates public flow).
      harness.includeDataMapAddress = true;

      final res = await client.finalizeUpload('up-pub-1', {'qh1': 'tx1'});
      expect(res.dataMap, equals('deadbeef'));
      expect(res.dataMapAddress, equals('cafebabe'));
      expect(res.chunksStored, equals(4));
      // Legacy address stays empty when daemon doesn't echo one.
      expect(res.address, equals(''));
    });

    test('FinalizeUploadResult.dataMapAddress defaults to "" for old daemons', () {
      // Pre-0.6.1 daemons don't return data_map_address — the field defaults
      // cleanly to empty string instead of throwing.
      final r = FinalizeUploadResult.fromJson({
        'data_map': 'deadbeef',
        'chunks_stored': 2,
      });
      expect(r.dataMapAddress, equals(''));
      expect(r.dataMap, equals('deadbeef'));
    });
  });

  group('Single-chunk external signer (V2-274)', () {
    test('prepareChunkUpload base64-encodes data and parses wave-batch shape', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      final res = await client.prepareChunkUpload(
        Uint8List.fromList(utf8.encode('hello')),
      );

      // Request: bytes must arrive base64-encoded under `data`.
      expect(harness.lastChunkPrepareBody, isNotNull);
      expect(harness.lastChunkPrepareBody!['data'], equals('aGVsbG8='));

      expect(res.alreadyStored, isFalse);
      expect(res.uploadId, equals('chunk-1'));
      expect(res.paymentType, equals('wave_batch'));
      expect(res.payments, hasLength(2));
      expect(res.payments[0].quoteHash, equals('qh1'));
      expect(res.payments[1].amount, equals('100'));
      expect(res.totalAmount, equals('200'));
      expect(res.paymentVaultAddress, equals('0xvault'));
      expect(res.paymentTokenAddress, equals('0xtoken'));
      expect(res.rpcUrl, equals('http://localhost:8545'));
    });

    test('prepareChunkUpload already_stored branch omits payment fields', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      // Tell the mock server to respond with already_stored=true.
      harness.chunkAlreadyStored = true;

      final res = await client.prepareChunkUpload(
        Uint8List.fromList(utf8.encode('already-on-network')),
      );

      expect(res.alreadyStored, isTrue);
      expect(res.address, isNotEmpty);
      expect(res.uploadId, equals(''));
      expect(res.payments, isEmpty);
      expect(res.totalAmount, equals(''));
      expect(res.paymentType, equals(''));
    });

    test('finalizeChunkUpload returns address and forwards body', () async {
      final harness = await _ExternalSignerMockServer.start();
      addTearDown(harness.stop);

      final client = AntdClient(baseUrl: harness.baseUrl);
      addTearDown(client.close);

      final addr = await client.finalizeChunkUpload('chunk-1', {
        'qh1': 'tx1',
        'qh2': 'tx2',
      });

      expect(addr, isNotEmpty);
      expect(addr.length, equals(64));

      expect(harness.lastChunkFinalizeBody, isNotNull);
      expect(harness.lastChunkFinalizeBody!['upload_id'], equals('chunk-1'));
      final tx = harness.lastChunkFinalizeBody!['tx_hashes'] as Map<String, dynamic>;
      expect(tx['qh1'], equals('tx1'));
      expect(tx['qh2'], equals('tx2'));
    });
  });
}

/// Local HTTP server on an ephemeral port that mimics the antd daemon's
/// external-signer endpoints. Mirrors the Python test rig
/// (`HTTPServer` on `127.0.0.1:0`) so the dart suite exercises the real
/// `http.Client` transport, not just a request callback.
class _ExternalSignerMockServer {
  final HttpServer _server;

  /// Toggle to make `/v1/chunks/prepare` return the already-stored branch.
  bool chunkAlreadyStored = false;

  /// Toggle to make `/v1/upload/finalize` echo a `data_map_address` (set by
  /// the public-visibility flow).
  bool includeDataMapAddress = false;

  Map<String, dynamic>? lastPrepareBody;
  Map<String, dynamic>? lastChunkPrepareBody;
  Map<String, dynamic>? lastChunkFinalizeBody;

  _ExternalSignerMockServer._(this._server);

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_ExternalSignerMockServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final harness = _ExternalSignerMockServer._(server);
    server.listen(harness._handle);
    return harness;
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    Map<String, dynamic>? body;
    if (raw.isNotEmpty) {
      try {
        body = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        body = null;
      }
    }

    final route = '${req.method} ${req.uri.path}';
    switch (route) {
      case 'POST /v1/upload/prepare':
        lastPrepareBody = body;
        _send(req, 200, {
          'upload_id': 'up-pub-1',
          'payment_type': 'wave_batch',
          'payments': [
            {'quote_hash': 'qh1', 'rewards_address': 'ra1', 'amount': '100'},
          ],
          'total_amount': '100',
          'payment_vault_address': 'dp1',
          'payment_token_address': 'pt1',
          'rpc_url': 'http://localhost:8545',
        });
        break;

      case 'POST /v1/upload/finalize':
        final resp = <String, dynamic>{
          'data_map': 'deadbeef',
          'chunks_stored': 4,
        };
        if (includeDataMapAddress) {
          resp['data_map_address'] = 'cafebabe';
        }
        _send(req, 200, resp);
        break;

      case 'POST /v1/chunks/prepare':
        lastChunkPrepareBody = body;
        if (chunkAlreadyStored) {
          _send(req, 200, {
            'address': 'bb' + ('11' * 31),
            'already_stored': true,
          });
        } else {
          _send(req, 200, {
            'address': 'aa' + ('00' * 31),
            'already_stored': false,
            'upload_id': 'chunk-1',
            'payment_type': 'wave_batch',
            'payments': [
              {'quote_hash': 'qh1', 'rewards_address': 'ra1', 'amount': '100'},
              {'quote_hash': 'qh2', 'rewards_address': 'ra2', 'amount': '100'},
            ],
            'total_amount': '200',
            'payment_vault_address': '0xvault',
            'payment_token_address': '0xtoken',
            'rpc_url': 'http://localhost:8545',
          });
        }
        break;

      case 'POST /v1/chunks/finalize':
        lastChunkFinalizeBody = body;
        _send(req, 200, {
          'address': 'cc' + ('22' * 31),
        });
        break;

      default:
        _send(req, 404, {'error': 'unknown route: $route'});
    }
  }

  void _send(HttpRequest req, int status, Map<String, dynamic> body) {
    final payload = jsonEncode(body);
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.contentLength = utf8.encode(payload).length;
    req.response.write(payload);
    req.response.close();
  }
}
