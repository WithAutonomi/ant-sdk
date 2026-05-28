import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import AntdSdk

/// In-process mock-server tests for the V2-284 external-signer prepare/finalize
/// surface added to ``AntdGrpcClient``. Mirrors the antd-rust / antd-go /
/// antd-py / antd-java / antd-kotlin / antd-csharp / antd-ruby / antd-dart
/// suites.
///
/// Each test spins up a real grpc-swift server on `127.0.0.1:0`, registers
/// mock service implementations that exercise the real proto types, then
/// dials with a real ``AntdGrpcClient``. This exercises the actual wire-shape
/// mapping (merkle-only field gating, visibility round-trip, etc.).
///
/// ``AntdGrpcClient`` (and therefore this suite) requires macOS 15+ / iOS 18+
/// / tvOS 18+ / watchOS 11+ because grpc-swift 2.x does. On Linux (the CI
/// environment via the dev2 sweep) the `@available` checks always pass.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class GrpcExternalSignerTests: XCTestCase {

    /// Helper: spin up an in-process server on a random port, dial it with a
    /// real ``AntdGrpcClient``, run `body`, then shutdown.
    private func withMockServer<T: Sendable>(
        _ body: @Sendable (AntdGrpcClient) async throws -> T
    ) async throws -> T {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        return try await withGRPCServer(
            transport: transport,
            services: [MockUploadService(), MockChunkService()]
        ) { _ in
            let listening = try await transport.listeningAddress
            guard let port = listening.ipv4?.port else {
                XCTFail("expected an ipv4 listening address; got \(listening)")
                throw RPCError(code: .internalError, message: "no ipv4 listening address")
            }
            let client = AntdGrpcClient(target: "127.0.0.1:\(port)")
            return try await body(client)
        }
    }

    // MARK: - prepare/finalize uploads

    /// 1. Empty visibility = proto3 default; mock echoes it into upload_id.
    func testPrepareUploadOmitsVisibilityWhenNil() async throws {
        try await withMockServer { client in
            let r = try await client.prepareUpload(path: "/tmp/x.bin")
            XCTAssertEqual(r.uploadId, "upid_file_")
            XCTAssertEqual(r.paymentType, "wave_batch")
            XCTAssertEqual(r.payments.count, 1)
            XCTAssertEqual(r.payments[0].quoteHash, "0xqa")
            XCTAssertNil(r.depth)
            XCTAssertNil(r.poolCommitments)
            XCTAssertNil(r.merklePaymentTimestamp)
        }
    }

    /// 2. Explicit visibility="public" → mock encodes it into upload_id.
    func testPrepareUploadForwardsVisibilityPublic() async throws {
        try await withMockServer { client in
            let r = try await client.prepareUpload(path: "/tmp/x.bin", visibility: "public")
            XCTAssertEqual(r.uploadId, "upid_file_public")
        }
    }

    /// 3. Convenience wrapper delegates to prepareUpload(path:, visibility:"public").
    func testPrepareUploadPublicWrapper() async throws {
        try await withMockServer { client in
            let r = try await client.prepareUploadPublic(path: "/tmp/x.bin")
            XCTAssertEqual(r.uploadId, "upid_file_public")
        }
    }

    /// 4. prepareDataUpload wave-batch — small payload, no MERKLE prefix.
    func testPrepareDataUploadWaveBatch() async throws {
        try await withMockServer { client in
            let r = try await client.prepareDataUpload(Data("small".utf8))
            XCTAssertEqual(r.uploadId, "upid_data_")
            XCTAssertEqual(r.paymentType, "wave_batch")
            XCTAssertNil(r.depth)
            XCTAssertNil(r.poolCommitments)
            XCTAssertNil(r.merklePaymentTimestamp)
        }
    }

    /// 5. prepareDataUpload merkle — payload starting "MERKLE" triggers merkle response.
    func testPrepareDataUploadMerkle() async throws {
        try await withMockServer { client in
            let r = try await client.prepareDataUpload(Data("MERKLE-large-payload".utf8))
            XCTAssertEqual(r.paymentType, "merkle")
            XCTAssertEqual(r.depth, 7)
            XCTAssertEqual(r.merklePaymentTimestamp, 1_700_000_000)
            XCTAssertNotNil(r.poolCommitments)
            XCTAssertEqual(r.poolCommitments?.count, 1)
            XCTAssertEqual(r.poolCommitments?[0].poolHash, "0xpool")
            XCTAssertEqual(r.poolCommitments?[0].candidates.first?.rewardsAddress, "0xc1")
        }
    }

    /// 6. finalizeUpload wave-batch private — upload_id doesn't end with "public", so dataMapAddress is empty.
    func testFinalizeUploadWaveBatchPrivate() async throws {
        try await withMockServer { client in
            let r = try await client.finalizeUpload(uploadId: "upid_file_", txHashes: ["0xq1": "0xtx1"])
            XCTAssertEqual(r.dataMap, "dm_wave")
            XCTAssertEqual(r.dataMapAddress, "")
            XCTAssertEqual(r.chunksStored, 3)
        }
    }

    /// 7. finalizeUpload wave-batch public — upload_id ends with "public", so dataMapAddress is populated.
    func testFinalizeUploadWaveBatchPublic() async throws {
        try await withMockServer { client in
            let r = try await client.finalizeUpload(uploadId: "upid_file_public", txHashes: ["0xq1": "0xtx1"])
            XCTAssertEqual(r.dataMapAddress, "addr_public_dm")
        }
    }

    /// 8. finalizeMerkleUpload default (no store_data_map param on swift) — address stays empty.
    ///
    /// Swift's REST + gRPC surface does NOT expose `store_data_map`, mirroring
    /// the kotlin SDK quirk — public DataMap is reached via
    /// `visibility = "public"` on prepare, not via the legacy daemon-wallet
    /// path. So the "store_data_map=true" variant in the canonical 12-test
    /// matrix collapses with this one here, leaving 11 tests for swift/kotlin.
    func testFinalizeMerkleUploadDefault() async throws {
        try await withMockServer { client in
            let r = try await client.finalizeMerkleUpload(uploadId: "upid_data_", winnerPoolHash: "0xwinpool")
            XCTAssertEqual(r.dataMap, "dm_merkle")
            XCTAssertEqual(r.address, "")
            XCTAssertEqual(r.chunksStored, 64)
        }
    }

    // MARK: - prepare/finalize chunks

    /// 9. prepareChunkUpload new chunk — full wave-batch shape.
    func testPrepareChunkUploadNewChunk() async throws {
        try await withMockServer { client in
            let r = try await client.prepareChunkUpload(Data("newchunk".utf8))
            XCTAssertFalse(r.alreadyStored)
            XCTAssertEqual(r.address, "0xnewchunk")
            XCTAssertEqual(r.uploadId, "upid_chunk_42")
            XCTAssertEqual(r.paymentType, "wave_batch")
            XCTAssertEqual(r.payments.count, 1)
            XCTAssertEqual(r.payments[0].quoteHash, "0xq1")
            XCTAssertEqual(r.totalAmount, "100")
            XCTAssertEqual(r.rpcUrl, "http://localhost:8545")
        }
    }

    /// 10. prepareChunkUpload already-stored short-circuit — `EXISTS` prefix.
    func testPrepareChunkUploadAlreadyStored() async throws {
        try await withMockServer { client in
            let r = try await client.prepareChunkUpload(Data("EXISTS-data".utf8))
            XCTAssertTrue(r.alreadyStored)
            XCTAssertEqual(r.address, "0xabc")
            XCTAssertEqual(r.uploadId, "")
            XCTAssertTrue(r.payments.isEmpty)
        }
    }

    /// 11. finalizeChunkUpload — address echoes the upload_id.
    func testFinalizeChunkUpload() async throws {
        try await withMockServer { client in
            let addr = try await client.finalizeChunkUpload(uploadId: "upid_chunk_42", txHashes: ["0xq1": "0xtxabc"])
            XCTAssertEqual(addr, "addr_for_upid_chunk_42")
        }
    }
}

