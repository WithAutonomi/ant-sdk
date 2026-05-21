import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AntdSdk

final class SmokeTests: XCTestCase {

    func testFactoryCreatesRestClient() {
        let client = AntdClient.createRest()
        XCTAssertTrue(client is AntdRestClient)
    }

    func testFactoryCreatesGrpcClient() {
        let client = AntdClient.createGrpc()
        XCTAssertTrue(client is AntdGrpcClient)
    }

    func testFactoryCreateWithTransportString() {
        let rest = AntdClient.create(transport: "rest")
        XCTAssertTrue(rest is AntdRestClient)

        let grpc = AntdClient.create(transport: "grpc")
        XCTAssertTrue(grpc is AntdGrpcClient)
    }

    func testPaymentModeRawValues() {
        XCTAssertEqual(PaymentMode.auto.rawValue, "auto")
        XCTAssertEqual(PaymentMode.merkle.rawValue, "merkle")
        XCTAssertEqual(PaymentMode.single.rawValue, "single")
    }

    func testModelsHaveCorrectStructure() {
        let health = HealthStatus(ok: true, network: "local")
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.network, "local")
        // Diagnostic fields default to empty / 0 for the 2-arg init,
        // so callers + pre-0.4.0 daemon responses both still work.
        XCTAssertEqual(health.version, "")
        XCTAssertEqual(health.evmNetwork, "")
        XCTAssertEqual(health.uptimeSeconds, 0)
        XCTAssertEqual(health.buildCommit, "")

        let fullHealth = HealthStatus(
            ok: true,
            network: "default",
            version: "0.4.0",
            evmNetwork: "arbitrum-one",
            uptimeSeconds: 42,
            buildCommit: "abcdef123456",
            paymentTokenAddress: "0xtoken",
            paymentVaultAddress: "0xvault"
        )
        XCTAssertEqual(fullHealth.version, "0.4.0")
        XCTAssertEqual(fullHealth.evmNetwork, "arbitrum-one")
        XCTAssertEqual(fullHealth.uptimeSeconds, 42)

        let put = PutResult(cost: "100", address: "abc123")
        XCTAssertEqual(put.cost, "100")
        XCTAssertEqual(put.address, "abc123")

        let dataPut = DataPutResult(dataMap: "deadbeef", chunksStored: 3, paymentModeUsed: "merkle")
        XCTAssertEqual(dataPut.dataMap, "deadbeef")
        XCTAssertEqual(dataPut.chunksStored, 3)
        XCTAssertEqual(dataPut.paymentModeUsed, "merkle")

        let filePut = FilePutResult(dataMap: "ab", storageCostAtto: "1", gasCostWei: "2", chunksStored: 4, paymentModeUsed: "auto")
        XCTAssertEqual(filePut.dataMap, "ab")
        XCTAssertEqual(filePut.chunksStored, 4)
    }

    func testErrorHierarchy() {
        let errors: [AntdError] = [
            NotFoundError("not found"),
            AlreadyExistsError("exists"),
            ForkError("fork"),
            BadRequestError("bad"),
            PaymentError("pay"),
            NetworkError("net"),
            TooLargeError("big"),
            InternalError("err"),
        ]

        for error in errors {
            XCTAssertTrue(error is AntdError)
        }

        XCTAssertEqual(NotFoundError("x").statusCode, 404)
        XCTAssertEqual(AlreadyExistsError("x").statusCode, 409)
        XCTAssertEqual(BadRequestError("x").statusCode, 400)
        XCTAssertEqual(PaymentError("x").statusCode, 402)
        XCTAssertEqual(NetworkError("x").statusCode, 502)
        XCTAssertEqual(TooLargeError("x").statusCode, 413)
        XCTAssertEqual(InternalError("x").statusCode, 500)
    }

    func testErrorMappingFromHTTPStatus() {
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(400, body: "bad") is BadRequestError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(402, body: "pay") is PaymentError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(404, body: "nf") is NotFoundError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(409, body: "exists") is AlreadyExistsError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(413, body: "big") is TooLargeError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(500, body: "err") is InternalError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(502, body: "net") is NetworkError)
    }
}

