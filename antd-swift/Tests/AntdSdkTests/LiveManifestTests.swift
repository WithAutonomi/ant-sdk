import XCTest
@testable import AntdSdk

/// Live manifest build and decode against a running antd (the release after
/// 0.15.0) with a devnet behind it. Nothing is uploaded or paid for: the test
/// builds and decodes manifests of data that is already stored.
///
/// The REST test is skipped unless `ANTD_TEST_URL` and
/// `ANTD_TEST_MANIFEST_ADDRESSES` are set; the gRPC test needs
/// `ANTD_TEST_GRPC` and `ANTD_TEST_MANIFEST_ADDRESSES`. The fixtures:
///
/// - `ANTD_TEST_MANIFEST_ADDRESSES`: two comma-separated public data addresses
/// - `ANTD_TEST_MANIFEST_SIZES`: their exact plaintext sizes, comma-separated
/// - `ANTD_TEST_MANIFEST_DATA_MAP`: a private upload's hex DataMap
/// - `ANTD_TEST_MANIFEST_DATA_MAP_SIZE`: its plaintext size (optional)
/// - `ANTD_TEST_MANIFEST_LINK`: a manifest link built from those three
///   entries (optional)
///
/// ```text
/// ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
/// ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> ANTD_TEST_MANIFEST_SIZES=<n>,<n> \
/// ANTD_TEST_MANIFEST_DATA_MAP=<hex> swift test --filter LiveManifestTests
/// ```
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class LiveManifestTests: XCTestCase {

    private struct Fixtures {
        let addresses: [String]
        let sizes: [UInt64]
        let dataMap: String
        let dataMapSize: UInt64?
        let link: String?
    }

    private static func fixtures() throws -> Fixtures {
        let vars = ProcessInfo.processInfo.environment
        func list(_ key: String) -> [String] {
            (vars[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let addresses = list("ANTD_TEST_MANIFEST_ADDRESSES")
        guard addresses.count == 2 else {
            throw XCTSkip("set ANTD_TEST_MANIFEST_ADDRESSES to two public data addresses to run")
        }
        let sizes = list("ANTD_TEST_MANIFEST_SIZES").compactMap(UInt64.init)
        guard sizes.count == 2, let dataMap = vars["ANTD_TEST_MANIFEST_DATA_MAP"], !dataMap.isEmpty else {
            throw XCTSkip("set ANTD_TEST_MANIFEST_SIZES and ANTD_TEST_MANIFEST_DATA_MAP to run")
        }
        return Fixtures(
            addresses: addresses,
            sizes: sizes,
            dataMap: dataMap,
            dataMapSize: vars["ANTD_TEST_MANIFEST_DATA_MAP_SIZE"].flatMap { UInt64($0) },
            link: vars["ANTD_TEST_MANIFEST_LINK"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func thrownError(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    func testLiveManifestsOverRest() async throws {
        guard let url = ProcessInfo.processInfo.environment["ANTD_TEST_URL"], !url.isEmpty else {
            throw XCTSkip("set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run")
        }
        try await exercise(AntdRestClient(baseURL: url), fixtures: Self.fixtures())
    }

    func testLiveManifestsOverGrpc() async throws {
        guard var target = ProcessInfo.processInfo.environment["ANTD_TEST_GRPC"], !target.isEmpty else {
            throw XCTSkip("set ANTD_TEST_GRPC and ANTD_TEST_MANIFEST_ADDRESSES to run")
        }
        // AntdGrpcClient takes host:port; accept a URL too.
        for scheme in ["http://", "https://"] where target.hasPrefix(scheme) {
            target = String(target.dropFirst(scheme.count))
        }
        try await exercise(AntdGrpcClient(target: target), fixtures: Self.fixtures())
    }

    /// The same checks over either transport, through the protocol.
    private func exercise(_ client: any AntdClientProtocol, fixtures fx: Fixtures) async throws {
        let paths = ["live/one.txt", "live/two.txt", "live/private.txt"]

        // 1. Build from the two addresses and the DataMap, each with a path.
        let built = try await client.buildManifest(
            entries: [
                ManifestEntryInput(path: paths[0], address: fx.addresses[0]),
                ManifestEntryInput(path: paths[1], address: fx.addresses[1]),
                ManifestEntryInput(path: paths[2], dataMap: fx.dataMap),
            ],
            options: BuildManifestOptions(name: "swift-live")
        )

        // 2. Kinds, effective names (sorted) and a link.
        XCTAssertFalse(built.manifest.isEmpty)
        let link = try XCTUnwrap(built.link, "a three-entry manifest fits in a link")
        XCTAssertTrue(link.hasPrefix("ant://manifest/"), link)
        XCTAssertEqual(built.entries.map(\.effectiveName), paths.sorted())
        let builtKinds = Dictionary(uniqueKeysWithValues: built.entries.map { ($0.effectiveName, $0.kind) })
        XCTAssertEqual(builtKinds, [paths[0]: "public", paths[1]: "public", paths[2]: "embedded"])
        let builtByName = Dictionary(uniqueKeysWithValues: built.entries.map { ($0.effectiveName, $0) })
        XCTAssertEqual(builtByName[paths[0]]?.contentAddress, fx.addresses[0].lowercased())
        XCTAssertNil(builtByName[paths[0]]?.size, "no size was given, so none is recorded")

        // 3. Decode the bytes and the link, resolving: exact sizes match the
        //    fixtures, and the DataMap entry is embedded with its DataMap.
        let fromBytes = try await client.decodeManifest(built.manifest, resolve: true)
        let fromLink = try await client.decodeManifestLink(link, resolve: true)
        for decoded in [fromBytes, fromLink] {
            XCTAssertEqual(decoded.source, "manifest")
            XCTAssertEqual(decoded.name, "swift-live")
            XCTAssertNil(decoded.torrentInfoHashV1)
            XCTAssertNil(decoded.torrentInfoHashV2)
            let byName = Dictionary(uniqueKeysWithValues: decoded.entries.map { ($0.effectiveName, $0) })
            XCTAssertEqual(byName.count, 3)
            for (path, size) in zip(paths, fx.sizes) {
                let entry = try XCTUnwrap(byName[path])
                XCTAssertEqual(entry.kind, "public")
                XCTAssertEqual(entry.exactSize, size, path)
                XCTAssertNil(entry.size, path)
                XCTAssertNil(entry.dataMap, path)
                XCTAssertNil(entry.error, path)
            }
            let embedded = try XCTUnwrap(byName[paths[2]])
            XCTAssertEqual(embedded.kind, "embedded")
            XCTAssertFalse(embedded.dataMap?.isEmpty ?? true, "an embedded entry decodes with its DataMap")
            XCTAssertNil(embedded.error)
            if let size = fx.dataMapSize {
                XCTAssertEqual(embedded.exactSize, size)
            }
        }

        // 4. The fixture link, built elsewhere from the same three entries.
        if let fixtureLink = fx.link {
            let decoded = try await client.decodeManifestLink(fixtureLink, resolve: false)
            XCTAssertEqual(decoded.source, "manifest")
            XCTAssertEqual(decoded.entries.count, 3)
            XCTAssertEqual(decoded.entries.filter { $0.kind == "public" }.map(\.contentAddress).sorted(),
                           fx.addresses.map { $0.lowercased() }.sorted())
            XCTAssertEqual(decoded.entries.filter { $0.kind == "embedded" }.count, 1)
        }

        // 5. Bad entries: both sources is refused before sending; an invalid
        //    path is the daemon's 400 / INVALID_ARGUMENT, naming the entry.
        let both = await Self.thrownError {
            _ = try await client.buildManifest(entries: [ManifestEntryInput(dataMap: fx.dataMap, address: fx.addresses[0])])
        }
        XCTAssertTrue(both is BadRequestError, "got \(String(describing: both))")
        let badPath = await Self.thrownError {
            _ = try await client.buildManifest(entries: [
                ManifestEntryInput(path: "ok.txt", address: fx.addresses[0]),
                ManifestEntryInput(path: "../x", address: fx.addresses[1]),
            ])
        }
        let bad = try XCTUnwrap(badPath as? BadRequestError, "got \(String(describing: badPath))")
        XCTAssertTrue(bad.message.contains("entries[1]"), bad.message)
    }
}