// MARK: - Mock services

/// Mock implementation of `UploadService` matching the canonical mock-service
/// behaviors documented in `reference_v2_284_sdk_fanout_recipe`. Encodes
/// visibility into `upload_id` so finalize can recover what prepare was
/// asked, without holding server-side state.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class MockUploadService: Antd_V1_UploadService.SimpleServiceProtocol, @unchecked Sendable {

    func prepareFileUpload(
        request: Antd_V1_PrepareFileUploadRequest,
        context: ServerContext
    ) async throws -> Antd_V1_PrepareUploadResponse {
        var resp = Antd_V1_PrepareUploadResponse()
        resp.uploadID = "upid_file_\(request.visibility)"
        resp.paymentType = "wave_batch"
        resp.totalAmount = "1"
        resp.paymentVaultAddress = "0xvault"
        resp.paymentTokenAddress = "0xtoken"
        resp.rpcURL = "http://localhost:8545"
        var payment = Antd_V1_PaymentEntry()
        payment.quoteHash = "0xqa"
        payment.rewardsAddress = "0xra"
        payment.amount = "1"
        resp.payments = [payment]
        return resp
    }

    func prepareDataUpload(
        request: Antd_V1_PrepareDataUploadRequest,
        context: ServerContext
    ) async throws -> Antd_V1_PrepareUploadResponse {
        let uid = "upid_data_\(request.visibility)"
        let prefix = String(data: request.data.prefix(6), encoding: .utf8) ?? ""
        if prefix == "MERKLE" {
            var merkle = Antd_V1_PrepareUploadResponse()
            merkle.uploadID = uid
            merkle.paymentType = "merkle"
            merkle.depth = 7
            merkle.merklePaymentTimestamp = 1_700_000_000
            merkle.totalAmount = "0"
            merkle.paymentVaultAddress = "0xvault"
            merkle.paymentTokenAddress = "0xtoken"
            merkle.rpcURL = "http://localhost:8545"
            var cand = Antd_V1_CandidateNodeEntry()
            cand.rewardsAddress = "0xc1"
            cand.amount = "5"
            var pool = Antd_V1_PoolCommitmentEntry()
            pool.poolHash = "0xpool"
            pool.candidates = [cand]
            merkle.poolCommitments = [pool]
            return merkle
        }
        var wave = Antd_V1_PrepareUploadResponse()
        wave.uploadID = uid
        wave.paymentType = "wave_batch"
        wave.totalAmount = "2"
        wave.paymentVaultAddress = "0xvault"
        wave.paymentTokenAddress = "0xtoken"
        wave.rpcURL = "http://localhost:8545"
        var p = Antd_V1_PaymentEntry()
        p.quoteHash = "0xqb"
        p.rewardsAddress = "0xrb"
        p.amount = "2"
        wave.payments = [p]
        return wave
    }

    func finalizeUpload(
        request: Antd_V1_FinalizeUploadRequest,
        context: ServerContext
    ) async throws -> Antd_V1_FinalizeUploadResponse {
        var resp = Antd_V1_FinalizeUploadResponse()
        if !request.winnerPoolHash.isEmpty {
            resp.dataMap = "dm_merkle"
            resp.address = request.storeDataMap ? "stored_on_network" : ""
            resp.chunksStored = 64
            return resp
        }
        resp.dataMap = "dm_wave"
        resp.dataMapAddress = request.uploadID.hasSuffix("public") ? "addr_public_dm" : ""
        resp.chunksStored = 3
        return resp
    }
}

