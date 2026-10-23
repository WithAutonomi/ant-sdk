import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AntdSdk

/// The SHA-256 of "hello", lowercase hex: a realistic 64-character value.
let sha256Hello = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

/// REST wire tests for the `sha256` fields (antd 0.17.0): every upload result
/// type reads it when the daemon sends it and reads `nil` when the key is
/// absent or empty; a manifest entry sends it only when set and reads it back
/// on build and decode; a daemon 400 for a bad hash maps to
/// ``BadRequestError`` with the server's message. Mirrors antd-go's
/// client_test.go and manifest_test.go.
final class Sha256Tests: XCTestCase {

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

    // MARK: - Upload results

    /// Each upload result with `sha256` in the body, then the same body
    /// without it (an older daemon) or with it empty.
    func testUploadResultsReadSha256WhenPresentAndNilWhenAbsentOrEmpty() async throws {
        let client = makeClient()
        let bodies: [String: [String: Any]] = [
            "/v1/data": ["data_map": "dm", "chunks_stored": 3, "payment_mode_used": "single"],
            "/v1/data/public": ["address": "ad", "chunks_stored": 3, "payment_mode_used": "single"],
            "/v1/files": ["data_map": "dm", "storage_cost_atto": "1", "gas_cost_wei": "2",
                          "chunks_stored": 3, "payment_mode_used": "single"],
            "/v1/files/public": ["address": "ad", "storage_cost_atto": "1", "gas_cost_wei": "2",
                                 "chunks_stored": 3, "payment_mode_used": "single"],
            "/v1/upload/finalize": ["address": "ad", "chunks_stored": 3, "data_map": "dm"],
        ]
        func run() async throws -> [String?] {
            [
                try await client.dataPut(Data("x".utf8)).sha256,
                try await client.dataPutPublic(Data("x".utf8)).sha256,
                try await client.filePut(path: "/tmp/x").sha256,
                try await client.filePutPublic(path: "/tmp/x").sha256,
                try await client.finalizeUpload(uploadId: "u", txHashes: [:]).sha256,
                try await client.finalizeMerkleUpload(uploadId: "u", winnerPoolHash: "0xab").sha256,
            ]
        }

        for (path, body) in bodies {
            var withHash = body
            withHash["sha256"] = sha256Hello
            StubURLProtocol.routes[path] = jsonBody(withHash)
        }
        let present = try await run()
        XCTAssertEqual(present, Array(repeating: sha256Hello, count: 6) as [String?])

        for (path, body) in bodies { StubURLProtocol.routes[path] = jsonBody(body) }
        let absent = try await run()
        XCTAssertEqual(absent, Array(repeating: nil, count: 6) as [String?], "no key reads as nil")

        for (path, body) in bodies {
            var emptyHash = body
            emptyHash["sha256"] = ""
            StubURLProtocol.routes[path] = jsonBody(emptyHash)
        }
        let empty = try await run()
        XCTAssertEqual(empty, Array(repeating: nil, count: 6) as [String?], "an empty string reads as nil")
    }

    /// The hash is passed through as the daemon sent it: no lowercasing, no
    /// length or hex check.
    func testUploadResultSha256IsPassedThroughUnchanged() async throws {
        StubURLProtocol.routes["/v1/data/public"] = jsonBody(["address": "ad", "sha256": "NOT-HEX-Upper"])
        let result = try await makeClient().dataPutPublic(Data("x".utf8))
        XCTAssertEqual(result.sha256, "NOT-HEX-Upper")
    }

    /// Existing construction keeps compiling and defaults the new field to nil.
    func testInitializersDefaultSha256ToNil() {
        XCTAssertNil(DataPutResult(dataMap: "dm").sha256)
        XCTAssertNil(DataPutPublicResult(address: "ad").sha256)
        XCTAssertNil(FilePutResult(dataMap: "dm", storageCostAtto: "1", gasCostWei: "2", chunksStored: 1, paymentModeUsed: "single").sha256)
        XCTAssertNil(FilePutPublicResult(address: "ad", storageCostAtto: "1", gasCostWei: "2", chunksStored: 1, paymentModeUsed: "single").sha256)
        XCTAssertNil(FinalizeUploadResult(address: "ad", chunksStored: 1).sha256)
        XCTAssertNil(FinalizeMerkleUploadResult(address: "ad", chunksStored: 1).sha256)
        XCTAssertNil(ManifestEntryInput(address: "11").sha256)
        XCTAssertNil(ManifestEntryInfo(effectiveName: "a", kind: "public", contentAddress: "11").sha256)
    }

