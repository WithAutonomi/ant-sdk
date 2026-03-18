import Foundation

/// Client protocol for the Autonomi network via the antd daemon.
///
/// All methods are async. Use ``AntdClient/createRest(baseURL:timeout:)`` or
/// ``AntdClient/createGrpc(target:)`` to create an instance.
public protocol AntdClientProtocol: Sendable {

    // Health
    func health() async throws -> HealthStatus

    // Data
    func dataPutPublic(_ data: Data) async throws -> PutResult
    func dataGetPublic(address: String) async throws -> Data
    func dataPutPrivate(_ data: Data) async throws -> PutResult
    func dataGetPrivate(dataMap: String) async throws -> Data
    func dataCost(_ data: Data) async throws -> String

    // Chunks
    func chunkPut(_ data: Data) async throws -> PutResult
    func chunkGet(address: String) async throws -> Data

    // Graph
    func graphEntryPut(ownerSecretKey: String, parents: [String], content: String, descendants: [GraphDescendant]) async throws -> PutResult
    func graphEntryGet(address: String) async throws -> GraphEntry
    func graphEntryExists(address: String) async throws -> Bool
    func graphEntryCost(publicKey: String) async throws -> String

    // Files
    func fileUploadPublic(path: String) async throws -> PutResult
    func fileDownloadPublic(address: String, destPath: String) async throws
    func dirUploadPublic(path: String) async throws -> PutResult
    func dirDownloadPublic(address: String, destPath: String) async throws
    func archiveGetPublic(address: String) async throws -> Archive
    func archivePutPublic(archive: Archive) async throws -> PutResult
    func fileCost(path: String, isPublic: Bool, includeArchive: Bool) async throws -> String
}
