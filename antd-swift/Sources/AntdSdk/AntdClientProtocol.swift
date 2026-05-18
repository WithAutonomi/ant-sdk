import Foundation

/// Client protocol for the Autonomi network via the antd daemon.
///
/// All methods are async. Use ``AntdClient/createRest(baseURL:timeout:)`` or
/// ``AntdClient/createGrpc(target:)`` to create an instance.
public protocol AntdClientProtocol: Sendable {

    // Health
    func health() async throws -> HealthStatus

    // Data
    func dataPutPublic(_ data: Data, paymentMode: String?) async throws -> PutResult
    func dataGetPublic(address: String) async throws -> Data
    func dataPutPrivate(_ data: Data, paymentMode: String?) async throws -> PutResult
    func dataGetPrivate(dataMap: String) async throws -> Data
    func dataCost(_ data: Data) async throws -> UploadCostEstimate

    // Chunks
    func chunkPut(_ data: Data) async throws -> PutResult
    func chunkGet(address: String) async throws -> Data
    func prepareChunkUpload(_ data: Data) async throws -> PrepareChunkResult
    func finalizeChunkUpload(uploadId: String, txHashes: [String: String]) async throws -> String

    // Files
    func fileUploadPublic(path: String, paymentMode: String?) async throws -> FileUploadResult
    func fileDownloadPublic(address: String, destPath: String) async throws
    func fileCost(path: String, isPublic: Bool) async throws -> UploadCostEstimate

    // Wallet
    func walletAddress() async throws -> WalletAddress
    func walletBalance() async throws -> WalletBalance
    func walletApprove() async throws -> Bool

    // External Signer (Two-Phase Upload)
    func prepareUpload(path: String, visibility: String?) async throws -> PrepareUploadResult
    func prepareUploadPublic(path: String) async throws -> PrepareUploadResult
    func prepareDataUpload(_ data: Data) async throws -> PrepareUploadResult
    func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult
    func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult
}