    // MARK: - Manifest entries

    func testBuildSendsSha256OnlyWhenSetAndReadsItBack() async throws {
        StubURLProtocol.routes["/v1/manifests/build"] = jsonBody([
            "manifest": manifestHeaderBase64,
            "entries": [
                ["effective_name": "a.txt", "path": "a.txt", "kind": "public", "content_address": "11",
                 "sha256": sha256Hello],
                ["effective_name": "22", "kind": "public", "content_address": "22"],
                ["effective_name": "33", "kind": "public", "content_address": "33", "sha256": ""],
            ],
        ])

        let built = try await makeClient().buildManifest(entries: [
            ManifestEntryInput(path: "a.txt", address: "11", sha256: sha256Hello),
            ManifestEntryInput(address: "22"),
            ManifestEntryInput(address: "33", sha256: ""),
        ])

        let body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/build"])
        let entries = try XCTUnwrap(body["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0]["sha256"] as? String, sha256Hello)
        XCTAssertNil(entries[1]["sha256"], "an unset hash is left out, not sent as null")
        XCTAssertNil(entries[2]["sha256"], "an empty hash is left out, not sent as an empty string")

        XCTAssertEqual(built.entries[0].sha256, sha256Hello)
        XCTAssertNil(built.entries[1].sha256, "an absent sha256 reads as nil")
        XCTAssertNil(built.entries[2].sha256, "an empty sha256 reads as nil")
    }

    func testDecodeReadsSha256OrNil() async throws {
        StubURLProtocol.routes["/v1/manifests/decode"] = jsonBody([
            "source": "manifest",
            "entries": [
                ["effective_name": "public.txt", "path": "public.txt", "kind": "public", "content_address": "11",
                 "sha256": sha256Hello],
                ["effective_name": "nohash.txt", "path": "nohash.txt", "kind": "public", "content_address": "22"],
                ["effective_name": "empty.txt", "path": "empty.txt", "kind": "public", "content_address": "33",
                 "sha256": ""],
            ],
        ])
        let client = makeClient()
        let fromBytes = try await client.decodeManifest(manifestHeader, resolve: false)
        let fromLink = try await client.decodeManifestLink("ant://manifest/wUFOVAE", resolve: false)
        for decoded in [fromBytes, fromLink] {
            XCTAssertEqual(decoded.entries.map(\.sha256), [sha256Hello, nil, nil] as [String?])
        }
    }

    /// The daemon's 400 for a malformed hash is the SDK's bad-request error,
    /// with the server's message kept. The bad value itself is sent as given.
    func testBadSha256Is400BadRequestWithTheServersMessage() async throws {
        StubURLProtocol.statuses["/v1/manifests/build"] = 400
        StubURLProtocol.routes["/v1/manifests/build"] = jsonBody([
            "error": "entries[0]: invalid hex sha256: Odd number of digits",
            "code": "BAD_REQUEST",
        ])
        do {
            _ = try await makeClient().buildManifest(entries: [ManifestEntryInput(address: "11", sha256: "zz")])
            XCTFail("expected a BadRequestError")
        } catch let error as BadRequestError {
            XCTAssertEqual(error.statusCode, 400)
            XCTAssertTrue(error.message.contains("entries[0]: invalid hex sha256"), error.message)
        }
        let body = decodeJSON(StubURLProtocol.lastBodies["/v1/manifests/build"])
        let entries = try XCTUnwrap(body["entries"] as? [[String: Any]])
        XCTAssertEqual(entries[0]["sha256"] as? String, "zz")
    }
}
