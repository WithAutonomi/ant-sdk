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
import 'generated/antd/v1/graph.pbgrpc.dart' as graph_pb;
import 'generated/antd/v1/graph.pb.dart' as graph_msg;
import 'generated/antd/v1/common.pb.dart' as common_pb;
import 'generated/antd/v1/files.pbgrpc.dart' as files_pb;
import 'generated/antd/v1/files.pb.dart' as files_msg;

import 'errors.dart';
import 'models.dart';

/// gRPC client for the antd daemon.
///
/// Provides the same 19 async methods as [AntdClient] (REST), but communicates
/// over gRPC using the proto-generated stubs from `antd/v1/*.proto`.
///
/// **Proto compilation**: Run `protoc` with the Dart gRPC plugin to generate
/// stubs into `lib/src/generated/`:
///
/// ```bash
/// protoc --dart_out=grpc:lib/src/generated \
///   -I../../antd/proto \
///   antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
///   antd/v1/chunks.proto antd/v1/graph.proto antd/v1/files.proto
/// ```
class GrpcAntdClient {
  final ClientChannel _channel;
  final bool _ownsChannel;
  final health_pb.HealthServiceClient _healthStub;
  final data_pb.DataServiceClient _dataStub;
  final chunks_pb.ChunkServiceClient _chunkStub;
  final graph_pb.GraphServiceClient _graphStub;
  final files_pb.FileServiceClient _fileStub;

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
        _graphStub = graph_pb.GraphServiceClient(
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
        );

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
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Data (Immutable)
  // ---------------------------------------------------------------------------

  /// Stores public immutable data on the network.
  Future<PutResult> dataPutPublic(Uint8List data) async {
    try {
      final req = data_msg.PutPublicDataRequest()..data = data;
      final resp = await _dataStub.putPublic(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.address,
      );
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

  /// Stores private encrypted data on the network.
  Future<PutResult> dataPutPrivate(Uint8List data) async {
    try {
      final req = data_msg.PutPrivateDataRequest()..data = data;
      final resp = await _dataStub.putPrivate(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.dataMap,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Retrieves private data using a data map.
  Future<Uint8List> dataGetPrivate(String dataMap) async {
    try {
      final req = data_msg.GetPrivateDataRequest()..dataMap = dataMap;
      final resp = await _dataStub.getPrivate(req);
      return Uint8List.fromList(resp.data);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Estimates the cost of storing data.
  Future<String> dataCost(Uint8List data) async {
    try {
      final req = data_msg.DataCostRequest()..data = data;
      final resp = await _dataStub.getCost(req);
      return resp.attoTokens;
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
  // Graph Entries (DAG Nodes)
  // ---------------------------------------------------------------------------

  /// Creates a new graph entry (DAG node).
  Future<PutResult> graphEntryPut(
    String ownerSecretKey,
    List<String> parents,
    String content,
    List<GraphDescendant> descendants,
  ) async {
    try {
      final req = graph_msg.PutGraphEntryRequest()
        ..ownerSecretKey = ownerSecretKey
        ..parents.addAll(parents)
        ..content = content
        ..descendants.addAll(
          descendants.map(
            (d) => common_pb.GraphDescendant()
              ..publicKey = d.publicKey
              ..content = d.content,
          ),
        );
      final resp = await _graphStub.put(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.address,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Retrieves a graph entry by address.
  Future<GraphEntry> graphEntryGet(String address) async {
    try {
      final req = graph_msg.GetGraphEntryRequest()..address = address;
      final resp = await _graphStub.get(req);
      return GraphEntry(
        owner: resp.owner,
        parents: List<String>.unmodifiable(resp.parents),
        content: resp.content,
        descendants: List<GraphDescendant>.unmodifiable(
          resp.descendants.map(
            (d) => GraphDescendant(publicKey: d.publicKey, content: d.content),
          ),
        ),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Checks if a graph entry exists at the given address.
  Future<bool> graphEntryExists(String address) async {
    try {
      final req = graph_msg.CheckGraphEntryRequest()..address = address;
      final resp = await _graphStub.checkExistence(req);
      return resp.exists;
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Estimates the cost of creating a graph entry.
  Future<String> graphEntryCost(String publicKey) async {
    try {
      final req = graph_msg.GraphEntryCostRequest()..publicKey = publicKey;
      final resp = await _graphStub.getCost(req);
      return resp.attoTokens;
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Files & Directories
  // ---------------------------------------------------------------------------

  /// Uploads a local file to the network.
  Future<PutResult> fileUploadPublic(String path) async {
    try {
      final req = files_msg.UploadFileRequest()..path = path;
      final resp = await _fileStub.uploadPublic(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.address,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Downloads a file from the network to a local path.
  Future<void> fileDownloadPublic(String address, String destPath) async {
    try {
      final req = files_msg.DownloadPublicRequest()
        ..address = address
        ..destPath = destPath;
      await _fileStub.downloadPublic(req);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Uploads a local directory to the network.
  Future<PutResult> dirUploadPublic(String path) async {
    try {
      final req = files_msg.UploadFileRequest()..path = path;
      final resp = await _fileStub.dirUploadPublic(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.address,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Downloads a directory from the network to a local path.
  Future<void> dirDownloadPublic(String address, String destPath) async {
    try {
      final req = files_msg.DownloadPublicRequest()
        ..address = address
        ..destPath = destPath;
      await _fileStub.dirDownloadPublic(req);
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Retrieves an archive manifest by address.
  Future<Archive> archiveGetPublic(String address) async {
    try {
      final req = files_msg.ArchiveGetRequest()..address = address;
      final resp = await _fileStub.archiveGetPublic(req);
      return Archive(
        entries: List<ArchiveEntry>.unmodifiable(
          resp.entries.map(
            (e) => ArchiveEntry(
              path: e.path,
              address: e.address,
              created: e.created.toInt(),
              modified: e.modified.toInt(),
              size: e.size.toInt(),
            ),
          ),
        ),
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Creates an archive manifest on the network.
  Future<PutResult> archivePutPublic(Archive archive) async {
    try {
      final req = files_msg.ArchivePutRequest()
        ..entries.addAll(
          archive.entries.map(
            (e) => files_msg.ArchiveEntry()
              ..path = e.path
              ..address = e.address
              ..created = e.created
              ..modified = e.modified
              ..size = e.size,
          ),
        );
      final resp = await _fileStub.archivePutPublic(req);
      return PutResult(
        cost: resp.cost.attoTokens,
        address: resp.address,
      );
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }

  /// Estimates the cost of uploading a file.
  Future<String> fileCost(
    String path, {
    bool isPublic = true,
    bool includeArchive = false,
  }) async {
    try {
      final req = files_msg.FileCostRequest()
        ..path = path
        ..isPublic = isPublic
        ..includeArchive = includeArchive;
      final resp = await _fileStub.getFileCost(req);
      return resp.attoTokens;
    } on GrpcError catch (e) {
      _handleError(e);
    }
  }
}
