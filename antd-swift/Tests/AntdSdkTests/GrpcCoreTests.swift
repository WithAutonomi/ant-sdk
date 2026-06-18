import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import AntdSdk

/// V2-480 + V2-499 in-process mock-server tests for `AntdGrpcClient`'s core
/// surface: health, data get/put (+ cost + streaming), chunk get/put, file
/// get/put (+ cost). Mirrors the antd-rust / antd-go / antd-py / antd-java /
/// antd-kotlin / antd-csharp / antd-ruby / antd-dart suites.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class GrpcCoreTests: XCTestCase {

    /// Boots an in-process server with all four core data-plane services and
    /// hands the body a client wired to it.
    private func withMockServer<T: Sendable>(
        _ body: @Sendable (AntdGrpcClient) async throws -> T
    ) async throws -> T {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        return try await withGRPCServer(
            transport: transport,
            services: [CoreMockHealthService(), CoreMockDataService(), CoreMockChunkService(), CoreMockFileService()],
            interceptors: [ContentLengthInterceptor(totalSize: "6")]
        ) { _ in
            let listening = try await transport.listeningAddress
            guard let port = listening.ipv4?.port else {
                XCTFail("expected an ipv4 listening address; got \(listening)")
                throw RPCError(code: .internalError, message: "no ipv4 listening address")
            }
            let client = AntdGrpcClient(target: "127.0.0.1:\(port)")
            return try await body(client)
        }
    }

    // MARK: - Health

    func testHealth() async throws {
        try await withMockServer { client in
            let h = try await client.health()
            XCTAssertTrue(h.ok)
            XCTAssertEqual(h.network, "local")
            XCTAssertEqual(h.version, "0.1.0")
        }
    }

    // MARK: - Data

    func testDataPut() async throws {
        try await withMockServer { client in
            let r = try await client.dataPut(Data("secret".utf8), paymentMode: .single)
            XCTAssertEqual(r.dataMap, "dm123")
        }
    }

    func testDataGet() async throws {
        try await withMockServer { client in
            let d = try await client.dataGet(dataMap: "dm123")
            XCTAssertEqual(String(decoding: d, as: UTF8.self), "secret")
        }
    }

    func testDataPutPublic() async throws {
        try await withMockServer { client in
            let r = try await client.dataPutPublic(Data("hello".utf8))
            XCTAssertEqual(r.address, "abc123")
        }
    }

    func testDataGetPublic() async throws {
        try await withMockServer { client in
            let d = try await client.dataGetPublic(address: "abc123")
            XCTAssertEqual(String(decoding: d, as: UTF8.self), "hello")
        }
    }

    func testDataCost() async throws {
        try await withMockServer { client in
            let c = try await client.dataCost(Data("test".utf8))
            XCTAssertEqual(c.cost, "50")
            XCTAssertEqual(c.fileSize, 4)
            XCTAssertEqual(c.chunkCount, 3)
            XCTAssertEqual(c.paymentMode, "single")
        }
    }

    // MARK: - Data streaming (V2-499)

    func testDataStream() async throws {
        try await withMockServer { client in
            var out = Data()
            for try await chunk in try await client.dataStream(dataMap: "dm123") {
                out.append(chunk)
            }
            XCTAssertEqual(String(decoding: out, as: UTF8.self), "secret")
        }
    }

    func testDataStreamPublic() async throws {
        try await withMockServer { client in
            var out = Data()
            for try await chunk in try await client.dataStreamPublic(address: "abc123") {
                out.append(chunk)
            }
            XCTAssertEqual(String(decoding: out, as: UTF8.self), "hello")
        }
    }

    func testDataStreamWithProgress() async throws {
        try await withMockServer { client in
            var out = Data()
            var progress: [DownloadProgress] = []
            var total: UInt64?
            for try await frame in try await client.dataStreamWithProgress(dataMap: "dm123") {
                switch frame {
                case .meta(let t): total = t
                case .data(let d): out.append(d)
                case .progress(let p): progress.append(p)
                }
            }
            XCTAssertEqual(String(decoding: out, as: UTF8.self), "secret")
            // x-content-length (injected by ContentLengthInterceptor) surfaces as Meta.
            XCTAssertEqual(total, 6)
            XCTAssertEqual(progress, [DownloadProgress(phase: "fetching", fetched: 1, total: 2)])
        }
    }

    func testDataStreamPublicWithProgress() async throws {
        try await withMockServer { client in
            var out = Data()
            var sawProgress = false
            var total: UInt64?
            for try await frame in try await client.dataStreamPublicWithProgress(address: "abc123") {
                switch frame {
                case .meta(let t): total = t
                case .data(let d): out.append(d)
                case .progress: sawProgress = true
                }
            }
            XCTAssertEqual(String(decoding: out, as: UTF8.self), "hello")
            XCTAssertEqual(total, 6)
            XCTAssertTrue(sawProgress)
        }
    }

    // MARK: - Chunks

    func testChunkPut() async throws {
        try await withMockServer { client in
            let r = try await client.chunkPut(Data("chunkdata".utf8))
            XCTAssertEqual(r.cost, "10")
            XCTAssertEqual(r.address, "chunk1")
        }
    }

    func testChunkGet() async throws {
        try await withMockServer { client in
            let d = try await client.chunkGet(address: "chunk1")
            XCTAssertEqual(String(decoding: d, as: UTF8.self), "chunkdata")
        }
    }

    // MARK: - Files

    func testFilePut() async throws {
        try await withMockServer { client in
            let r = try await client.filePut(path: "/tmp/x.bin", paymentMode: .single)
            XCTAssertEqual(r.dataMap, "private_dm")
            XCTAssertEqual(r.storageCostAtto, "500")
            XCTAssertEqual(r.chunksStored, 2)
            XCTAssertEqual(r.paymentModeUsed, "single")
        }
    }

    func testFilePutPublic() async throws {
        try await withMockServer { client in
            let r = try await client.filePutPublic(path: "/tmp/x.bin")
            XCTAssertEqual(r.address, "file1")
            XCTAssertEqual(r.gasCostWei, "42")
            XCTAssertEqual(r.chunksStored, 3)
        }
    }

    func testFileGet() async throws {
        try await withMockServer { client in
            // Mock returns an empty GetFileResponse; success = no throw.
            try await client.fileGet(dataMap: "dm123", destPath: "/tmp/out.bin")
        }
    }

    func testFileGetPublic() async throws {
        try await withMockServer { client in
            try await client.fileGetPublic(address: "abc123", destPath: "/tmp/out.bin")
        }
    }

    func testFileCost() async throws {
        try await withMockServer { client in
            let c = try await client.fileCost(path: "/tmp/x.bin", isPublic: true)
            XCTAssertEqual(c.cost, "50")
            XCTAssertEqual(c.chunkCount, 3)
        }
    }
}

