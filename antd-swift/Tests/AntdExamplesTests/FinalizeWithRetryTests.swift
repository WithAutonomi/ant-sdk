import XCTest
@testable import AntdSdk
@testable import AntdExamples

/// Tests for the example's bounded same-payment retry helper
/// (`Examples.finalizeWithRetry`). Whenever it stops it must rethrow the
/// original `PartialUploadError` (type, counts and flags intact), and it
/// must never keep going when retention is unknown or the daemon kept
/// nothing: it has no re-prepare or payment path of its own.
final class FinalizeWithRetryTests: XCTestCase {

    private struct Done: Equatable { let value: String }

    private func partial(
        stored: UInt64 = 1, failed: UInt64 = 2, total: UInt64 = 3,
        retryable: Bool, known: Bool
    ) -> PartialUploadError {
        PartialUploadError(
            "Partial upload: \(stored)/\(total) chunks stored, \(failed) failed",
            chunksStored: stored, chunksFailed: failed, totalChunks: total,
            retryable: retryable, retentionKnown: known
        )
    }

    /// Retryable, then success: returns the result after resuming.
    func testRetryableThenSuccessReturnsResult() async throws {
        var calls = 0
        var backoffs: [Int] = []
        let result = try await Examples.finalizeWithRetry(
            uploadId: "u1",
            backoff: { backoffs.append($0) }
        ) { () async throws -> Done in
            calls += 1
            if calls == 1 { throw self.partial(retryable: true, known: true) }
            return Done(value: "ok")
        }
        XCTAssertEqual(result, Done(value: "ok"))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(backoffs, [1])
    }

    /// A `chunksFailed` that stops shrinking is stuck: the original error
    /// is rethrown, not a rebuilt base `AntdError`.
    func testStuckRethrowsOriginalPartialUploadError() async throws {
        let original = partial(failed: 2, retryable: true, known: true)
        var calls = 0
        do {
            _ = try await Examples.finalizeWithRetry(uploadId: "u1", backoff: { _ in }) { () async throws -> Done in
                calls += 1
                throw original
            }
            XCTFail("expected PartialUploadError")
        } catch let error as PartialUploadError {
            XCTAssertTrue(error === original)
            XCTAssertEqual(error.chunksFailed, 2)
            XCTAssertTrue(error.retryable)
            XCTAssertTrue(error.retentionKnown)
        }
        XCTAssertEqual(calls, 2)
    }

    /// Attempts exhausted while still shrinking: the last original error is
    /// rethrown after exactly `maxAttempts` calls.
    func testExhaustedRethrowsLastOriginalPartialUploadError() async throws {
        var calls = 0
        var last: PartialUploadError?
        do {
            _ = try await Examples.finalizeWithRetry(uploadId: "u1", maxAttempts: 3, backoff: { _ in }) { () async throws -> Done in
                calls += 1
                let e = self.partial(failed: UInt64(10 - calls), retryable: true, known: true)
                last = e
                throw e
            }
            XCTFail("expected PartialUploadError")
        } catch let error as PartialUploadError {
            XCTAssertTrue(error === last)
            XCTAssertEqual(error.chunksFailed, 7)
        }
        XCTAssertEqual(calls, 3)
    }

