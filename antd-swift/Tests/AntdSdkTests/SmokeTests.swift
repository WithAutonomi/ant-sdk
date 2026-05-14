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

// MARK: - V2-249 (public-prepare) + V2-274 (chunks prepare/finalize) tests

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
