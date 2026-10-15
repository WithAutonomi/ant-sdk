import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import AntdSdk

/// In-process mock-server tests for ``AntdGrpcClient``'s manifest surface
/// (`ManifestService`): proto3 presence both ways, raw bytes, the
/// both-or-neither check, INVALID_ARGUMENT mapping, and the raised message
/// limits with a manifest past grpc-swift's 4 MiB default.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class GrpcManifestTests: XCTestCase {

    /// Past grpc-swift's default 4 MiB limit, well under the SDK's 256 MiB.
    static let bigManifestSize = 5 * 1024 * 1024

    /// The server accepts requests up to 16 MiB (its own default is also
    /// 4 MiB), so a big Decode request reaches the mock.
    private func withMockServer<T: Sendable>(
        service: MockManifestService = MockManifestService(),
        _ body: @Sendable (AntdGrpcClient, Int) async throws -> T
    ) async throws -> T {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext,
            config: .defaults { $0.rpc.maxRequestPayloadSize = 16 * 1024 * 1024 }
        )
        return try await withGRPCServer(transport: transport, services: [service]) { _ in
            let listening = try await transport.listeningAddress
            guard let port = listening.ipv4?.port else {
                XCTFail("expected an ipv4 listening address; got \(listening)")
                throw RPCError(code: .internalError, message: "no ipv4 listening address")
            }
            return try await body(AntdGrpcClient(target: "127.0.0.1:\(port)"), port)
        }
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

    func testBuildSetsPresenceAndReadsUnsetSizesAsNil() async throws {
        let service = MockManifestService()
        try await withMockServer(service: service) { client, _ in
            let built = try await client.buildManifest(
                entries: [
                    ManifestEntryInput(path: "a.txt", size: 10, dataMap: "abcd"),
                    ManifestEntryInput(address: "11"),
                ],
                options: BuildManifestOptions(name: "album")
            )
            XCTAssertEqual(built.manifest, manifestHeader, "gRPC carries the raw bytes")
            XCTAssertEqual(built.link, "ant://manifest/wUFOVAE")
            XCTAssertEqual(built.entries.count, 2)
            XCTAssertEqual(built.entries[0].size, 10)
            XCTAssertEqual(built.entries[0].exactSize, 10)
            XCTAssertEqual(built.entries[0].path, "a.txt")
            XCTAssertNil(built.entries[0].dataMap, "an empty data_map reads as nil")
            XCTAssertNil(built.entries[1].size, "an absent optional size reads as nil, not 0")
            XCTAssertNil(built.entries[1].exactSize, "an absent optional exact_size reads as nil, not 0")
            XCTAssertNil(built.entries[1].path)
            XCTAssertNil(built.entries[1].error)
        }
        let req = try XCTUnwrap(service.lastBuild)
        XCTAssertTrue(req.hasName)
        XCTAssertEqual(req.name, "album")
        XCTAssertTrue(req.hasEmbedRoots, "embed_roots is always sent")
        XCTAssertTrue(req.embedRoots, "and defaults to true")
        XCTAssertEqual(req.entries.count, 2)
        let (first, second) = (req.entries[0], req.entries[1])
        XCTAssertTrue(first.hasPath)
        XCTAssertEqual(first.path, "a.txt")
        XCTAssertTrue(first.hasSize)
        XCTAssertEqual(first.size, 10)
        XCTAssertEqual(first.source, .dataMap("abcd"))
        XCTAssertFalse(second.hasPath, "an unset path keeps no presence")
        XCTAssertFalse(second.hasSize, "an unset size keeps no presence, not 0")
        XCTAssertEqual(second.source, .address("11"))
    }

    func testBuildSendsEmbedRootsFalseAndLeavesAnEmptyNameUnset() async throws {
        let service = MockManifestService()
        try await withMockServer(service: service) { client, _ in
            _ = try await client.buildManifest(
                entries: [ManifestEntryInput(path: "", size: 0, address: "11")],
                options: BuildManifestOptions(name: "", torrentInfoHashes: ["aa"], embedRoots: false)
            )
        }
        let req = try XCTUnwrap(service.lastBuild)
        XCTAssertFalse(req.hasName)
        XCTAssertTrue(req.hasEmbedRoots)
        XCTAssertFalse(req.embedRoots)
        XCTAssertEqual(req.torrentInfoHashes, ["aa"])
        XCTAssertFalse(req.entries[0].hasPath, "an empty path is not sent")
        XCTAssertTrue(req.entries[0].hasSize, "a size of 0 is a size, so it is sent")
        XCTAssertEqual(req.entries[0].size, 0)
    }

    func testBuildRejectsBothOrNeitherBeforeSending() async throws {
        let service = MockManifestService()
        try await withMockServer(service: service) { client, _ in
            for entries in [[ManifestEntryInput()], [ManifestEntryInput(dataMap: "aa", address: "bb")]] {
                let error = await Self.thrownError { _ = try await client.buildManifest(entries: entries) }
                let bad = try XCTUnwrap(error as? BadRequestError, "got \(String(describing: error))")
                XCTAssertTrue(bad.message.contains("entries[0]"), bad.message)
            }
        }
        XCTAssertEqual(service.calls("build"), 0, "nothing may be sent")
    }

    func testInvalidArgumentMapsToBadRequestAndKeepsTheMessage() async throws {
        try await withMockServer { client, _ in
            let error = await Self.thrownError {
                _ = try await client.buildManifest(entries: [ManifestEntryInput(path: "../x", address: "11")])
            }
            let bad = try XCTUnwrap(error as? BadRequestError, "got \(String(describing: error))")
            XCTAssertTrue(bad.message.contains("entries[0]: invalid path"), bad.message)
        }
    }

    // MARK: - Decode

    func testDecodeBytesAndLink() async throws {
        let service = MockManifestService()
        try await withMockServer(service: service) { client, _ in
            let fromBytes = try await client.decodeManifest(manifestHeader, resolve: true)
            XCTAssertEqual(fromBytes.source, "manifest")
            XCTAssertEqual(fromBytes.name, "bytes:5")
            XCTAssertEqual(fromBytes.torrentInfoHashV1, "resolved")
            XCTAssertNil(fromBytes.torrentInfoHashV2, "an empty hash reads as nil")
            let embedded = try XCTUnwrap(fromBytes.entries.first)
            XCTAssertEqual(embedded.dataMap, "abcd")
            XCTAssertEqual(embedded.exactSize, UInt64(UInt32.max) + 1, "sizes are UInt64")
            XCTAssertNil(embedded.size)
            XCTAssertEqual(fromBytes.entries.last?.error, "Record not found: gone")
            XCTAssertNil(fromBytes.entries.last?.exactSize)

            let addr = String(repeating: "42", count: 31) + "aa"
            let fromLink = try await client.decodeManifestLink(addr, resolve: false)
            XCTAssertEqual(fromLink.source, "file_link")
            XCTAssertNil(fromLink.name, "an unset optional name reads as nil")
            XCTAssertNil(fromLink.torrentInfoHashV1)
            XCTAssertEqual(fromLink.entries.map(\.contentAddress), [addr])
            XCTAssertNil(fromLink.entries[0].path)
        }
        XCTAssertEqual(service.lastDecode?.link, String(repeating: "42", count: 31) + "aa")
        XCTAssertEqual(service.lastDecode?.resolve, false)
        XCTAssertEqual(service.calls("decode"), 2)
    }

    func testDecodeRefusesEmptyInputBeforeSending() async throws {
        let service = MockManifestService()
        try await withMockServer(service: service) { client, _ in
            let empty = await Self.thrownError { _ = try await client.decodeManifest(Data(), resolve: false) }
            XCTAssertTrue(empty is BadRequestError, "got \(String(describing: empty))")
            let noLink = await Self.thrownError { _ = try await client.decodeManifestLink("", resolve: true) }
            XCTAssertTrue(noLink is BadRequestError, "got \(String(describing: noLink))")
        }
        XCTAssertEqual(service.calls("decode"), 0, "nothing may be sent")
    }

    // MARK: - Message limits

    /// Inspection: every manifest call carries both limits at 256 MiB, well
    /// past a 64 MiB manifest.
    func testManifestCallOptionsRaiseBothMessageLimits() {
        let options = AntdGrpcClient.manifestCallOptions
        XCTAssertEqual(AntdGrpcClient.maxManifestMessageBytes, 256 * 1024 * 1024)
        XCTAssertEqual(options.maxRequestMessageBytes, AntdGrpcClient.maxManifestMessageBytes)
        XCTAssertEqual(options.maxResponseMessageBytes, AntdGrpcClient.maxManifestMessageBytes)
        XCTAssertGreaterThan(AntdGrpcClient.maxManifestMessageBytes, 64 * 1024 * 1024)
    }

    /// A 5 MiB manifest (past grpc-swift's 4 MiB default) comes back from
    /// Build and goes out with Decode. The control call makes the same Build
    /// request with default call options and fails on the 4 MiB payload
    /// limit (grpc-swift reports it as INTERNAL wrapping RESOURCE_EXHAUSTED,
    /// which the SDK would surface as an InternalError), so it is the SDK's
    /// options that let the manifest through.
    func testAManifestPastTheDefaultLimitGoesBothWays() async throws {
        let size = Self.bigManifestSize
        try await withMockServer { client, port in
            let built = try await client.buildManifest(
                entries: [ManifestEntryInput(address: "11")],
                options: BuildManifestOptions(name: "big")
            )
            XCTAssertEqual(built.manifest.count, size)

            let decoded = try await client.decodeManifest(built.manifest, resolve: false)
            XCTAssertEqual(decoded.name, "bytes:\(size)")

            let control = await Self.thrownError {
                let transport = try HTTP2ClientTransport.Posix(
                    target: .dns(host: "127.0.0.1", port: port),
                    transportSecurity: .plaintext
                )
                try await withGRPCClient(transport: transport) { raw in
                    var req = Antd_V1_BuildManifestRequest()
                    req.name = "big"
                    var entry = Antd_V1_ManifestEntryInput()
                    entry.address = "11"
                    req.entries = [entry]
                    _ = try await Antd_V1_ManifestService.Client(wrapping: raw).build(req)
                }
            }
            let rpc = try XCTUnwrap(control as? RPCError, "got \(String(describing: control))")
            XCTAssertTrue(rpc.message.contains("exceeded the configured maximum payload size"), rpc.message)
        }
    }

    // MARK: - Protocol dispatch

    /// The gRPC client implements every manifest requirement itself: called
    /// through the protocol, none of them falls through to the throwing
    /// default, and each reaches the server.
    func testEveryManifestMethodDispatchesThroughTheProtocol() async throws {
        let service = MockManifestService()
        try await withMockServer(service: service) { grpc, _ in
            let client: any AntdClientProtocol = grpc
            let entries = [ManifestEntryInput(path: "a.txt", size: 10, dataMap: "abcd"), ManifestEntryInput(address: "11")]
            let built = try await client.buildManifest(entries: entries, options: BuildManifestOptions(name: "album"))
            XCTAssertEqual(built.manifest, manifestHeader)
            let builtDefault = try await client.buildManifest(entries: entries)
            XCTAssertEqual(builtDefault.entries.count, 2)
            let decoded = try await client.decodeManifest(manifestHeader, resolve: false)
            XCTAssertEqual(decoded.source, "manifest")
            let decodedLink = try await client.decodeManifestLink("ab", resolve: false)
            XCTAssertEqual(decodedLink.source, "file_link")
        }
        XCTAssertEqual(service.calls("build"), 2)
        XCTAssertEqual(service.calls("decode"), 2)
    }
}