    /// The daemon kept nothing: rethrown at once for the caller to re-prepare.
    func testConfirmedNotRetainedStopsImmediately() async throws {
        let original = partial(retryable: false, known: true)
        var calls = 0
        var backoffs = 0
        do {
            _ = try await Examples.finalizeWithRetry(uploadId: "u1", backoff: { _ in backoffs += 1 }) { () async throws -> Done in
                calls += 1
                throw original
            }
            XCTFail("expected PartialUploadError")
        } catch let error as PartialUploadError {
            XCTAssertTrue(error === original)
            XCTAssertFalse(error.retryable)
            XCTAssertTrue(error.retentionKnown)
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(backoffs, 0)
    }

    /// Retention unknown: rethrown at once, no further finalize, no backoff;
    /// the helper has no re-prepare or payment path to fall into.
    func testUnknownRetentionStopsWithoutRetrying() async throws {
        let original = partial(retryable: false, known: false)
        var calls = 0
        var backoffs = 0
        do {
            _ = try await Examples.finalizeWithRetry(uploadId: "u1", backoff: { _ in backoffs += 1 }) { () async throws -> Done in
                calls += 1
                throw original
            }
            XCTFail("expected PartialUploadError")
        } catch let error as PartialUploadError {
            XCTAssertTrue(error === original)
            XCTAssertFalse(error.retryable)
            XCTAssertFalse(error.retentionKnown)
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(backoffs, 0)
    }

    /// End to end from the gRPC status text: the SDK's ABORTED mapping must
    /// steer the helper to stop at once and advise reconciling, never to
    /// retry and never to "kept nothing", whenever the daemon's closing
    /// retention hint cannot be read. Only the explicit not-retained hint
    /// gets the re-prepare advice.
    func testGrpcPartialWithoutAReadableHintStopsAndReconciles() async throws {
        let counts = "Partial upload: 6/10 chunks stored, 4 failed after retries: quorum"
        let cases: [(name: String, tail: String, known: Bool)] = [
            ("not-retained hint", " (stored chunks persist; re-prepare the same content to retry only the remainder)", true),
            ("no hint", "", false),
            // The review's reproducer: the retained hint cut short.
            ("truncated retained hint", " (paid attempt retai", false),
            ("unclosed retained hint", " (paid attempt retained: call finalize again", false),
            ("truncated not-retained hint", " (stored chunks persist; re-prepare the same con", false),
            ("newline after the retained hint", " (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)\n", false),
        ]
        for c in cases {
            let mapped = try XCTUnwrap(
                ErrorMapping.fromGRPCStatus(code: 10, detail: counts + c.tail) as? PartialUploadError,
                c.name
            )
            var calls = 0
            var backoffs = 0
            do {
                _ = try await Examples.finalizeWithRetry(uploadId: "u1", backoff: { _ in backoffs += 1 }) { () async throws -> Done in
                    calls += 1
                    throw mapped
                }
                XCTFail("\(c.name): expected PartialUploadError")
            } catch let error as PartialUploadError {
                XCTAssertTrue(error === mapped, c.name)
                XCTAssertEqual(error.chunksStored, 6, c.name)
                XCTAssertEqual(error.chunksFailed, 4, c.name)
                XCTAssertEqual(error.totalChunks, 10, c.name)
                XCTAssertFalse(error.retryable, c.name)
                XCTAssertEqual(error.retentionKnown, c.known, c.name)
            }
            XCTAssertEqual(calls, 1, c.name)
            XCTAssertEqual(backoffs, 0, c.name)

            let advice = Examples.nonRetryableAdvice(mapped, uploadId: "u1")
            XCTAssertTrue(advice.contains("6/10 chunks"), c.name)
            if c.known {
                XCTAssertTrue(advice.contains("kept nothing"), c.name)
                XCTAssertFalse(advice.contains("retention unknown"), c.name)
            } else {
                XCTAssertTrue(advice.contains("retention unknown"), c.name)
                XCTAssertTrue(advice.contains("reconcile"), c.name)
                XCTAssertFalse(advice.contains("kept nothing"), c.name)
                XCTAssertFalse(advice.contains("re-prepare the same content"), c.name)
            }
        }
    }

    /// Any other error propagates untouched on the first failure.
    func testOtherErrorsPropagateUntouched() async throws {
        let original = NetworkError("upstream unreachable")
        var calls = 0
        do {
            _ = try await Examples.finalizeWithRetry(uploadId: "u1", backoff: { _ in }) { () async throws -> Done in
                calls += 1
                throw original
            }
            XCTFail("expected NetworkError")
        } catch let error as PartialUploadError {
            XCTFail("unexpected PartialUploadError: \(error)")
        } catch let error as NetworkError {
            XCTAssertTrue(error === original)
        }
        XCTAssertEqual(calls, 1)
    }
}
