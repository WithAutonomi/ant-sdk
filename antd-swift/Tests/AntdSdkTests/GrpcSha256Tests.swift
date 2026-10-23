import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import AntdSdk

/// In-process mock-server tests for the `sha256` fields (antd 0.17.0) over
/// gRPC: each upload response reads a non-empty `sha256` and reads `nil` for
/// the proto3 zero value `""`; a manifest entry sets `ManifestEntryInput.sha256`
/// (proto3 optional) only when given; `ManifestEntryInfo.sha256` reads `nil`
/// when empty; INVALID_ARGUMENT for a bad hash maps to ``BadRequestError``.
///
/// The mocks key off the request: a payload / path / upload id of `"none"`
/// answers with no `sha256` (the empty string), anything else answers with
/// ``sha256Hello``.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class GrpcSha256Tests: XCTestCase {

    private func withMockServer<T: Sendable>(
        manifest: Sha256MockManifestService = Sha256MockManifestService(),
        _ body: @Sendable (AntdGrpcClient) async throws -> T
    ) async throws -> T {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        return try await withGRPCServer(
            transport: transport,
            services: [Sha256MockDataService(), Sha256MockFileService(), Sha256MockUploadService(), manifest]
        ) { _ in
            let listening = try await transport.listeningAddress
            guard let port = listening.ipv4?.port else {
                XCTFail("expected an ipv4 listening address; got \(listening)")
                throw RPCError(code: .internalError, message: "no ipv4 listening address")
            }
            return try await body(AntdGrpcClient(target: "127.0.0.1:\(port)"))
        }
    }

    // MARK: - Upload results

    func testUploadResultsReadSha256() async throws {
        try await withMockServer { client in
            let some = Data("some".utf8)
            let results: [String?] = [
                try await client.dataPut(some).sha256,
                try await client.dataPutPublic(some).sha256,
                try await client.filePut(path: "/tmp/some").sha256,
                try await client.filePutPublic(path: "/tmp/some").sha256,
                try await client.finalizeUpload(uploadId: "some", txHashes: [:]).sha256,
                try await client.finalizeMerkleUpload(uploadId: "some", winnerPoolHash: "0xab").sha256,
            ]
            XCTAssertEqual(results, Array(repeating: sha256Hello, count: 6) as [String?])
        }
    }

    /// The proto3 zero value (`""`) is "no hash" (an older daemon), not an
    /// empty string.
    func testUploadResultsReadAnEmptySha256AsNil() async throws {
        try await withMockServer { client in
            let none = Data("none".utf8)
            let results: [String?] = [
                try await client.dataPut(none).sha256,
                try await client.dataPutPublic(none).sha256,
                try await client.filePut(path: "none").sha256,
                try await client.filePutPublic(path: "none").sha256,
                try await client.finalizeUpload(uploadId: "none", txHashes: [:]).sha256,
                try await client.finalizeMerkleUpload(uploadId: "none", winnerPoolHash: "0xab").sha256,
            ]
            XCTAssertEqual(results, Array(repeating: nil, count: 6) as [String?])
        }
    }

    /// Both real clients through the protocol existential, so a signature
    /// drift that fell through to a default would show up here.
    func testSha256ThroughTheProtocol() async throws {
        try await withMockServer { client in
            let viaProtocol: any AntdClientProtocol = client
            let result = try await viaProtocol.dataPutPublic(Data("some".utf8), paymentMode: .auto)
            XCTAssertEqual(result.sha256, sha256Hello)
        }
    }

    // MARK: - Manifest entries

    func testBuildSetsSha256PresenceOnlyWhenGivenAndReadsItBack() async throws {
        let service = Sha256MockManifestService()
        try await withMockServer(manifest: service) { client in
            let built = try await client.buildManifest(entries: [
                ManifestEntryInput(path: "a.txt", address: "11", sha256: sha256Hello),
                ManifestEntryInput(address: "22"),
                ManifestEntryInput(address: "33", sha256: ""),
            ])
            XCTAssertEqual(built.entries.map(\.sha256), [sha256Hello, nil, nil] as [String?],
                           "an empty sha256 in the response reads as nil")
        }
        let req = try XCTUnwrap(service.lastBuild)
        XCTAssertEqual(req.entries.count, 3)
        XCTAssertTrue(req.entries[0].hasSha256)
        XCTAssertEqual(req.entries[0].sha256, sha256Hello)
        XCTAssertFalse(req.entries[1].hasSha256, "an unset hash keeps no presence")
        XCTAssertFalse(req.entries[2].hasSha256, "an empty hash keeps no presence")
    }

    func testDecodeReadsSha256OrNil() async throws {
        try await withMockServer { client in
            let fromBytes = try await client.decodeManifest(manifestHeader, resolve: false)
            let fromLink = try await client.decodeManifestLink("ant://manifest/wUFOVAE", resolve: false)
            for decoded in [fromBytes, fromLink] {
                XCTAssertEqual(decoded.entries.map(\.sha256), [sha256Hello, nil] as [String?])
            }
        }
    }

    /// INVALID_ARGUMENT is the SDK's bad-request error, with the server's
    /// message kept. The bad value is sent as given.
    func testBadSha256IsInvalidArgumentAndMapsToBadRequest() async throws {
        let service = Sha256MockManifestService()
        try await withMockServer(manifest: service) { client in
            do {
                _ = try await client.buildManifest(entries: [ManifestEntryInput(address: "11", sha256: "zz")])
                XCTFail("expected a BadRequestError")
            } catch let error as BadRequestError {
                XCTAssertEqual(error.statusCode, 400)
                XCTAssertTrue(error.message.contains("entries[0]: invalid hex sha256"), error.message)
            }
        }
        XCTAssertEqual(service.lastBuild?.entries.first?.sha256, "zz")
    }
}

