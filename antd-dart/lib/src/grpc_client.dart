import 'dart:typed_data';

import 'package:grpc/grpc.dart';

// Proto-generated Dart stubs — produced by `protoc` with the `dart` plugin.
// Run: protoc --dart_out=grpc:lib/src/generated antd/v1/*.proto
// The generated files are expected under lib/src/generated/antd/v1/.
import 'generated/antd/v1/health.pbgrpc.dart' as health_pb;
import 'generated/antd/v1/data.pbgrpc.dart' as data_pb;
import 'generated/antd/v1/data.pb.dart' as data_msg;
import 'generated/antd/v1/chunks.pbgrpc.dart' as chunks_pb;
import 'generated/antd/v1/chunks.pb.dart' as chunks_msg;
import 'generated/antd/v1/files.pbgrpc.dart' as files_pb;
import 'generated/antd/v1/files.pb.dart' as files_msg;
import 'generated/antd/v1/upload.pbgrpc.dart' as upload_pb;
import 'generated/antd/v1/upload.pb.dart' as upload_msg;
import 'generated/antd/v1/wallet.pbgrpc.dart' as wallet_pb;
import 'generated/antd/v1/wallet.pb.dart' as wallet_msg;

import 'discover.dart';
import 'errors.dart';
import 'models.dart';

/// gRPC client for the antd daemon.
///
/// Provides the same upload/download surface as [AntdClient] (REST), but
/// communicates over gRPC using the proto-generated stubs from
/// `antd/v1/*.proto`.
///
/// **Proto compilation**: Run `protoc` with the Dart gRPC plugin to generate
/// stubs into `lib/src/generated/`:
///
/// ```bash
/// protoc --dart_out=grpc:lib/src/generated \
///   -I../../antd/proto \
///   antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
///   antd/v1/chunks.proto antd/v1/files.proto
/// ```
class GrpcAntdClient {
  final ClientChannel _channel;
  final bool _ownsChannel;
  final health_pb.HealthServiceClient _healthStub;
  final data_pb.DataServiceClient _dataStub;
  final chunks_pb.ChunkServiceClient _chunkStub;
  final files_pb.FileServiceClient _fileStub;
  final upload_pb.UploadServiceClient _uploadStub;
  final wallet_pb.WalletServiceClient _walletStub;

  /// Creates a new antd gRPC client.
  ///
  /// [host] defaults to `'localhost'`.
  /// [port] defaults to `50051`.
  /// [channel] optionally provide a pre-configured [ClientChannel].
  GrpcAntdClient({
    String host = 'localhost',
    int port = 50051,
    ClientChannel? channel,
  })  : _channel = channel ??
            ClientChannel(
              host,
              port: port,
              options:
                  const ChannelOptions(credentials: ChannelCredentials.insecure()),
            ),
        _ownsChannel = channel == null,
        _healthStub = health_pb.HealthServiceClient(
          channel ??
              ClientChannel(
                host,
                port: port,
                options: const ChannelOptions(
                    credentials: ChannelCredentials.insecure()),
              ),
        ),
        _dataStub = data_pb.DataServiceClient(
          channel ??
              ClientChannel(
                host,
                port: port,
                options: const ChannelOptions(
                    credentials: ChannelCredentials.insecure()),
              ),
        ),
        _chunkStub = chunks_pb.ChunkServiceClient(
          channel ??
              ClientChannel(
                host,
                port: port,
                options: const ChannelOptions(
                    credentials: ChannelCredentials.insecure()),
              ),
        ),
        _fileStub = files_pb.FileServiceClient(
          channel ??
              ClientChannel(
                host,
                port: port,
                options: const ChannelOptions(
                    credentials: ChannelCredentials.insecure()),
              ),
        ),
        _uploadStub = upload_pb.UploadServiceClient(
          channel ??
              ClientChannel(
                host,
                port: port,
                options: const ChannelOptions(
                    credentials: ChannelCredentials.insecure()),
              ),
        ),
        _walletStub = wallet_pb.WalletServiceClient(
          channel ??
              ClientChannel(
                host,
                port: port,
                options: const ChannelOptions(
                    credentials: ChannelCredentials.insecure()),
              ),
        );

