import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import AntdSdk

/// In-process mock-server tests for ``AntdGrpcClient``'s pointer surface
/// (`PointerService`). The mock throws the statuses the daemon sends, with the
/// `x-antd-error-code` trailer where the daemon sets it, so the client's
/// trailer-based error mapping is exercised end to end.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class GrpcPointerTests: XCTestCase {

    private func withMockServer<T: Sendable>(
        service: MockPointerService = MockPointerService(),
        _ body: @Sendable (AntdGrpcClient) async throws -> T
    ) async throws -> T {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        return try await withGRPCServer(transport: transport, services: [service]) { _ in
            let listening = try await transport.listeningAddress
            guard let port = listening.ipv4?.port else {
                XCTFail("expected an ipv4 listening address; got \(listening)")
                throw RPCError(code: .internalError, message: "no ipv4 listening address")
            }
            return try await body(AntdGrpcClient(target: "127.0.0.1:\(port)"))
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

    // MARK: - Methods

    func testPointerKeys() async throws {
        try await withMockServer { client in
            let keys = try await client.pointerKeys()
            XCTAssertEqual(keys.map(\.address), [MockPointerService.addrA, MockPointerService.addrB])
        }
    }

    func testPointerCreateForwardsTheRequestAndParsesTheCounter() async throws {
        try await withMockServer { client in
            let w = try await client.pointerCreate(owner: MockPointerService.addrA, target: "t1", kind: .pointer)
            XCTAssertEqual(w.address, MockPointerService.addrA)
            // The mock echoes target and kind into the state id.
            XCTAssertEqual(w.stateId, "create:t1:pointer")
            XCTAssertEqual(w.counter, 0)
        }
    }

    func testPointerUpdateReadsTheFinalCounter() async throws {
        try await withMockServer { client in
            let w = try await client.pointerUpdate(owner: MockPointerService.addrA, target: "t2", kind: .chunk)
            XCTAssertEqual(w.stateId, "update:t2:chunk")
            XCTAssertEqual(w.counter, UInt64.max)
        }
    }

    func testPointerTransferWithFinality() async throws {
        try await withMockServer { client in
            let t = try await client.pointerTransfer(owner: MockPointerService.addrA, recipient: MockPointerService.addrB)
            XCTAssertEqual(t.stateId, "sf")
            XCTAssertNil(t.finalityError)
            let f = try XCTUnwrap(t.finality)
            XCTAssertEqual(f.status, .final)
            XCTAssertTrue(f.isFinal)
            XCTAssertNil(f.counter)
            XCTAssertEqual(f.transferredTo, MockPointerService.addrB)
            XCTAssertEqual(f.state?.holders, 7)
            XCTAssertEqual(f.state?.transferredTo, MockPointerService.addrB)
            XCTAssertNil(f.majority)
        }
    }

    func testPointerTransferWithoutFinalityKeepsTheReason() async throws {
        try await withMockServer { client in
            let t = try await client.pointerTransfer(owner: MockPointerService.addrA, recipient: "no-finality")
            XCTAssertNil(t.finality)
            XCTAssertEqual(t.finalityError, "close group did not answer")
        }
    }

    func testPointerGetMapsEmptyStringsToNil() async throws {
        try await withMockServer { client in
            let finalRecord = try await client.pointerGet(address: MockPointerService.addrA)
            XCTAssertTrue(finalRecord.isFinal)
            XCTAssertEqual(finalRecord.counter, UInt64.max)
            XCTAssertEqual(finalRecord.transferredTo, MockPointerService.addrB)
            XCTAssertEqual(finalRecord.targetKind, .pointer)

            let open = try await client.pointerGet(address: "open")
            XCTAssertFalse(open.isFinal)
            XCTAssertEqual(open.counter, 2)
            XCTAssertNil(open.transferredTo)
            XCTAssertEqual(open.kindTag, .max, "a tag past UInt8 reads as UInt8.max")
            XCTAssertNil(open.targetKind)
        }
    }

    func testPointerGetRejectsAMalformedCounter() async throws {
        try await withMockServer { client in
            let error = await Self.thrownError { _ = try await client.pointerGet(address: "bad-counter") }
            XCTAssertTrue(error is InternalError, "got \(String(describing: error))")
        }
    }

    func testPointerResolve() async throws {
        try await withMockServer { client in
            let t = try await client.pointerResolve(address: MockPointerService.addrA)
            XCTAssertEqual(t, PointerTarget(kind: "chunk", kindTag: 0, target: "t1"))
        }
    }

    func testPointerFinalityOpenForkedAndUnknown() async throws {
        try await withMockServer { client in
            let open = try await client.pointerFinality(address: "open")
            XCTAssertEqual(open.status, .open)
            XCTAssertEqual(open.counter, 4)
            XCTAssertNil(open.state)
            XCTAssertNil(open.majority)
            XCTAssertNil(open.transferredTo)
            XCTAssertEqual(open.group, 7)
            XCTAssertEqual(open.answered, 6)

            let forked = try await client.pointerFinality(address: "forked")
            XCTAssertEqual(forked.status, .forked)
            XCTAssertNil(forked.counter)
            XCTAssertEqual(forked.states.map(\.stateId), ["x", "y"])
            XCTAssertEqual(forked.majority?.stateId, "x")

            let unknown = try await client.pointerFinality(address: "unknown")
            XCTAssertEqual(unknown.status, .unknown("contested"))
        }
    }

    func testPointerController() async throws {
        try await withMockServer { client in
            let c = try await client.pointerController(address: MockPointerService.addrA)
            XCTAssertEqual(c, PointerController(pointer: MockPointerService.addrB, transfers: [MockPointerService.addrB], frozen: false))
        }
    }

    func testPointerPrepareCreateAndTransferWithSignedQuotes() async throws {
        try await withMockServer { client in
            let p = try await client.pointerPrepare(owner: MockPointerService.addrA, op: .create(target: "t1"))
            XCTAssertEqual(p.op, "create")
            XCTAssertEqual(p.uploadId, "up:create:t1:chunk::false")
            XCTAssertEqual(p.counter, 0)
            XCTAssertEqual(p.paymentType, "wave_batch")
            XCTAssertEqual(p.payments, [PaymentInfo(quoteHash: "0xq", rewardsAddress: "0xr", amount: "7")])
            XCTAssertEqual(p.rpcUrl, "http://rpc")
            XCTAssertEqual(p.signedQuotes, [])

            let t = try await client.pointerPrepare(
                owner: MockPointerService.addrA,
                op: .transfer(recipient: MockPointerService.addrB),
                options: PointerPrepareOptions(includeSignedQuotes: true)
            )
            XCTAssertEqual(t.uploadId, "up:transfer:::\(MockPointerService.addrB):true")
            XCTAssertEqual(t.counter, UInt64.max)
            // Bytes over gRPC, base64 in the model, as over REST.
            XCTAssertEqual(t.signedQuotes, [
                SignedQuoteEntry(quoteHash: "0xq", quote: Data("quote".utf8).base64EncodedString(), commitmentSidecar: nil),
            ])
        }
    }

    func testPointerFinalize() async throws {
        try await withMockServer { client in
            let f = try await client.pointerFinalize(uploadId: "up1", txHashes: ["0xq": "0xtx", "0xq2": "0xtx"])
            XCTAssertEqual(f.stateId, "finalized:up1:2")
            XCTAssertEqual(f.counter, 1)
            XCTAssertNil(f.finality)
        }
    }

    // MARK: - Errors from the x-antd-error-code trailer

    func testTaggedStatusesMapToTheTypedErrors() async throws {
        try await withMockServer { client in
            let finalError = await Self.thrownError {
                _ = try await client.pointerUpdate(owner: "final", target: "t", kind: .chunk)
            }
            XCTAssertTrue(finalError is PointerFinalError, "got \(String(describing: finalError))")
            XCTAssertEqual((finalError as? AntdError)?.message, "Pointer is final: handed over")

            let forked = await Self.thrownError {
                _ = try await client.pointerUpdate(owner: "forked", target: "t", kind: .chunk)
            }
            XCTAssertTrue(forked is PointerForkedError, "got \(String(describing: forked))")

            let conflict = await Self.thrownError {
                _ = try await client.pointerUpdate(owner: "conflict", target: "t", kind: .chunk)
            }
            XCTAssertTrue(conflict is ConflictError, "got \(String(describing: conflict))")

            let exists = await Self.thrownError {
                _ = try await client.pointerCreate(owner: "exists", target: "t", kind: .chunk)
            }
            XCTAssertTrue(exists is AlreadyExistsError, "got \(String(describing: exists))")
        }
    }

    func testUntaggedOrMismatchedStatusesKeepTheCodeMapping() async throws {
        try await withMockServer { client in
            let untagged = await Self.thrownError {
                _ = try await client.pointerUpdate(owner: "untagged", target: "t", kind: .chunk)
            }
            XCTAssertTrue(untagged is PaymentError, "got \(String(describing: untagged))")

            let mismatched = await Self.thrownError {
                _ = try await client.pointerUpdate(owner: "mismatched", target: "t", kind: .chunk)
            }
            XCTAssertTrue(mismatched is ForkError, "got \(String(describing: mismatched))")
            XCTAssertFalse(mismatched is PointerFinalError)
        }
    }

    func testShortfallRetryableComesFromTheClosingHint() async throws {
        let service = MockPointerService()
        try await withMockServer(service: service) { client in
            let retained = await Self.thrownError {
                _ = try await client.pointerFinalize(uploadId: "short-retained", txHashes: [:])
            }
            XCTAssertEqual((retained as? CloseGroupShortfallError)?.retryable, true, "got \(String(describing: retained))")

            let read = await Self.thrownError {
                _ = try await client.pointerFinalize(uploadId: "short", txHashes: [:])
            }
            XCTAssertEqual((read as? CloseGroupShortfallError)?.retryable, false, "got \(String(describing: read))")
        }
        XCTAssertEqual(service.calls("finalize"), 2, "each failed finalize reached the daemon once")
    }

    /// A paid write that fails is surfaced, not retried.
    func testAFailedPaidWriteIsSentExactlyOnce() async throws {
        let service = MockPointerService()
        try await withMockServer(service: service) { client in
            let error = await Self.thrownError {
                _ = try await client.pointerCreate(owner: "short", target: "t", kind: .chunk)
            }
            XCTAssertTrue(error is CloseGroupShortfallError, "got \(String(describing: error))")
        }
        XCTAssertEqual(service.calls("create"), 1)
    }
}

// MARK: - Mock PointerService

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class MockPointerService: Antd_V1_PointerService.SimpleServiceProtocol, @unchecked Sendable {
    static let addrA = String(repeating: "a", count: 64)
    static let addrB = String(repeating: "b", count: 64)
    static let maxCounter = "18446744073709551615"

    private let lock = NSLock()
    private var callCounts: [String: Int] = [:]

    func calls(_ method: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCounts[method] ?? 0
    }

    private func record(_ method: String) {
        lock.lock()
        callCounts[method, default: 0] += 1
        lock.unlock()
    }

    /// The status the daemon sends for an error that shares a gRPC code with
    /// older ones: the antd code rides in the `x-antd-error-code` trailer.
    private func tagged(_ code: RPCError.Code, _ message: String, _ antdCode: String) -> RPCError {
        var metadata = Metadata()
        metadata.addString(antdCode, forKey: "x-antd-error-code")
        return RPCError(code: code, message: message, metadata: metadata)
    }

    /// Errors keyed by the owner a write names.
    private func writeError(owner: String) -> RPCError? {
        switch owner {
        case "final": return tagged(.failedPrecondition, "Pointer is final: handed over", "POINTER_FINAL")
        case "forked": return tagged(.failedPrecondition, "Pointer is forked: two finals", "POINTER_FORKED")
        case "conflict": return tagged(.aborted, "Conflict: a prepared write awaits payment", "CONFLICT")
        case "short": return tagged(.unavailable, "Close group shortfall: stored on 3 of 7", "CLOSE_GROUP_SHORTFALL")
        case "exists": return RPCError(code: .alreadyExists, message: "Already exists: pointer")
        case "untagged": return RPCError(code: .failedPrecondition, message: "Payment error: insufficient funds")
        // A tag that disagrees with the status code is not trusted.
        case "mismatched": return tagged(.aborted, "conflicting update", "POINTER_FINAL")
        default: return nil
        }
    }

    private func finalState(_ id: String, holders: UInt32, transferredTo: String = "") -> Antd_V1_PointerFinalState {
        var s = Antd_V1_PointerFinalState()
        s.stateID = id
        s.kind = "pointer"
        s.kindTag = 1
        s.target = Self.addrB
        s.holders = holders
        s.transferredTo = transferredTo
        return s
    }

    func listKeys(request: Antd_V1_ListPointerKeysRequest, context: ServerContext) async throws -> Antd_V1_ListPointerKeysResponse {
        record("listKeys")
        var r = Antd_V1_ListPointerKeysResponse()
        r.keys = [Self.addrA, Self.addrB].map {
            var k = Antd_V1_PointerKey()
            k.address = $0
            return k
        }
        return r
    }

    func create(request: Antd_V1_PointerWriteRequest, context: ServerContext) async throws -> Antd_V1_PointerWriteResponse {
        record("create")
        if let e = writeError(owner: request.owner) { throw e }
        var r = Antd_V1_PointerWriteResponse()
        r.address = request.owner
        r.stateID = "create:\(request.target):\(request.kind)"
        r.counter = "0"
        return r
    }

    func update(request: Antd_V1_PointerWriteRequest, context: ServerContext) async throws -> Antd_V1_PointerWriteResponse {
        record("update")
        if let e = writeError(owner: request.owner) { throw e }
        var r = Antd_V1_PointerWriteResponse()
        r.address = request.owner
        r.stateID = "update:\(request.target):\(request.kind)"
        r.counter = Self.maxCounter
        return r
    }

    func transfer(request: Antd_V1_PointerTransferRequest, context: ServerContext) async throws -> Antd_V1_PointerTransferResponse {
        record("transfer")
        if let e = writeError(owner: request.owner) { throw e }
        var r = Antd_V1_PointerTransferResponse()
        r.address = request.owner
        r.stateID = "sf"
        if request.recipient == "no-finality" {
            r.finalityError = "close group did not answer"
        } else {
            var f = Antd_V1_PointerFinality()
            f.address = request.owner
            f.group = 7
            f.answered = 7
            f.status = "final"
            f.state = finalState("sf", holders: 7, transferredTo: request.recipient)
            f.transferredTo = request.recipient
            r.finality = f
        }
        return r
    }

    func get(request: Antd_V1_GetPointerRequest, context: ServerContext) async throws -> Antd_V1_PointerRecord {
        record("get")
        var r = Antd_V1_PointerRecord()
        r.address = request.address
        r.owner = "00"
        r.target = "t1"
        r.stateID = "s"
        switch request.address {
        case "open":
            r.counter = "2"
            r.kind = "unknown"
            r.kindTag = 300
        case "bad-counter":
            r.counter = "-1"
        default:
            r.counter = Self.maxCounter
            r.kind = "pointer"
            r.kindTag = 1
            r.isFinal = true
            r.transferredTo = Self.addrB
        }
        return r
    }

    func resolve(request: Antd_V1_ResolvePointerRequest, context: ServerContext) async throws -> Antd_V1_PointerResolved {
        record("resolve")
        var r = Antd_V1_PointerResolved()
        r.kind = "chunk"
        r.kindTag = 0
        r.target = "t1"
        return r
    }

    func finality(request: Antd_V1_PointerFinalityRequest, context: ServerContext) async throws -> Antd_V1_PointerFinality {
        record("finality")
        var f = Antd_V1_PointerFinality()
        f.address = request.address
        f.group = 7
        f.answered = 6
        switch request.address {
        case "open":
            f.status = "open"
            f.counter = "4"
        case "forked":
            f.status = "forked"
            f.states = [finalState("x", holders: 4), finalState("y", holders: 2)]
            f.majority = finalState("x", holders: 4)
        default:
            f.status = "contested"
        }
        return f
    }

    func controller(request: Antd_V1_PointerControllerRequest, context: ServerContext) async throws -> Antd_V1_PointerController {
        record("controller")
        var c = Antd_V1_PointerController()
        c.pointer = Self.addrB
        c.transfers = [Self.addrB]
        c.frozen = false
        return c
    }

    func prepare(request: Antd_V1_PreparePointerRequest, context: ServerContext) async throws -> Antd_V1_PreparePointerResponse {
        record("prepare")
        if let e = writeError(owner: request.owner) { throw e }
        var p = Antd_V1_PreparePointerResponse()
        p.uploadID = "up:\(request.op):\(request.target):\(request.kind):\(request.recipient):\(request.includeSignedQuotes)"
        p.op = request.op
        p.address = request.owner
        p.stateID = "s"
        p.counter = request.op == "transfer" ? Self.maxCounter : "0"
        p.paymentType = "wave_batch"
        var pay = Antd_V1_PaymentEntry()
        pay.quoteHash = "0xq"
        pay.rewardsAddress = "0xr"
        pay.amount = "7"
        p.payments = [pay]
        p.totalAmount = "7"
        p.paymentVaultAddress = "0xv"
        p.paymentTokenAddress = "0xt"
        p.rpcURL = "http://rpc"
        if request.includeSignedQuotes {
            var q = Antd_V1_SignedQuoteEntry()
            q.quoteHash = "0xq"
            q.quote = Data("quote".utf8)
            p.signedQuotes = [q]
        }
        return p
    }

    func finalize(request: Antd_V1_FinalizePointerRequest, context: ServerContext) async throws -> Antd_V1_FinalizePointerResponse {
        record("finalize")
        switch request.uploadID {
        case "short-retained":
            throw tagged(
                .unavailable,
                "Close group shortfall: stored on 4 of 7 (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)",
                "CLOSE_GROUP_SHORTFALL"
            )
        case "short":
            throw tagged(.unavailable, "Close group shortfall: only 3 answered", "CLOSE_GROUP_SHORTFALL")
        default:
            var f = Antd_V1_FinalizePointerResponse()
            f.address = Self.addrA
            f.stateID = "finalized:\(request.uploadID):\(request.txHashes.count)"
            f.counter = "1"
            return f
        }
    }
}