// MARK: - Mock services

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class Sha256MockDataService: Antd_V1_DataService.SimpleServiceProtocol, @unchecked Sendable {
    func put(request: Antd_V1_PutDataRequest, context: ServerContext) async throws -> Antd_V1_PutDataResponse {
        var resp = Antd_V1_PutDataResponse()
        resp.dataMap = "dm"
        resp.chunksStored = 3
        if request.data != Data("none".utf8) { resp.sha256 = sha256Hello }
        return resp
    }

    func putPublic(request: Antd_V1_PutPublicDataRequest, context: ServerContext) async throws -> Antd_V1_PutPublicDataResponse {
        var resp = Antd_V1_PutPublicDataResponse()
        resp.address = "ad"
        resp.chunksStored = 3
        if request.data != Data("none".utf8) { resp.sha256 = sha256Hello }
        return resp
    }

    func get(request: Antd_V1_GetDataRequest, context: ServerContext) async throws -> Antd_V1_GetDataResponse {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func getPublic(request: Antd_V1_GetPublicDataRequest, context: ServerContext) async throws -> Antd_V1_GetPublicDataResponse {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func stream(request: Antd_V1_StreamDataRequest, response: RPCWriter<Antd_V1_DataChunk>, context: ServerContext) async throws {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func streamPublic(request: Antd_V1_StreamPublicDataRequest, response: RPCWriter<Antd_V1_DataChunk>, context: ServerContext) async throws {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func cost(request: Antd_V1_DataCostRequest, context: ServerContext) async throws -> Antd_V1_Cost {
        throw RPCError(code: .unimplemented, message: "not used")
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class Sha256MockFileService: Antd_V1_FileService.SimpleServiceProtocol, @unchecked Sendable {
    func put(request: Antd_V1_PutFileRequest, context: ServerContext) async throws -> Antd_V1_PutFileResponse {
        var resp = Antd_V1_PutFileResponse()
        resp.dataMap = "dm"
        resp.storageCostAtto = "1"
        resp.gasCostWei = "2"
        resp.chunksStored = 3
        if request.path != "none" { resp.sha256 = sha256Hello }
        return resp
    }

    func putPublic(request: Antd_V1_PutFileRequest, context: ServerContext) async throws -> Antd_V1_PutFilePublicResponse {
        var resp = Antd_V1_PutFilePublicResponse()
        resp.address = "ad"
        resp.storageCostAtto = "1"
        resp.gasCostWei = "2"
        resp.chunksStored = 3
        if request.path != "none" { resp.sha256 = sha256Hello }
        return resp
    }

    func get(request: Antd_V1_GetFileRequest, context: ServerContext) async throws -> Antd_V1_GetFileResponse {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func getPublic(request: Antd_V1_GetFilePublicRequest, context: ServerContext) async throws -> Antd_V1_GetFileResponse {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func cost(request: Antd_V1_FileCostRequest, context: ServerContext) async throws -> Antd_V1_Cost {
        throw RPCError(code: .unimplemented, message: "not used")
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class Sha256MockUploadService: Antd_V1_UploadService.SimpleServiceProtocol, @unchecked Sendable {
    func prepareFileUpload(request: Antd_V1_PrepareFileUploadRequest, context: ServerContext) async throws -> Antd_V1_PrepareUploadResponse {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func prepareDataUpload(request: Antd_V1_PrepareDataUploadRequest, context: ServerContext) async throws -> Antd_V1_PrepareUploadResponse {
        throw RPCError(code: .unimplemented, message: "not used")
    }

    func finalizeUpload(request: Antd_V1_FinalizeUploadRequest, context: ServerContext) async throws -> Antd_V1_FinalizeUploadResponse {
        var resp = Antd_V1_FinalizeUploadResponse()
        resp.address = "ad"
        resp.chunksStored = 3
        resp.dataMap = "dm"
        if request.uploadID != "none" { resp.sha256 = sha256Hello }
        return resp
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class Sha256MockManifestService: Antd_V1_ManifestService.SimpleServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var builds: [Antd_V1_BuildManifestRequest] = []

    var lastBuild: Antd_V1_BuildManifestRequest? {
        lock.lock()
        defer { lock.unlock() }
        return builds.last
    }

    func build(request: Antd_V1_BuildManifestRequest, context: ServerContext) async throws -> Antd_V1_BuildManifestResponse {
        lock.lock()
        builds.append(request)
        lock.unlock()

        for (i, entry) in request.entries.enumerated() where entry.hasSha256 && entry.sha256 == "zz" {
            throw RPCError(code: .invalidArgument, message: "entries[\(i)]: invalid hex sha256: Odd number of digits")
        }
        // Echo each entry's hash; an unset one comes back as "" (plain string).
        var resp = Antd_V1_BuildManifestResponse()
        resp.manifest = manifestHeader
        resp.entries = request.entries.enumerated().map { i, entry in
            var info = Antd_V1_ManifestEntryInfo()
            info.effectiveName = "e\(i)"
            info.kind = "public"
            info.contentAddress = "11"
            info.sha256 = entry.sha256
            return info
        }
        return resp
    }

    func decode(request: Antd_V1_DecodeManifestRequest, context: ServerContext) async throws -> Antd_V1_DecodeManifestResponse {
        var resp = Antd_V1_DecodeManifestResponse()
        resp.source = "manifest"
        var hashed = Antd_V1_ManifestEntryInfo()
        hashed.effectiveName = "public.txt"
        hashed.kind = "public"
        hashed.contentAddress = "11"
        hashed.sha256 = sha256Hello
        var plain = Antd_V1_ManifestEntryInfo()
        plain.effectiveName = "nohash.txt"
        plain.kind = "public"
        plain.contentAddress = "22"
        resp.entries = [hashed, plain]
        return resp
    }
}
