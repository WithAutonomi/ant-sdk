import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AntdSdk

/// The five-byte `.ant` header; `"wUFOVAE="` is its base64.
let manifestHeader = Data([0xC1, 0x41, 0x4E, 0x54, 0x01])
let manifestHeaderBase64 = "wUFOVAE="

/// REST wire tests for the manifest API over a stubbed URLSession
/// (``StubURLProtocol``): the base64 round trip, unset sizes reading as `nil`,
/// the both-or-neither entry check, the `embed_roots` default and the 400
/// mapping. Mirrors antd-go's manifest_test.go.
final class ManifestTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> AntdRestClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self] + (config.protocolClasses ?? [])
        return AntdRestClient(baseURL: "http://stub.local", session: URLSession(configuration: config))
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

    private static func thrownError(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Build

    func testBuildManifestSendsEntriesAndOptionsAndDecodesTheBase64() async throws {
        StubURLProtocol.routes["/v1/manifests/build"] = jsonBody([
            "manifest": manifestHeaderBase64,
            "link": "ant://manifest/wUFOVAE",
            "entries": [
                ["effective_name": "a.txt", "path": "a.txt", "size": 10, "kind": "embedded",
                 "content_address": "cc", "exact_size": 10],
                ["effective_name": "11", "kind": "public", "content_address": "11"],
            ],
        ])

        let built = try await makeClient().buildManifest(
            entries: [
                ManifestEntryInput(path: "a.txt", size: 10, dataMap: "abcd"),
                ManifestEntryInput(address: "11"),
            ],
            options: BuildManifestOptions(name: "album", torrentInfoHashes: ["aa", "bb"], embedRoots: false)
        )

        let body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/build"])
        XCTAssertEqual(body["name"] as? String, "album")
        XCTAssertEqual(body["embed_roots"] as? Bool, false)
        XCTAssertEqual(body["torrent_info_hashes"] as? [String], ["aa", "bb"])
        let entries = try XCTUnwrap(body["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0]["path"] as? String, "a.txt")
        XCTAssertEqual(entries[0]["data_map"] as? String, "abcd")
        XCTAssertEqual((entries[0]["size"] as? NSNumber)?.uint64Value, 10)
        XCTAssertNil(entries[0]["address"], "an embedded entry must not send an address")
        XCTAssertEqual(entries[1]["address"] as? String, "11")
        XCTAssertNil(entries[1]["data_map"])
        XCTAssertNil(entries[1]["path"], "an unset path is left out")
        XCTAssertNil(entries[1]["size"], "an unset size is left out, not sent as 0")

        // The base64 on the wire comes back as the raw bytes.
        XCTAssertEqual(built.manifest, manifestHeader)
        XCTAssertEqual(built.link, "ant://manifest/wUFOVAE")
        XCTAssertEqual(built.entries.count, 2)
        let (embedded, pub) = (built.entries[0], built.entries[1])
        XCTAssertEqual(embedded, ManifestEntryInfo(
            effectiveName: "a.txt", path: "a.txt", size: 10, kind: "embedded",
            contentAddress: "cc", exactSize: 10
        ))
        XCTAssertEqual(pub.kind, "public")
        XCTAssertEqual(pub.effectiveName, "11")
        XCTAssertNil(pub.path)
        XCTAssertNil(pub.size, "an absent size reads as nil, not 0")
        XCTAssertNil(pub.exactSize, "an absent exact_size reads as nil, not 0")
        XCTAssertNil(pub.dataMap)
        XCTAssertNil(pub.error)
    }

    /// Default options embed roots: `embed_roots` is sent as `true`, and an
    /// unset name and torrent hashes are left out.
    func testBuildManifestDefaultsToEmbeddingRoots() async throws {
        StubURLProtocol.routes["/v1/manifests/build"] = jsonBody(["manifest": "", "entries": [] as [Any]])
        let client = makeClient()

        XCTAssertTrue(BuildManifestOptions().embedRoots)

        let built = try await client.buildManifest(entries: [ManifestEntryInput(address: "11")])
        var body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/build"])
        XCTAssertEqual(body["embed_roots"] as? Bool, true)
        XCTAssertNil(body["name"])
        XCTAssertNil(body["torrent_info_hashes"])
        XCTAssertEqual(built.manifest, Data())
        XCTAssertNil(built.link, "an absent link reads as nil")

        // An explicit empty name is not sent either.
        _ = try await client.buildManifest(
            entries: [ManifestEntryInput(address: "11")],
            options: BuildManifestOptions(name: "")
        )
        body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/build"])
        XCTAssertEqual(body["embed_roots"] as? Bool, true)
        XCTAssertNil(body["name"])
    }

    /// An entry with both or neither of dataMap and address is refused as a
    /// BadRequestError naming the entry, and nothing is sent.
    func testBuildManifestRejectsBothOrNeitherBeforeSending() async throws {
        let client = makeClient()
        let cases: [(entries: [ManifestEntryInput], index: Int)] = [
            ([ManifestEntryInput()], 0),
            ([ManifestEntryInput(path: "a.txt")], 0),
            ([ManifestEntryInput(dataMap: "", address: "")], 0),
            ([ManifestEntryInput(dataMap: "aa", address: "bb")], 0),
            ([ManifestEntryInput(address: "11"), ManifestEntryInput(dataMap: "aa", address: "bb")], 1),
        ]
        for (entries, index) in cases {
            let error = await Self.thrownError { _ = try await client.buildManifest(entries: entries) }
            let bad = try XCTUnwrap(error as? BadRequestError, "got \(String(describing: error)) for \(entries)")
            XCTAssertTrue(bad.message.contains("entries[\(index)]"), bad.message)
        }
        XCTAssertNil(StubURLProtocol.lastBodies["/v1/manifests/build"], "nothing may be sent")
    }

    func testBuildManifestRefusesBadBase64FromTheDaemon() async throws {
        StubURLProtocol.routes["/v1/manifests/build"] = jsonBody(["manifest": "not base64!", "entries": [] as [Any]])
        let error = await Self.thrownError {
            _ = try await self.makeClient().buildManifest(entries: [ManifestEntryInput(address: "11")])
        }
        XCTAssertTrue(error is InternalError, "got \(String(describing: error))")
    }

    // MARK: - Decode

    func testDecodeManifestSendsBase64AndReadsUnsetFieldsAsNil() async throws {
        StubURLProtocol.routes["/v1/manifests/decode"] = jsonBody([
            "source": "manifest",
            "name": "album",
            "torrent_info_hash_v2": "bb",
            "entries": [
                ["effective_name": "a.txt", "path": "a.txt", "kind": "embedded",
                 "content_address": "cc", "data_map": "abcd", "exact_size": 4_294_967_296],
                ["effective_name": "b", "path": "b", "kind": "public", "content_address": "dd",
                 "error": "Record not found: gone"],
            ],
        ])

        let decoded = try await makeClient().decodeManifest(manifestHeader, resolve: true)

        let body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/decode"])
        XCTAssertEqual(body["manifest"] as? String, manifestHeaderBase64, "the bytes travel as base64")
        XCTAssertEqual(body["resolve"] as? Bool, true)
        XCTAssertNil(body["link"])

        XCTAssertEqual(decoded.source, "manifest")
        XCTAssertEqual(decoded.name, "album")
        XCTAssertNil(decoded.torrentInfoHashV1)
        XCTAssertEqual(decoded.torrentInfoHashV2, "bb")
        let (embedded, failed) = (decoded.entries[0], decoded.entries[1])
        XCTAssertEqual(embedded.dataMap, "abcd")
        XCTAssertEqual(embedded.exactSize, 4_294_967_296, "sizes are UInt64")
        XCTAssertNil(embedded.size, "an absent size reads as nil, not 0")
        XCTAssertNil(embedded.error)
        XCTAssertEqual(failed.error, "Record not found: gone")
        XCTAssertNil(failed.exactSize)
        XCTAssertNil(failed.dataMap)
    }

    func testDecodeManifestLinkSendsOnlyTheLink() async throws {
        StubURLProtocol.routes["/v1/manifests/decode"] = jsonBody([
            "source": "file_link",
            "entries": [["effective_name": "ab", "kind": "public", "content_address": "ab", "exact_size": 0]],
        ])

        let decoded = try await makeClient().decodeManifestLink("ant://manifest/wUFOVAE", resolve: false)

        let body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/decode"])
        XCTAssertEqual(body["link"] as? String, "ant://manifest/wUFOVAE")
        XCTAssertEqual(body["resolve"] as? Bool, false)
        XCTAssertNil(body["manifest"], "a link request must not send manifest bytes")
        XCTAssertEqual(decoded.source, "file_link")
        XCTAssertNil(decoded.name)
        XCTAssertEqual(decoded.entries.first?.exactSize, 0, "a present 0 stays 0")
        XCTAssertNil(decoded.entries.first?.path)
    }

    func testDecodeRefusesEmptyInputBeforeSending() async throws {
        let client = makeClient()
        let empty = await Self.thrownError { _ = try await client.decodeManifest(Data(), resolve: false) }
        XCTAssertTrue(empty is BadRequestError, "got \(String(describing: empty))")
        let noLink = await Self.thrownError { _ = try await client.decodeManifestLink("", resolve: false) }
        XCTAssertTrue(noLink is BadRequestError, "got \(String(describing: noLink))")
        XCTAssertNil(StubURLProtocol.lastBodies["/v1/manifests/decode"], "nothing may be sent")
    }

    // MARK: - Errors

    /// The daemon's 400 for an invalid entry is a BadRequestError that keeps
    /// the daemon's message, `entries[i]` included.
    func testABadRequestMapsToBadRequestErrorAndKeepsTheMessage() async throws {
        StubURLProtocol.statuses["/v1/manifests/build"] = 400
        StubURLProtocol.routes["/v1/manifests/build"] = jsonBody([
            "error": "Bad request: entries[0]: invalid path \"../x\": parent components are not allowed",
            "code": "BAD_REQUEST",
        ])
        let error = await Self.thrownError {
            _ = try await self.makeClient().buildManifest(entries: [ManifestEntryInput(path: "../x", address: "11")])
        }
        let bad = try XCTUnwrap(error as? BadRequestError, "got \(String(describing: error))")
        XCTAssertEqual(bad.statusCode, 400)
        XCTAssertTrue(bad.message.contains("entries[0]: invalid path"), bad.message)

        StubURLProtocol.statuses["/v1/manifests/decode"] = 400
        StubURLProtocol.routes["/v1/manifests/decode"] = jsonBody([
            "error": "Bad request: not a manifest: missing or invalid header", "code": "BAD_REQUEST",
        ])
        let decodeError = await Self.thrownError {
            _ = try await self.makeClient().decodeManifest(Data("nope".utf8), resolve: false)
        }
        XCTAssertTrue(decodeError is BadRequestError, "got \(String(describing: decodeError))")
    }
}

// MARK: - Protocol defaults

/// A conformer written before the manifest API: it implements every other
/// requirement and none of the manifest methods. That it compiles at all is
/// half the test.
private struct PreManifestClient: AntdClientProtocol {
    private func unused() -> AntdError { AntdError("not used by these tests") }

    func health() async throws -> HealthStatus { HealthStatus(ok: true, network: "legacy") }
    func dataPut(_ data: Data, paymentMode: PaymentMode) async throws -> DataPutResult { throw unused() }
    func dataGet(dataMap: String) async throws -> Data { throw unused() }
    func dataPutPublic(_ data: Data, paymentMode: PaymentMode) async throws -> DataPutPublicResult { throw unused() }
    func dataGetPublic(address: String) async throws -> Data { throw unused() }
    func dataCost(_ data: Data, paymentMode: PaymentMode) async throws -> UploadCostEstimate { throw unused() }
    func chunkPut(_ data: Data) async throws -> PutResult { throw unused() }
    func chunkGet(address: String) async throws -> Data { throw unused() }
    func prepareChunkUpload(_ data: Data) async throws -> PrepareChunkResult { throw unused() }
    func finalizeChunkUpload(uploadId: String, txHashes: [String: String]) async throws -> String { throw unused() }
    func filePut(path: String, paymentMode: PaymentMode) async throws -> FilePutResult { throw unused() }
    func fileGet(dataMap: String, destPath: String) async throws { throw unused() }
    func filePutPublic(path: String, paymentMode: PaymentMode) async throws -> FilePutPublicResult { throw unused() }
    func fileGetPublic(address: String, destPath: String) async throws { throw unused() }
    func fileCost(path: String, isPublic: Bool, paymentMode: PaymentMode) async throws -> UploadCostEstimate { throw unused() }
    func walletAddress() async throws -> WalletAddress { throw unused() }
    func walletBalance() async throws -> WalletBalance { throw unused() }
    func walletApprove() async throws -> Bool { throw unused() }
    func prepareUpload(path: String, visibility: String?) async throws -> PrepareUploadResult { throw unused() }
    func prepareUploadPublic(path: String) async throws -> PrepareUploadResult { throw unused() }
    func prepareDataUpload(_ data: Data) async throws -> PrepareUploadResult { throw unused() }
    func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult { throw unused() }
    func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult { throw unused() }
}

final class ManifestProtocolDefaultTests: XCTestCase {

    /// Every manifest method of a conformer that does not implement them
    /// throws NotSupportedError naming the method, before any I/O.
    func testAPreManifestConformerCompilesAndItsManifestMethodsThrowNotSupported() async throws {
        let client: any AntdClientProtocol = PreManifestClient()
        let health = try await client.health()
        XCTAssertEqual(health.network, "legacy")

        let entries = [ManifestEntryInput(address: "11")]
        let calls: [(String, () async throws -> Void)] = [
            ("buildManifest", { _ = try await client.buildManifest(entries: entries, options: BuildManifestOptions()) }),
            // The convenience overload routes through the defaulted requirement.
            ("buildManifest", { _ = try await client.buildManifest(entries: entries) }),
            ("decodeManifest", { _ = try await client.decodeManifest(manifestHeader, resolve: true) }),
            ("decodeManifestLink", { _ = try await client.decodeManifestLink("ant://manifest/x", resolve: false) }),
        ]
        for (method, call) in calls {
            do {
                try await call()
                XCTFail("\(method) should have thrown")
            } catch let error as NotSupportedError {
                XCTAssertTrue(error.message.hasPrefix("\(method) is not supported by PreManifestClient"), error.message)
                XCTAssertEqual(error.statusCode, 0)
            } catch {
                XCTFail("\(method) threw \(error), expected NotSupportedError")
            }
        }
    }

    /// The real REST client implements every manifest requirement itself:
    /// called through the protocol, none of them falls through to a default.
    func testTheRestClientDispatchesEveryManifestMethodThroughTheProtocol() async throws {
        StubURLProtocol.reset()
        func json(_ obj: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: obj) }
        StubURLProtocol.routes = [
            "/v1/manifests/build": json(["manifest": manifestHeaderBase64, "entries": [] as [Any]]),
            "/v1/manifests/decode": json(["source": "manifest", "entries": [] as [Any]]),
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self] + (config.protocolClasses ?? [])
        let client: any AntdClientProtocol = AntdRestClient(baseURL: "http://stub.local", session: URLSession(configuration: config))

        let built = try await client.buildManifest(entries: [ManifestEntryInput(address: "11")], options: BuildManifestOptions())
        XCTAssertEqual(built.manifest, manifestHeader)
        let builtDefault = try await client.buildManifest(entries: [ManifestEntryInput(address: "11")])
        XCTAssertEqual(builtDefault.manifest, manifestHeader)
        let decoded = try await client.decodeManifest(manifestHeader, resolve: false)
        XCTAssertEqual(decoded.source, "manifest")
        let decodedLink = try await client.decodeManifestLink("ant://manifest/x", resolve: false)
        XCTAssertEqual(decodedLink.source, "manifest")
        let lastDecode = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBodies["/v1/manifests/decode"])) as? [String: Any]
        )
        XCTAssertEqual(lastDecode["link"] as? String, "ant://manifest/x")
    }
}