// MARK: - Mock ManifestService

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class MockManifestService: Antd_V1_ManifestService.SimpleServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var callCounts: [String: Int] = [:]
    private var builds: [Antd_V1_BuildManifestRequest] = []
    private var decodes: [Antd_V1_DecodeManifestRequest] = []

    func calls(_ method: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCounts[method] ?? 0
    }

    var lastBuild: Antd_V1_BuildManifestRequest? {
        lock.lock()
        defer { lock.unlock() }
        return builds.last
    }

    var lastDecode: Antd_V1_DecodeManifestRequest? {
        lock.lock()
        defer { lock.unlock() }
        return decodes.last
    }

    private func record(build: Antd_V1_BuildManifestRequest? = nil, decode: Antd_V1_DecodeManifestRequest? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let build {
            callCounts["build", default: 0] += 1
            builds.append(build)
        }
        if let decode {
            callCounts["decode", default: 0] += 1
            decodes.append(decode)
        }
    }

    func build(request: Antd_V1_BuildManifestRequest, context: ServerContext) async throws -> Antd_V1_BuildManifestResponse {
        record(build: request)

        // The daemon's refusal of a bad entry, named by index.
        for (i, entry) in request.entries.enumerated() where entry.path == "../x" {
            throw RPCError(code: .invalidArgument, message: "entries[\(i)]: invalid path \"../x\": parent components are not allowed")
        }
        var resp = Antd_V1_BuildManifestResponse()
        if request.name == "big" {
            resp.manifest = Data(repeating: 0xA5, count: GrpcManifestTests.bigManifestSize)
            return resp
        }
        resp.manifest = manifestHeader
        resp.link = "ant://manifest/wUFOVAE"
        var embedded = Antd_V1_ManifestEntryInfo()
        embedded.effectiveName = "a.txt"
        embedded.path = "a.txt"
        embedded.size = 10
        embedded.kind = "embedded"
        embedded.contentAddress = "cc"
        embedded.exactSize = 10
        var pub = Antd_V1_ManifestEntryInfo()
        pub.effectiveName = "11"
        pub.kind = "public"
        pub.contentAddress = "11"
        resp.entries = [embedded, pub]
        return resp
    }

    func decode(request: Antd_V1_DecodeManifestRequest, context: ServerContext) async throws -> Antd_V1_DecodeManifestResponse {
        record(decode: request)

        var resp = Antd_V1_DecodeManifestResponse()
        switch request.input {
        case .manifest(let bytes):
            resp.source = "manifest"
            resp.name = "bytes:\(bytes.count)"
            var embedded = Antd_V1_ManifestEntryInfo()
            embedded.effectiveName = "a.txt"
            embedded.path = "a.txt"
            embedded.kind = "embedded"
            embedded.contentAddress = "cc"
            embedded.dataMap = "abcd"
            embedded.exactSize = UInt64(UInt32.max) + 1
            var failed = Antd_V1_ManifestEntryInfo()
            failed.effectiveName = "b"
            failed.path = "b"
            failed.kind = "public"
            failed.contentAddress = "dd"
            failed.error = "Record not found: gone"
            resp.entries = [embedded, failed]
        case .link(let link):
            resp.source = "file_link"
            var entry = Antd_V1_ManifestEntryInfo()
            entry.effectiveName = link
            entry.kind = "public"
            entry.contentAddress = link
            resp.entries = [entry]
        case nil:
            throw RPCError(code: .invalidArgument, message: "needs a manifest (.ant bytes) or a link")
        }
        if request.resolve {
            resp.torrentInfoHashV1 = "resolved"
        }
        return resp
    }
}
