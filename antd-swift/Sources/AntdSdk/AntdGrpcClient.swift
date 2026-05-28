import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf

/// gRPC client for the antd daemon (grpc-swift 2.x).
///
/// > Note: grpc-swift 2.x requires macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+.
/// > Use ``AntdRestClient`` via ``AntdClient/createRest(baseURL:timeout:)`` on
/// > older platforms.
///
/// V2-284 implements the external-signer prepare/finalize surface (file + data +
/// chunks). V2-286 implements the wallet surface (`walletAddress`, `walletBalance`,
/// `walletApprove`). Other RPCs throw `notImplemented()` until subsequent gRPC
/// fan-out work lands.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public final class AntdGrpcClient: AntdClientProtocol, @unchecked Sendable {

    private let host: String
    private let port: Int

    public init(target: String = "localhost:50051") {
        let (h, p) = Self.parseTarget(target)
        self.host = h
        self.port = p
    }

    /// Accepts `"host:port"` or `"host"` (default port 50051).
    private static func parseTarget(_ target: String) -> (String, Int) {
        if let colon = target.lastIndex(of: ":"),
           let p = Int(target[target.index(after: colon)...]) {
            return (String(target[..<colon]), p)
        }
        return (target, 50051)
    }

    // MARK: - Connection helper

    /// Opens a one-shot grpc-swift connection to the daemon for the duration of
    /// `body`. Per-call connection setup keeps the SDK surface simple; the cost
    /// is one TCP handshake per RPC, which is acceptable for the external-signer
    /// flow (one prepare + one finalize per upload) and the wallet flow (caller
    /// queries balance/address occasionally, approves once).
    private func withGRPC<T: Sendable>(
        _ body: @Sendable (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T {
        do {
            let transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .plaintext
            )
            return try await withGRPCClient(transport: transport, handleClient: body)
        } catch let rpcError as RPCError {
            throw ErrorMapping.fromGRPCStatus(code: rpcError.code.rawValue, detail: rpcError.message)
        }
    }

    // MARK: - Out-of-scope (later gRPC tickets)

    private func notImplemented() -> AntdError {
        InternalError("not yet implemented on the gRPC client; use AntdClient.createRest()")
    }

    public func health() async throws -> HealthStatus { throw notImplemented() }
    public func dataPut(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> DataPutResult { throw notImplemented() }
    public func dataGet(dataMap: String) async throws -> Data { throw notImplemented() }
    public func dataPutPublic(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> DataPutPublicResult { throw notImplemented() }
    public func dataGetPublic(address: String) async throws -> Data { throw notImplemented() }
    public func dataCost(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> UploadCostEstimate { throw notImplemented() }
    public func chunkPut(_ data: Data) async throws -> PutResult { throw notImplemented() }
    public func chunkGet(address: String) async throws -> Data { throw notImplemented() }
    public func filePut(path: String, paymentMode: PaymentMode = .auto) async throws -> FilePutResult { throw notImplemented() }
    public func fileGet(dataMap: String, destPath: String) async throws { throw notImplemented() }
    public func filePutPublic(path: String, paymentMode: PaymentMode = .auto) async throws -> FilePutPublicResult { throw notImplemented() }
    public func fileGetPublic(address: String, destPath: String) async throws { throw notImplemented() }
    public func fileCost(path: String, isPublic: Bool = true, paymentMode: PaymentMode = .auto) async throws -> UploadCostEstimate { throw notImplemented() }
    // MARK: - External signer (V2-284)

    /// Prepares a file upload for external signing.
    ///
    /// `visibility == "public"` bundles the DataMap chunk into the same payment
    /// batch, so finalize can return its on-network address via
    /// ``FinalizeUploadResult/dataMapAddress``. `nil` leaves the proto3 default
    /// of `""`, preserving the wire shape for daemons predating the
    /// public-prepare addition.
    public func prepareUpload(path: String, visibility: String? = nil) async throws -> PrepareUploadResult {
        try await withGRPC { client in
            var req = Antd_V1_PrepareFileUploadRequest()
            req.path = path
            if let visibility = visibility { req.visibility = visibility }
            let resp = try await Antd_V1_UploadService.Client(wrapping: client).prepareFileUpload(req)
            return Self.mapPrepare(resp)
        }
    }

    public func prepareUploadPublic(path: String) async throws -> PrepareUploadResult {
        try await prepareUpload(path: path, visibility: "public")
    }

    public func prepareDataUpload(_ data: Data) async throws -> PrepareUploadResult {
        try await withGRPC { client in
            var req = Antd_V1_PrepareDataUploadRequest()
            req.data = data
            let resp = try await Antd_V1_UploadService.Client(wrapping: client).prepareDataUpload(req)
            return Self.mapPrepare(resp)
        }
    }

    public func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult {
        try await withGRPC { client in
            var req = Antd_V1_FinalizeUploadRequest()
            req.uploadID = uploadId
            req.txHashes = txHashes
            let resp = try await Antd_V1_UploadService.Client(wrapping: client).finalizeUpload(req)
            return FinalizeUploadResult(
                address: resp.address,
                chunksStored: Int64(resp.chunksStored),
                dataMap: resp.dataMap,
                dataMapAddress: resp.dataMapAddress
            )
        }
    }

    /// Merkle finalize uses the same FinalizeUpload RPC; `winnerPoolHash` is
    /// populated and `txHashes` left empty. Mirrors the REST surface, which
    /// also does not expose the legacy `store_data_map` daemon-wallet path
    /// (use `visibility = "public"` on prepare for the public-DataMap case).
    public func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult {
        try await withGRPC { client in
            var req = Antd_V1_FinalizeUploadRequest()
            req.uploadID = uploadId
            req.winnerPoolHash = winnerPoolHash
            let resp = try await Antd_V1_UploadService.Client(wrapping: client).finalizeUpload(req)
            return FinalizeMerkleUploadResult(
                address: resp.address,
                chunksStored: Int64(resp.chunksStored),
                dataMap: resp.dataMap,
                dataMapAddress: resp.dataMapAddress
            )
        }
    }

    public func prepareChunkUpload(_ data: Data) async throws -> PrepareChunkResult {
        try await withGRPC { client in
            var req = Antd_V1_PrepareChunkRequest()
            req.data = data
            let resp = try await Antd_V1_ChunkService.Client(wrapping: client).prepareChunk(req)
            let payments = resp.payments.map {
                PaymentInfo(quoteHash: $0.quoteHash, rewardsAddress: $0.rewardsAddress, amount: $0.amount)
            }
            return PrepareChunkResult(
                address: resp.address,
                alreadyStored: resp.alreadyStored,
                uploadId: resp.uploadID,
                paymentType: resp.paymentType,
                payments: payments,
                totalAmount: resp.totalAmount,
                paymentVaultAddress: resp.paymentVaultAddress,
                paymentTokenAddress: resp.paymentTokenAddress,
                rpcUrl: resp.rpcURL
            )
        }
    }

    public func finalizeChunkUpload(uploadId: String, txHashes: [String: String]) async throws -> String {
        try await withGRPC { client in
            var req = Antd_V1_FinalizeChunkRequest()
            req.uploadID = uploadId
            req.txHashes = txHashes
            let resp = try await Antd_V1_ChunkService.Client(wrapping: client).finalizeChunk(req)
            return resp.address
        }
    }

    // MARK: - Mapping

    /// Merkle-only fields (`depth`, `poolCommitments`, `merklePaymentTimestamp`)
    /// are gated on `payment_type == "merkle"`. proto3 scalar defaults are not
    /// enough — REST omits these fields entirely on wave-batch, and the model
    /// layer expects `nil` there.
    private static func mapPrepare(_ resp: Antd_V1_PrepareUploadResponse) -> PrepareUploadResult {
        let payments = resp.payments.map {
            PaymentInfo(quoteHash: $0.quoteHash, rewardsAddress: $0.rewardsAddress, amount: $0.amount)
        }
        let isMerkle = resp.paymentType == "merkle"
        let depth: Int? = isMerkle ? Int(resp.depth) : nil
        let merkleTs: UInt64? = isMerkle ? resp.merklePaymentTimestamp : nil
        let pools: [PoolCommitmentEntry]? = isMerkle
            ? resp.poolCommitments.map { pc in
                PoolCommitmentEntry(
                    poolHash: pc.poolHash,
                    candidates: pc.candidates.map {
                        CandidateNodeEntry(rewardsAddress: $0.rewardsAddress, amount: $0.amount)
                    }
                )
            }
            : nil
        return PrepareUploadResult(
            uploadId: resp.uploadID,
            payments: payments,
            totalAmount: resp.totalAmount,
            paymentVaultAddress: resp.paymentVaultAddress,
            paymentTokenAddress: resp.paymentTokenAddress,
            rpcUrl: resp.rpcURL,
            paymentType: resp.paymentType.isEmpty ? "wave_batch" : resp.paymentType,
            depth: depth,
            poolCommitments: pools,
            merklePaymentTimestamp: merkleTs
        )
    }

    // MARK: - Wallet (V2-286)
    //
    // A missing daemon wallet emits gRPC `failedPrecondition`, which
    // `ErrorMapping.fromGRPCStatus` maps to `PaymentError`. (Semantic a bit
    // off vs REST's 503 but matches every other SDK's gRPC->SDK mapping.)

    public func walletAddress() async throws -> WalletAddress {
        try await withGRPC { client in
            let req = Antd_V1_GetWalletAddressRequest()
            let resp = try await Antd_V1_WalletService.Client(wrapping: client).getAddress(req)
            return WalletAddress(address: resp.address)
        }
    }

    public func walletBalance() async throws -> WalletBalance {
        try await withGRPC { client in
            let req = Antd_V1_GetWalletBalanceRequest()
            let resp = try await Antd_V1_WalletService.Client(wrapping: client).getBalance(req)
            return WalletBalance(balance: resp.balance, gasBalance: resp.gasBalance)
        }
    }

    public func walletApprove() async throws -> Bool {
        try await withGRPC { client in
            let req = Antd_V1_WalletApproveRequest()
            let resp = try await Antd_V1_WalletService.Client(wrapping: client).approve(req)
            return resp.approved
        }
    }
}
