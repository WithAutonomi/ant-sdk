import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'discover.dart';
import 'errors.dart';
import 'models.dart';

/// Default base URL for the antd daemon.
const defaultBaseUrl = 'http://localhost:8082';

/// Default request timeout.
const defaultTimeout = Duration(minutes: 5);

/// REST client for the antd daemon.
class AntdClient {
  final String _baseUrl;
  final Duration _timeout;
  final http.Client _httpClient;
  final bool _ownsClient;

  /// Creates a new antd REST client.
  ///
  /// [baseUrl] defaults to `http://localhost:8082`.
  /// [timeout] defaults to 5 minutes.
  /// [httpClient] optionally provide a custom HTTP client (e.g. for testing).
  AntdClient({
    String baseUrl = defaultBaseUrl,
    Duration timeout = defaultTimeout,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _timeout = timeout,
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Creates an antd REST client by auto-discovering the daemon port from the
  /// daemon.port file written by antd on startup. Falls back to [defaultBaseUrl]
  /// if the port file is not found.
  factory AntdClient.autoDiscover({
    Duration timeout = defaultTimeout,
    http.Client? httpClient,
  }) {
    final discovered = discoverDaemonUrl();
    final baseUrl = discovered.isNotEmpty ? discovered : defaultBaseUrl;
    return AntdClient(
      baseUrl: baseUrl,
      timeout: timeout,
      httpClient: httpClient,
    );
  }

  /// Closes the HTTP client. Only closes if the client was created internally.
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  // --- Internal helpers ---

  String _url(String path) => '$_baseUrl$path';

  static String _b64Encode(Uint8List data) => base64.encode(data);

  static Uint8List _b64Decode(String s) => base64.decode(s);

  Future<Map<String, dynamic>?> _doJson(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse(_url(path));
    final http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient
            .get(uri, headers: _headers(false))
            .timeout(_timeout);
        break;
      case 'POST':
        response = await _httpClient
            .post(uri,
                headers: _headers(body != null),
                body: body != null ? jsonEncode(body) : null)
            .timeout(_timeout);
        break;
      case 'PUT':
        response = await _httpClient
            .put(uri,
                headers: _headers(body != null),
                body: body != null ? jsonEncode(body) : null)
            .timeout(_timeout);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var msg = response.body;
      try {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        if (parsed.containsKey('error')) {
          msg = parsed['error'] as String;
        }
      } catch (_) {
        // Use raw body as message
      }
      throw errorForStatus(response.statusCode, msg);
    }

    if (response.body.isEmpty) {
      return null;
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<int> _doHead(String path) async {
    final uri = Uri.parse(_url(path));
    final response = await _httpClient
        .head(uri)
        .timeout(_timeout);
    return response.statusCode;
  }

  Map<String, String> _headers(bool hasBody) {
    if (hasBody) {
      return {'Content-Type': 'application/json'};
    }
    return {};
  }

  // --- Health ---

  /// Checks the antd daemon status.
  Future<HealthStatus> health() async {
    final json = await _doJson('GET', '/health');
    return HealthStatus.fromJson(json!);
  }

  // --- Data ---

  /// Stores public immutable data on the network.
  Future<PutResult> dataPutPublic(Uint8List data, {String? paymentMode}) async {
    final body = <String, dynamic>{
      'data': _b64Encode(data),
    };
    if (paymentMode != null) body['payment_mode'] = paymentMode;
    final json = await _doJson('POST', '/v1/data/public', body);
    return PutResult.fromJson(json!);
  }

  /// Retrieves public data by address.
  Future<Uint8List> dataGetPublic(String address) async {
    final json = await _doJson('GET', '/v1/data/public/$address');
    return _b64Decode(json!['data'] as String);
  }

  /// Stores private encrypted data on the network.
  Future<PutResult> dataPutPrivate(Uint8List data, {String? paymentMode}) async {
    final body = <String, dynamic>{
      'data': _b64Encode(data),
    };
    if (paymentMode != null) body['payment_mode'] = paymentMode;
    final json = await _doJson('POST', '/v1/data/private', body);
    return PutResult.fromJson(json!, addressKey: 'data_map');
  }

  /// Retrieves private data using a data map.
  Future<Uint8List> dataGetPrivate(String dataMap) async {
    final encoded = Uri.encodeComponent(dataMap);
    final json = await _doJson('GET', '/v1/data/private?data_map=$encoded');
    return _b64Decode(json!['data'] as String);
  }

  /// Estimates the cost of storing data.
  Future<String> dataCost(Uint8List data) async {
    final json = await _doJson('POST', '/v1/data/cost', {
      'data': _b64Encode(data),
    });
    return json!['cost'] as String;
  }

  // --- Chunks ---

  /// Stores a raw chunk on the network.
  Future<PutResult> chunkPut(Uint8List data) async {
    final json = await _doJson('POST', '/v1/chunks', {
      'data': _b64Encode(data),
    });
    return PutResult.fromJson(json!);
  }

  /// Retrieves a chunk by address.
  Future<Uint8List> chunkGet(String address) async {
    final json = await _doJson('GET', '/v1/chunks/$address');
    return _b64Decode(json!['data'] as String);
  }

  // --- Files ---

  /// Uploads a local file to the network.
  Future<PutResult> fileUploadPublic(String path, {String? paymentMode}) async {
    final body = <String, dynamic>{
      'path': path,
    };
    if (paymentMode != null) body['payment_mode'] = paymentMode;
    final json = await _doJson('POST', '/v1/files/upload/public', body);
    return PutResult.fromJson(json!);
  }

  /// Downloads a file from the network to a local path.
  Future<void> fileDownloadPublic(String address, String destPath) async {
    await _doJson('POST', '/v1/files/download/public', {
      'address': address,
      'dest_path': destPath,
    });
  }

  /// Uploads a local directory to the network.
  Future<PutResult> dirUploadPublic(String path, {String? paymentMode}) async {
    final body = <String, dynamic>{
      'path': path,
    };
    if (paymentMode != null) body['payment_mode'] = paymentMode;
    final json = await _doJson('POST', '/v1/dirs/upload/public', body);
    return PutResult.fromJson(json!);
  }

  /// Downloads a directory from the network to a local path.
  Future<void> dirDownloadPublic(String address, String destPath) async {
    await _doJson('POST', '/v1/dirs/download/public', {
      'address': address,
      'dest_path': destPath,
    });
  }

  /// Estimates the cost of uploading a file.
  Future<String> fileCost(
    String path, {
    bool isPublic = true,
  }) async {
    final json = await _doJson('POST', '/v1/cost/file', {
      'path': path,
      'is_public': isPublic,
    });
    return json!['cost'] as String;
  }

  // --- Wallet ---

  /// Returns the wallet address configured on the daemon.
  Future<WalletAddress> walletAddress() async {
    final json = await _doJson('GET', '/v1/wallet/address');
    return WalletAddress.fromJson(json!);
  }

  /// Returns the wallet balance (tokens and gas).
  Future<WalletBalance> walletBalance() async {
    final json = await _doJson('GET', '/v1/wallet/balance');
    return WalletBalance.fromJson(json!);
  }

  /// Approves the wallet to spend tokens on payment contracts (one-time operation).
  Future<bool> walletApprove() async {
    final json = await _doJson('POST', '/v1/wallet/approve', {});
    return json!['approved'] as bool;
  }

  // --- External Signer (Two-Phase Upload) ---

  /// Prepares a file upload for external signing.
  Future<PrepareUploadResult> prepareUpload(String path) async {
    final json = await _doJson('POST', '/v1/upload/prepare', {'path': path});
    return PrepareUploadResult.fromJson(json!);
  }

  /// Prepares a data upload for external signing.
  /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
  Future<PrepareUploadResult> prepareDataUpload(Uint8List data) async {
    final json = await _doJson('POST', '/v1/data/prepare', {'data': _b64Encode(data)});
    return PrepareUploadResult.fromJson(json!);
  }

  /// Finalizes an upload after an external signer has submitted payment transactions.
  Future<FinalizeUploadResult> finalizeUpload(
    String uploadId,
    Map<String, String> txHashes,
  ) async {
    final json = await _doJson('POST', '/v1/upload/finalize', {
      'upload_id': uploadId,
      'tx_hashes': txHashes,
    });
    return FinalizeUploadResult.fromJson(json!);
  }

  /// Finalizes a merkle batch upload after selecting a winning pool.
  ///
  /// [uploadId] is the hex upload identifier from [prepareUpload].
  /// [winnerPoolHash] is the 0x-prefixed pool hash selected by the signer.
  /// [storeDataMap] if true, stores the data map on the network (default false).
  Future<FinalizeUploadResult> finalizeMerkleUpload(
    String uploadId,
    String winnerPoolHash, {
    bool storeDataMap = false,
  }) async {
    final json = await _doJson('POST', '/v1/upload/finalize', {
      'upload_id': uploadId,
      'winner_pool_hash': winnerPoolHash,
      'store_data_map': storeDataMap,
    });
    return FinalizeUploadResult.fromJson(json!);
  }
}
