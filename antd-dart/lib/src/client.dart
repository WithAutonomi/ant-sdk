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

  /// Issues a streaming request and returns the response body as a
  /// `Stream<List<int>>` on success. Mirrors [_doJson]'s non-2xx handling:
  /// the (short) error body is drained and parsed for `{"error"}` before the
  /// mapped [AntdError] is thrown. On 2xx the body stream is returned
  /// un-buffered so the caller can consume it with constant memory.
  Future<Stream<List<int>>> _doStream(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse(_url(path));
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final response =
        await _httpClient.send(request).timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain the (short) error body so we can parse {"error"} like _doJson.
      final raw = await response.stream.bytesToString();
      var msg = raw;
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        if (parsed.containsKey('error')) {
          msg = parsed['error'] as String;
        }
      } catch (_) {
        // Use raw body as message.
      }
      throw errorForStatus(response.statusCode, msg);
    }

    return response.stream;
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

  /// Stores private encrypted data on the network and returns the caller-held
  /// DataMap (hex). The DataMap is NOT stored on-network — the caller keeps
  /// it as the only retrieval handle.
  Future<DataPutResult> dataPut(
    Uint8List data, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    final json = await _doJson('POST', '/v1/data', {
      'data': _b64Encode(data),
      'payment_mode': paymentMode.wire,
    });
    return DataPutResult.fromJson(json!);
  }

  /// Retrieves private data from a caller-held DataMap (hex).
  Future<Uint8List> dataGet(String dataMap) async {
    final json = await _doJson('POST', '/v1/data/get', {
      'data_map': dataMap,
    });
    return _b64Decode(json!['data'] as String);
  }

  /// Streams private data from a caller-held DataMap (hex) — the streaming
  /// counterpart to [dataGet].
  ///
  /// Returns a `Stream<List<int>>` of the decrypted bytes, consumed with
  /// constant memory rather than buffering the whole payload like [dataGet].
  /// On a non-2xx response the (short) error body is parsed for `{"error"}`
  /// and surfaced as the matching [AntdError] before any bytes are yielded.
  ///
  /// Requires antd >= 0.10.0.
  Future<Stream<List<int>>> dataStream(String dataMap) {
    return _doStream('POST', '/v1/data/stream', {
      'data_map': dataMap,
    });
  }

  /// Stores public immutable data on the network. The DataMap is stored
  /// on-network as an extra chunk; the returned [address] is the shareable
  /// retrieval handle.
  Future<DataPutPublicResult> dataPutPublic(
    Uint8List data, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    final json = await _doJson('POST', '/v1/data/public', {
      'data': _b64Encode(data),
      'payment_mode': paymentMode.wire,
    });
    return DataPutPublicResult.fromJson(json!);
  }

  /// Retrieves public data by address.
  Future<Uint8List> dataGetPublic(String address) async {
    final json = await _doJson('GET', '/v1/data/public/$address');
    return _b64Decode(json!['data'] as String);
  }

  /// Streams public data by address — the streaming counterpart to
  /// [dataGetPublic].
  ///
  /// Returns a `Stream<List<int>>` of the bytes, consumed with constant
  /// memory rather than buffering the whole payload like [dataGetPublic].
  /// On a non-2xx response the (short) error body is parsed for `{"error"}`
  /// and surfaced as the matching [AntdError] before any bytes are yielded.
  ///
  /// Requires antd >= 0.10.0.
  Future<Stream<List<int>>> dataStreamPublic(String address) {
    return _doStream('GET', '/v1/data/public/$address/stream');
  }

  /// Pre-upload cost breakdown for the given bytes.
  ///
  /// The server samples a small number of chunk addresses and extrapolates,
  /// much faster than quoting every chunk on slow networks. Gas is advisory.
  Future<UploadCostEstimate> dataCost(
    Uint8List data, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    final json = await _doJson('POST', '/v1/data/cost', {
      'data': _b64Encode(data),
      'payment_mode': paymentMode.wire,
    });
    return UploadCostEstimate.fromJson(json!);
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

  /// Prepares a single chunk for external-signer publish via
  /// `POST /v1/chunks/prepare`.
  ///
  /// The daemon collects storage quotes for the chunk, stashes the prepared
  /// state, and returns either:
  ///
  ///   * [PrepareChunkResult.alreadyStored] = true with [PrepareChunkResult.address]
  ///     set, if the chunk is already on-network. No payment / finalize is
  ///     needed.
  ///   * [PrepareChunkResult.alreadyStored] = false with [PrepareChunkResult.uploadId]
  ///     + [PrepareChunkResult.payments] populated, in which case the caller
  ///     signs and submits `payForQuotes()` externally, then calls
  ///     [finalizeChunkUpload] with the resulting tx hashes.
  ///
  /// Unlike [chunkPut], this method does NOT require the daemon to have a
  /// wallet — all funds flow through the external signer.
  ///
  /// Requires antd >= 0.7.0.
  Future<PrepareChunkResult> prepareChunkUpload(Uint8List data) async {
    final json = await _doJson('POST', '/v1/chunks/prepare', {
      'data': _b64Encode(data),
    });
    return PrepareChunkResult.fromJson(json!);
  }

  /// Submits a single prepared chunk to the network after external payment
  /// via `POST /v1/chunks/finalize`.
  ///
  /// [txHashes] maps each non-zero quote_hash from [prepareChunkUpload]'s
  /// [PrepareChunkResult.payments] to the corresponding tx_hash returned by
  /// `payForQuotes()`. Returns the hex-encoded network address of the stored
  /// chunk (matches [PrepareChunkResult.address]).
  ///
  /// Requires antd >= 0.7.0.
  Future<String> finalizeChunkUpload(
    String uploadId,
    Map<String, String> txHashes,
  ) async {
    final json = await _doJson('POST', '/v1/chunks/finalize', {
      'upload_id': uploadId,
      'tx_hashes': txHashes,
    });
    return json!['address'] as String? ?? '';
  }

  // --- Files ---

  /// Uploads a local file as a private upload and returns the caller-held
  /// DataMap (hex). The DataMap is NOT stored on-network.
  Future<FilePutResult> filePut(
    String path, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    final json = await _doJson('POST', '/v1/files', {
      'path': path,
      'payment_mode': paymentMode.wire,
    });
    return FilePutResult.fromJson(json!);
  }

  /// Downloads a private file from a caller-held DataMap (hex) into [destPath].
  Future<void> fileGet(String dataMap, String destPath) async {
    await _doJson('POST', '/v1/files/get', {
      'data_map': dataMap,
      'dest_path': destPath,
    });
  }

  /// Uploads a local file as a public upload. The DataMap is stored on-network
  /// as an extra chunk; the returned address is the shareable handle.
  Future<FilePutPublicResult> filePutPublic(
    String path, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    final json = await _doJson('POST', '/v1/files/public', {
      'path': path,
      'payment_mode': paymentMode.wire,
    });
    return FilePutPublicResult.fromJson(json!);
  }

  /// Downloads a public file from an on-network DataMap address to [destPath].
  Future<void> fileGetPublic(String address, String destPath) async {
    await _doJson('POST', '/v1/files/public/get', {
      'address': address,
      'dest_path': destPath,
    });
  }

  /// Pre-upload cost breakdown for the file at [path].
  Future<UploadCostEstimate> fileCost(
    String path, {
    bool isPublic = true,
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    final json = await _doJson('POST', '/v1/files/cost', {
      'path': path,
      'is_public': isPublic,
      'payment_mode': paymentMode.wire,
    });
    return UploadCostEstimate.fromJson(json!);
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
  ///
  /// [visibility] controls how the DataMap is handled:
  ///   * `"public"` — bundles the DataMap chunk into the same external-signer
  ///     payment batch, so one EVM transaction covers data chunks + DataMap.
  ///     After [finalizeUpload], [FinalizeUploadResult.dataMapAddress] is the
  ///     shareable retrieval handle.
  ///   * `"private"` or `null` — keeps the existing private-only behaviour
  ///     (the DataMap is returned to the caller as bytes only).
  ///
  /// The JSON field is included only when [visibility] is non-null, preserving
  /// wire compatibility with pre-public daemons.
  Future<PrepareUploadResult> prepareUpload(
    String path, {
    String? visibility,
  }) async {
    final body = <String, dynamic>{'path': path};
    if (visibility != null) body['visibility'] = visibility;
    final json = await _doJson('POST', '/v1/upload/prepare', body);
    return PrepareUploadResult.fromJson(json!);
  }

  /// Convenience wrapper: prepares a *public* file upload for external
  /// signing. Equivalent to [prepareUpload] with `visibility: "public"`.
  ///
  /// Requires antd >= 0.6.1.
  Future<PrepareUploadResult> prepareUploadPublic(String path) {
    return prepareUpload(path, visibility: 'public');
  }

  /// Prepares a data upload for external signing.
  /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
  ///
  /// [visibility]`="public"` returns 501 from the daemon until upstream
  /// ant-client exposes `data_prepare_upload_with_visibility`; use
  /// [prepareUploadPublic] with a file path until then.
  Future<PrepareUploadResult> prepareDataUpload(
    Uint8List data, {
    String? visibility,
  }) async {
    final body = <String, dynamic>{'data': _b64Encode(data)};
    if (visibility != null) body['visibility'] = visibility;
    final json = await _doJson('POST', '/v1/data/prepare', body);
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
