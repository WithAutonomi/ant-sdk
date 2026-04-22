import Foundation
import GRPCNIOTransportHTTP2
import GRPCProtobuf

/// gRPC client for the antd daemon.
///
/// > Note: The gRPC client requires the generated protobuf stubs from `antd/proto/antd/v1/`.
/// > Run `scripts/generate-protos.sh` to generate them into `Sources/AntdSdk/Proto/`.
/// > Until proto generation is set up, use ``AntdRestClient`` instead.
public final class AntdGrpcClient: AntdClientProtocol, @unchecked Sendable {

    private let target: String

    public init(target: String = "localhost:50051") {
        self.target = target
    }

    // MARK: - Placeholder implementations
    // Full gRPC implementation requires generated proto stubs.
    // The REST client is the recommended default. These methods
    // throw an error until proto generation is configured.

    private func notImplemented() -> AntdError {
        InternalError("gRPC client requires generated proto stubs. Use AntdClient.createRest() or run scripts/generate-protos.sh first.")
    }

    public func health() async throws -> HealthStatus { throw notImplemented() }
    public func dataPutPublic(_ data: Data, paymentMode: String? = nil) async throws -> PutResult { throw notImplemented() }
    public func dataGetPublic(address: String) async throws -> Data { throw notImplemented() }
    public func dataPutPrivate(_ data: Data, paymentMode: String? = nil) async throws -> PutResult { throw notImplemented() }
    public func dataGetPrivate(dataMap: String) async throws -> Data { throw notImplemented() }
    public func dataCost(_ data: Data) async throws -> UploadCostEstimate { throw notImplemented() }
    public func chunkPut(_ data: Data) async throws -> PutResult { throw notImplemented() }
    public func chunkGet(address: String) async throws -> Data { throw notImplemented() }
    public func fileUploadPublic(path: String, paymentMode: String? = nil) async throws -> FileUploadResult { throw notImplemented() }
    public func fileDownloadPublic(address: String, destPath: String) async throws { throw notImplemented() }
    public func dirUploadPublic(path: String, paymentMode: String? = nil) async throws -> FileUploadResult { throw notImplemented() }
    public func dirDownloadPublic(address: String, destPath: String) async throws { throw notImplemented() }
    public func fileCost(path: String, isPublic: Bool = true) async throws -> UploadCostEstimate { throw notImplemented() }
    public func walletAddress() async throws -> WalletAddress { throw notImplemented() }
    public func walletBalance() async throws -> WalletBalance { throw notImplemented() }
    public func walletApprove() async throws -> Bool { throw notImplemented() }
    public func prepareUpload(path: String) async throws -> PrepareUploadResult { throw notImplemented() }
    public func prepareDataUpload(_ data: Data) async throws -> PrepareUploadResult { throw notImplemented() }
    public func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult { throw notImplemented() }
    public func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult { throw notImplemented() }
}