// MARK: - Mock services

/// Server interceptor that attaches an `x-content-length` initial-metadata
/// header to every response, mirroring how the daemon advertises the download
/// byte total — so the gRPC consumer's Meta-frame path is exercised end-to-end.
struct ContentLengthInterceptor: ServerInterceptor {
    let totalSize: String

    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingServerRequest<Input>,
        context: ServerContext,
        next: @Sendable (StreamingServerRequest<Input>, ServerContext) async throws -> StreamingServerResponse<Output>
    ) async throws -> StreamingServerResponse<Output> {
        var response = try await next(request, context)
        response.metadata.addString(totalSize, forKey: "x-content-length")
        return response
    }
}

private func chunk(_ s: String) -> Antd_V1_DataChunk {
    var c = Antd_V1_DataChunk()
    c.data = Data(s.utf8)
    return c
}

private func progressChunk(phase: String, fetched: UInt64, total: UInt64) -> Antd_V1_DataChunk {
    var p = Antd_V1_DownloadProgress()
    p.phase = phase
    p.fetched = fetched
    p.total = total
    var c = Antd_V1_DataChunk()
    c.progress = p
    return c
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class CoreMockHealthService: Antd_V1_HealthService.SimpleServiceProtocol, @unchecked Sendable {
    func check(request: Antd_V1_HealthCheckRequest, context: ServerContext) async throws -> Antd_V1_HealthCheckResponse {
        var r = Antd_V1_HealthCheckResponse()
        r.status = "ok"
        r.network = "local"
        r.version = "0.1.0"
        r.evmNetwork = "local"
        r.uptimeSeconds = 1
        return r
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class CoreMockDataService: Antd_V1_DataService.SimpleServiceProtocol, @unchecked Sendable {
    func put(request: Antd_V1_PutDataRequest, context: ServerContext) async throws -> Antd_V1_PutDataResponse {
        var r = Antd_V1_PutDataResponse()
        r.dataMap = "dm123"
        return r
    }

    func putPublic(request: Antd_V1_PutPublicDataRequest, context: ServerContext) async throws -> Antd_V1_PutPublicDataResponse {
        var r = Antd_V1_PutPublicDataResponse()
        r.address = "abc123"
        return r
    }

    func get(request: Antd_V1_GetDataRequest, context: ServerContext) async throws -> Antd_V1_GetDataResponse {
        var r = Antd_V1_GetDataResponse()
        r.data = Data("secret".utf8)
        return r
    }

    func getPublic(request: Antd_V1_GetPublicDataRequest, context: ServerContext) async throws -> Antd_V1_GetPublicDataResponse {
        var r = Antd_V1_GetPublicDataResponse()
        r.data = Data("hello".utf8)
        return r
    }

    // Two chunks each so the client's chunk-by-chunk consumption is exercised.
    // When the caller opts into progress, a leading DownloadProgress frame is
    // interleaved so the oneof handling and *WithProgress path are both covered.
    func stream(request: Antd_V1_StreamDataRequest, response: GRPCCore.RPCWriter<Antd_V1_DataChunk>, context: ServerContext) async throws {
        if request.includeProgress {
            try await response.write(progressChunk(phase: "fetching", fetched: 1, total: 2))
        }
        try await response.write(chunk("sec"))
        try await response.write(chunk("ret"))
    }

    func streamPublic(request: Antd_V1_StreamPublicDataRequest, response: GRPCCore.RPCWriter<Antd_V1_DataChunk>, context: ServerContext) async throws {
        if request.includeProgress {
            try await response.write(progressChunk(phase: "fetching", fetched: 1, total: 2))
        }
        try await response.write(chunk("hel"))
        try await response.write(chunk("lo"))
    }

    func cost(request: Antd_V1_DataCostRequest, context: ServerContext) async throws -> Antd_V1_Cost {
        var c = Antd_V1_Cost()
        c.attoTokens = "50"
        c.fileSize = 4
        c.chunkCount = 3
        c.estimatedGasCostWei = "150000000000000"
        c.paymentMode = "single"
        return c
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class CoreMockChunkService: Antd_V1_ChunkService.SimpleServiceProtocol, @unchecked Sendable {
    func get(request: Antd_V1_GetChunkRequest, context: ServerContext) async throws -> Antd_V1_GetChunkResponse {
        var r = Antd_V1_GetChunkResponse()
        r.data = Data("chunkdata".utf8)
        return r
    }

    func put(request: Antd_V1_PutChunkRequest, context: ServerContext) async throws -> Antd_V1_PutChunkResponse {
        var r = Antd_V1_PutChunkResponse()
        var cost = Antd_V1_Cost()
        cost.attoTokens = "10"
        r.cost = cost
        r.address = "chunk1"
        return r
    }

    // External-signer RPCs are covered by GrpcExternalSignerTests; canned here
    // only to satisfy the protocol.
    func prepareChunk(request: Antd_V1_PrepareChunkRequest, context: ServerContext) async throws -> Antd_V1_PrepareChunkResponse {
        Antd_V1_PrepareChunkResponse()
    }

    func finalizeChunk(request: Antd_V1_FinalizeChunkRequest, context: ServerContext) async throws -> Antd_V1_FinalizeChunkResponse {
        Antd_V1_FinalizeChunkResponse()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class CoreMockFileService: Antd_V1_FileService.SimpleServiceProtocol, @unchecked Sendable {
    func put(request: Antd_V1_PutFileRequest, context: ServerContext) async throws -> Antd_V1_PutFileResponse {
        var r = Antd_V1_PutFileResponse()
        r.dataMap = "private_dm"
        r.storageCostAtto = "500"
        r.gasCostWei = "21"
        r.chunksStored = 2
        r.paymentModeUsed = "single"
        return r
    }

    func putPublic(request: Antd_V1_PutFileRequest, context: ServerContext) async throws -> Antd_V1_PutFilePublicResponse {
        var r = Antd_V1_PutFilePublicResponse()
        r.address = "file1"
        r.storageCostAtto = "1000"
        r.gasCostWei = "42"
        r.chunksStored = 3
        r.paymentModeUsed = "auto"
        return r
    }

    func get(request: Antd_V1_GetFileRequest, context: ServerContext) async throws -> Antd_V1_GetFileResponse {
        Antd_V1_GetFileResponse()
    }

    func getPublic(request: Antd_V1_GetFilePublicRequest, context: ServerContext) async throws -> Antd_V1_GetFileResponse {
        Antd_V1_GetFileResponse()
    }

    func cost(request: Antd_V1_FileCostRequest, context: ServerContext) async throws -> Antd_V1_Cost {
        var c = Antd_V1_Cost()
        c.attoTokens = "50"
        c.fileSize = 4
        c.chunkCount = 3
        c.estimatedGasCostWei = "150000000000000"
        c.paymentMode = "single"
        return c
    }
}
