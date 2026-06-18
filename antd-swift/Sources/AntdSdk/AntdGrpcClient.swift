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
/// Implements the full core surface: health, data get/put (private + public) +
/// cost + streaming, chunk get/put, file get/put (private + public) + cost
/// (V2-480); the external-signer prepare/finalize surface (V2-284); and the
/// wallet surface (V2-286). Data streaming (`dataStream`/`dataStreamPublic`) is
/// the gRPC counterpart to the REST streaming download (V2-499).
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

    // MARK: - Health

    public func health() async throws -> HealthStatus {
        try await withGRPC { client in
            let resp = try await Antd_V1_HealthService.Client(wrapping: client)
                .check(Antd_V1_HealthCheckRequest())
            return HealthStatus(
                ok: resp.status == "ok",
                network: resp.network,
                version: resp.version,
                evmNetwork: resp.evmNetwork,
                uptimeSeconds: resp.uptimeSeconds,
                buildCommit: resp.buildCommit,
                paymentTokenAddress: resp.paymentTokenAddress,
                paymentVaultAddress: resp.paymentVaultAddress
            )
        }
    }

    // MARK: - Data (Immutable)

    public func dataPut(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> DataPutResult {
        try await withGRPC { client in
            var req = Antd_V1_PutDataRequest()
            req.data = data
            req.paymentMode = paymentMode.rawValue
            let resp = try await Antd_V1_DataService.Client(wrapping: client).put(req)
            // gRPC PutDataResponse carries only the DataMap (+ an empty Cost);
            // chunks_stored / payment_mode_used aren't on the wire here.
            return DataPutResult(dataMap: resp.dataMap, chunksStored: resp.chunksStored, paymentModeUsed: resp.paymentModeUsed)
        }
    }

    public func dataGet(dataMap: String) async throws -> Data {
        try await withGRPC { client in
            var req = Antd_V1_GetDataRequest()
            req.dataMap = dataMap
            let resp = try await Antd_V1_DataService.Client(wrapping: client).get(req)
            return resp.data
        }
    }

    public func dataPutPublic(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> DataPutPublicResult {
        try await withGRPC { client in
            var req = Antd_V1_PutPublicDataRequest()
            req.data = data
            req.paymentMode = paymentMode.rawValue
            let resp = try await Antd_V1_DataService.Client(wrapping: client).putPublic(req)
            return DataPutPublicResult(address: resp.address, chunksStored: resp.chunksStored, paymentModeUsed: resp.paymentModeUsed)
        }
    }

    public func dataGetPublic(address: String) async throws -> Data {
        try await withGRPC { client in
            var req = Antd_V1_GetPublicDataRequest()
            req.address = address
            let resp = try await Antd_V1_DataService.Client(wrapping: client).getPublic(req)
            return resp.data
        }
    }

    public func dataCost(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> UploadCostEstimate {
        try await withGRPC { client in
            var req = Antd_V1_DataCostRequest()
            req.data = data
            req.paymentMode = paymentMode.rawValue
            let resp = try await Antd_V1_DataService.Client(wrapping: client).cost(req)
            return Self.mapCost(resp)
        }
    }

    // MARK: - Data streaming (V2-499)

    /// Streams private data from a caller-held DataMap, one decrypt batch at a
    /// time — the gRPC counterpart to ``dataGet(dataMap:)``. The returned stream
    /// yields raw byte chunks; the underlying gRPC connection stays open until
    /// the stream is fully consumed or the consuming task is cancelled.
    public func dataStream(dataMap: String) async throws -> AsyncThrowingStream<Data, Error> {
        streamChunks { client, continuation in
            var req = Antd_V1_StreamDataRequest()
            req.dataMap = dataMap
            try await Antd_V1_DataService.Client(wrapping: client).stream(req) { response in
                for try await chunk in response.messages {
                    continuation.yield(chunk.data)
                }
            }
        }
    }

    /// Streams public data by address — the gRPC counterpart to
    /// ``dataGetPublic(address:)``.
    public func dataStreamPublic(address: String) async throws -> AsyncThrowingStream<Data, Error> {
        streamChunks { client, continuation in
            var req = Antd_V1_StreamPublicDataRequest()
            req.address = address
            try await Antd_V1_DataService.Client(wrapping: client).streamPublic(req) { response in
                for try await chunk in response.messages {
                    continuation.yield(chunk.data)
                }
            }
        }
    }

    /// ``dataStream(dataMap:)`` with interleaved fetch-progress frames so the
    /// caller can drive a *determinate* download progress bar. Sets the
    /// request's `includeProgress` flag; the returned stream yields
    /// ``DownloadFrame`` values — each a plaintext chunk (`.data`) or a
    /// ``DownloadProgress`` update (`.progress`). The byte denominator arrives
    /// separately as the `x-content-length` response header.
    public func dataStreamWithProgress(dataMap: String) async throws -> AsyncThrowingStream<DownloadFrame, Error> {
        streamFrames { client, continuation in
            var req = Antd_V1_StreamDataRequest()
            req.dataMap = dataMap
            req.includeProgress = true
            try await Antd_V1_DataService.Client(wrapping: client).stream(req) { response in
                if let meta = Self.metaFrame(from: response.metadata) {
                    continuation.yield(meta)
                }
                for try await chunk in response.messages {
                    continuation.yield(Self.frame(of: chunk))
                }
            }
        }
    }

    /// ``dataStreamPublic(address:)`` with interleaved fetch-progress frames.
    /// See ``dataStreamWithProgress(dataMap:)``.
    public func dataStreamPublicWithProgress(address: String) async throws -> AsyncThrowingStream<DownloadFrame, Error> {
        streamFrames { client, continuation in
            var req = Antd_V1_StreamPublicDataRequest()
            req.address = address
            req.includeProgress = true
            try await Antd_V1_DataService.Client(wrapping: client).streamPublic(req) { response in
                if let meta = Self.metaFrame(from: response.metadata) {
                    continuation.yield(meta)
                }
                for try await chunk in response.messages {
                    continuation.yield(Self.frame(of: chunk))
                }
            }
        }
    }

    /// Read the total download size from a stream response's `x-content-length`
    /// initial metadata as a leading ``DownloadFrame/meta(_:)``. Returns `nil`
    /// when the header is absent or unparseable (older daemons).
    private static func metaFrame(from metadata: Metadata) -> DownloadFrame? {
        for value in metadata[stringValues: "x-content-length"] {
            if let total = UInt64(value) {
                return .meta(total)
            }
            break
        }
        return nil
    }

    /// Maps a wire `DataChunk` (oneof `kind {data | progress}`) onto a public
    /// ``DownloadFrame``. A frame with no arm set (shouldn't occur) becomes an
    /// empty data frame, matching the antd-rust reference consumer.
    private static func frame(of chunk: Antd_V1_DataChunk) -> DownloadFrame {
        switch chunk.kind {
        case .progress(let p):
            return .progress(DownloadProgress(phase: p.phase, fetched: p.fetched, total: p.total))
        case .data(let d):
            return .data(d)
        case .none:
            return .data(Data())
        }
    }

    /// Bridges a grpc-swift server-stream of ``DownloadFrame`` into an
    /// `AsyncThrowingStream` (the ``DownloadFrame`` counterpart to
    /// ``streamChunks(_:)``).
    private func streamFrames(
        _ pump: @escaping @Sendable (
            GRPCClient<HTTP2ClientTransport.Posix>,
            AsyncThrowingStream<DownloadFrame, Error>.Continuation
        ) async throws -> Void
    ) -> AsyncThrowingStream<DownloadFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withGRPC { client in
                        try await pump(client, continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Bridges a grpc-swift server-stream into an `AsyncThrowingStream`. A task
    /// holds the per-call connection (`withGRPC`) open while it pumps chunks
    /// into the continuation; cancelling the consumer cancels the task, and
    /// gRPC errors (already mapped to `AntdError` by `withGRPC`) finish the
    /// stream with that error.
    private func streamChunks(
        _ pump: @escaping @Sendable (
            GRPCClient<HTTP2ClientTransport.Posix>,
            AsyncThrowingStream<Data, Error>.Continuation
        ) async throws -> Void
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withGRPC { client in
                        try await pump(client, continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Chunks

    public func chunkPut(_ data: Data) async throws -> PutResult {
        try await withGRPC { client in
            var req = Antd_V1_PutChunkRequest()
            req.data = data
            let resp = try await Antd_V1_ChunkService.Client(wrapping: client).put(req)
            return PutResult(cost: resp.cost.attoTokens, address: resp.address)
        }
    }

    public func chunkGet(address: String) async throws -> Data {
        try await withGRPC { client in
            var req = Antd_V1_GetChunkRequest()
            req.address = address
            let resp = try await Antd_V1_ChunkService.Client(wrapping: client).get(req)
            return resp.data
        }
    }

    // MARK: - Files

    public func filePut(path: String, paymentMode: PaymentMode = .auto) async throws -> FilePutResult {
        try await withGRPC { client in
            var req = Antd_V1_PutFileRequest()
            req.path = path
            req.paymentMode = paymentMode.rawValue
            let resp = try await Antd_V1_FileService.Client(wrapping: client).put(req)
            return FilePutResult(
                dataMap: resp.dataMap,
                storageCostAtto: resp.storageCostAtto,
                gasCostWei: resp.gasCostWei,
                chunksStored: resp.chunksStored,
                paymentModeUsed: resp.paymentModeUsed
            )
        }
    }

    public func fileGet(dataMap: String, destPath: String) async throws {
        try await withGRPC { client in
            var req = Antd_V1_GetFileRequest()
            req.dataMap = dataMap
            req.destPath = destPath
            _ = try await Antd_V1_FileService.Client(wrapping: client).get(req)
        }
    }

    public func filePutPublic(path: String, paymentMode: PaymentMode = .auto) async throws -> FilePutPublicResult {
        try await withGRPC { client in
            var req = Antd_V1_PutFileRequest()
            req.path = path
            req.paymentMode = paymentMode.rawValue
            let resp = try await Antd_V1_FileService.Client(wrapping: client).putPublic(req)
            return FilePutPublicResult(
                address: resp.address,
                storageCostAtto: resp.storageCostAtto,
                gasCostWei: resp.gasCostWei,
                chunksStored: resp.chunksStored,
                paymentModeUsed: resp.paymentModeUsed
            )
        }
    }

    public func fileGetPublic(address: String, destPath: String) async throws {
        try await withGRPC { client in
            var req = Antd_V1_GetFilePublicRequest()
            req.address = address
            req.destPath = destPath
            _ = try await Antd_V1_FileService.Client(wrapping: client).getPublic(req)
        }
    }

    public func fileCost(path: String, isPublic: Bool = true, paymentMode: PaymentMode = .auto) async throws -> UploadCostEstimate {
        try await withGRPC { client in
            var req = Antd_V1_FileCostRequest()
            req.path = path
            req.isPublic = isPublic
            req.paymentMode = paymentMode.rawValue
            let resp = try await Antd_V1_FileService.Client(wrapping: client).cost(req)
            return Self.mapCost(resp)
        }
    }

    /// Maps the shared `Cost` message into the SDK's `UploadCostEstimate`.
    private static func mapCost(_ resp: Antd_V1_Cost) -> UploadCostEstimate {
        UploadCostEstimate(
            cost: resp.attoTokens,
            fileSize: resp.fileSize,
            chunkCount: resp.chunkCount,
            estimatedGasCostWei: resp.estimatedGasCostWei,
            paymentMode: resp.paymentMode
        )
    }

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
