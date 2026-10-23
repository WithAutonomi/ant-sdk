import XCTest
@testable import AntdSdk

/// Live `sha256` checks against a running antd 0.17.0 or later with a devnet
/// behind it. Read-only apart from ONE small paid public data upload per
/// transport (step 4).
///
/// The REST test is skipped unless `ANTD_TEST_URL` and `ANTD_TEST_SHA_LINK`
/// are set; the gRPC test needs `ANTD_TEST_GRPC` and `ANTD_TEST_SHA_LINK`.
/// The fixtures:
///
/// - `ANTD_TEST_SHA_LINK`: a manifest link with entries `public.txt`
///   (sha256), `private.txt` (sha256) and `nohash.txt` (none)
/// - `ANTD_TEST_SHA_PUBLIC_SHA256`: `public.txt`'s hash
/// - `ANTD_TEST_SHA_DATA_MAP_SHA256`: `private.txt`'s hash
/// - `ANTD_TEST_SHA_PUBLIC_ADDRESS`: the public data's address
///
/// ```text
/// ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \n/// ANTD_TEST_SHA_LINK=<link> ANTD_TEST_SHA_PUBLIC_SHA256=<hex> \n/// ANTD_TEST_SHA_DATA_MAP_SHA256=<hex> ANTD_TEST_SHA_PUBLIC_ADDRESS=<hex> \n/// swift test --filter LiveSha256Tests
/// ```
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class LiveSha256Tests: XCTestCase {

    private struct Fixtures {
        let link: String
        let publicSha256: String
        let dataMapSha256: String
        let publicAddress: String
    }

    private static func fixtures() throws -> Fixtures {
        let vars = ProcessInfo.processInfo.environment
        func value(_ key: String) throws -> String {
            guard let v = vars[key], !v.isEmpty else { throw XCTSkip("set \(key) to run") }
            return v
        }
        return Fixtures(
            link: try value("ANTD_TEST_SHA_LINK"),
            publicSha256: try value("ANTD_TEST_SHA_PUBLIC_SHA256"),
            dataMapSha256: try value("ANTD_TEST_SHA_DATA_MAP_SHA256"),
            publicAddress: try value("ANTD_TEST_SHA_PUBLIC_ADDRESS")
        )
    }

    func testLiveSha256OverRest() async throws {
        guard let url = ProcessInfo.processInfo.environment["ANTD_TEST_URL"], !url.isEmpty else {
            throw XCTSkip("set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run")
        }
        try await exercise(AntdRestClient(baseURL: url), fixtures: Self.fixtures(), transport: "rest")
    }

    func testLiveSha256OverGrpc() async throws {
        guard var target = ProcessInfo.processInfo.environment["ANTD_TEST_GRPC"], !target.isEmpty else {
            throw XCTSkip("set ANTD_TEST_GRPC and ANTD_TEST_SHA_LINK to run")
        }
        // AntdGrpcClient takes host:port; accept a URL too.
        for scheme in ["http://", "https://"] where target.hasPrefix(scheme) {
            target = String(target.dropFirst(scheme.count))
        }
        try await exercise(AntdGrpcClient(target: target), fixtures: Self.fixtures(), transport: "grpc")
    }

    /// The same checks over either transport, through the protocol.
    private func exercise(_ client: any AntdClientProtocol, fixtures fx: Fixtures, transport: String) async throws {
        // 1. Decode the fixture link without resolving: hashes per entry.
        let decoded = try await client.decodeManifestLink(fx.link, resolve: false)
        let byName = Dictionary(uniqueKeysWithValues: decoded.entries.map { ($0.effectiveName, $0) })
        XCTAssertEqual(byName["public.txt"]?.sha256, fx.publicSha256)
        XCTAssertEqual(byName["private.txt"]?.sha256, fx.dataMapSha256)
        let nohash = try XCTUnwrap(byName["nohash.txt"], "nohash.txt is in the fixture manifest")
        XCTAssertNil(nohash.sha256)

        // 2. Build with a hash: the returned entry carries it.
        let built = try await client.buildManifest(entries: [
            ManifestEntryInput(path: "a.txt", address: fx.publicAddress, sha256: fx.publicSha256),
        ])
        XCTAssertEqual(built.entries.count, 1)
        XCTAssertEqual(built.entries[0].sha256, fx.publicSha256)

        // 3. A malformed hash is the daemon's 400 / INVALID_ARGUMENT.
        do {
            _ = try await client.buildManifest(entries: [
                ManifestEntryInput(path: "a.txt", address: fx.publicAddress, sha256: "zz"),
            ])
            XCTFail("expected a BadRequestError")
        } catch let error as BadRequestError {
            XCTAssertEqual(error.statusCode, 400)
            XCTAssertTrue(error.message.contains("sha256"), error.message)
        }

        // 4. One paid call: a small public upload unique to this run. The
        //    returned hash is the SHA-256 of the same bytes computed here.
        let payload = Data("sha-fanout swift \(Int(Date().timeIntervalSince1970)) \(transport)".utf8)
        let put = try await client.dataPutPublic(payload, paymentMode: .auto)
        let expected = Self.sha256Hex(payload)
        print("live sha256 [\(transport)]: local=\(expected) returned=\(put.sha256 ?? "nil")")
        XCTAssertEqual(put.sha256, expected)
    }

    // MARK: - SHA-256 (FIPS 180-4), so the test needs no crypto dependency

    func testSha256HexKnownVectors() {
        XCTAssertEqual(Self.sha256Hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(Self.sha256Hex(Data("hello".utf8)), sha256Hello)
        XCTAssertEqual(
            Self.sha256Hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8((bitLength >> UInt64(shift)) & 0xff)) }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

        for chunk in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(message[j]) << 24 | UInt32(message[j + 1]) << 16 | UInt32(message[j + 2]) << 8 | UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
