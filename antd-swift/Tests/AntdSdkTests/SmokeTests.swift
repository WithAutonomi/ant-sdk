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

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    func testFactoryCreatesGrpcClient() {
        let client = AntdClient.createGrpc()
        XCTAssertTrue(client is AntdGrpcClient)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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
            PartialUploadError("partial", chunksStored: 1, chunksFailed: 1, totalChunks: 2, retryable: true, retentionKnown: true),
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
        XCTAssertEqual(
            PartialUploadError("x", chunksStored: 1, chunksFailed: 1, totalChunks: 2, retryable: false, retentionKnown: true).statusCode,
            502
        )
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

    // MARK: - PARTIAL_UPLOAD mapping

    /// A 502 whose body carries `code: "PARTIAL_UPLOAD"` maps to the typed
    /// error with the structured counts and the `retryable` flag; the
    /// `error` field becomes the message.
    func testErrorMappingPartialUploadBodyCarriesCountsAndRetryable() throws {
        let body = #"{"error":"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)","code":"PARTIAL_UPLOAD","chunks_stored":300,"chunks_failed":12,"total_chunks":312,"retryable":true}"#
        let partial = try XCTUnwrap(ErrorMapping.fromHTTPStatus(502, body: body) as? PartialUploadError)
        XCTAssertEqual(partial.statusCode, 502)
        XCTAssertEqual(partial.chunksStored, 300)
        XCTAssertEqual(partial.chunksFailed, 12)
        XCTAssertEqual(partial.totalChunks, 312)
        XCTAssertTrue(partial.retryable)
        XCTAssertTrue(partial.retentionKnown)
        XCTAssertTrue(partial.message.hasPrefix("Partial upload: 300/312 chunks stored, 12 failed"))
    }

    /// An older daemon (< 0.14.0) never sends `retryable`. The counts still
    /// map, but retention reads as unknown and `retryable` as false: the
    /// caller neither loops on the upload_id nor treats it as a confirmed
    /// "nothing retained" and pays again.
    func testErrorMappingPartialUploadRetryableDefaultsFalse() throws {
        let body = #"{"error":"Partial upload: 300/312 chunks stored, 12 failed after retries","code":"PARTIAL_UPLOAD","chunks_stored":300,"chunks_failed":12,"total_chunks":312}"#
        let partial = try XCTUnwrap(ErrorMapping.fromHTTPStatus(502, body: body) as? PartialUploadError)
        XCTAssertEqual(partial.chunksStored, 300)
        XCTAssertEqual(partial.chunksFailed, 12)
        XCTAssertEqual(partial.totalChunks, 312)
        XCTAssertFalse(partial.retryable)
        XCTAssertFalse(partial.retentionKnown)
    }

    /// A plain 502 (any other `code`, or a non-JSON body) keeps the
    /// status-based mapping.
    func testErrorMappingPlain502StillMapsToNetworkError() {
        let envelope = ErrorMapping.fromHTTPStatus(502, body: #"{"error":"upstream unreachable","code":"NETWORK_ERROR"}"#)
        XCTAssertTrue(envelope is NetworkError)
        XCTAssertFalse(envelope is PartialUploadError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(502, body: "not json") is NetworkError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(404, body: #"{"error":"nf","code":"NOT_FOUND"}"#) is NotFoundError)
    }

    /// gRPC ABORTED whose message carries the daemon's `Partial upload:`
    /// prefix has the counts and the retained hint parsed from the status
    /// message, so both transports throw the same typed error with a 502
    /// status. Any other ABORTED keeps the pre-existing `ForkError` mapping.
    func testErrorMappingGRPCAbortedParsesPartialUploadMessage() throws {
        let retained = try XCTUnwrap(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)") as? PartialUploadError
        )
        XCTAssertEqual(retained.statusCode, 502)
        XCTAssertEqual(retained.chunksStored, 300)
        XCTAssertEqual(retained.chunksFailed, 12)
        XCTAssertEqual(retained.totalChunks, 312)
        XCTAssertTrue(retained.retryable)
        XCTAssertTrue(retained.retentionKnown)

        let notRetained = try XCTUnwrap(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)") as? PartialUploadError
        )
        XCTAssertEqual(notRetained.chunksStored, 300)
        XCTAssertFalse(notRetained.retryable)
        XCTAssertTrue(notRetained.retentionKnown)

        // The prefix with garbled counts: still typed, counts zero, retention
        // unknown, not retryable.
        let garbled = try XCTUnwrap(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "Partial upload: counts unavailable") as? PartialUploadError
        )
        XCTAssertEqual(garbled.statusCode, 502)
        XCTAssertEqual(garbled.chunksStored, 0)
        XCTAssertEqual(garbled.chunksFailed, 0)
        XCTAssertEqual(garbled.totalChunks, 0)
        XCTAssertFalse(garbled.retryable)
        XCTAssertFalse(garbled.retentionKnown)
        XCTAssertEqual(garbled.message, "Partial upload: counts unavailable")

        // The gate is anchored: a message that only mentions the prefix
        // further in is not a partial upload.
        XCTAssertTrue(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "finalize failed: Partial upload: 1/2 chunks stored, 1 failed") is ForkError
        )

        // Any other ABORTED keeps the pre-existing ForkError mapping and is
        // never misreported as a partial upload.
        let fork = try XCTUnwrap(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "something else entirely") as? ForkError
        )
        XCTAssertEqual(fork.statusCode, 409)
        XCTAssertEqual(fork.message, "something else entirely")
        XCTAssertFalse(ErrorMapping.fromGRPCStatus(code: 10, detail: "") is PartialUploadError)
        XCTAssertTrue(ErrorMapping.fromGRPCStatus(code: 10, detail: "") is ForkError)
    }

    /// The message parser recovers (stored, failed, total, retryable,
    /// retentionKnown) from the daemon's `PARTIAL_UPLOAD` text and degrades
    /// to zeros, unknown retention and not retryable otherwise.
    func testParsePartialUploadMessage() {
        let cases: [(message: String, stored: UInt64, failed: UInt64, total: UInt64, retryable: Bool, known: Bool)] = [
            ("Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 300, 12, 312, true, true),
            ("Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)", 300, 12, 312, false, true),
            // Readable counts but no retention hint: retention unknown, not
            // "nothing retained".
            ("Partial upload: 300/312 chunks stored, 12 failed after retries", 300, 12, 312, false, false),
            ("Partial upload: 0/1 chunks stored, 1 failed after retries: timeout (paid attempt retained: ...)", 0, 1, 1, true, true),
            ("something else entirely", 0, 0, 0, false, false),
            ("", 0, 0, 0, false, false),
            // The hint alone never makes a message retryable: the counts must
            // match and convert first, and until they do retention is unknown.
            ("Partial upload: counts unavailable (paid attempt retained: ...)", 0, 0, 0, false, false),
            ("Partial upload: 18446744073709551616/3 chunks stored, 2 failed (paid attempt retained: ...)", 0, 0, 0, false, false),
            ("Partial upload: 1/18446744073709551616 chunks stored, 2 failed (paid attempt retained: ...)", 0, 0, 0, false, false),
            ("Partial upload: 1/3 chunks stored, 18446744073709551616 failed (paid attempt retained: ...)", 0, 0, 0, false, false),
            // UInt64.max itself converts.
            ("Partial upload: 18446744073709551615/18446744073709551615 chunks stored, 0 failed (paid attempt retained: ...)", UInt64.max, 0, UInt64.max, true, true),
            // Non-ASCII decimal digits match the pattern but do not convert.
            ("Partial upload: \u{0661}/\u{0663} chunks stored, \u{0662} failed (paid attempt retained: ...)", 0, 0, 0, false, false),
            // The counts pattern is anchored at the start of the message.
            ("upstream error: Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained: ...)", 0, 0, 0, false, false),
            // Counts quoted later in a garbled message are not read.
            ("Partial upload: garbled; was Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)", 0, 0, 0, false, false),
        ]
        for c in cases {
            let parsed = ErrorMapping.parsePartialUploadMessage(c.message)
            XCTAssertEqual(parsed.chunksStored, c.stored, c.message)
            XCTAssertEqual(parsed.chunksFailed, c.failed, c.message)
            XCTAssertEqual(parsed.totalChunks, c.total, c.message)
            XCTAssertEqual(parsed.retryable, c.retryable, c.message)
            XCTAssertEqual(parsed.retentionKnown, c.known, c.message)
        }
    }

    // MARK: - PARTIAL_UPLOAD malformed input

    /// The retained hint enables a retry only when the counts parsed in
    /// full. A count past `UInt64.max` in any position, with the hint
    /// present, still maps to the typed error, but with zero counts,
    /// unknown retention and `retryable == false`.
    func testErrorMappingGRPCOverflowCountDisablesRetry() throws {
        let overflow = "18446744073709551616" // UInt64.max + 1
        let hint = " after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"
        let messages = [
            "Partial upload: \(overflow)/3 chunks stored, 2 failed" + hint,
            "Partial upload: 1/\(overflow) chunks stored, 2 failed" + hint,
            "Partial upload: 1/3 chunks stored, \(overflow) failed" + hint,
        ]
        for message in messages {
            let partial = try XCTUnwrap(
                ErrorMapping.fromGRPCStatus(code: 10, detail: message) as? PartialUploadError,
                message
            )
            XCTAssertEqual(partial.statusCode, 502, message)
            XCTAssertEqual(partial.chunksStored, 0, message)
            XCTAssertEqual(partial.chunksFailed, 0, message)
            XCTAssertEqual(partial.totalChunks, 0, message)
            XCTAssertFalse(partial.retryable, message)
            XCTAssertFalse(partial.retentionKnown, message)
            XCTAssertEqual(partial.message, message)
        }
    }

    /// A `Partial upload:` message whose counts do not match the pattern
    /// reads as unknown retention and is not retryable, even with the hint.
    func testErrorMappingGRPCRegexMissWithHintIsNotRetryable() throws {
        let message = "Partial upload: counts unavailable (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"
        let partial = try XCTUnwrap(ErrorMapping.fromGRPCStatus(code: 10, detail: message) as? PartialUploadError)
        XCTAssertEqual(partial.chunksStored, 0)
        XCTAssertEqual(partial.chunksFailed, 0)
        XCTAssertEqual(partial.totalChunks, 0)
        XCTAssertFalse(partial.retryable)
        XCTAssertFalse(partial.retentionKnown)
    }

    /// Well-formed counts: the closing hint decides retention. The retained
    /// hint gives known and retryable; no hint gives unknown retention and
    /// not retryable, with the counts still read.
    func testErrorMappingGRPCWellFormedRetryableFollowsHint() throws {
        let withHint = try XCTUnwrap(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)") as? PartialUploadError
        )
        XCTAssertEqual(withHint.chunksStored, 1)
        XCTAssertEqual(withHint.chunksFailed, 2)
        XCTAssertEqual(withHint.totalChunks, 3)
        XCTAssertTrue(withHint.retryable)
        XCTAssertTrue(withHint.retentionKnown)

        let withoutHint = try XCTUnwrap(
            ErrorMapping.fromGRPCStatus(code: 10, detail: "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum") as? PartialUploadError
        )
        XCTAssertEqual(withoutHint.chunksStored, 1)
        XCTAssertEqual(withoutHint.chunksFailed, 2)
        XCTAssertEqual(withoutHint.totalChunks, 3)
        XCTAssertFalse(withoutHint.retryable)
        XCTAssertFalse(withoutHint.retentionKnown)
    }

    /// Only an ABORTED whose message starts with `Partial upload:` is a
    /// partial upload. One that embeds the marker further in (a wrapped
    /// upstream error, say) keeps the ForkError mapping, hint or not.
    func testErrorMappingGRPCEmbeddedMarkerIsNotPartialUpload() throws {
        for message in [
            "upstream error: Partial upload: 1/3 chunks stored, 2 failed",
            "upstream error: Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained: call finalize again with the same upload_id)",
            " Partial upload: 1/3 chunks stored, 2 failed",
            "partial upload: 1/3 chunks stored, 2 failed",
        ] {
            let mapped = ErrorMapping.fromGRPCStatus(code: 10, detail: message)
            XCTAssertFalse(mapped is PartialUploadError, message)
            let fork = try XCTUnwrap(mapped as? ForkError, message)
            XCTAssertEqual(fork.statusCode, 409, message)
            XCTAssertEqual(fork.message, message)
        }
        // The prefix on a non-ABORTED status is not a partial upload either.
        XCTAssertTrue(
            ErrorMapping.fromGRPCStatus(code: 13, detail: "Partial upload: 1/3 chunks stored, 2 failed") is InternalError
        )
    }

    /// REST: a `PARTIAL_UPLOAD` envelope whose counts, `retryable`, `code`
    /// or `error` carry the wrong JSON type is not trusted. The typed
    /// envelope fails to decode and the status-based mapping applies, so
    /// the caller gets a typed ``AntdError`` (never a `DecodingError`) and
    /// never a `retryable == true` built from a quoted or coerced value.
    func testErrorMappingRESTMalformedPartialUploadFieldsFallBackToStatus() {
        let counts: [(label: String, json: String)] = [
            ("quoted number", #""1""#),
            ("boolean", "true"),
            ("negative", "-1"),
            ("array", "[]"),
            ("object", "{}"),
            ("past UInt64.max", "18446744073709551616"),
        ]
        var bodies: [(label: String, body: String)] = []
        for field in ["chunks_stored", "chunks_failed", "total_chunks"] {
            for c in counts {
                let stored = field == "chunks_stored" ? c.json : "1"
                let failed = field == "chunks_failed" ? c.json : "2"
                let total = field == "total_chunks" ? c.json : "3"
                let body = #"{"error":"Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)","code":"PARTIAL_UPLOAD","chunks_stored":\#(stored),"chunks_failed":\#(failed),"total_chunks":\#(total),"retryable":true}"#
                bodies.append(("\(field) as \(c.label)", body))
            }
        }
        bodies += [
            ("retryable as quoted true", #"{"error":"Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)","code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":"true"}"#),
            ("retryable as number", #"{"error":"Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)","code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":1}"#),
            ("code as object", #"{"error":"Partial upload: 1/3 chunks stored, 2 failed","code":{},"chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":true}"#),
            ("code as array", #"{"error":"Partial upload: 1/3 chunks stored, 2 failed","code":["PARTIAL_UPLOAD"],"retryable":true}"#),
            ("error as number", #"{"error":42,"code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":true}"#),
            ("error as object", #"{"error":{"msg":"x"},"code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":true}"#),
            ("top-level array", #"[{"code":"PARTIAL_UPLOAD","retryable":true}]"#),
        ]
        for (label, body) in bodies {
            let mapped = ErrorMapping.fromHTTPStatus(502, body: body)
            XCTAssertFalse(mapped is PartialUploadError, label)
            XCTAssertTrue(mapped is NetworkError, "\(label): got \(mapped)")
            XCTAssertEqual(mapped.statusCode, 502, label)
            XCTAssertEqual(mapped.message, body, label)
        }
        // The same malformed envelope on another status keeps that status's
        // mapping.
        XCTAssertTrue(
            ErrorMapping.fromHTTPStatus(500, body: #"{"error":"x","code":"PARTIAL_UPLOAD","chunks_failed":"1","retryable":"true"}"#) is InternalError
        )
    }

    /// REST: absent or `null` counts read zero, and an absent or `null`
    /// `retryable` reads as unknown retention and not retryable, on an
    /// otherwise well-typed `PARTIAL_UPLOAD` envelope.
    func testErrorMappingRESTPartialUploadMissingOrNullFieldsReadZeroFalse() throws {
        for body in [
            #"{"error":"Partial upload","code":"PARTIAL_UPLOAD"}"#,
            #"{"error":"Partial upload","code":"PARTIAL_UPLOAD","chunks_stored":null,"chunks_failed":null,"total_chunks":null,"retryable":null}"#,
        ] {
            let partial = try XCTUnwrap(ErrorMapping.fromHTTPStatus(502, body: body) as? PartialUploadError, body)
            XCTAssertEqual(partial.chunksStored, 0, body)
            XCTAssertEqual(partial.chunksFailed, 0, body)
            XCTAssertEqual(partial.totalChunks, 0, body)
            XCTAssertFalse(partial.retryable, body)
            XCTAssertFalse(partial.retentionKnown, body)
            XCTAssertEqual(partial.message, "Partial upload", body)
        }
        // A missing `error` falls back to the raw body as the message.
        let noError = try XCTUnwrap(
            ErrorMapping.fromHTTPStatus(502, body: #"{"code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":true}"#) as? PartialUploadError
        )
        XCTAssertEqual(noError.chunksFailed, 2)
        XCTAssertTrue(noError.retryable)
        XCTAssertTrue(noError.retentionKnown)
    }

    // MARK: - PARTIAL_UPLOAD retention

    /// REST: `retentionKnown` follows the presence of `retryable` as a JSON
    /// boolean. `true` → known and retryable; `false` → known, not retryable
    /// (the daemon kept nothing); absent or `null` → unknown, not retryable.
    func testErrorMappingRESTRetentionKnownFollowsRetryableField() throws {
        let prefix = #"{"error":"Partial upload: 1/3 chunks stored, 2 failed","code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3"#
        let cases: [(tail: String, retryable: Bool, known: Bool)] = [
            (#","retryable":true}"#, true, true),
            (#","retryable":false}"#, false, true),
            ("}", false, false),
            (#","retryable":null}"#, false, false),
        ]
        for c in cases {
            let body = prefix + c.tail
            let partial = try XCTUnwrap(ErrorMapping.fromHTTPStatus(502, body: body) as? PartialUploadError, body)
            XCTAssertEqual(partial.chunksStored, 1, body)
            XCTAssertEqual(partial.chunksFailed, 2, body)
            XCTAssertEqual(partial.totalChunks, 3, body)
            XCTAssertEqual(partial.retryable, c.retryable, body)
            XCTAssertEqual(partial.retentionKnown, c.known, body)
        }
    }

    /// gRPC: well-formed with the retained hint → known and retryable;
    /// well-formed with the not-retained hint → known, not retryable;
    /// well-formed with no hint or a truncated one → unknown, not retryable;
    /// overflow or pattern miss with the hint → unknown, not retryable.
    func testErrorMappingGRPCRetentionKnownRequiresParsedCountsAndHint() throws {
        let hint = " after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"
        let cases: [(message: String, retryable: Bool, known: Bool)] = [
            ("Partial upload: 1/3 chunks stored, 2 failed" + hint, true, true),
            ("Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)", false, true),
            ("Partial upload: 1/3 chunks stored, 2 failed after retries: quorum", false, false),
            ("Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retai", false, false),
            ("Partial upload: 1/3 chunks stored, 18446744073709551616 failed" + hint, false, false),
            ("Partial upload: counts unavailable" + hint, false, false),
        ]
        for c in cases {
            let partial = try XCTUnwrap(ErrorMapping.fromGRPCStatus(code: 10, detail: c.message) as? PartialUploadError, c.message)
            XCTAssertEqual(partial.retryable, c.retryable, c.message)
            XCTAssertEqual(partial.retentionKnown, c.known, c.message)
        }
    }

    /// The daemon's two closing hints (`partial_upload_hint` in
    /// antd/src/error.rs).
    private static let retainedTail = " (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"
    private static let notRetainedTail = " (stored chunks persist; re-prepare the same content to retry only the remainder)"

    /// Only the hint that closes the message decides retention. Every case
    /// has readable counts (1 stored, 2 failed, 3 total), which read
    /// whatever the tail.
    private static let retentionTailCases: [(name: String, message: String, retryable: Bool, known: Bool)] = [
        ("retained hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum" + retainedTail, true, true),
        ("short retained hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retained)", true, true),
        ("not-retained hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum" + notRetainedTail, false, true),
        ("parenthesised reason before the hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (2 of 5 peers)" + notRetainedTail, false, true),
        ("retained hint in the reason, not-retained tail", "Partial upload: 1/3 chunks stored, 2 failed after retries: peer said (paid attempt retained)" + notRetainedTail, false, true),
        // Readable counts but no readable answer on retention: unknown (stop
        // and reconcile), never "nothing retained" (re-prepare).
        ("no hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum", false, false),
        ("truncated retained hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retai", false, false),
        ("retained hint without its closing paren", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retained: call finalize again", false, false),
        ("truncated not-retained hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (stored chunks persist; re-prepare the same con", false, false),
        ("unrecognised hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (something else)", false, false),
        ("text after the hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum" + retainedTail + " trailing", false, false),
        ("newline after the hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum" + retainedTail + "\n", false, false),
        ("CRLF after the not-retained hint", "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum" + notRetainedTail + "\r\n", false, false),
        ("retained hint only in the reason", "Partial upload: 1/3 chunks stored, 2 failed after retries: peer said (paid attempt retained) (connection reset)", false, false),
    ]

    /// Parser: the counts read for every tail, and only a closing hint the
    /// daemon writes makes retention known.
    func testParsePartialUploadMessageRetentionTail() {
        for c in Self.retentionTailCases {
            let parsed = ErrorMapping.parsePartialUploadMessage(c.message)
            XCTAssertEqual(parsed.chunksStored, 1, c.name)
            XCTAssertEqual(parsed.chunksFailed, 2, c.name)
            XCTAssertEqual(parsed.totalChunks, 3, c.name)
            XCTAssertEqual(parsed.retryable, c.retryable, c.name)
            XCTAssertEqual(parsed.retentionKnown, c.known, c.name)
        }
    }

    /// Mapping: the same table through a gRPC ABORTED status.
    func testErrorMappingGRPCRetentionTail() throws {
        for c in Self.retentionTailCases {
            let partial = try XCTUnwrap(
                ErrorMapping.fromGRPCStatus(code: 10, detail: c.message) as? PartialUploadError,
                c.name
            )
            XCTAssertEqual(partial.statusCode, 502, c.name)
            XCTAssertEqual(partial.chunksStored, 1, c.name)
            XCTAssertEqual(partial.chunksFailed, 2, c.name)
            XCTAssertEqual(partial.totalChunks, 3, c.name)
            XCTAssertEqual(partial.retryable, c.retryable, c.name)
            XCTAssertEqual(partial.retentionKnown, c.known, c.name)
            XCTAssertEqual(partial.message, c.message, c.name)
        }
    }

    /// `retryable` implies `retentionKnown`, even for a hand-built error.
    func testPartialUploadErrorRetryableImpliesRetentionKnown() {
        let unknown = PartialUploadError("x", chunksStored: 1, chunksFailed: 2, totalChunks: 3, retryable: true, retentionKnown: false)
        XCTAssertFalse(unknown.retryable)
        XCTAssertFalse(unknown.retentionKnown)
        let known = PartialUploadError("x", chunksStored: 1, chunksFailed: 2, totalChunks: 3, retryable: true, retentionKnown: true)
        XCTAssertTrue(known.retryable)
        XCTAssertTrue(known.retentionKnown)
    }

    // MARK: - PARTIAL_UPLOAD error-type compatibility

    /// `PartialUploadError` subclasses `NetworkError`, so a
    /// `catch let e as NetworkError` written before the typed error existed
    /// still catches a partial upload from either transport.
    func testCatchNetworkErrorStillCatchesPartialUpload() {
        let rest = ErrorMapping.fromHTTPStatus(502, body: #"{"error":"Partial upload: 1/3 chunks stored, 2 failed","code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":2,"total_chunks":3,"retryable":true}"#)
        let grpc = ErrorMapping.fromGRPCStatus(code: 10, detail: "Partial upload: 1/3 chunks stored, 2 failed")
        for mapped in [rest, grpc] {
            XCTAssertTrue(mapped is PartialUploadError, "\(mapped)")
            do {
                throw mapped
            } catch let e as NetworkError {
                XCTAssertEqual(e.statusCode, 502)
                XCTAssertTrue(e is PartialUploadError)
            } catch {
                XCTFail("expected a NetworkError catch, got \(error)")
            }
        }
        // A plain NetworkError is not a partial upload.
        XCTAssertFalse(NetworkError("net") is PartialUploadError)
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
    /// Path → HTTP status to return (defaults to 200 when absent).
    static var statuses: [String: Int] = [:]
    /// Path → raw bytes to stream back (non-JSON). Takes precedence over
    /// `routes` when set; used by the streaming tests.
    static var rawRoutes: [String: Data] = [:]

    static func reset() {
        routes = [:]
        lastBodies = [:]
        statuses = [:]
        rawRoutes = [:]
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

        let status = StubURLProtocol.statuses[path] ?? 200
        let bodyData = StubURLProtocol.rawRoutes[path]
            ?? StubURLProtocol.routes[path]
            ?? Data("{}".utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
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
            "total_chunks": 3,
            "already_stored_count": 1,
        ])

        let client = makeClient()
        let result = try await client.prepareUploadPublic(path: "/tmp/file.dat")
        XCTAssertEqual(result.uploadId, "up_wave_1")
        // already-stored preflight (added in antd 0.10.0)
        XCTAssertEqual(result.totalChunks, 3)
        XCTAssertEqual(result.alreadyStoredCount, 1)

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

    // MARK: - partial upload (finalize resumable since antd 0.14.0)

    /// A 502 `PARTIAL_UPLOAD` body surfaces as `PartialUploadError` with the
    /// structured counts and the `retryable` flag, not as a bare
    /// `NetworkError`, so callers can resume against the same payment.
    func testFinalizeSurfacesPartialUploadErrorWithCounts() async throws {
        StubURLProtocol.statuses["/v1/upload/finalize"] = 502
        StubURLProtocol.routes["/v1/upload/finalize"] = jsonBody([
            "error": "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)",
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300,
            "chunks_failed": 12,
            "total_chunks": 312,
            "retryable": true,
        ])

        let client = makeClient()
        do {
            _ = try await client.finalizeMerkleUpload(uploadId: "mb1", winnerPoolHash: "0xw1")
            XCTFail("expected PartialUploadError")
        } catch let error as PartialUploadError {
            XCTAssertEqual(error.statusCode, 502)
            XCTAssertEqual(error.chunksStored, 300)
            XCTAssertEqual(error.chunksFailed, 12)
            XCTAssertEqual(error.totalChunks, 312)
            XCTAssertTrue(error.retryable)
            XCTAssertTrue(error.retentionKnown)
            XCTAssertTrue(error.message.hasPrefix("Partial upload: 300/312"))
        } catch {
            XCTFail("expected PartialUploadError, got \(error)")
        }
    }

    /// An older daemon (< 0.14.0) omits `retryable`; retention reads as
    /// unknown and `retryable` as false, so the caller stops and reconciles
    /// instead of looping on the upload_id or paying again.
    func testFinalizePartialUploadRetryableDefaultsFalse() async throws {
        StubURLProtocol.statuses["/v1/upload/finalize"] = 502
        StubURLProtocol.routes["/v1/upload/finalize"] = jsonBody([
            "error": "Partial upload: 300/312 chunks stored, 12 failed after retries",
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300,
            "chunks_failed": 12,
            "total_chunks": 312,
        ])

        let client = makeClient()
        do {
            _ = try await client.finalizeUpload(uploadId: "u1", txHashes: ["0xq": "0xt"])
            XCTFail("expected PartialUploadError")
        } catch let error as PartialUploadError {
            XCTAssertEqual(error.chunksStored, 300)
            XCTAssertEqual(error.chunksFailed, 12)
            XCTAssertEqual(error.totalChunks, 312)
            XCTAssertFalse(error.retryable)
            XCTAssertFalse(error.retentionKnown)
        } catch {
            XCTFail("expected PartialUploadError, got \(error)")
        }
    }

    /// Code written before `PartialUploadError` existed caught a finalize 502
    /// as `NetworkError`; it still does, now with the typed error inside.
    func testFinalizePartialUploadIsCaughtAsNetworkError() async throws {
        StubURLProtocol.statuses["/v1/upload/finalize"] = 502
        StubURLProtocol.routes["/v1/upload/finalize"] = jsonBody([
            "error": "Partial upload: 300/312 chunks stored, 12 failed after retries",
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300,
            "chunks_failed": 12,
            "total_chunks": 312,
            "retryable": false,
        ])

        let client = makeClient()
        do {
            _ = try await client.finalizeUpload(uploadId: "u1", txHashes: ["0xq": "0xt"])
            XCTFail("expected NetworkError")
        } catch let error as NetworkError {
            XCTAssertEqual(error.statusCode, 502)
            let partial = try XCTUnwrap(error as? PartialUploadError)
            XCTAssertEqual(partial.chunksFailed, 12)
            XCTAssertFalse(partial.retryable)
            XCTAssertTrue(partial.retentionKnown)
        } catch {
            XCTFail("expected NetworkError, got \(error)")
        }
    }

    /// A 502 without the `PARTIAL_UPLOAD` code still maps to `NetworkError`.
    func testFinalizePlain502StillMapsToNetworkError() async throws {
        StubURLProtocol.statuses["/v1/upload/finalize"] = 502
        StubURLProtocol.routes["/v1/upload/finalize"] = jsonBody([
            "error": "upstream unreachable",
            "code": "NETWORK_ERROR",
        ])

        let client = makeClient()
        do {
            _ = try await client.finalizeUpload(uploadId: "up1", txHashes: [:])
            XCTFail("expected NetworkError")
        } catch let error as NetworkError {
            XCTAssertEqual(error.statusCode, 502)
        } catch {
            XCTFail("expected NetworkError, got \(error)")
        }
    }

    /// A `PARTIAL_UPLOAD` body whose fields carry the wrong JSON types
    /// (quoted count, quoted `retryable`) surfaces as a typed
    /// `NetworkError` on a real finalize call: never a `PartialUploadError`
    /// with a coerced `retryable`, and never a `DecodingError` escaping to
    /// the caller.
    func testFinalizeMalformedPartialUploadBodyMapsToNetworkError() async throws {
        let body = #"{"error":"Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)","code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":"2","total_chunks":3,"retryable":"true"}"#
        StubURLProtocol.statuses["/v1/upload/finalize"] = 502
        StubURLProtocol.routes["/v1/upload/finalize"] = Data(body.utf8)

        let client = makeClient()
        do {
            _ = try await client.finalizeUpload(uploadId: "u1", txHashes: ["0xq": "0xt"])
            XCTFail("expected NetworkError")
        } catch let error as PartialUploadError {
            XCTFail("malformed body must not map to PartialUploadError: \(error)")
        } catch let error as NetworkError {
            XCTAssertEqual(error.statusCode, 502)
            XCTAssertEqual(error.message, body)
        } catch {
            XCTFail("expected NetworkError, got \(type(of: error)): \(error)")
        }
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

// MARK: - V2-289 (streaming download) tests

final class DataStreamTests: XCTestCase {

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

    private func decodeJSON(_ data: Data?) -> [String: Any] {
        guard let data = data, !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func collect(_ stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var data = Data()
        for try await chunk in stream { data.append(chunk) }
        return data
    }

    /// dataStream POSTs to `/v1/data/stream` with `{data_map}` and streams the
    /// decrypted bytes back.
    func testDataStreamPostsDataMapAndStreamsBytes() async throws {
        StubURLProtocol.rawRoutes["/v1/data/stream"] = Data("decrypted private payload".utf8)

        let client = makeClient()
        let stream = try await client.dataStream(dataMap: "abcd")
        let data = try await collect(stream)

        XCTAssertEqual(String(data: data, encoding: .utf8), "decrypted private payload")

        let req = decodeJSON(StubURLProtocol.lastBodies["/v1/data/stream"])
        XCTAssertEqual(req["data_map"] as? String, "abcd")
    }

    /// dataStreamPublic GETs `/v1/data/public/{address}/stream` and streams bytes.
    func testDataStreamPublicGetsAddressStreamPathAndStreamsBytes() async throws {
        StubURLProtocol.rawRoutes["/v1/data/public/0xPUB/stream"] = Data("public stream payload".utf8)

        let client = makeClient()
        let stream = try await client.dataStreamPublic(address: "0xPUB")
        let data = try await collect(stream)

        XCTAssertEqual(String(data: data, encoding: .utf8), "public stream payload")
    }

    /// A non-2xx response parses the `{"error"}` envelope into the matching
    /// AntdError subclass before any bytes reach the caller.
    func testDataStreamMapsErrorEnvelope() async throws {
        StubURLProtocol.statuses["/v1/data/stream"] = 404
        StubURLProtocol.rawRoutes["/v1/data/stream"] = Data(
            #"{"error":"data map not found","code":"not_found"}"#.utf8
        )

        let client = makeClient()
        do {
            // The error surfaces while draining the stream (delegate-driven),
            // not from the call itself — so iterate to trigger it.
            let stream = try await client.dataStream(dataMap: "missing")
            _ = try await collect(stream)
            XCTFail("expected dataStream to throw on 404")
        } catch let error as NotFoundError {
            XCTAssertEqual(error.message, "data map not found")
            XCTAssertEqual(error.statusCode, 404)
        }
    }

    /// dataStreamPublic surfaces a non-2xx as the mapped error too.
    func testDataStreamPublicMapsErrorEnvelope() async throws {
        StubURLProtocol.statuses["/v1/data/public/0xBAD/stream"] = 502
        StubURLProtocol.rawRoutes["/v1/data/public/0xBAD/stream"] = Data(
            #"{"error":"network unavailable","code":"network"}"#.utf8
        )

        let client = makeClient()
        do {
            // The error surfaces while draining the stream (delegate-driven),
            // not from the call itself — so iterate to trigger it.
            let stream = try await client.dataStreamPublic(address: "0xBAD")
            _ = try await collect(stream)
            XCTFail("expected dataStreamPublic to throw on 502")
        } catch let error as NetworkError {
            XCTAssertEqual(error.message, "network unavailable")
            XCTAssertEqual(error.statusCode, 502)
        }
    }

    private func collectFrames(
        _ stream: AsyncThrowingStream<DownloadFrame, Error>
    ) async throws -> (data: Data, progress: [DownloadProgress], total: UInt64?) {
        var data = Data()
        var progress: [DownloadProgress] = []
        var total: UInt64?
        for try await frame in stream {
            switch frame {
            case .meta(let t): total = t
            case .data(let d): data.append(d)
            case .progress(let p): progress.append(p)
            }
        }
        return (data, progress, total)
    }

    private func ndjson(_ lines: [[String: Any]]) -> Data {
        let joined = lines
            .map { String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            .joined(separator: "\n")
        return Data((joined + "\n").utf8)
    }

    /// dataStreamWithProgress opts into NDJSON and yields interleaved data +
    /// progress frames; the base64 payload lives under the `chunk` key.
    func testDataStreamWithProgressParsesNdjson() async throws {
        StubURLProtocol.rawRoutes["/v1/data/stream"] = ndjson([
            ["type": "meta", "total_size": 6],
            ["type": "progress", "phase": "fetching", "fetched": 1, "total": 2],
            ["type": "data", "chunk": Data("sec".utf8).base64EncodedString()],
            ["type": "progress", "phase": "fetching", "fetched": 2, "total": 2],
            ["type": "data", "chunk": Data("ret".utf8).base64EncodedString()],
        ])

        let client = makeClient()
        let stream = try await client.dataStreamWithProgress(dataMap: "abcd")
        let (data, progress, total) = try await collectFrames(stream)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "secret")
        XCTAssertEqual(total, 6)
        XCTAssertEqual(progress, [
            DownloadProgress(phase: "fetching", fetched: 1, total: 2),
            DownloadProgress(phase: "fetching", fetched: 2, total: 2),
        ])
    }

    /// A terminal NDJSON `error` frame surfaces mid-stream (a raw octet-stream
    /// download cannot signal a failure after the body has started).
    func testDataStreamWithProgressSurfacesErrorFrame() async throws {
        StubURLProtocol.rawRoutes["/v1/data/stream"] = ndjson([
            ["type": "data", "chunk": Data("partial".utf8).base64EncodedString()],
            ["type": "error", "message": "chunk fetch failed"],
        ])

        let client = makeClient()
        do {
            let stream = try await client.dataStreamWithProgress(dataMap: "abcd")
            _ = try await collectFrames(stream)
            XCTFail("expected terminal error frame to throw")
        } catch let error as InternalError {
            XCTAssertEqual(error.message, "chunk fetch failed")
        }
    }
}