// MARK: - Stub URL protocol

/// Stubs URLSession with a custom `URLProtocol`, so the prepare/finalize
/// surfaces can be exercised without a live antd daemon. This is the same
/// shape that lets the Python suite assert wire-body content on a local
/// HTTPServer — adapted for Swift's URL Loading System. Works on both
/// macOS Foundation and Linux swift-corelibs-foundation.
final class StubURLProtocol: URLProtocol {

    /// Path → canned JSON body. Set per-test before `makeClient`.
    static var routes: [String: Data] = [:]
    /// Path → most recent request body. Inspected by the test.
    static var lastBodies: [String: Data] = [:]

    static func reset() {
        routes = [:]
        lastBodies = [:]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path

        // URLSession on Linux moves the body off NSURLRequest into a stream;
        // read it back through httpBodyStream when httpBody is nil.
        if let body = request.httpBody {
            StubURLProtocol.lastBodies[path] = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buf = Data()
            let bufferSize = 4096
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { pointer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(pointer, maxLength: bufferSize)
                if read <= 0 { break }
                buf.append(pointer, count: read)
            }
            StubURLProtocol.lastBodies[path] = buf
        }

        let bodyData = StubURLProtocol.routes[path] ?? Data("{}".utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bodyData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - PaymentMode + put/get rename wire tests

final class PutGetRenameWireTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> AntdRestClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        return AntdRestClient(baseURL: "http://stub.local", session: session)
    }

    private func jsonBody(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    private func decodeJSON(_ data: Data?) -> [String: Any] {
        guard let data = data, !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// dataPut hits `POST /v1/data` and surfaces all three result fields.
    func testDataPutWiresPaymentModeAndSurfacesResult() async throws {
        StubURLProtocol.routes["/v1/data"] = jsonBody([
            "data_map": "deadbeef",
            "chunks_stored": 3,
            "payment_mode_used": "merkle",
        ])

        let client = makeClient()
        let payload = Data("private bytes".utf8)
        let result = try await client.dataPut(payload, paymentMode: .merkle)

        XCTAssertEqual(result.dataMap, "deadbeef")
        XCTAssertEqual(result.chunksStored, 3)
        XCTAssertEqual(result.paymentModeUsed, "merkle")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/data"])
        XCTAssertEqual(req["payment_mode"] as? String, "merkle")
        XCTAssertEqual(req["data"] as? String, payload.base64EncodedString())
    }

    /// dataGet POSTs to `/v1/data/get` with the data_map.
    func testDataGetUsesPostWithDataMap() async throws {
        StubURLProtocol.routes["/v1/data/get"] = jsonBody([
            "data": Data("retrieved".utf8).base64EncodedString(),
        ])

        let client = makeClient()
        let data = try await client.dataGet(dataMap: "abcd")

        XCTAssertEqual(String(data: data, encoding: .utf8), "retrieved")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/data/get"])
        XCTAssertEqual(req["data_map"] as? String, "abcd")
    }

    /// dataPutPublic hits `POST /v1/data/public`, no `data_map` in response.
    func testDataPutPublicSurfacesAddressAndPaymentMode() async throws {
        StubURLProtocol.routes["/v1/data/public"] = jsonBody([
            "address": "0xAA",
            "chunks_stored": 2,
            "payment_mode_used": "single",
        ])

        let client = makeClient()
        let result = try await client.dataPutPublic(Data("public bytes".utf8), paymentMode: .single)

        XCTAssertEqual(result.address, "0xAA")
        XCTAssertEqual(result.chunksStored, 2)
        XCTAssertEqual(result.paymentModeUsed, "single")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/data/public"])
        XCTAssertEqual(req["payment_mode"] as? String, "single")
    }

    /// filePut hits `POST /v1/files` with full cost surface.
    func testFilePutWiresPaymentModeAndSurfacesResult() async throws {
        StubURLProtocol.routes["/v1/files"] = jsonBody([
            "data_map": "feedface",
            "storage_cost_atto": "123",
            "gas_cost_wei": "456",
            "chunks_stored": 5,
            "payment_mode_used": "auto",
        ])

        let client = makeClient()
        let result = try await client.filePut(path: "/tmp/x", paymentMode: .auto)

        XCTAssertEqual(result.dataMap, "feedface")
        XCTAssertEqual(result.storageCostAtto, "123")
        XCTAssertEqual(result.gasCostWei, "456")
        XCTAssertEqual(result.chunksStored, 5)
        XCTAssertEqual(result.paymentModeUsed, "auto")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/files"])
        XCTAssertEqual(req["payment_mode"] as? String, "auto")
        XCTAssertEqual(req["path"] as? String, "/tmp/x")
    }

    /// fileGet POSTs to `/v1/files/get` with `{data_map, dest_path}`.
    func testFileGetWiresDataMapAndDestPath() async throws {
        StubURLProtocol.routes["/v1/files/get"] = jsonBody([:])

        let client = makeClient()
        try await client.fileGet(dataMap: "feedface", destPath: "/tmp/out")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/files/get"])
        XCTAssertEqual(req["data_map"] as? String, "feedface")
        XCTAssertEqual(req["dest_path"] as? String, "/tmp/out")
    }

    /// filePutPublic hits `POST /v1/files/public`.
    func testFilePutPublicWiresPaymentMode() async throws {
        StubURLProtocol.routes["/v1/files/public"] = jsonBody([
            "address": "0xPUB",
            "storage_cost_atto": "10",
            "gas_cost_wei": "20",
            "chunks_stored": 1,
            "payment_mode_used": "merkle",
        ])

        let client = makeClient()
        let result = try await client.filePutPublic(path: "/tmp/p", paymentMode: .merkle)

        XCTAssertEqual(result.address, "0xPUB")
        XCTAssertEqual(result.chunksStored, 1)

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/files/public"])
        XCTAssertEqual(req["payment_mode"] as? String, "merkle")
    }

    /// fileGetPublic POSTs to `/v1/files/public/get`.
    func testFileGetPublicWiresAddressAndDestPath() async throws {
        StubURLProtocol.routes["/v1/files/public/get"] = jsonBody([:])

        let client = makeClient()
        try await client.fileGetPublic(address: "0xPUB", destPath: "/tmp/out")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/files/public/get"])
        XCTAssertEqual(req["address"] as? String, "0xPUB")
        XCTAssertEqual(req["dest_path"] as? String, "/tmp/out")
    }

    /// dataCost hits `POST /v1/data/cost` with payment_mode in body.
    func testDataCostWiresPaymentMode() async throws {
        StubURLProtocol.routes["/v1/data/cost"] = jsonBody([
            "cost": "999",
            "file_size": 1024,
            "chunk_count": 4,
            "estimated_gas_cost_wei": "111",
            "payment_mode": "single",
        ])

        let client = makeClient()
        let est = try await client.dataCost(Data("x".utf8), paymentMode: .single)

        XCTAssertEqual(est.cost, "999")
        XCTAssertEqual(est.fileSize, 1024)
        XCTAssertEqual(est.chunkCount, 4)
        XCTAssertEqual(est.paymentMode, "single")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/data/cost"])
        XCTAssertEqual(req["payment_mode"] as? String, "single")
    }

    /// fileCost hits `POST /v1/files/cost` with payment_mode + is_public.
    func testFileCostWiresPaymentModeAndIsPublic() async throws {
        StubURLProtocol.routes["/v1/files/cost"] = jsonBody([
            "cost": "888",
            "file_size": 2048,
            "chunk_count": 8,
            "estimated_gas_cost_wei": "222",
            "payment_mode": "merkle",
        ])

        let client = makeClient()
        let est = try await client.fileCost(path: "/tmp/y", isPublic: false, paymentMode: .merkle)

        XCTAssertEqual(est.cost, "888")
        XCTAssertEqual(est.fileSize, 2048)

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/files/cost"])
        XCTAssertEqual(req["payment_mode"] as? String, "merkle")
        XCTAssertEqual(req["is_public"] as? Bool, false)
        XCTAssertEqual(req["path"] as? String, "/tmp/y")
    }
}

// MARK: - V2-249 (public-prepare) + V2-274 (chunks prepare/finalize) tests

final class PreparePublicAndChunkTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    // MARK: helpers

    private func makeClient() -> AntdRestClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        return AntdRestClient(baseURL: "http://stub.local", session: session)
    }

    private func jsonBody(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    private func decodeJSON(_ data: Data?) -> [String: Any] {
        guard let data = data, !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    // MARK: - V2-249 PR4 — visibility forwarding + dataMapAddress

    /// prepareUploadPublic must forward `visibility: "public"` on the wire.
    func testPrepareUploadPublicForwardsVisibility() async throws {
        StubURLProtocol.routes["/v1/upload/prepare"] = jsonBody([
            "upload_id": "up_wave_1",
            "payment_type": "wave_batch",
            "payments": [
                ["quote_hash": "qh1", "rewards_address": "0xR1", "amount": "100"],
            ],
            "total_amount": "100",
            "payment_vault_address": "0xDP",
            "payment_token_address": "0xTK",
            "rpc_url": "http://rpc.local",
        ])

        let client = makeClient()
        let result = try await client.prepareUploadPublic(path: "/tmp/file.dat")
        XCTAssertEqual(result.uploadId, "up_wave_1")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/upload/prepare"])
        XCTAssertEqual(req["visibility"] as? String, "public")
        XCTAssertEqual(req["path"] as? String, "/tmp/file.dat")
    }

    /// prepareUpload with no visibility must omit the field — preserves the
    /// pre-public daemon wire shape.
    func testPrepareUploadOmitsVisibilityWhenNil() async throws {
        StubURLProtocol.routes["/v1/upload/prepare"] = jsonBody([
            "upload_id": "up_wave_2",
            "payment_type": "wave_batch",
            "payments": [],
            "total_amount": "0",
            "payment_vault_address": "0xDP",
            "payment_token_address": "0xTK",
            "rpc_url": "http://rpc.local",
        ])

        let client = makeClient()
        _ = try await client.prepareUpload(path: "/tmp/private.dat")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/upload/prepare"])
        XCTAssertNil(req["visibility"], "visibility must be absent when nil")
        XCTAssertEqual(req["path"] as? String, "/tmp/private.dat")
    }

    /// finalizeUpload surfaces `dataMap` + `dataMapAddress` when the daemon
    /// returns them (public prepare).
    func testFinalizeSurfacesDataMapAddressForPublicUpload() async throws {
        StubURLProtocol.routes["/v1/upload/finalize"] = jsonBody([
            "address": "0xFINAL",
            "chunks_stored": 42,
            "data_map": "deadbeef",
            "data_map_address": "0xDMAP",
        ])

        let client = makeClient()
        let result = try await client.finalizeUpload(
            uploadId: "up_wave_1",
            txHashes: ["qh1": "tx1"]
        )
        XCTAssertEqual(result.address, "0xFINAL")
        XCTAssertEqual(result.chunksStored, 42)
        XCTAssertEqual(result.dataMap, "deadbeef")
        XCTAssertEqual(result.dataMapAddress, "0xDMAP")
    }

    /// Private prepares leave `dataMapAddress` empty (daemon omits the field).
    func testFinalizeOmitsDataMapAddressForPrivateUpload() async throws {
        StubURLProtocol.routes["/v1/upload/finalize"] = jsonBody([
            "address": "0xFINAL",
            "chunks_stored": 42,
            "data_map": "deadbeef",
        ])

        let client = makeClient()
        let result = try await client.finalizeUpload(
            uploadId: "up_wave_1",
            txHashes: ["qh1": "tx1"]
        )
        XCTAssertEqual(result.dataMap, "deadbeef")
        XCTAssertEqual(result.dataMapAddress, "")
    }

    // MARK: - V2-274 — chunks prepare/finalize

    /// `already_stored: true` → address populated, payment fields empty.
    func testPrepareChunkUploadAlreadyStored() async throws {
        StubURLProtocol.routes["/v1/chunks/prepare"] = jsonBody([
            "address": "addr_already_stored",
            "already_stored": true,
        ])

        let client = makeClient()
        let result = try await client.prepareChunkUpload(Data("already_chunk_data".utf8))

        XCTAssertEqual(result.address, "addr_already_stored")
        XCTAssertTrue(result.alreadyStored)
        XCTAssertEqual(result.uploadId, "")
        XCTAssertEqual(result.totalAmount, "")
        XCTAssertTrue(result.payments.isEmpty)

        // Body is base64 of the input bytes.
        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/chunks/prepare"])
        XCTAssertEqual(
            req["data"] as? String,
            Data("already_chunk_data".utf8).base64EncodedString()
        )
    }

    /// `already_stored: false` → full wave-batch payment shape.
    func testPrepareChunkUploadNewChunk() async throws {
        StubURLProtocol.routes["/v1/chunks/prepare"] = jsonBody([
            "address": "addr_chunk_new",
            "already_stored": false,
            "upload_id": "chunk_up_1",
            "payment_type": "wave_batch",
            "payments": [
                ["quote_hash": "qhC", "rewards_address": "0xRC", "amount": "7"],
            ],
            "total_amount": "7",
            "payment_vault_address": "0xVC",
            "payment_token_address": "0xTC",
            "rpc_url": "http://rpc.local",
        ])

        let client = makeClient()
        let result = try await client.prepareChunkUpload(Data("new_chunk_data".utf8))

        XCTAssertEqual(result.address, "addr_chunk_new")
        XCTAssertFalse(result.alreadyStored)
        XCTAssertEqual(result.uploadId, "chunk_up_1")
        XCTAssertEqual(result.paymentType, "wave_batch")
        XCTAssertEqual(result.payments.count, 1)
        XCTAssertEqual(result.payments[0].quoteHash, "qhC")
        XCTAssertEqual(result.payments[0].rewardsAddress, "0xRC")
        XCTAssertEqual(result.payments[0].amount, "7")
        XCTAssertEqual(result.totalAmount, "7")
        XCTAssertEqual(result.paymentVaultAddress, "0xVC")
        XCTAssertEqual(result.paymentTokenAddress, "0xTC")
        XCTAssertEqual(result.rpcUrl, "http://rpc.local")
    }

    /// finalizeChunkUpload returns the address and forwards
    /// `{upload_id, tx_hashes}`.
    func testFinalizeChunkUploadReturnsAddressAndForwardsBody() async throws {
        StubURLProtocol.routes["/v1/chunks/finalize"] = jsonBody([
            "address": "addr_chunk_new",
        ])

        let client = makeClient()
        let addr = try await client.finalizeChunkUpload(
            uploadId: "chunk_up_1",
            txHashes: ["qhC": "tx_C"]
        )
        XCTAssertEqual(addr, "addr_chunk_new")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/chunks/finalize"])
        XCTAssertEqual(req["upload_id"] as? String, "chunk_up_1")
        let txHashes = req["tx_hashes"] as? [String: String]
        XCTAssertEqual(txHashes?["qhC"], "tx_C")
    }
}