  /// Creates a gRPC client by auto-discovering the daemon port from the
  /// daemon.port file written by antd on startup. Falls back to
  /// `localhost:50051` if the port file is not found or has no gRPC line.
  factory GrpcAntdClient.autoDiscover() {
    final target = discoverGrpcTarget();
    if (target.isEmpty) {
      return GrpcAntdClient.withChannel();
    }
    final parts = target.split(':');
    final host = parts[0];
    final port = int.parse(parts[1]);
    return GrpcAntdClient.withChannel(host: host, port: port);
  }

  /// Factory constructor that creates stubs from a single shared channel.
  factory GrpcAntdClient.withChannel({
    String host = 'localhost',
    int port = 50051,
  }) {
    final channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    return GrpcAntdClient(channel: channel);
  }

  /// Shuts down the gRPC channel. Only closes if the channel was created
  /// internally.
  Future<void> close() async {
    if (_ownsChannel) {
      await _channel.shutdown();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helper
  // ---------------------------------------------------------------------------

  /// Translates a gRPC error into the matching [AntdError] subclass.
  static Never _handleError(GrpcError e) {
    switch (e.code) {
      case StatusCode.invalidArgument:
        throw BadRequestError(e.message ?? 'invalid argument');
      case StatusCode.notFound:
        throw NotFoundError(e.message ?? 'not found');
      case StatusCode.alreadyExists:
        throw AlreadyExistsError(e.message ?? 'already exists');
      case StatusCode.resourceExhausted:
        throw TooLargeError(e.message ?? 'resource exhausted');
      case StatusCode.internal:
        throw InternalError(e.message ?? 'internal error');
      case StatusCode.unavailable:
        throw NetworkError(e.message ?? 'unavailable');
      case StatusCode.failedPrecondition:
        throw PaymentError(e.message ?? 'failed precondition');
      default:
        throw AntdError(e.code, e.message ?? 'gRPC error');
    }
  }

  // ---------------------------------------------------------------------------
  // Health
  // ---------------------------------------------------------------------------

  /// Checks the antd daemon status.
  Future<HealthStatus> health() async {
    try {
      final resp =
          await _healthStub.check(health_pb.HealthCheckRequest());
      return HealthStatus(
        ok: resp.status == 'ok',
        network: resp.network,
        version: resp.version,
        evmNetwork: resp.evmNetwork,
        uptimeSeconds: resp.uptimeSeconds.toInt(),
        buildCommit: resp.buildCommit,
        paymentTokenAddress: resp.paymentTokenAddress,
        paymentVaultAddress: resp.paymentVaultAddress,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// Stores private data via gRPC. Returns the caller-held DataMap.
  ///
  /// The gRPC `PutDataResponse` carries `chunksStored` and `paymentModeUsed`
  /// alongside the DataMap (empty cost message, matching REST).
  Future<DataPutResult> dataPut(
    Uint8List data, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    try {
      final req = data_msg.PutDataRequest()
        ..data = data
        ..paymentMode = paymentMode.wire;
      final resp = await _dataStub.put(req);
      return DataPutResult(dataMap: resp.dataMap, chunksStored: resp.chunksStored.toInt(), paymentModeUsed: resp.paymentModeUsed);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Retrieves private data using the DataMap.
  Future<Uint8List> dataGet(String dataMap) async {
    try {
      final req = data_msg.GetDataRequest()..dataMap = dataMap;
      final resp = await _dataStub.get(req);
      return Uint8List.fromList(resp.data);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Stores public immutable data on the network.
  ///
  /// gRPC `PutPublicDataResponse` only carries `address` (and an empty cost
  /// message) — `chunksStored` / `paymentModeUsed` are surfaced as defaults.
  Future<DataPutPublicResult> dataPutPublic(
    Uint8List data, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    try {
      final req = data_msg.PutPublicDataRequest()
        ..data = data
        ..paymentMode = paymentMode.wire;
      final resp = await _dataStub.putPublic(req);
      return DataPutPublicResult(address: resp.address, chunksStored: resp.chunksStored.toInt(), paymentModeUsed: resp.paymentModeUsed);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Retrieves public data by address.
  Future<Uint8List> dataGetPublic(String address) async {
    try {
      final req = data_msg.GetPublicDataRequest()..address = address;
      final resp = await _dataStub.getPublic(req);
      return Uint8List.fromList(resp.data);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Streams private data from a caller-held DataMap (hex), one decrypt batch
  /// at a time, instead of buffering the whole object. The gRPC counterpart to
  /// [dataGet] and mirror of the REST client's [dataStream]; yields raw byte
  /// chunks the caller consumes incrementally.
  Stream<List<int>> dataStream(String dataMap) async* {
    final req = data_msg.StreamDataRequest()..dataMap = dataMap;
    try {
      await for (final chunk in _dataStub.stream(req)) {
        yield chunk.data;
      }
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Streams public data by address — the gRPC counterpart to [dataGetPublic].
  Stream<List<int>> dataStreamPublic(String address) async* {
    final req = data_msg.StreamPublicDataRequest()..address = address;
    try {
      await for (final chunk in _dataStub.streamPublic(req)) {
        yield chunk.data;
      }
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Maps a wire `DataChunk` (oneof `kind { data | progress }`) onto a public
  /// [DownloadFrame]. A chunk with no arm set (shouldn't occur) is treated as an
  /// empty data frame, matching the antd-rust reference consumer.
  static DownloadFrame _frameOf(data_msg.DataChunk chunk) {
    if (chunk.whichKind() == data_msg.DataChunk_Kind.progress) {
      final p = chunk.progress;
      return DownloadFrame.progress(DownloadProgress(
        phase: p.phase,
        fetched: p.fetched.toInt(),
        total: p.total.toInt(),
      ));
    }
    return DownloadFrame.data(chunk.data);
  }

  /// Reads the total download size from a stream response's `x-content-length`
  /// header and wraps it as a leading [DownloadFrame.meta]. Returns `null` when
  /// the header is absent or unparseable (older daemons), so the caller simply
  /// yields no meta frame.
  static DownloadFrame? _metaFrameOf(Map<String, String> headers) {
    final raw = headers['x-content-length'];
    if (raw == null) return null;
    final total = int.tryParse(raw);
    if (total == null) return null;
    return DownloadFrame.meta(total);
  }

  /// Like [dataStream] but requests interleaved fetch-progress frames so the
  /// caller can drive a *determinate* progress bar. Sets the request's
  /// `include_progress` flag and yields [DownloadFrame]s — each a plaintext
  /// chunk or a [DownloadProgress] update. The byte denominator is surfaced as
  /// a leading [DownloadFrame.meta], read from the response's `x-content-length`
  /// metadata header.
  Stream<DownloadFrame> dataStreamWithProgress(String dataMap) async* {
    final req = data_msg.StreamDataRequest()
      ..dataMap = dataMap
      ..includeProgress = true;
    try {
      final response = _dataStub.stream(req);
      // Headers (initial metadata) arrive before the first message; emit the
      // byte total as the first frame when present.
      final meta = _metaFrameOf(await response.headers);
      if (meta != null) yield meta;
      await for (final chunk in response) {
        yield _frameOf(chunk);
      }
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Like [dataStreamPublic] but requests interleaved fetch-progress frames.
  /// See [dataStreamWithProgress].
  Stream<DownloadFrame> dataStreamPublicWithProgress(String address) async* {
    final req = data_msg.StreamPublicDataRequest()
      ..address = address
      ..includeProgress = true;
    try {
      final response = _dataStub.streamPublic(req);
      final meta = _metaFrameOf(await response.headers);
      if (meta != null) yield meta;
      await for (final chunk in response) {
        yield _frameOf(chunk);
      }
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Pre-upload cost breakdown for the given bytes.
  Future<UploadCostEstimate> dataCost(
    Uint8List data, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    try {
      final req = data_msg.DataCostRequest()
        ..data = data
        ..paymentMode = paymentMode.wire;
      final resp = await _dataStub.cost(req);
      return UploadCostEstimate(
        cost: resp.attoTokens,
        fileSize: resp.fileSize.toInt(),
        chunkCount: resp.chunkCount,
        estimatedGasCostWei: resp.estimatedGasCostWei,
        paymentMode: resp.paymentMode,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Chunks
  // ---------------------------------------------------------------------------

  /// Stores a raw chunk on the network.
  Future<PutResult> chunkPut(Uint8List data) async {
    try {
      final req = chunks_msg.PutChunkRequest()..data = data;
      final resp = await _chunkStub.put(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.address,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Retrieves a chunk by address.
  Future<Uint8List> chunkGet(String address) async {
    try {
      final req = chunks_msg.GetChunkRequest()..address = address;
      final resp = await _chunkStub.get(req);
      return Uint8List.fromList(resp.data);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  /// Uploads a local file as a private upload and returns the caller-held
  /// DataMap.
  Future<FilePutResult> filePut(
    String path, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    try {
      final req = files_msg.PutFileRequest()
        ..path = path
        ..paymentMode = paymentMode.wire;
      final resp = await _fileStub.put(req);
      return FilePutResult(
        dataMap: resp.dataMap,
        storageCostAtto: resp.storageCostAtto,
        gasCostWei: resp.gasCostWei,
        chunksStored: resp.chunksStored.toInt(),
        paymentModeUsed: resp.paymentModeUsed,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Downloads a private file from a caller-held DataMap into [destPath].
  Future<void> fileGet(String dataMap, String destPath) async {
    try {
      final req = files_msg.GetFileRequest()
        ..dataMap = dataMap
        ..destPath = destPath;
      await _fileStub.get(req);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Uploads a local file as a public upload.
  Future<FilePutPublicResult> filePutPublic(
    String path, {
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    try {
      final req = files_msg.PutFileRequest()
        ..path = path
        ..paymentMode = paymentMode.wire;
      final resp = await _fileStub.putPublic(req);
      return FilePutPublicResult(
        address: resp.address,
        storageCostAtto: resp.storageCostAtto,
        gasCostWei: resp.gasCostWei,
        chunksStored: resp.chunksStored.toInt(),
        paymentModeUsed: resp.paymentModeUsed,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Downloads a public file from an on-network DataMap address into [destPath].
  Future<void> fileGetPublic(String address, String destPath) async {
    try {
      final req = files_msg.GetFilePublicRequest()
        ..address = address
        ..destPath = destPath;
      await _fileStub.getPublic(req);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Pre-upload cost breakdown for the file at [path].
  Future<UploadCostEstimate> fileCost(
    String path, {
    bool isPublic = true,
    PaymentMode paymentMode = PaymentMode.auto,
  }) async {
    try {
      final req = files_msg.FileCostRequest()
        ..path = path
        ..isPublic = isPublic
        ..paymentMode = paymentMode.wire;
      final resp = await _fileStub.cost(req);
      return UploadCostEstimate(
        cost: resp.attoTokens,
        fileSize: resp.fileSize.toInt(),
        chunkCount: resp.chunkCount,
        estimatedGasCostWei: resp.estimatedGasCostWei,
        paymentMode: resp.paymentMode,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // --- External Signer (chunks) ---

  /// Prepares a single chunk for external-signer publish.
  ///
  /// When the chunk is already on-network, the result has
  /// [PrepareChunkResult.alreadyStored] = `true` and the caller can skip the
  /// finalize step.
  ///
  /// Unlike [chunkPut], does NOT require the daemon to have a wallet — funds
  /// flow through the external signer. Requires antd >= 0.9.0.
  Future<PrepareChunkResult> prepareChunkUpload(Uint8List data) async {
    try {
      final req = chunks_msg.PrepareChunkRequest()..data = data;
      final resp = await _chunkStub.prepareChunk(req);
      return PrepareChunkResult(
        address: resp.address,
        alreadyStored: resp.alreadyStored,
        uploadId: resp.uploadId,
        paymentType: resp.paymentType,
        payments: resp.payments
            .map((p) => PaymentInfo(
                  quoteHash: p.quoteHash,
                  rewardsAddress: p.rewardsAddress,
                  amount: p.amount,
                ))
            .toList(),
        totalAmount: resp.totalAmount,
        paymentVaultAddress: resp.paymentVaultAddress,
        paymentTokenAddress: resp.paymentTokenAddress,
        rpcUrl: resp.rpcUrl,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // --- Wallet ---
  //
  // V2-286: parity with REST AntdClient. A missing daemon wallet emits gRPC
  // FailedPrecondition which _handleError surfaces as PaymentError
  // (established FailedPrecondition->Payment convention across all SDKs).

  Future<WalletAddress> walletAddress() async {
    try {
      final resp = await _walletStub.getAddress(wallet_msg.GetWalletAddressRequest());
      return WalletAddress(address: resp.address);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Submits a prepared chunk after external payment. Returns the chunk
  /// address (matches [PrepareChunkResult.address]).
  ///
  /// Requires antd >= 0.9.0.
  Future<String> finalizeChunkUpload(
    String uploadId,
    Map<String, String> txHashes,
  ) async {
    try {
      final req = chunks_msg.FinalizeChunkRequest()..uploadId = uploadId;
      req.txHashes.addAll(txHashes);
      final resp = await _chunkStub.finalizeChunk(req);
      return resp.address;
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  Future<WalletBalance> walletBalance() async {
    try {
      final resp = await _walletStub.getBalance(wallet_msg.GetWalletBalanceRequest());
      return WalletBalance(balance: resp.balance, gasBalance: resp.gasBalance);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // --- External Signer (uploads) ---

  /// Prepares a file upload for external signing.
  ///
  /// [visibility] = `"public"` bundles the DataMap chunk into the same
  /// external-signer payment batch; `null` / `"private"` keeps it
  /// caller-held. Requires antd >= 0.9.0.
  Future<PrepareUploadResult> prepareUpload(
    String path, {
    String? visibility,
  }) async {
    try {
      final req = upload_msg.PrepareFileUploadRequest()
        ..path = path
        ..visibility = visibility ?? '';
      final resp = await _uploadStub.prepareFileUpload(req);
      return _mapPrepareUploadResponse(resp);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  Future<bool> walletApprove() async {
    try {
      final resp = await _walletStub.approve(wallet_msg.WalletApproveRequest());
      return resp.approved;
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Convenience wrapper for [prepareUpload] with `visibility: "public"`.
  Future<PrepareUploadResult> prepareUploadPublic(String path) {
    return prepareUpload(path, visibility: 'public');
  }

  /// Prepares an in-memory data upload for external signing.
  ///
  /// Requires antd >= 0.9.0.
  Future<PrepareUploadResult> prepareDataUpload(
    Uint8List data, {
    String? visibility,
  }) async {
    try {
      final req = upload_msg.PrepareDataUploadRequest()
        ..data = data
        ..visibility = visibility ?? '';
      final resp = await _uploadStub.prepareDataUpload(req);
      return _mapPrepareUploadResponse(resp);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Finalizes a wave-batch upload after the external signer has submitted
  /// the on-chain payment transactions.
  Future<FinalizeUploadResult> finalizeUpload(
    String uploadId,
    Map<String, String> txHashes,
  ) async {
    try {
      final req = upload_msg.FinalizeUploadRequest()..uploadId = uploadId;
      req.txHashes.addAll(txHashes);
      final resp = await _uploadStub.finalizeUpload(req);
      return FinalizeUploadResult(
        address: resp.address,
        chunksStored: resp.chunksStored.toInt(),
        dataMap: resp.dataMap,
        dataMapAddress: resp.dataMapAddress,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Finalizes a merkle-batch upload after the winning pool has been
  /// determined.
  Future<FinalizeUploadResult> finalizeMerkleUpload(
    String uploadId,
    String winnerPoolHash, {
    bool storeDataMap = false,
  }) async {
    try {
      final req = upload_msg.FinalizeUploadRequest()
        ..uploadId = uploadId
        ..winnerPoolHash = winnerPoolHash
        ..storeDataMap = storeDataMap;
      final resp = await _uploadStub.finalizeUpload(req);
      return FinalizeUploadResult(
        address: resp.address,
        chunksStored: resp.chunksStored.toInt(),
        dataMap: resp.dataMap,
        dataMapAddress: resp.dataMapAddress,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Maps a `PrepareUploadResponse` proto into a [PrepareUploadResult],
  /// populating merkle-only fields (`depth`, `poolCommitments`,
  /// `merklePaymentTimestamp`) only when `paymentType == "merkle"`.
  PrepareUploadResult _mapPrepareUploadResponse(
      upload_msg.PrepareUploadResponse resp) {
    final isMerkle = resp.paymentType == 'merkle';
    return PrepareUploadResult(
      uploadId: resp.uploadId,
      payments: resp.payments
          .map((p) => PaymentInfo(
                quoteHash: p.quoteHash,
                rewardsAddress: p.rewardsAddress,
                amount: p.amount,
              ))
          .toList(),
      totalAmount: resp.totalAmount,
      paymentVaultAddress: resp.paymentVaultAddress,
      paymentTokenAddress: resp.paymentTokenAddress,
      rpcUrl: resp.rpcUrl,
      paymentType: resp.paymentType,
      depth: isMerkle ? resp.depth : null,
      poolCommitments: isMerkle
          ? resp.poolCommitments
              .map((pc) => PoolCommitmentEntry(
                    poolHash: pc.poolHash,
                    candidates: pc.candidates
                        .map((c) => CandidateNodeEntry(
                              rewardsAddress: c.rewardsAddress,
                              amount: c.amount,
                            ))
                        .toList(),
                  ))
              .toList()
          : null,
      merklePaymentTimestamp:
          isMerkle ? resp.merklePaymentTimestamp.toInt() : null,
    );
  }
}
