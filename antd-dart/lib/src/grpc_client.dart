import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
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
import 'generated/antd/v1/manifests.pbgrpc.dart' as manifests_pb;
import 'generated/antd/v1/manifests.pb.dart' as manifests_msg;
import 'generated/antd/v1/upload.pbgrpc.dart' as upload_pb;
import 'generated/antd/v1/upload.pb.dart' as upload_msg;
import 'generated/antd/v1/wallet.pbgrpc.dart' as wallet_pb;
import 'generated/antd/v1/wallet.pb.dart' as wallet_msg;
import 'generated/antd/v1/pointers.pbgrpc.dart' as pointers_pb;
import 'generated/antd/v1/pointers.pb.dart' as pointers_msg;

import 'discover.dart';
import 'errors.dart';
import 'manifests.dart';
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

  /// PointerService, on the client's own channel.
  late final pointers_pb.PointerServiceClient _pointerStub =
      pointers_pb.PointerServiceClient(_channel);

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

  /// Metadata key the daemon (with the pointer API) sets on statuses whose
  /// gRPC code is shared with older errors, carrying the REST `code` string.
  static const _errorCodeTrailer = 'x-antd-error-code';

  /// The typed error for a status the daemon tagged with `x-antd-error-code`
  /// in its trailers, when the tag and the status code agree. Anything else
  /// (an untagged status, a tag this SDK does not know, or a tag on an
  /// unexpected code) is `null` and keeps the code-based mapping, so a
  /// FAILED_PRECONDITION without the tag is still a [PaymentError].
  static AntdError? _taggedError(GrpcError e) {
    final tag = e.trailers?[_errorCodeTrailer];
    if (tag == null) return null;
    final message = e.message ?? '';
    switch ((e.code, tag)) {
      case (StatusCode.failedPrecondition, 'POINTER_FINAL'):
        return PointerFinalError(message);
      case (StatusCode.failedPrecondition, 'POINTER_FORKED'):
        return ForkError(message);
      case (StatusCode.aborted, 'CONFLICT'):
        return ConflictError(message);
      case (StatusCode.unavailable, 'CLOSE_GROUP_SHORTFALL'):
        // No structured detail over gRPC: retryable comes from the message's
        // closing "(paid attempt retained...)" hint.
        return CloseGroupShortfallError.fromMessage(message);
      default:
        return null;
    }
  }

  /// Translates a gRPC error into the matching [AntdError] subclass,
  /// preferring the daemon's `x-antd-error-code` trailer where it sent one
  /// (see [_taggedError]).
  static Never _handleError(GrpcError e) {
    final tagged = _taggedError(e);
    if (tagged != null) throw tagged;
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
      case StatusCode.aborted:
        // PARTIAL_UPLOAD: some chunks stored, some still unstored after
        // retries. The counts and the daemon's closing retention hint ride
        // the message text over gRPC (no structured detail yet), so parse
        // them best-effort to match the REST client's typed error:
        // retentionKnown needs the counts to convert and the message to end
        // with one of the daemon's two hints, and retryable needs the "paid
        // attempt retained" one (see PartialUploadError.fromMessage). Every
        // such message opens with the daemon's fixed "Partial upload:"
        // prefix, so gate on the message starting with it (anchored, as
        // antd-rust does): any other ABORTED, including one that quotes the
        // phrase further in, keeps the generic mapping so it is not
        // misreported as a partial upload.
        final message = e.message;
        if (message != null &&
            PartialUploadError.isPartialUploadMessage(message)) {
          throw PartialUploadError.fromMessage(message);
        }
        throw AntdError(e.code, e.message ?? 'gRPC error');
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

  // ---------------------------------------------------------------------------
  // Manifests
  // ---------------------------------------------------------------------------
  //
  // ManifestService: the same methods and types as the REST AntdClient's
  // manifest methods. Nothing is uploaded or paid for. gRPC carries the
  // `.ant` bytes raw.
  //
  // Message size: a manifest can be 64 MiB, so Build's response and
  // Decode's request can pass the 4 MiB default other gRPC stacks enforce
  // (antd-go raises its receive limit per call). grpc-dart enforces no
  // message size limit in either direction (its frame decoder takes the
  // length each message header gives) and has no CallOptions or
  // ChannelOptions setting for one, so there is nothing to raise here; the
  // daemon accepts manifest requests up to 100 MiB. A test sends and
  // receives an 8 MiB manifest to keep that true.

  /// ManifestService, on the client's own channel.
  late final manifests_pb.ManifestServiceClient _manifestStub =
      manifests_pb.ManifestServiceClient(_channel);

  /// Builds a `.ant` manifest from DataMaps and public addresses already in
  /// hand. Nothing is uploaded or paid for. See [AntdClient.buildManifest].
  ///
  /// An entry with both or neither of `dataMap` and `address` throws
  /// [BadRequestError] before anything is sent; the daemon's INVALID_ARGUMENT
  /// for the rest (naming `entries[i]`) is a [BadRequestError].
  ///
  /// Requires antd 0.16.0 or later.
  Future<BuiltManifest> buildManifest(
    List<ManifestEntryInput> entries, {
    String? name,
    List<String>? torrentInfoHashes,
    bool embedRoots = true,
  }) async {
    checkManifestEntries(entries);
    final req = manifests_msg.BuildManifestRequest()..embedRoots = embedRoots;
    if (name != null && name.isNotEmpty) req.name = name;
    if (torrentInfoHashes != null) {
      req.torrentInfoHashes.addAll(torrentInfoHashes);
    }
    for (final e in entries) {
      final entry = manifests_msg.ManifestEntryInput();
      final path = e.path;
      if (path != null && path.isNotEmpty) entry.path = path;
      final size = e.size;
      if (size != null) entry.size = Int64(size);
      final dataMap = e.dataMap;
      if (dataMap != null && dataMap.isNotEmpty) {
        entry.dataMap = dataMap;
      } else {
        entry.address = e.address!;
      }
      req.entries.add(entry);
    }
    try {
      final resp = await _manifestStub.build(req);
      return BuiltManifest(
        manifest: Uint8List.fromList(resp.manifest),
        link: resp.link.isEmpty ? null : resp.link,
        entries: resp.entries.map(_manifestEntryInfo).toList(),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Decodes `.ant` bytes. Nothing is uploaded or paid for. See
  /// [AntdClient.decodeManifest] for [resolve].
  ///
  /// Requires antd 0.16.0 or later.
  Future<DecodedManifest> decodeManifest(
    Uint8List manifest, {
    bool resolve = false,
  }) async {
    if (manifest.isEmpty) {
      throw const BadRequestError(manifestDecodeEmptyMessage);
    }
    return _decodeManifest(manifests_msg.DecodeManifestRequest()
      ..manifest = manifest
      ..resolve = resolve);
  }

  /// Decodes an `ant://` manifest link, file link or bare 64-hex address.
  /// See [AntdClient.decodeManifestLink].
  ///
  /// Requires antd 0.16.0 or later.
  Future<DecodedManifest> decodeManifestLink(
    String link, {
    bool resolve = false,
  }) async {
    if (link.isEmpty) {
      throw const BadRequestError(manifestDecodeEmptyMessage);
    }
    return _decodeManifest(manifests_msg.DecodeManifestRequest()
      ..link = link
      ..resolve = resolve);
  }

  Future<DecodedManifest> _decodeManifest(
      manifests_msg.DecodeManifestRequest req) async {
    try {
      final resp = await _manifestStub.decode(req);
      return DecodedManifest(
        source: resp.source,
        name: resp.hasName() && resp.name.isNotEmpty ? resp.name : null,
        torrentInfoHashV1:
            resp.torrentInfoHashV1.isEmpty ? null : resp.torrentInfoHashV1,
        torrentInfoHashV2:
            resp.torrentInfoHashV2.isEmpty ? null : resp.torrentInfoHashV2,
        entries: resp.entries.map(_manifestEntryInfo).toList(),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Maps a wire `ManifestEntryInfo`. The proto3 `optional` fields read as
  /// null when absent, never as 0 or "": presence, not the value, decides.
  static ManifestEntryInfo _manifestEntryInfo(
      manifests_msg.ManifestEntryInfo e) {
    return ManifestEntryInfo(
      effectiveName: e.effectiveName,
      path: e.hasPath() && e.path.isNotEmpty ? e.path : null,
      size: e.hasSize() ? e.size.toInt() : null,
      kind: e.kind,
      contentAddress: e.contentAddress,
      dataMap: e.dataMap.isEmpty ? null : e.dataMap,
      exactSize: e.hasExactSize() ? e.exactSize.toInt() : null,
      error: e.error.isEmpty ? null : e.error,
    );
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
  /// Throws [PartialUploadError] when the chunk stayed unstored after the
  /// daemon's retries; see [finalizeUpload] for the retry contract.
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
  ///
  /// Throws [PartialUploadError] (gRPC ABORTED) when some chunks stayed
  /// unstored after the daemon's retries. The payment persists and the stored
  /// chunks stay on the network. When [PartialUploadError.retryable] is
  /// `true` (antd >= 0.14.0) the daemon kept the paid attempt under the same
  /// [uploadId]: call this method again with the same arguments to store the
  /// remainder against the same payment, bounding the loop (cap attempts; a
  /// [PartialUploadError.chunksFailed] that stops shrinking means stuck).
  /// When [PartialUploadError.retentionKnown] is `true` but `retryable` is
  /// not, the daemon confirmed nothing was retained: re-prepare the same
  /// content, which skips already-stored chunks so the retry pays only for
  /// the remainder. When `retentionKnown` is `false`, retention is unknown
  /// and the daemon may still hold the paid attempt: stop, keep [uploadId]
  /// and the payment artefacts, and reconcile before re-preparing or paying
  /// again. See [PartialUploadError], `docs/external-signer-flow.md` §6 and
  /// `example/finalize_with_retry.dart` (`finalizeWithRetry`).
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
  ///
  /// Throws [PartialUploadError] when some chunks stayed unstored after the
  /// daemon's retries; see [finalizeUpload] for the retry contract. A merkle
  /// finalize that deliberately left sub-batches unpaid reports
  /// [PartialUploadError.retryable] = `false` (with
  /// [PartialUploadError.retentionKnown] = `true` when the message's counts
  /// parse and it ends with the daemon's not-retained hint), so that case is
  /// a re-prepare.
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

  // ---------------------------------------------------------------------------
  // Pointers
  // ---------------------------------------------------------------------------
  //
  // PointerService: the same methods, types and errors as the REST
  // AntdClient's pointer methods. Every write pays, and every attempt pays
  // again: this client never retries, and callers must not retry
  // pointerCreate, pointerUpdate, pointerTransfer or pointerFinalize
  // automatically (pointerFinalize only on a retryable
  // CloseGroupShortfallError). Reads are free to retry.
  //
  // Unset fields arrive as "" or an absent message over gRPC, and read as
  // null, as REST's nulls do.

  /// Returns the addresses of the pointers this daemon holds owner keys for.
  /// Only these can be written.
  Future<List<String>> pointerKeys() async {
    try {
      final resp =
          await _pointerStub.listKeys(pointers_msg.ListPointerKeysRequest());
      return resp.keys.map((k) => k.address).toList();
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Creates the pointer at [owner], pointing at [target], paid by the daemon
  /// wallet. Throws [AlreadyExistsError], before paying, if it exists.
  ///
  /// Pays for the write: do not retry it automatically.
  Future<PointerWriteResult> pointerCreate(
    String owner,
    String target, {
    PointerKind kind = PointerKind.chunk,
  }) async {
    try {
      final req = _pointerWriteRequest(owner, target, kind);
      final resp = await _pointerStub.create(req);
      return _pointerWriteResult(resp);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Points the pointer at [owner] at [target], paid by the daemon wallet,
  /// creating it if it does not exist. Throws [PointerFinalError] if the
  /// pointer was handed over or frozen (usually before paying; see
  /// [PointerFinalError]), and [ConflictError] if a prepared write to it
  /// awaits payment (refused before paying) or the update lost to a newer
  /// state while in flight (possibly after paying). Read the pointer before
  /// writing again.
  ///
  /// Pays for the write: do not retry it automatically.
  Future<PointerWriteResult> pointerUpdate(
    String owner,
    String target, {
    PointerKind kind = PointerKind.chunk,
  }) async {
    try {
      final req = _pointerWriteRequest(owner, target, kind);
      final resp = await _pointerStub.update(req);
      return _pointerWriteResult(resp);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Hands the pointer at [owner] over to the pointer at [recipient], for
  /// good, paid by the daemon wallet. Irreversible once stored. See
  /// [AntdClient.pointerTransfer].
  ///
  /// Pays for the write: do not retry it automatically.
  Future<PointerTransferResult> pointerTransfer(
    String owner,
    String recipient,
  ) async {
    try {
      final req = pointers_msg.PointerTransferRequest()
        ..owner = owner
        ..recipient = recipient;
      final resp = await _pointerStub.transfer(req);
      return PointerTransferResult(
        address: resp.address,
        stateId: resp.stateId,
        finality: resp.hasFinality() ? _pointerFinality(resp.finality) : null,
        finalityError: _nonEmpty(resp.finalityError),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Reads the pointer at [address]. Throws [NotFoundError] if no pointer
  /// exists there.
  Future<PointerRecord> pointerGet(String address) async {
    try {
      final req = pointers_msg.GetPointerRequest()..address = address;
      final r = await _pointerStub.get(req);
      return PointerRecord(
        address: r.address,
        owner: r.owner,
        counter: parsePointerCounter('counter', r.counter),
        kind: r.kind,
        kindTag: r.kindTag,
        target: r.target,
        stateId: r.stateId,
        isFinal: r.isFinal,
        transferredTo: _nonEmpty(r.transferredTo),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Follows a chain of pointers from [address] to the target at its end.
  /// Throws [NotFoundError] if a pointer on the chain does not exist.
  Future<PointerTarget> pointerResolve(String address) async {
    try {
      final req = pointers_msg.ResolvePointerRequest()..address = address;
      final r = await _pointerStub.resolve(req);
      return PointerTarget(kind: r.kind, kindTag: r.kindTag, target: r.target);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Asks the whole close group where the pointer at [address] stands. Only
  /// [PointerFinality.isFinal] means a transfer is beyond dispute.
  Future<PointerFinality> pointerFinality(String address) async {
    try {
      final req = pointers_msg.PointerFinalityRequest()..address = address;
      return _pointerFinality(await _pointerStub.finality(req));
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Follows the transfers from [address] to the pointer whose owner now
  /// decides what it resolves to.
  Future<PointerController> pointerController(String address) async {
    try {
      final req = pointers_msg.PointerControllerRequest()..address = address;
      final c = await _pointerStub.controller(req);
      return PointerController(
        pointer: c.pointer,
        transfers: c.transfers.toList(),
        frozen: c.frozen,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Signs a pointer write with the daemon's loaded owner key and quotes it
  /// for an external signer, which pays with `payForQuotes()` and then calls
  /// [pointerFinalize]. The daemon needs no wallet. While the prepared write
  /// awaits payment, other writes to the pointer throw [ConflictError].
  Future<PointerPrepareResult> pointerPrepare(
    PointerPrepareRequest request,
  ) async {
    try {
      final r = await _pointerStub.prepare(pointers_msg.PreparePointerRequest()
        ..owner = request.owner
        ..op = request.op.wire
        ..target = request.target ?? ''
        ..kind = request.kind?.wire ?? ''
        ..recipient = request.recipient ?? ''
        ..includeSignedQuotes = request.includeSignedQuotes);
      return PointerPrepareResult(
        uploadId: r.uploadId,
        op: r.op,
        address: r.address,
        stateId: r.stateId,
        counter: parsePointerCounter('counter', r.counter),
        paymentType: r.paymentType,
        payments: r.payments
            .map((p) => PaymentInfo(
                  quoteHash: p.quoteHash,
                  rewardsAddress: p.rewardsAddress,
                  amount: p.amount,
                ))
            .toList(),
        totalAmount: r.totalAmount,
        paymentVaultAddress: r.paymentVaultAddress,
        paymentTokenAddress: r.paymentTokenAddress,
        rpcUrl: r.rpcUrl,
        // gRPC carries the quotes as bytes; base64 them to match REST.
        signedQuotes: r.signedQuotes
            .map((q) => SignedQuoteEntry(
                  quoteHash: q.quoteHash,
                  quote: base64.encode(q.quote),
                  commitmentSidecar: q.commitmentSidecar.isEmpty
                      ? null
                      : base64.encode(q.commitmentSidecar),
                ))
            .toList(),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Stores a prepared pointer write once its external signer has paid.
  ///
  /// A write that falls short after payment throws a
  /// [CloseGroupShortfallError] with [CloseGroupShortfallError.retryable] set
  /// (read from the status message's closing hint): call this again with the
  /// same [uploadId] to store it against the same payment, bounding the
  /// loop. See [AntdClient.pointerFinalize].
  Future<PointerFinalizeResult> pointerFinalize(
    String uploadId,
    Map<String, String> txHashes,
  ) async {
    try {
      final req = pointers_msg.FinalizePointerRequest()..uploadId = uploadId;
      req.txHashes.addAll(txHashes);
      final r = await _pointerStub.finalize(req);
      return PointerFinalizeResult(
        address: r.address,
        stateId: r.stateId,
        counter: parsePointerCounter('counter', r.counter),
        finality: r.hasFinality() ? _pointerFinality(r.finality) : null,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  static String? _nonEmpty(String value) => value.isEmpty ? null : value;

  static pointers_msg.PointerWriteRequest _pointerWriteRequest(
    String owner,
    String target,
    PointerKind kind,
  ) =>
      pointers_msg.PointerWriteRequest()
        ..owner = owner
        ..target = target
        ..kind = kind.wire;

  static PointerWriteResult _pointerWriteResult(
          pointers_msg.PointerWriteResponse r) =>
      PointerWriteResult(
        address: r.address,
        stateId: r.stateId,
        counter: parsePointerCounter('counter', r.counter),
      );

  static PointerFinalState _pointerFinalState(
          pointers_msg.PointerFinalState s) =>
      PointerFinalState(
        stateId: s.stateId,
        kind: s.kind,
        kindTag: s.kindTag,
        target: s.target,
        holders: s.holders,
        transferredTo: _nonEmpty(s.transferredTo),
      );

  static PointerFinality _pointerFinality(pointers_msg.PointerFinality f) =>
      PointerFinality(
        address: f.address,
        group: f.group,
        answered: f.answered,
        status: PointerFinalityStatus.fromWire(f.status),
        counter: f.counter.isEmpty
            ? null
            : parsePointerCounter('counter', f.counter),
        state: f.hasState() ? _pointerFinalState(f.state) : null,
        states: f.states.map(_pointerFinalState).toList(),
        majority: f.hasMajority() ? _pointerFinalState(f.majority) : null,
        transferredTo: _nonEmpty(f.transferredTo),
      );

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
      // Already-stored preflight (parity with REST): the external signer
      // pays for (totalChunks - alreadyStoredCount) chunks.
      totalChunks: resp.totalChunks.toInt(),
      alreadyStoredCount: resp.alreadyStoredCount.toInt(),
    );
  }
}