/// Mock implementation of `ChunkService` with `PrepareChunk` + `FinalizeChunk`
/// overrides. Other RPCs (`Get` / `Put`) throw — not exercised by V2-284.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class MockChunkService: Antd_V1_ChunkService.SimpleServiceProtocol, @unchecked Sendable {

    func get(
        request: Antd_V1_GetChunkRequest,
        context: ServerContext
    ) async throws -> Antd_V1_GetChunkResponse {
        throw RPCError(code: .unimplemented, message: "not exercised by V2-284 tests")
    }

    func put(
        request: Antd_V1_PutChunkRequest,
        context: ServerContext
    ) async throws -> Antd_V1_PutChunkResponse {
        throw RPCError(code: .unimplemented, message: "not exercised by V2-284 tests")
    }

    func prepareChunk(
        request: Antd_V1_PrepareChunkRequest,
        context: ServerContext
    ) async throws -> Antd_V1_PrepareChunkResponse {
        var resp = Antd_V1_PrepareChunkResponse()
        let prefix = String(data: request.data.prefix(6), encoding: .utf8) ?? ""
        if prefix == "EXISTS" {
            resp.address = "0xabc"
            resp.alreadyStored = true
            return resp
        }
        resp.address = "0xnewchunk"
        resp.alreadyStored = false
        resp.uploadID = "upid_chunk_42"
        resp.paymentType = "wave_batch"
        resp.totalAmount = "100"
        resp.paymentVaultAddress = "0xvault"
        resp.paymentTokenAddress = "0xtoken"
        resp.rpcURL = "http://localhost:8545"
        var p = Antd_V1_PaymentEntry()
        p.quoteHash = "0xq1"
        p.rewardsAddress = "0xr1"
        p.amount = "100"
        resp.payments = [p]
        return resp
    }

    func finalizeChunk(
        request: Antd_V1_FinalizeChunkRequest,
        context: ServerContext
    ) async throws -> Antd_V1_FinalizeChunkResponse {
        var resp = Antd_V1_FinalizeChunkResponse()
        resp.address = "addr_for_\(request.uploadID)"
        return resp
    }
}
