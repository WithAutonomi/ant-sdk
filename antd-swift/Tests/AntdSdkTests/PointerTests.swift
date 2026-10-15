import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AntdSdk

/// Pointer API over REST against a stubbed `URLSession` (``StubURLProtocol``),
/// plus the model parsing and error mapping both transports share.
final class PointerRestTests: XCTestCase {

    private let addrA = String(repeating: "a", count: 64)
    private let addrB = String(repeating: "b", count: 64)
    private let target1 = String(repeating: "1", count: 64)
    private let target2 = String(repeating: "2", count: 64)
    private let maxCounter = "18446744073709551615"

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

    private func requestBody(_ path: String) -> [String: Any] {
        guard let data = StubURLProtocol.lastBodies[path], !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func finalityJSON(status: String, counter: Any = NSNull(), transferredTo: Any = NSNull()) -> [String: Any] {
        [
            "address": addrA,
            "group": 7,
            "answered": 7,
            "status": status,
            "counter": counter,
            "state": NSNull(),
            "states": [] as [Any],
            "majority": NSNull(),
            "transferred_to": transferredTo,
        ]
    }

    /// Runs `body` and returns the error it threw, failing if it did not.
    private func thrownError(
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Error? {
        do {
            try await body()
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Methods

    func testPointerKeysIsAGetAndListsAddresses() async throws {
        StubURLProtocol.routes["/v1/pointers/keys"] = jsonBody([
            "keys": [["address": addrA], ["address": addrB]],
        ])
        let keys = try await makeClient().pointerKeys()
        XCTAssertEqual(keys, [PointerKey(address: addrA), PointerKey(address: addrB)])
        XCTAssertEqual(StubURLProtocol.lastMethods["/v1/pointers/keys"], "GET")
    }

    func testPointerCreateSendsOwnerTargetKindAndParsesCounter() async throws {
        StubURLProtocol.routes["/v1/pointers"] = jsonBody([
            "address": addrA, "state_id": "s0", "counter": "0",
        ])
        let w = try await makeClient().pointerCreate(owner: addrA, target: target1, kind: .chunk)
        XCTAssertEqual(w, PointerWriteResult(address: addrA, stateId: "s0", counter: 0))

        XCTAssertEqual(StubURLProtocol.lastMethods["/v1/pointers"], "POST")
        let req = requestBody("/v1/pointers")
        XCTAssertEqual(req["owner"] as? String, addrA)
        XCTAssertEqual(req["target"] as? String, target1)
        XCTAssertEqual(req["kind"] as? String, "chunk")
    }

    func testPointerUpdateForwardsPointerKindAndReadsTheFinalCounter() async throws {
        StubURLProtocol.routes["/v1/pointers/update"] = jsonBody([
            "address": addrA, "state_id": "s1", "counter": maxCounter,
        ])
        let w = try await makeClient().pointerUpdate(owner: addrA, target: addrB, kind: .pointer)
        XCTAssertEqual(w.counter, UInt64.max)
        XCTAssertEqual(w.counter, PointerRecord.finalCounter)
        XCTAssertEqual(requestBody("/v1/pointers/update")["kind"] as? String, "pointer")
    }

    func testPointerCreateDefaultsToChunkKind() async throws {
        StubURLProtocol.routes["/v1/pointers"] = jsonBody([
            "address": addrA, "state_id": "s0", "counter": "0",
        ])
        _ = try await makeClient().pointerCreate(owner: addrA, target: target1)
        XCTAssertEqual(requestBody("/v1/pointers")["kind"] as? String, "chunk")
    }

    func testPointerTransferParsesTheCloseGroupFinality() async throws {
        var finality = finalityJSON(status: "final", transferredTo: addrB)
        finality["state"] = [
            "state_id": "sf", "kind": "pointer", "kind_tag": 1, "target": addrB,
            "holders": 7, "transferred_to": addrB,
        ]
        StubURLProtocol.routes["/v1/pointers/transfer"] = jsonBody([
            "address": addrA, "state_id": "sf", "finality": finality,
        ])
        let t = try await makeClient().pointerTransfer(owner: addrA, recipient: addrB)

        let req = requestBody("/v1/pointers/transfer")
        XCTAssertEqual(req["owner"] as? String, addrA)
        XCTAssertEqual(req["recipient"] as? String, addrB)
        XCTAssertEqual(t.address, addrA)
        XCTAssertEqual(t.stateId, "sf")
        XCTAssertNil(t.finalityError)
        let f = try XCTUnwrap(t.finality)
        XCTAssertEqual(f.status, .final)
        XCTAssertTrue(f.isFinal)
        XCTAssertNil(f.counter)
        XCTAssertEqual(f.transferredTo, addrB)
        XCTAssertEqual(
            f.state,
            PointerFinalState(stateId: "sf", kind: "pointer", kindTag: 1, target: addrB, holders: 7, transferredTo: addrB)
        )
        XCTAssertNil(f.majority)
        XCTAssertEqual(f.states, [])
    }

    func testPointerTransferWithoutFinalityKeepsTheReason() async throws {
        StubURLProtocol.routes["/v1/pointers/transfer"] = jsonBody([
            "address": addrA, "state_id": "sf", "finality": NSNull(),
            "finality_error": "close group did not answer",
        ])
        let t = try await makeClient().pointerTransfer(owner: addrA, recipient: addrB)
        XCTAssertNil(t.finality)
        XCTAssertEqual(t.finalityError, "close group did not answer")
    }

    func testPointerGetReadsIsFinalAndTransferredTo() async throws {
        StubURLProtocol.routes["/v1/pointers/\(addrA)"] = jsonBody([
            "address": addrA,
            "owner": String(repeating: "c", count: 3904),
            "counter": maxCounter,
            "kind": "pointer",
            "kind_tag": 1,
            "target": addrB,
            "state_id": "sf",
            "is_final": true,
            "transferred_to": addrB,
        ])
        let r = try await makeClient().pointerGet(address: addrA)
        XCTAssertEqual(StubURLProtocol.lastMethods["/v1/pointers/\(addrA)"], "GET")
        XCTAssertEqual(r.counter, UInt64.max)
        XCTAssertTrue(r.isFinal)
        XCTAssertEqual(r.transferredTo, addrB)
        XCTAssertEqual(r.kind, "pointer")
        XCTAssertEqual(r.kindTag, 1)
        XCTAssertEqual(r.targetKind, .pointer)
        XCTAssertEqual(r.owner.count, 3904)
        XCTAssertEqual(r.stateId, "sf")
    }

    func testPointerGetOpenRecordHasNoTransferAndKeepsAnUnknownKindTag() async throws {
        StubURLProtocol.routes["/v1/pointers/\(addrA)"] = jsonBody([
            "address": addrA, "owner": "00", "counter": "3", "kind": "unknown",
            "kind_tag": 9, "target": target1, "state_id": "s3", "is_final": false,
            "transferred_to": NSNull(),
        ])
        let r = try await makeClient().pointerGet(address: addrA)
        XCTAssertEqual(r.counter, 3)
        XCTAssertFalse(r.isFinal)
        XCTAssertNil(r.transferredTo)
        XCTAssertEqual(r.kindTag, 9)
        XCTAssertNil(r.targetKind)
    }

    /// A counter that is not a plain decimal UInt64 is an error, never a
    /// silent zero.
    func testMalformedCountersAreRejected() async throws {
        for bad in ["", "-1", "+5", " 5", "5 ", "1.0", "0x10", "18446744073709551616", "abc"] {
            StubURLProtocol.routes["/v1/pointers/\(addrA)"] = jsonBody([
                "address": addrA, "owner": "00", "counter": bad, "kind": "chunk",
                "kind_tag": 0, "target": target1, "state_id": "s", "is_final": false,
            ])
            let error = await thrownError { _ = try await self.makeClient().pointerGet(address: self.addrA) }
            XCTAssertTrue(error is InternalError, "counter \(bad.debugDescription) gave \(String(describing: error))")
        }
        // A missing counter, and a JSON number instead of a string, are
        // refused too.
        StubURLProtocol.routes["/v1/pointers/update"] = jsonBody(["address": addrA, "state_id": "s"])
        let missing = await thrownError {
            _ = try await self.makeClient().pointerUpdate(owner: self.addrA, target: self.target1, kind: .chunk)
        }
        XCTAssertTrue(missing is InternalError)
        StubURLProtocol.routes["/v1/pointers/update"] = jsonBody(["address": addrA, "state_id": "s", "counter": 4])
        let numeric = await thrownError {
            _ = try await self.makeClient().pointerUpdate(owner: self.addrA, target: self.target1, kind: .chunk)
        }
        XCTAssertNotNil(numeric)
    }

    func testPointerResolve() async throws {
        StubURLProtocol.routes["/v1/pointers/\(addrA)/resolve"] = jsonBody([
            "kind": "chunk", "kind_tag": 0, "target": target2,
        ])
        let t = try await makeClient().pointerResolve(address: addrA)
        XCTAssertEqual(t, PointerTarget(kind: "chunk", kindTag: 0, target: target2))
        XCTAssertEqual(t.targetKind, .chunk)
        XCTAssertEqual(StubURLProtocol.lastMethods["/v1/pointers/\(addrA)/resolve"], "GET")
    }

    func testPointerFinalityOpenReadsCounterAndNulls() async throws {
        StubURLProtocol.routes["/v1/pointers/\(addrA)/finality"] = jsonBody(finalityJSON(status: "open", counter: "1"))
        let f = try await makeClient().pointerFinality(address: addrA)
        XCTAssertEqual(f.status, .open)
        XCTAssertFalse(f.isFinal)
        XCTAssertEqual(f.counter, 1)
        XCTAssertEqual(f.group, 7)
        XCTAssertEqual(f.answered, 7)
        XCTAssertNil(f.state)
        XCTAssertNil(f.majority)
        XCTAssertNil(f.transferredTo)
        XCTAssertEqual(f.states, [])
    }

    func testPointerFinalityForkedListsEveryStateAndTheMajority() async throws {
        let s1: [String: Any] = ["state_id": "x", "kind": "pointer", "kind_tag": 1, "target": addrB, "holders": 5, "transferred_to": addrB]
        let s2: [String: Any] = ["state_id": "y", "kind": "chunk", "kind_tag": 0, "target": target1, "holders": 2, "transferred_to": NSNull()]
        var body = finalityJSON(status: "forked")
        body["states"] = [s1, s2]
        body["majority"] = s1
        StubURLProtocol.routes["/v1/pointers/\(addrA)/finality"] = jsonBody(body)
        let f = try await makeClient().pointerFinality(address: addrA)
        XCTAssertEqual(f.status, .forked)
        XCTAssertEqual(f.states.map(\.stateId), ["x", "y"])
        XCTAssertEqual(f.states[1].transferredTo, nil)
        XCTAssertEqual(f.majority?.stateId, "x")
        XCTAssertEqual(f.majority?.holders, 5)
    }

    func testPointerFinalityKeepsAStatusThisSdkDoesNotKnow() async throws {
        StubURLProtocol.routes["/v1/pointers/\(addrA)/finality"] = jsonBody(finalityJSON(status: "contested"))
        let f = try await makeClient().pointerFinality(address: addrA)
        XCTAssertEqual(f.status, .unknown("contested"))
        XCTAssertEqual(f.status.wire, "contested")
    }

    func testPointerController() async throws {
        StubURLProtocol.routes["/v1/pointers/\(addrA)/controller"] = jsonBody([
            "pointer": addrB, "transfers": [addrB], "frozen": false,
        ])
        let c = try await makeClient().pointerController(address: addrA)
        XCTAssertEqual(c, PointerController(pointer: addrB, transfers: [addrB], frozen: false))
    }

    func testPointerPrepareCreateSendsTargetAndKindOnly() async throws {
        StubURLProtocol.routes["/v1/pointers/prepare"] = jsonBody([
            "upload_id": "up1", "op": "create", "address": addrA, "state_id": "s0",
            "counter": "0", "payment_type": "wave_batch",
            "payments": [["quote_hash": "0xq", "rewards_address": "0xr", "amount": "7"]],
            "total_amount": "7", "payment_vault_address": "0xv",
            "payment_token_address": "0xt", "rpc_url": "http://rpc",
        ])
        let p = try await makeClient().pointerPrepare(owner: addrA, op: .create(target: target1))

        let req = requestBody("/v1/pointers/prepare")
        XCTAssertEqual(req["owner"] as? String, addrA)
        XCTAssertEqual(req["op"] as? String, "create")
        XCTAssertEqual(req["target"] as? String, target1)
        XCTAssertEqual(req["kind"] as? String, "chunk")
        XCTAssertNil(req["recipient"])
        XCTAssertNil(req["include_signed_quotes"])

        XCTAssertEqual(p.uploadId, "up1")
        XCTAssertEqual(p.op, "create")
        XCTAssertEqual(p.counter, 0)
        XCTAssertEqual(p.paymentType, "wave_batch")
        XCTAssertEqual(p.payments, [PaymentInfo(quoteHash: "0xq", rewardsAddress: "0xr", amount: "7")])
        XCTAssertEqual(p.totalAmount, "7")
        XCTAssertEqual(p.paymentVaultAddress, "0xv")
        XCTAssertEqual(p.paymentTokenAddress, "0xt")
        XCTAssertEqual(p.rpcUrl, "http://rpc")
        XCTAssertEqual(p.signedQuotes, [])
    }

    func testPointerPrepareTransferWithSignedQuotes() async throws {
        StubURLProtocol.routes["/v1/pointers/prepare"] = jsonBody([
            "upload_id": "up2", "op": "transfer", "address": addrA, "state_id": "sf",
            "counter": maxCounter, "payment_type": "wave_batch", "payments": [] as [Any],
            "total_amount": "0", "payment_vault_address": "0xv",
            "payment_token_address": "0xt", "rpc_url": "http://rpc",
            "signed_quotes": [
                ["quote_hash": "0xq1", "quote": "cXVvdGU=", "commitment_sidecar": "c2lkZQ=="],
                ["quote_hash": "0xq2", "quote": "cXVvdGUy"],
            ],
        ])
        let p = try await makeClient().pointerPrepare(
            owner: addrA,
            op: .transfer(recipient: addrB),
            options: PointerPrepareOptions(includeSignedQuotes: true)
        )
        let req = requestBody("/v1/pointers/prepare")
        XCTAssertEqual(req["op"] as? String, "transfer")
        XCTAssertEqual(req["recipient"] as? String, addrB)
        XCTAssertNil(req["target"])
        XCTAssertNil(req["kind"])
        XCTAssertEqual(req["include_signed_quotes"] as? Bool, true)

        XCTAssertEqual(p.counter, UInt64.max)
        XCTAssertEqual(p.signedQuotes, [
            SignedQuoteEntry(quoteHash: "0xq1", quote: "cXVvdGU=", commitmentSidecar: "c2lkZQ=="),
            SignedQuoteEntry(quoteHash: "0xq2", quote: "cXVvdGUy", commitmentSidecar: nil),
        ])
    }

    func testPointerFinalizeSendsUploadIdAndTxHashes() async throws {
        StubURLProtocol.routes["/v1/pointers/finalize"] = jsonBody([
            "address": addrA, "state_id": "s1", "counter": "1",
        ])
        let f = try await makeClient().pointerFinalize(uploadId: "up1", txHashes: ["0xq": "0xtx"])
        let req = requestBody("/v1/pointers/finalize")
        XCTAssertEqual(req["upload_id"] as? String, "up1")
        XCTAssertEqual(req["tx_hashes"] as? [String: String], ["0xq": "0xtx"])
        XCTAssertEqual(f, PointerFinalizeResult(address: addrA, stateId: "s1", counter: 1, finality: nil))
    }

    func testPointerFinalizeOfATransferCarriesFinality() async throws {
        StubURLProtocol.routes["/v1/pointers/finalize"] = jsonBody([
            "address": addrA, "state_id": "sf", "counter": maxCounter,
            "finality": finalityJSON(status: "settling"),
        ])
        let f = try await makeClient().pointerFinalize(uploadId: "up2", txHashes: [:])
        XCTAssertEqual(f.counter, UInt64.max)
        XCTAssertEqual(f.finality?.status, .settling)
    }

    // MARK: - Errors through the client

    func testPointerRefusalsMapByCodeNotAsAlreadyExists() async throws {
        let cases: [(String, (Error) -> Bool)] = [
            ("POINTER_FINAL", { $0 is PointerFinalError }),
            ("POINTER_FORKED", { $0 is PointerForkedError && $0 is ForkError }),
            ("CONFLICT", { $0 is ConflictError }),
            ("ALREADY_EXISTS", { $0 is AlreadyExistsError }),
        ]
        for (code, matches) in cases {
            StubURLProtocol.statuses["/v1/pointers/update"] = 409
            StubURLProtocol.routes["/v1/pointers/update"] = jsonBody(["error": "refused: \(code)", "code": code])
            let error = await thrownError {
                _ = try await self.makeClient().pointerUpdate(owner: self.addrA, target: self.target1, kind: .chunk)
            }
            XCTAssertTrue(error.map(matches) ?? false, "\(code) gave \(String(describing: error))")
            XCTAssertEqual((error as? AntdError)?.statusCode, 409)
            // The new codes carry the body's `error` text; the status-based
            // mapping (ALREADY_EXISTS) keeps its existing raw-body message.
            if code != "ALREADY_EXISTS" {
                XCTAssertEqual((error as? AntdError)?.message, "refused: \(code)")
            }
        }
    }

    /// A paid write that fails is surfaced, not retried: the daemon sees one
    /// request.
    func testAFailedPaidWriteIsSentExactlyOnce() async throws {
        StubURLProtocol.statuses["/v1/pointers"] = 503
        StubURLProtocol.routes["/v1/pointers"] = jsonBody([
            "error": "Close group shortfall: stored on 3 of 7", "code": "CLOSE_GROUP_SHORTFALL",
        ])
        let error = await thrownError {
            _ = try await self.makeClient().pointerCreate(owner: self.addrA, target: self.target1, kind: .chunk)
        }
        let shortfall = try XCTUnwrap(error as? CloseGroupShortfallError)
        XCTAssertFalse(shortfall.retryable)
        XCTAssertEqual(shortfall.statusCode, 503)
        XCTAssertEqual(StubURLProtocol.requestCounts["/v1/pointers"], 1)
    }

    func testARetainedFinalizeShortfallIsRetryable() async throws {
        StubURLProtocol.statuses["/v1/pointers/finalize"] = 503
        StubURLProtocol.routes["/v1/pointers/finalize"] = jsonBody([
            "error": "Close group shortfall: x (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)",
            "code": "CLOSE_GROUP_SHORTFALL",
            "retryable": true,
        ])
        let error = await thrownError {
            _ = try await self.makeClient().pointerFinalize(uploadId: "up1", txHashes: ["0xq": "0xtx"])
        }
        XCTAssertEqual((error as? CloseGroupShortfallError)?.retryable, true)
        XCTAssertEqual(StubURLProtocol.requestCounts["/v1/pointers/finalize"], 1)
    }

    func testAnUnknownOwnerIsABadRequest() async throws {
        StubURLProtocol.statuses["/v1/pointers"] = 400
        StubURLProtocol.routes["/v1/pointers"] = jsonBody(["error": "no key loaded for owner", "code": "BAD_REQUEST"])
        let error = await thrownError {
            _ = try await self.makeClient().pointerCreate(owner: self.addrA, target: self.target1, kind: .chunk)
        }
        XCTAssertTrue(error is BadRequestError)
    }

    func testAMissingPointerIsNotFound() async throws {
        StubURLProtocol.statuses["/v1/pointers/\(addrA)"] = 404
        StubURLProtocol.routes["/v1/pointers/\(addrA)"] = jsonBody(["error": "not found", "code": "NOT_FOUND"])
        let error = await thrownError { _ = try await self.makeClient().pointerGet(address: self.addrA) }
        XCTAssertTrue(error is NotFoundError)
    }
}

/// Error mapping and models shared by both transports.
final class PointerMappingTests: XCTestCase {

    func testRESTCodesThatShareAStatusMapToTheirOwnErrors() throws {
        func map(_ status: Int, _ body: String) -> AntdError { ErrorMapping.fromHTTPStatus(status, body: body) }

        XCTAssertTrue(map(409, #"{"error":"final","code":"POINTER_FINAL"}"#) is PointerFinalError)
        XCTAssertTrue(map(409, #"{"error":"forked","code":"POINTER_FORKED"}"#) is PointerForkedError)
        XCTAssertTrue(map(409, #"{"error":"pending","code":"CONFLICT"}"#) is ConflictError)
        XCTAssertTrue(map(409, #"{"error":"exists","code":"ALREADY_EXISTS"}"#) is AlreadyExistsError)
        XCTAssertTrue(map(409, "exists") is AlreadyExistsError)

        let retained = try XCTUnwrap(
            map(503, #"{"error":"short","code":"CLOSE_GROUP_SHORTFALL","retryable":true}"#) as? CloseGroupShortfallError
        )
        XCTAssertTrue(retained.retryable)
        XCTAssertEqual(retained.message, "short")
        XCTAssertEqual(retained.statusCode, 503)
        let read = try XCTUnwrap(
            map(503, #"{"error":"short","code":"CLOSE_GROUP_SHORTFALL"}"#) as? CloseGroupShortfallError
        )
        XCTAssertFalse(read.retryable)
        XCTAssertFalse((map(503, #"{"error":"short","code":"CLOSE_GROUP_SHORTFALL","retryable":false}"#) as? CloseGroupShortfallError)?.retryable ?? true)
        XCTAssertTrue(map(503, #"{"error":"no wallet","code":"SERVICE_UNAVAILABLE"}"#) is ServiceUnavailableError)
        // A wrongly typed `retryable` is not trusted: the status mapping stays.
        XCTAssertTrue(map(503, #"{"error":"short","code":"CLOSE_GROUP_SHORTFALL","retryable":"true"}"#) is ServiceUnavailableError)
    }

    func testGRPCTagsMapOnlyWhenTheyAgreeWithTheCode() throws {
        func map(_ code: Int, _ detail: String, _ tag: String?) -> AntdError {
            ErrorMapping.fromGRPCStatus(code: code, detail: detail, antdErrorCode: tag)
        }
        XCTAssertTrue(map(9, "Pointer is final: x", "POINTER_FINAL") is PointerFinalError)
        XCTAssertTrue(map(9, "Pointer is forked: x", "POINTER_FORKED") is PointerForkedError)
        XCTAssertTrue(map(10, "Conflict: pending", "CONFLICT") is ConflictError)
        XCTAssertTrue(map(14, "Close group shortfall: x", "CLOSE_GROUP_SHORTFALL") is CloseGroupShortfallError)

        // Untagged, unknown or mismatched tags keep the code-based mapping.
        XCTAssertTrue(map(9, "insufficient funds", nil) is PaymentError)
        XCTAssertTrue(map(9, "insufficient funds", "SOMETHING_NEW") is PaymentError)
        XCTAssertTrue(map(10, "Pointer is final: x", "POINTER_FINAL") is ForkError)
        XCTAssertFalse(map(10, "Pointer is final: x", "POINTER_FINAL") is PointerFinalError)
        XCTAssertTrue(map(14, "unreachable", nil) is NetworkError)
        XCTAssertTrue(map(14, "unreachable", "CONFLICT") is NetworkError)
        XCTAssertTrue(map(6, "exists", nil) is AlreadyExistsError)
        XCTAssertTrue(map(10, "conflicting update", nil) is ForkError)

        // Status codes mirror REST.
        XCTAssertEqual(map(9, "x", "POINTER_FINAL").statusCode, 409)
        XCTAssertEqual(map(14, "x", "CLOSE_GROUP_SHORTFALL").statusCode, 503)
    }

    func testGRPCShortfallIsRetryableOnlyWithTheClosingRetainedHint() throws {
        func retryable(_ detail: String) -> Bool? {
            (ErrorMapping.fromGRPCStatus(code: 14, detail: detail, antdErrorCode: "CLOSE_GROUP_SHORTFALL")
                as? CloseGroupShortfallError)?.retryable
        }
        XCTAssertEqual(retryable(
            "Close group shortfall: stored on 4 of 7 (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)"
        ), true)
        XCTAssertEqual(retryable("Close group shortfall: only 3 answered"), false)
        // Truncated, quoted mid-message, or followed by more text: not read.
        XCTAssertEqual(retryable("Close group shortfall: x (paid attempt retai"), false)
        XCTAssertEqual(retryable("Close group shortfall: (paid attempt retained) then more"), false)
        XCTAssertEqual(retryable("Close group shortfall: x (paid attempt retained: y)\n"), false)
    }

    func testClosingRetentionHintStillDrivesPartialUploads() {
        XCTAssertEqual(ErrorMapping.closingRetentionHint("x (paid attempt retained: call finalize again)"), true)
        XCTAssertEqual(ErrorMapping.closingRetentionHint("x (stored chunks persist; re-prepare the same content to retry)"), false)
        XCTAssertNil(ErrorMapping.closingRetentionHint("x (something else)"))
        XCTAssertNil(ErrorMapping.closingRetentionHint("no hint"))
    }

    func testPointerForkedErrorIsAForkError() {
        let e: AntdError = PointerForkedError("forked")
        XCTAssertTrue(e is ForkError)
        XCTAssertEqual(e.statusCode, 409)
        XCTAssertEqual(PointerFinalError("x").statusCode, 409)
        XCTAssertEqual(ConflictError("x").statusCode, 409)
        XCTAssertEqual(CloseGroupShortfallError("x").statusCode, 503)
        XCTAssertFalse(CloseGroupShortfallError("x").retryable)
    }

    func testFinalityStatusWireRoundTrip() {
        let known: [PointerFinalityStatus] = [.open, .settling, .unconfirmed, .final, .forked]
        for status in known {
            XCTAssertEqual(PointerFinalityStatus(wire: status.wire), status)
        }
        XCTAssertEqual(PointerFinalityStatus(wire: "final"), .final)
        XCTAssertEqual(PointerFinalityStatus(wire: "later"), .unknown("later"))
        XCTAssertEqual(PointerFinalityStatus(wire: ""), .unknown(""))
    }

    func testPointerKindAndOpWireNames() {
        XCTAssertEqual(PointerKind(tag: 0), .chunk)
        XCTAssertEqual(PointerKind(tag: 1), .pointer)
        XCTAssertNil(PointerKind(tag: 2))
        XCTAssertEqual(PointerKind.chunk.rawValue, "chunk")
        XCTAssertEqual(PointerKind.pointer.rawValue, "pointer")
        XCTAssertEqual(PointerOp.create(target: "t").wireName, "create")
        XCTAssertEqual(PointerOp.update(target: "t", kind: .pointer).wireName, "update")
        XCTAssertEqual(PointerOp.transfer(recipient: "r").wireName, "transfer")
        XCTAssertEqual(PointerOp.create(target: "t"), .create(target: "t", kind: .chunk))
    }

    func testCounterParsing() throws {
        XCTAssertEqual(try PointerWire.counter("counter", "0"), 0)
        XCTAssertEqual(try PointerWire.counter("counter", "18446744073709551615"), UInt64.max)
        XCTAssertNil(try PointerWire.optionalCounter("counter", nil))
        XCTAssertNil(try PointerWire.optionalCounter("counter", ""))
        XCTAssertEqual(try PointerWire.optionalCounter("counter", "7"), 7)
        for bad in [nil, "", "-0", "+1", "1e3", "18446744073709551616", "٣"] as [String?] {
            XCTAssertThrowsError(try PointerWire.counter("counter", bad), "\(String(describing: bad))") {
                XCTAssertTrue($0 is InternalError)
            }
        }
        XCTAssertThrowsError(try PointerWire.optionalCounter("counter", "x"))
        XCTAssertEqual(PointerWire.kindTag(UInt32(1)), 1)
        XCTAssertEqual(PointerWire.kindTag(UInt32(300)), .max)
        XCTAssertEqual(PointerWire.kindTag(nil as UInt64?), .max)
    }
}
