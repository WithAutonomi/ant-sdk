import XCTest
@testable import AntdSdk

/// Live pointer round trip against a running antd with a devnet behind it.
///
/// Skipped unless all three are set:
///
/// - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
/// - `ANTD_TEST_GRPC`: its gRPC endpoint, e.g. `127.0.0.1:50051`
/// - `ANTD_TEST_POINTER_OWNERS`: two comma-separated pointer addresses the
///   daemon holds keys for (`antd --pointer-keys`) and that have **never been
///   written**. The test creates both, transfers the first to the second, and
///   leaves the second with a prepared write awaiting payment (an hour), so
///   each pair can be used once.
///
/// Every write is paid by the daemon's wallet, so run it against a devnet:
///
/// ```text
/// ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
/// ANTD_TEST_POINTER_OWNERS=<hex>,<hex> swift test --filter LivePointerTests
/// ```
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class LivePointerTests: XCTestCase {

    private struct Env {
        let rest: String
        let grpc: String
        let first: String
        let second: String
    }

    private static func env() -> Env? {
        let vars = ProcessInfo.processInfo.environment
        guard let rest = vars["ANTD_TEST_URL"], !rest.isEmpty,
              let grpc = vars["ANTD_TEST_GRPC"], !grpc.isEmpty,
              let owners = vars["ANTD_TEST_POINTER_OWNERS"]
        else { return nil }
        let pair = owners.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else { return nil }
        // AntdGrpcClient takes host:port; accept a URL too.
        var target = grpc
        for scheme in ["http://", "https://"] where target.hasPrefix(scheme) {
            target = String(target.dropFirst(scheme.count))
        }
        return Env(rest: rest, grpc: target, first: pair[0], second: pair[1])
    }

    /// The daemon accepts a `0x` prefix but always returns bare hex.
    private static func bare(_ address: String) -> String {
        let lower = address.lowercased()
        return lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower
    }

    private static func thrownError(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    func testLivePointerRoundTrip() async throws {
        guard let env = Self.env() else {
            throw XCTSkip("set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run")
        }
        let (a, b) = (Self.bare(env.first), Self.bare(env.second))
        let rest = AntdRestClient(baseURL: env.rest)
        let grpc = AntdGrpcClient(target: env.grpc)

        // Both owners must be writable through this daemon, over both
        // transports.
        let keys = try await rest.pointerKeys().map { Self.bare($0.address) }
        XCTAssertTrue(keys.contains(a) && keys.contains(b), "daemon holds no key for one of the owners: \(keys)")
        let grpcKeys = try await grpc.pointerKeys().map { Self.bare($0.address) }
        XCTAssertEqual(Set(grpcKeys), Set(keys))

        // Real targets, so the chain can be followed back to bytes.
        let payloadOne = Data("antd-swift pointer target one".utf8)
        let payloadTwo = Data("antd-swift pointer target two".utf8)
        let one = try await rest.dataPutPublic(payloadOne, paymentMode: .auto).address
        let two = try await rest.dataPutPublic(payloadTwo, paymentMode: .auto).address

        // ── REST: create, read, update ──
        let unwritten = await Self.thrownError { _ = try await rest.pointerGet(address: a) }
        guard unwritten is NotFoundError else {
            XCTFail("owner \(a) has been written before; use a fresh pair (got \(String(describing: unwritten)))")
            return
        }
        // The 0x prefix is accepted on input.
        var w = try await rest.pointerCreate(owner: "0x" + a, target: one, kind: .chunk)
        XCTAssertEqual(w.counter, 0)
        XCTAssertEqual(Self.bare(w.address), a)
        let again = await Self.thrownError { _ = try await rest.pointerCreate(owner: a, target: two, kind: .chunk) }
        XCTAssertTrue(again is AlreadyExistsError, "got \(String(describing: again))")

        var r = try await rest.pointerGet(address: a)
        XCTAssertEqual(r.counter, 0)
        XCTAssertEqual(r.target, Self.bare(one))
        XCTAssertFalse(r.isFinal)
        XCTAssertNil(r.transferredTo)
        XCTAssertEqual(r.targetKind, .chunk)
        XCTAssertEqual(r.owner.count, 2 * 1952)
        var res = try await rest.pointerResolve(address: a)
        XCTAssertEqual(res.target, Self.bare(one))
        let fetched = try await rest.dataGetPublic(address: res.target)
        XCTAssertEqual(fetched, payloadOne)

        w = try await rest.pointerUpdate(owner: a, target: two, kind: .chunk)
        XCTAssertEqual(w.counter, 1)
        res = try await rest.pointerResolve(address: a)
        XCTAssertEqual(res.target, Self.bare(two))
        var f = try await rest.pointerFinality(address: a)
        XCTAssertEqual(f.status, .open)
        XCTAssertEqual(f.counter, 1)
        XCTAssertEqual(f.answered, f.group)
        XCTAssertNil(f.state)
        XCTAssertNil(f.transferredTo)

        // ── gRPC: a write, then reads ──
        w = try await grpc.pointerCreate(owner: b, target: one, kind: .chunk)
        XCTAssertEqual(w.counter, 0)
        r = try await grpc.pointerGet(address: b)
        XCTAssertEqual(r.counter, 0)
        XCTAssertEqual(r.target, Self.bare(one))
        XCTAssertNil(r.transferredTo)
        f = try await grpc.pointerFinality(address: a)
        XCTAssertEqual(f.status, .open)
        XCTAssertEqual(f.counter, 1)

        // ── transfer a -> b ──
        let t = try await rest.pointerTransfer(owner: a, recipient: b)
        let tf = try XCTUnwrap(t.finality, "the close group should answer after the transfer (\(t.finalityError ?? ""))")
        XCTAssertEqual(tf.status, .final)
        XCTAssertEqual(tf.transferredTo.map(Self.bare), b)
        r = try await rest.pointerGet(address: a)
        XCTAssertTrue(r.isFinal)
        XCTAssertEqual(r.counter, UInt64.max)
        XCTAssertEqual(r.transferredTo.map(Self.bare), b)
        let c = try await rest.pointerController(address: a)
        XCTAssertEqual(Self.bare(c.pointer), b)
        XCTAssertEqual(c.transfers.map(Self.bare), [b])
        XCTAssertFalse(c.frozen)
        // a now resolves through b.
        res = try await grpc.pointerResolve(address: a)
        XCTAssertEqual(res.target, Self.bare(one))
        f = try await grpc.pointerFinality(address: a)
        XCTAssertTrue(f.isFinal)
        r = try await grpc.pointerGet(address: a)
        XCTAssertTrue(r.isFinal)
        XCTAssertEqual(r.counter, UInt64.max)
        let gc = try await grpc.pointerController(address: a)
        XCTAssertEqual(gc.transfers.map(Self.bare), [b])

        // A final pointer refuses every write, before anything is paid.
        var e = await Self.thrownError { _ = try await rest.pointerUpdate(owner: a, target: one, kind: .chunk) }
        XCTAssertTrue(e is PointerFinalError, "REST update: \(String(describing: e))")
        e = await Self.thrownError { _ = try await grpc.pointerUpdate(owner: a, target: one, kind: .chunk) }
        XCTAssertTrue(e is PointerFinalError, "gRPC update: \(String(describing: e))")
        e = await Self.thrownError { _ = try await rest.pointerTransfer(owner: a, recipient: b) }
        XCTAssertTrue(e is PointerFinalError, "REST transfer: \(String(describing: e))")

        // ── external signer, up to the quote ──
        // Last: the prepared write blocks b's other writes until it expires.
        let p = try await rest.pointerPrepare(owner: b, op: .update(target: two, kind: .chunk))
        XCTAssertEqual(p.op, "update")
        XCTAssertEqual(p.counter, 1)
        XCTAssertEqual(p.paymentType, "wave_batch")
        XCTAssertFalse(p.payments.isEmpty)
        XCTAssertFalse(p.uploadId.isEmpty)
        e = await Self.thrownError { _ = try await rest.pointerUpdate(owner: b, target: two, kind: .chunk) }
        XCTAssertTrue(e is ConflictError, "REST update while prepared: \(String(describing: e))")
        e = await Self.thrownError {
            _ = try await grpc.pointerPrepare(
                owner: b,
                op: .update(target: two, kind: .chunk),
                options: PointerPrepareOptions(includeSignedQuotes: true)
            )
        }
        XCTAssertTrue(e is ConflictError, "gRPC prepare while prepared: \(String(describing: e))")
        // A finalize without the payment is refused and keeps the session.
        e = await Self.thrownError { _ = try await rest.pointerFinalize(uploadId: p.uploadId, txHashes: [:]) }
        XCTAssertTrue(e is BadRequestError, "finalize without payment: \(String(describing: e))")
        e = await Self.thrownError { _ = try await grpc.pointerFinalize(uploadId: p.uploadId, txHashes: [:]) }
        XCTAssertTrue(e is BadRequestError, "gRPC finalize without payment: \(String(describing: e))")
        e = await Self.thrownError { _ = try await rest.pointerUpdate(owner: b, target: two, kind: .chunk) }
        XCTAssertTrue(e is ConflictError, "REST update after a refused finalize: \(String(describing: e))")
    }
}
