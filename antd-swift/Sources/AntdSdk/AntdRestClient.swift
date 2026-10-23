import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class AntdRestClient: AntdClientProtocol, @unchecked Sendable {

    private let baseURL: String
    private let session: URLSession

    public init(baseURL: String = "http://localhost:8082", timeout: TimeInterval = 300) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    /// Internal init for tests that want to inject a custom session
    /// (typically with a stub `URLProtocol` registered via
    /// `configuration.protocolClasses`).
    internal init(baseURL: String, session: URLSession) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session
    }

    // MARK: - Helpers

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw BadRequestError("invalid URL: \(baseURL)\(path)") }
        let (data, response) = try await session.data(from: url)
        try ensureSuccess(response, data: data)
        return try JSONDecoder.snakeCase.decode(T.self, from: data)
    }

    // Internal, not private: the manifest methods (AntdRestClient+Manifests.swift)
    // post through it from their own file.
    func postJSON<T: Decodable>(_ path: String, body: Any) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw BadRequestError("invalid URL: \(baseURL)\(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response, data: data)
        return try JSONDecoder.snakeCase.decode(T.self, from: data)
    }

    private func postJSONNoResult(_ path: String, body: Any) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw BadRequestError("invalid URL: \(baseURL)\(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response, data: data)
    }

    private func headExists(_ path: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw BadRequestError("invalid URL: \(baseURL)\(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        if httpResponse.statusCode == 404 { return false }
        try ensureSuccess(response, data: data)
        return true
    }

    private func ensureSuccess(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ErrorMapping.fromHTTPStatus(httpResponse.statusCode, body: body)
        }
    }

    // MARK: - Health

    public func health() async throws -> HealthStatus {
        do {
            let resp: HealthResponseDTO = try await getJSON("/health")
            return resp.toHealthStatus()
        } catch {
            return HealthStatus(ok: false, network: "unknown")
        }
    }

    // MARK: - Data

    public func dataPut(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> DataPutResult {
        let body: [String: Any] = [
            "data": data.base64EncodedString(),
            "payment_mode": paymentMode.rawValue,
        ]
        let resp: DataPutDTO = try await postJSON("/v1/data", body: body)
        return DataPutResult(
            dataMap: resp.dataMap,
            chunksStored: resp.chunksStored ?? 0,
            paymentModeUsed: resp.paymentModeUsed ?? "",
            sha256: ManifestWire.nonEmpty(resp.sha256)
        )
    }

    public func dataGet(dataMap: String) async throws -> Data {
        let resp: DataDTO = try await postJSON("/v1/data/get", body: ["data_map": dataMap])
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    public func dataPutPublic(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> DataPutPublicResult {
        let body: [String: Any] = [
            "data": data.base64EncodedString(),
            "payment_mode": paymentMode.rawValue,
        ]
        let resp: DataPutPublicDTO = try await postJSON("/v1/data/public", body: body)
        return DataPutPublicResult(
            address: resp.address,
            chunksStored: resp.chunksStored ?? 0,
            paymentModeUsed: resp.paymentModeUsed ?? "",
            sha256: ManifestWire.nonEmpty(resp.sha256)
        )
    }

    public func dataGetPublic(address: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/data/public/\(address)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    // MARK: - Data (streaming) — V2-289

    /// Streams private data from a caller-held DataMap (hex) instead of
    /// buffering the whole object in memory. The streaming counterpart to
    /// ``dataGet(dataMap:)``.
    ///
    /// On a 2xx response the returned `AsyncThrowingStream<Data, Error>` yields
    /// the decrypted bytes incrementally (constant memory) as the daemon
    /// delivers them. On a non-2xx response the JSON `{"error":...}` body is
    /// parsed and the matching ``AntdError`` is thrown from the stream *before*
    /// any payload chunk is handed to the caller.
    ///
    /// This is implemented with a delegate-driven `URLSessionDataTask` rather
    /// than `URLSession.bytes(for:)`, because `URLSession.AsyncBytes` is
    /// Darwin-only and does not exist in swift-corelibs-foundation (Linux).
    ///
    /// > Note: this POSTs the same body as ``dataGet(dataMap:)``
    /// > (`{"data_map":"<hex>"}`) to `POST /v1/data/stream`.
    public func dataStream(dataMap: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard let url = URL(string: "\(baseURL)/v1/data/stream") else {
            throw BadRequestError("invalid URL: \(baseURL)/v1/data/stream")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data_map": dataMap])
        return openByteStream(request)
    }

    /// Streams public data by address — the streaming counterpart to
    /// ``dataGetPublic(address:)``. Issues `GET /v1/data/public/{address}/stream`.
    ///
    /// On a 2xx response the returned `AsyncThrowingStream<Data, Error>` yields
    /// the bytes incrementally (constant memory). On a non-2xx response the JSON
    /// `{"error":...}` body is parsed and the matching ``AntdError`` is thrown
    /// from the stream before any payload chunk is handed to the caller.
    ///
    /// Like ``dataStream(dataMap:)``, this uses a delegate-driven data task so
    /// it compiles on both Darwin Foundation and swift-corelibs-foundation
    /// (Linux), which has no `URLSession.AsyncBytes`.
    public func dataStreamPublic(address: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard let url = URL(string: "\(baseURL)/v1/data/public/\(address)/stream") else {
            throw BadRequestError("invalid URL: \(baseURL)/v1/data/public/\(address)/stream")
        }
        let request = URLRequest(url: url)
        return openByteStream(request)
    }

    /// ``dataStream(dataMap:)`` with interleaved fetch-progress frames so the
    /// caller can drive a *determinate* download progress bar. Opts into NDJSON
    /// framing (`Accept: application/x-ndjson`); the returned stream yields
    /// ``DownloadFrame`` values — each a plaintext chunk (`.data`) or a
    /// ``DownloadProgress`` update (`.progress`).
    public func dataStreamWithProgress(dataMap: String) async throws -> AsyncThrowingStream<DownloadFrame, Error> {
        guard let url = URL(string: "\(baseURL)/v1/data/stream") else {
            throw BadRequestError("invalid URL: \(baseURL)/v1/data/stream")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.ndjsonContentType, forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data_map": dataMap])
        return Self.ndjsonFrames(from: openByteStream(request))
    }

    /// ``dataStreamPublic(address:)`` with interleaved fetch-progress frames.
    /// See ``dataStreamWithProgress(dataMap:)``.
    public func dataStreamPublicWithProgress(address: String) async throws -> AsyncThrowingStream<DownloadFrame, Error> {
        guard let url = URL(string: "\(baseURL)/v1/data/public/\(address)/stream") else {
            throw BadRequestError("invalid URL: \(baseURL)/v1/data/public/\(address)/stream")
        }
        var request = URLRequest(url: url)
        request.setValue(Self.ndjsonContentType, forHTTPHeaderField: "Accept")
        return Self.ndjsonFrames(from: openByteStream(request))
    }

    /// Media type that opts the stream endpoints into NDJSON progress framing.
    private static let ndjsonContentType = "application/x-ndjson"

    /// Adapts a raw NDJSON byte stream into a ``DownloadFrame`` stream, buffering
    /// partial lines across chunk boundaries and parsing each complete line. The
    /// leading `meta` frame and unknown frame types are skipped; a terminal
    /// `error` frame finishes the stream by throwing (a raw octet-stream
    /// download cannot signal a mid-stream failure).
    private static func ndjsonFrames(
        from byteStream: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<DownloadFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = Data()
                do {
                    for try await chunk in byteStream {
                        buffer.append(chunk)
                        while let nl = buffer.firstIndex(of: 0x0A) {
                            let line = Data(buffer[buffer.startIndex..<nl])
                            buffer = Data(buffer[buffer.index(after: nl)...])
                            if let frame = try parseNdjsonFrame(line) {
                                continuation.yield(frame)
                            }
                        }
                    }
                    if let frame = try parseNdjsonFrame(buffer) {
                        continuation.yield(frame)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parses one NDJSON line into a ``DownloadFrame``. Returns `nil` for the
    /// leading `meta` frame, blank lines, and unknown frame types
    /// (forward-compat); throws ``InternalError`` on a terminal `error` frame.
    private static func parseNdjsonFrame(_ line: Data) throws -> DownloadFrame? {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else {
            return nil
        }
        switch type {
        case "data":
            let b64 = obj["chunk"] as? String ?? ""
            return .data(Data(base64Encoded: b64) ?? Data())
        case "progress":
            func u64(_ v: Any?) -> UInt64 { (v as? NSNumber)?.uint64Value ?? 0 }
            return .progress(DownloadProgress(
                phase: obj["phase"] as? String ?? "",
                fetched: u64(obj["fetched"]),
                total: u64(obj["total"])
            ))
        case "error":
            throw InternalError(obj["message"] as? String ?? "stream error")
        case "meta":
            func u64(_ v: Any?) -> UInt64 { (v as? NSNumber)?.uint64Value ?? 0 }
            return .meta(u64(obj["total_size"]))
        default:
            return nil
        }
    }

    /// Opens a delegate-driven byte stream for `request`. The HTTP status is
    /// inspected in the response delegate callback: on a non-2xx status the
    /// (short) error body is buffered and, when the task completes, mapped to an
    /// ``AntdError`` (mirroring the buffered ``ensureSuccess(_:data:)`` path,
    /// but parsing the daemon's `{"error":...}` JSON envelope when present).
    ///
    /// Each session is created with its own delegate and invalidated when the
    /// stream finishes (or the consumer cancels), so neither the delegate nor
    /// the session leaks. The `config` is copied from the shared ``session`` so
    /// the same timeouts — and, in tests, the stub `URLProtocol` — apply.
    private func openByteStream(_ request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        // Copy the configuration of the shared session so the delegate session
        // inherits its timeouts and any injected `protocolClasses` (test stub).
        let config = session.configuration
        return AsyncThrowingStream { continuation in
            let delegate = StreamingDelegate(continuation: continuation)
            let streamSession = URLSession(
                configuration: config,
                delegate: delegate,
                delegateQueue: nil
            )
            let task = streamSession.dataTask(with: request)
            // Once the stream finishes (success, error, or cancellation), tear
            // the task down and let the session release the delegate.
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                streamSession.finishTasksAndInvalidate()
            }
            task.resume()
        }
    }

    /// `URLSessionDataDelegate` that bridges a `URLSessionDataTask` into an
    /// `AsyncThrowingStream<Data, Error>`. Only delegate methods that exist on
    /// both Darwin Foundation and swift-corelibs-foundation are used, so it
    /// compiles and runs on Linux (Swift 6.0.3) as well as Apple platforms.
    private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let continuation: AsyncThrowingStream<Data, Error>.Continuation
        /// The HTTP status seen in `didReceive response`; defaults to 200 when a
        /// non-HTTP response is delivered (treated as success, matching the
        /// buffered path's `ensureSuccess`).
        private var statusCode = 200
        /// True once a non-2xx status is seen: subsequent body chunks are
        /// buffered as the error envelope instead of being yielded.
        private var isError = false
        /// Buffered error body, populated only on the non-2xx path.
        private var errorBody = Data()

        init(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
            self.continuation = continuation
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            if let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
                isError = !(200...299).contains(http.statusCode)
            }
            // Continue receiving in both cases: on the error path we need the
            // short `{"error":...}` body, which arrives via `didReceive data`.
            completionHandler(.allow)
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive data: Data
        ) {
            if isError {
                errorBody.append(data)
            } else {
                continuation.yield(data)
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            if isError {
                // Non-2xx: surface the mapped daemon error, ignoring any
                // transport error (the body is the authoritative message).
                continuation.finish(throwing: Self.streamError(status: statusCode, body: errorBody))
                return
            }
            if let error = error {
                // A cancelled task is the normal teardown path once the consumer
                // stops iterating; don't surface it as a failure.
                if (error as NSError).code == NSURLErrorCancelled {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: error)
                }
                return
            }
            continuation.finish()
        }

        /// Maps a non-2xx streaming response to an ``AntdError``. The raw body
        /// goes to the mapper first, as in the buffered
        /// ``ensureSuccess(_:data:)`` path, so the envelope's `code` selects
        /// the typed errors (e.g. `CLOSE_GROUP_SHORTFALL`). When no code
        /// applies, the status-based error carries the envelope's `error` text
        /// rather than the raw JSON.
        private static func streamError(status: Int, body: Data) -> AntdError {
            let raw = String(data: body, encoding: .utf8) ?? ""
            let mapped = ErrorMapping.fromHTTPStatus(status, body: raw)
            if mapped.message == raw,
               let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let parsed = obj["error"] as? String {
                return ErrorMapping.fromHTTPStatus(status, body: parsed)
            }
            return mapped
        }
    }

    public func dataCost(_ data: Data, paymentMode: PaymentMode = .auto) async throws -> UploadCostEstimate {
        let body: [String: Any] = [
            "data": data.base64EncodedString(),
            "payment_mode": paymentMode.rawValue,
        ]
        let resp: CostDTO = try await postJSON("/v1/data/cost", body: body)
        return UploadCostEstimate(
            cost: resp.cost,
            fileSize: resp.fileSize ?? 0,
            chunkCount: resp.chunkCount ?? 0,
            estimatedGasCostWei: resp.estimatedGasCostWei ?? "",
            paymentMode: resp.paymentMode ?? "")
    }

    // MARK: - Chunks

    public func chunkPut(_ data: Data) async throws -> PutResult {
        let resp: CostAddressDTO = try await postJSON("/v1/chunks", body: ["data": data.base64EncodedString()])
        return PutResult(cost: resp.cost ?? "", address: resp.address)
    }

    public func chunkGet(address: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/chunks/\(address)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    /// Prepare a single chunk for external-signer publish.
    ///
    /// Returns either ``PrepareChunkResult/alreadyStored`` `= true` (no
    /// payment needed) or a wave-batch payment intent. After the external
    /// signer pays, call ``finalizeChunkUpload(uploadId:txHashes:)`` with the
    /// resulting tx hashes.
    public func prepareChunkUpload(_ data: Data) async throws -> PrepareChunkResult {
        let resp: PrepareChunkDTO = try await postJSON(
            "/v1/chunks/prepare",
            body: ["data": data.base64EncodedString()]
        )
        let payments = (resp.payments ?? []).map {
            PaymentInfo(quoteHash: $0.quoteHash, rewardsAddress: $0.rewardsAddress, amount: $0.amount)
        }
        return PrepareChunkResult(
            address: resp.address,
            alreadyStored: resp.alreadyStored ?? false,
            uploadId: resp.uploadId ?? "",
            paymentType: resp.paymentType ?? "",
            payments: payments,
            totalAmount: resp.totalAmount ?? "",
            paymentVaultAddress: resp.paymentVaultAddress ?? "",
            paymentTokenAddress: resp.paymentTokenAddress ?? "",
            rpcUrl: resp.rpcUrl ?? ""
        )
    }

    /// Submit a prepared chunk to the network after external payment.
    /// Returns the network address of the stored chunk (matches
    /// ``PrepareChunkResult/address``).
    public func finalizeChunkUpload(uploadId: String, txHashes: [String: String]) async throws -> String {
        let body: [String: Any] = ["upload_id": uploadId, "tx_hashes": txHashes]
        let resp: AddressDTO = try await postJSON("/v1/chunks/finalize", body: body)
        return resp.address
    }

    // MARK: - Files

    public func filePut(path: String, paymentMode: PaymentMode = .auto) async throws -> FilePutResult {
        let body: [String: Any] = [
            "path": path,
            "payment_mode": paymentMode.rawValue,
        ]
        let resp: FilePutDTO = try await postJSON("/v1/files", body: body)
        return FilePutResult(
            dataMap: resp.dataMap,
            storageCostAtto: resp.storageCostAtto,
            gasCostWei: resp.gasCostWei,
            chunksStored: resp.chunksStored,
            paymentModeUsed: resp.paymentModeUsed,
            sha256: ManifestWire.nonEmpty(resp.sha256)
        )
    }

    public func fileGet(dataMap: String, destPath: String) async throws {
        try await postJSONNoResult("/v1/files/get", body: ["data_map": dataMap, "dest_path": destPath])
    }

    public func filePutPublic(path: String, paymentMode: PaymentMode = .auto) async throws -> FilePutPublicResult {
        let body: [String: Any] = [
            "path": path,
            "payment_mode": paymentMode.rawValue,
        ]
        let resp: FilePutPublicDTO = try await postJSON("/v1/files/public", body: body)
        return FilePutPublicResult(
            address: resp.address,
            storageCostAtto: resp.storageCostAtto,
            gasCostWei: resp.gasCostWei,
            chunksStored: resp.chunksStored,
            paymentModeUsed: resp.paymentModeUsed,
            sha256: ManifestWire.nonEmpty(resp.sha256)
        )
    }

    public func fileGetPublic(address: String, destPath: String) async throws {
        try await postJSONNoResult("/v1/files/public/get", body: ["address": address, "dest_path": destPath])
    }

    public func fileCost(path: String, isPublic: Bool = true, paymentMode: PaymentMode = .auto) async throws -> UploadCostEstimate {
        let body: [String: Any] = [
            "path": path,
            "is_public": isPublic,
            "payment_mode": paymentMode.rawValue,
        ]
        let resp: CostDTO = try await postJSON("/v1/files/cost", body: body)
        return UploadCostEstimate(
            cost: resp.cost,
            fileSize: resp.fileSize ?? 0,
            chunkCount: resp.chunkCount ?? 0,
            estimatedGasCostWei: resp.estimatedGasCostWei ?? "",
            paymentMode: resp.paymentMode ?? "")
    }

    // MARK: - Wallet

    public func walletAddress() async throws -> WalletAddress {
        let resp: WalletAddressDTO = try await getJSON("/v1/wallet/address")
        return WalletAddress(address: resp.address)
    }

    public func walletBalance() async throws -> WalletBalance {
        let resp: WalletBalanceDTO = try await getJSON("/v1/wallet/balance")
        return WalletBalance(balance: resp.balance, gasBalance: resp.gasBalance)
    }

    /// Approves the wallet to spend tokens on payment contracts (one-time operation).
    public func walletApprove() async throws -> Bool {
        let resp: WalletApproveDTO = try await postJSON("/v1/wallet/approve", body: [:] as [String: Any])
        return resp.approved
    }

    // MARK: - External Signer (Two-Phase Upload)

    /// Prepares a file upload for external signing.
    ///
    /// - Parameters:
    ///   - path: Path to the file to upload.
    ///   - visibility: ``"public"`` bundles the DataMap chunk into the same
    ///     external-signer payment batch — the resulting
    ///     ``FinalizeUploadResult/dataMapAddress`` on finalize is the
    ///     shareable retrieval handle. ``"private"`` or `nil` keeps the
    ///     existing private-only behaviour. The field is omitted from the
    ///     wire request when `nil`, preserving compatibility with daemons
    ///     that predate the public-prepare wire shape.
    public func prepareUpload(path: String, visibility: String? = nil) async throws -> PrepareUploadResult {
        var body: [String: Any] = ["path": path]
        if let visibility = visibility { body["visibility"] = visibility }
        let resp: PrepareUploadDTO = try await postJSON("/v1/upload/prepare", body: body)
        return mapPrepareDTO(resp)
    }

    /// Convenience wrapper: prepare a *public* file upload for external signing.
    /// Equivalent to ``prepareUpload(path:visibility:)`` with `visibility: "public"`.
    public func prepareUploadPublic(path: String) async throws -> PrepareUploadResult {
        try await prepareUpload(path: path, visibility: "public")
    }

    /// Prepares a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    public func prepareDataUpload(_ data: Data) async throws -> PrepareUploadResult {
        let resp: PrepareUploadDTO = try await postJSON("/v1/data/prepare", body: ["data": data.base64EncodedString()])
        return mapPrepareDTO(resp)
    }

    /// Finalizes a wave-batch upload after an external signer has submitted payment transactions.
    ///
    /// Throws ``PartialUploadError`` when some chunks stayed unstored after the
    /// daemon's retries. The on-chain payment persists and the stored chunks
    /// stay on the network; how to finish depends on
    /// ``PartialUploadError/retryable`` and
    /// ``PartialUploadError/retentionKnown``:
    ///
    /// - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt under
    ///   the same `uploadId`. Call this method again with the **same**
    ///   arguments (same `uploadId`, same payment artefacts) to store the
    ///   remainder against the same payment — no re-prepare, no second
    ///   signature, no double payment. Bound that loop: a persistent failure
    ///   throws on every call, so cap the attempts and treat a
    ///   ``PartialUploadError/chunksFailed`` that stops shrinking as stuck.
    /// - `retentionKnown && !retryable`: the daemon confirmed nothing was
    ///   retained (for example a merkle finalize with deliberately unpaid
    ///   batches). Re-prepare the same content; already stored chunks are
    ///   skipped, so the retry pays only for the remainder.
    /// - `!retentionKnown`: retention is unknown, and the daemon may still
    ///   hold the paid attempt. Stop automatic recovery, keep the `uploadId`
    ///   and the original payment artefacts, and reconcile before
    ///   re-preparing or paying again. Never pay again on this signal alone.
    ///   Daemons older than 0.14.0 never send `retryable`, so their REST
    ///   partial uploads read as unknown.
    ///
    /// See `docs/external-signer-flow.md` §6.
    public func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult {
        let body: [String: Any] = ["upload_id": uploadId, "tx_hashes": txHashes]
        let resp: FinalizeUploadDTO = try await postJSON("/v1/upload/finalize", body: body)
        return FinalizeUploadResult(
            address: resp.address ?? "",
            chunksStored: resp.chunksStored,
            dataMap: resp.dataMap ?? "",
            dataMapAddress: resp.dataMapAddress ?? "",
            sha256: ManifestWire.nonEmpty(resp.sha256)
        )
    }

    /// Finalizes a merkle batch upload after the external signer has submitted
    /// the `payForMerkleTree` transaction. `winnerPoolHash` is the bytes32 value
    /// from the `MerklePaymentMade` event (hex with 0x prefix).
    ///
    /// Throws ``PartialUploadError`` when some chunks stayed unstored after the
    /// daemon's retries. The on-chain payment persists and the stored chunks
    /// stay on the network; how to finish depends on
    /// ``PartialUploadError/retryable`` and
    /// ``PartialUploadError/retentionKnown``:
    ///
    /// - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt under
    ///   the same `uploadId`. Call this method again with the **same**
    ///   arguments (same `uploadId`, same payment artefacts) to store the
    ///   remainder against the same payment — no re-prepare, no second
    ///   signature, no double payment. Bound that loop: a persistent failure
    ///   throws on every call, so cap the attempts and treat a
    ///   ``PartialUploadError/chunksFailed`` that stops shrinking as stuck.
    /// - `retentionKnown && !retryable`: the daemon confirmed nothing was
    ///   retained (for example a merkle finalize with deliberately unpaid
    ///   batches). Re-prepare the same content; already stored chunks are
    ///   skipped, so the retry pays only for the remainder.
    /// - `!retentionKnown`: retention is unknown, and the daemon may still
    ///   hold the paid attempt. Stop automatic recovery, keep the `uploadId`
    ///   and the original payment artefacts, and reconcile before
    ///   re-preparing or paying again. Never pay again on this signal alone.
    ///   Daemons older than 0.14.0 never send `retryable`, so their REST
    ///   partial uploads read as unknown.
    ///
    /// See `docs/external-signer-flow.md` §6.
    public func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult {
        let body: [String: Any] = ["upload_id": uploadId, "winner_pool_hash": winnerPoolHash]
        let resp: FinalizeUploadDTO = try await postJSON("/v1/upload/finalize", body: body)
        return FinalizeMerkleUploadResult(
            address: resp.address ?? "",
            chunksStored: resp.chunksStored,
            dataMap: resp.dataMap ?? "",
            dataMapAddress: resp.dataMapAddress ?? "",
            sha256: ManifestWire.nonEmpty(resp.sha256)
        )
    }

    // MARK: - Pointers
    //
    // A pointer's owner key lives in the daemon (`antd --pointer-keys`); a
    // write names the pointer by its address. Every write pays, and every
    // attempt pays again: nothing here retries a create, update, transfer or
    // finalize. Reads are free to retry; a read during an update or churn can
    // throw `CloseGroupShortfallError`.

    public func pointerKeys() async throws -> [PointerKey] {
        let resp: PointerKeysDTO = try await getJSON("/v1/pointers/keys")
        return (resp.keys ?? []).map { PointerKey(address: $0.address ?? "") }
    }

    /// Creates the pointer at `owner`, paid by the daemon wallet
    /// (`POST /v1/pointers`). Pays once and is never retried; see
    /// ``AntdClientProtocol/pointerCreate(owner:target:kind:)``.
    public func pointerCreate(owner: String, target: String, kind: PointerKind = .chunk) async throws -> PointerWriteResult {
        try await pointerWrite("/v1/pointers", owner: owner, target: target, kind: kind)
    }

    /// Points the pointer at `owner` at `target`, paid by the daemon wallet
    /// (`POST /v1/pointers/update`). Pays once and is never retried; see
    /// ``AntdClientProtocol/pointerUpdate(owner:target:kind:)``.
    public func pointerUpdate(owner: String, target: String, kind: PointerKind = .chunk) async throws -> PointerWriteResult {
        try await pointerWrite("/v1/pointers/update", owner: owner, target: target, kind: kind)
    }

    private func pointerWrite(_ path: String, owner: String, target: String, kind: PointerKind) async throws -> PointerWriteResult {
        let body: [String: Any] = ["owner": owner, "target": target, "kind": kind.rawValue]
        let resp: PointerWriteDTO = try await postJSON(path, body: body)
        return try resp.toModel()
    }

    /// Hands the pointer at `owner` over to `recipient` for good, paid by the
    /// daemon wallet (`POST /v1/pointers/transfer`). Pays once and is never
    /// retried; see ``AntdClientProtocol/pointerTransfer(owner:recipient:)``.
    public func pointerTransfer(owner: String, recipient: String) async throws -> PointerTransferResult {
        let body: [String: Any] = ["owner": owner, "recipient": recipient]
        let resp: PointerTransferDTO = try await postJSON("/v1/pointers/transfer", body: body)
        return PointerTransferResult(
            address: resp.address ?? "",
            stateId: resp.stateId ?? "",
            finality: try resp.finality?.toModel(),
            finalityError: PointerWire.nonEmpty(resp.finalityError)
        )
    }

    /// `GET /v1/pointers/{address}`.
    public func pointerGet(address: String) async throws -> PointerRecord {
        let resp: PointerRecordDTO = try await getJSON("/v1/pointers/\(address)")
        return PointerRecord(
            address: resp.address ?? "",
            owner: resp.owner ?? "",
            counter: try PointerWire.counter("counter", resp.counter),
            kind: resp.kind ?? "",
            kindTag: PointerWire.kindTag(resp.kindTag),
            target: resp.target ?? "",
            stateId: resp.stateId ?? "",
            isFinal: resp.isFinal ?? false,
            transferredTo: PointerWire.nonEmpty(resp.transferredTo)
        )
    }

    /// `GET /v1/pointers/{address}/resolve`.
    public func pointerResolve(address: String) async throws -> PointerTarget {
        let resp: PointerTargetDTO = try await getJSON("/v1/pointers/\(address)/resolve")
        return PointerTarget(
            kind: resp.kind ?? "",
            kindTag: PointerWire.kindTag(resp.kindTag),
            target: resp.target ?? ""
        )
    }

    /// `GET /v1/pointers/{address}/finality`.
    public func pointerFinality(address: String) async throws -> PointerFinality {
        let resp: PointerFinalityDTO = try await getJSON("/v1/pointers/\(address)/finality")
        return try resp.toModel()
    }

    /// `GET /v1/pointers/{address}/controller`.
    public func pointerController(address: String) async throws -> PointerController {
        let resp: PointerControllerDTO = try await getJSON("/v1/pointers/\(address)/controller")
        return PointerController(
            pointer: resp.pointer ?? "",
            transfers: resp.transfers ?? [],
            frozen: resp.frozen ?? false
        )
    }

    /// `POST /v1/pointers/prepare`: the daemon signs `op` and quotes it for an
    /// external signer. See
    /// ``AntdClientProtocol/pointerPrepare(owner:op:options:)``.
    public func pointerPrepare(owner: String, op: PointerOp, options: PointerPrepareOptions) async throws -> PointerPrepareResult {
        var body: [String: Any] = ["owner": owner, "op": op.wireName]
        switch op {
        case .create(let target, let kind), .update(let target, let kind):
            body["target"] = target
            body["kind"] = kind.rawValue
        case .transfer(let recipient):
            body["recipient"] = recipient
        }
        if options.includeSignedQuotes { body["include_signed_quotes"] = true }
        let resp: PointerPrepareDTO = try await postJSON("/v1/pointers/prepare", body: body)
        return PointerPrepareResult(
            uploadId: resp.uploadId ?? "",
            op: resp.op ?? "",
            address: resp.address ?? "",
            stateId: resp.stateId ?? "",
            counter: try PointerWire.counter("counter", resp.counter),
            paymentType: resp.paymentType ?? "",
            payments: (resp.payments ?? []).map {
                PaymentInfo(quoteHash: $0.quoteHash, rewardsAddress: $0.rewardsAddress, amount: $0.amount)
            },
            totalAmount: resp.totalAmount ?? "",
            paymentVaultAddress: resp.paymentVaultAddress ?? "",
            paymentTokenAddress: resp.paymentTokenAddress ?? "",
            rpcUrl: resp.rpcUrl ?? "",
            signedQuotes: (resp.signedQuotes ?? []).map {
                SignedQuoteEntry(
                    quoteHash: $0.quoteHash ?? "",
                    quote: $0.quote ?? "",
                    commitmentSidecar: PointerWire.nonEmpty($0.commitmentSidecar)
                )
            }
        )
    }

    /// `POST /v1/pointers/finalize`: stores a prepared write once it is paid.
    /// Never retried here; see
    /// ``AntdClientProtocol/pointerFinalize(uploadId:txHashes:)`` for the
    /// `retryable` contract.
    public func pointerFinalize(uploadId: String, txHashes: [String: String]) async throws -> PointerFinalizeResult {
        let body: [String: Any] = ["upload_id": uploadId, "tx_hashes": txHashes]
        let resp: PointerFinalizeDTO = try await postJSON("/v1/pointers/finalize", body: body)
        return PointerFinalizeResult(
            address: resp.address ?? "",
            stateId: resp.stateId ?? "",
            counter: try PointerWire.counter("counter", resp.counter),
            finality: try resp.finality?.toModel()
        )
    }

    // MARK: - Prepare DTO Mapping

    private func mapPrepareDTO(_ resp: PrepareUploadDTO) -> PrepareUploadResult {
        let payments = (resp.payments ?? []).map { PaymentInfo(quoteHash: $0.quoteHash, rewardsAddress: $0.rewardsAddress, amount: $0.amount) }
        let poolCommitments = resp.poolCommitments?.map { pc in
            PoolCommitmentEntry(
                poolHash: pc.poolHash,
                candidates: pc.candidates.map { CandidateNodeEntry(rewardsAddress: $0.rewardsAddress, amount: $0.amount) }
            )
        }
        return PrepareUploadResult(
            uploadId: resp.uploadId,
            payments: payments,
            totalAmount: resp.totalAmount,
            paymentVaultAddress: resp.paymentVaultAddress,
            paymentTokenAddress: resp.paymentTokenAddress,
            rpcUrl: resp.rpcUrl,
            paymentType: resp.paymentType ?? "wave_batch",
            depth: resp.depth,
            poolCommitments: poolCommitments,
            merklePaymentTimestamp: resp.merklePaymentTimestamp,
            totalChunks: resp.totalChunks ?? 0,
            alreadyStoredCount: resp.alreadyStoredCount ?? 0
        )
    }
}

// MARK: - Internal DTOs

private struct HealthResponseDTO: Decodable {
    let status: String?
    let network: String?
    let version: String?
    let evm_network: String?
    let uptime_seconds: UInt64?
    let build_commit: String?
    let payment_token_address: String?
    let payment_vault_address: String?

    func toHealthStatus() -> HealthStatus {
        HealthStatus(
            ok: status == "ok",
            network: network ?? "unknown",
            version: version ?? "",
            evmNetwork: evm_network ?? "",
            uptimeSeconds: uptime_seconds ?? 0,
            buildCommit: build_commit ?? "",
            paymentTokenAddress: payment_token_address ?? "",
            paymentVaultAddress: payment_vault_address ?? ""
        )
    }
}

private struct CostAddressDTO: Decodable {
    // PUT responses sometimes omit `cost`; default to empty downstream (#69 in PR queue).
    let cost: String?
    let address: String
}

// Wire fields are snake_case; the shared JSONDecoder uses .convertFromSnakeCase,
// so property names are camelCase here. Adding explicit CodingKeys would
// suppress that strategy (the decoder skips the conversion when CodingKeys are
// present and matches against the raw values verbatim) and silently nil out
// every snake_case-named field.
private struct DataPutDTO: Decodable {
    let dataMap: String
    let chunksStored: UInt64?
    let paymentModeUsed: String?
    let sha256: String?
}

private struct DataPutPublicDTO: Decodable {
    let address: String
    let chunksStored: UInt64?
    let paymentModeUsed: String?
    let sha256: String?
}

private struct FilePutDTO: Decodable {
    let dataMap: String
    let storageCostAtto: String
    let gasCostWei: String
    let chunksStored: UInt64
    let paymentModeUsed: String
    let sha256: String?
}

private struct FilePutPublicDTO: Decodable {
    let address: String
    let storageCostAtto: String
    let gasCostWei: String
    let chunksStored: UInt64
    let paymentModeUsed: String
    let sha256: String?
}

private struct DataDTO: Decodable {
    let data: String
}

private struct CostDTO: Decodable {
    let cost: String
    // Wire fields are snake_case (file_size, chunk_count, …); the shared
    // JSONDecoder uses .convertFromSnakeCase, so name them camelCase here
    // — otherwise decoding silently nils them out and the caller sees zeros.
    let fileSize: UInt64?
    let chunkCount: UInt32?
    let estimatedGasCostWei: String?
    let paymentMode: String?
}

private struct WalletAddressDTO: Decodable {
    let address: String
}

private struct WalletBalanceDTO: Decodable {
    let balance: String
    let gasBalance: String
}

private struct WalletApproveDTO: Decodable {
    let approved: Bool
}

private struct PaymentInfoDTO: Decodable {
    let quoteHash: String
    let rewardsAddress: String
    let amount: String
}

private struct CandidateNodeEntryDTO: Decodable {
    let rewardsAddress: String
    let amount: String
}

private struct PoolCommitmentEntryDTO: Decodable {
    let poolHash: String
    let candidates: [CandidateNodeEntryDTO]
}

private struct PrepareUploadDTO: Decodable {
    let uploadId: String
    let payments: [PaymentInfoDTO]?
    let totalAmount: String
    let paymentVaultAddress: String
    let paymentTokenAddress: String
    let rpcUrl: String
    let paymentType: String?
    let depth: Int?
    let poolCommitments: [PoolCommitmentEntryDTO]?
    let merklePaymentTimestamp: UInt64?
    // Optional so older daemons that omit these still decode (defaulted to 0 on map).
    let totalChunks: UInt64?
    let alreadyStoredCount: UInt64?
}

private struct FinalizeUploadDTO: Decodable {
    let address: String?
    let chunksStored: Int64
    // `data_map` is always present on success but old daemons may omit it;
    // `data_map_address` is populated only when prepare was public.
    let dataMap: String?
    let dataMapAddress: String?
    let sha256: String?
}

private struct PrepareChunkDTO: Decodable {
    let address: String
    let alreadyStored: Bool?
    let uploadId: String?
    let paymentType: String?
    let payments: [PaymentInfoDTO]?
    let totalAmount: String?
    let paymentVaultAddress: String?
    let paymentTokenAddress: String?
    let rpcUrl: String?
}

private struct AddressDTO: Decodable {
    let address: String
}

// Pointer DTOs. Counters are decimal strings on the wire (a final state sits
// at UInt64.max) and are parsed strictly by `PointerWire.counter`; unset
// values arrive as JSON `null`.

private struct PointerKeysDTO: Decodable {
    let keys: [PointerKeyDTO]?
}

private struct PointerKeyDTO: Decodable {
    let address: String?
}

private struct PointerWriteDTO: Decodable {
    let address: String?
    let stateId: String?
    let counter: String?

    func toModel() throws -> PointerWriteResult {
        PointerWriteResult(
            address: address ?? "",
            stateId: stateId ?? "",
            counter: try PointerWire.counter("counter", counter)
        )
    }
}

private struct PointerRecordDTO: Decodable {
    let address: String?
    let owner: String?
    let counter: String?
    let kind: String?
    let kindTag: UInt64?
    let target: String?
    let stateId: String?
    let isFinal: Bool?
    let transferredTo: String?
}

private struct PointerTargetDTO: Decodable {
    let kind: String?
    let kindTag: UInt64?
    let target: String?
}

private struct PointerFinalStateDTO: Decodable {
    let stateId: String?
    let kind: String?
    let kindTag: UInt64?
    let target: String?
    let holders: UInt64?
    let transferredTo: String?

    func toModel() -> PointerFinalState {
        PointerFinalState(
            stateId: stateId ?? "",
            kind: kind ?? "",
            kindTag: PointerWire.kindTag(kindTag),
            target: target ?? "",
            holders: UInt32(clamping: holders ?? 0),
            transferredTo: PointerWire.nonEmpty(transferredTo)
        )
    }
}

private struct PointerFinalityDTO: Decodable {
    let address: String?
    let group: UInt64?
    let answered: UInt64?
    let status: String?
    let counter: String?
    let state: PointerFinalStateDTO?
    let states: [PointerFinalStateDTO]?
    let majority: PointerFinalStateDTO?
    let transferredTo: String?

    func toModel() throws -> PointerFinality {
        PointerFinality(
            address: address ?? "",
            group: UInt32(clamping: group ?? 0),
            answered: UInt32(clamping: answered ?? 0),
            status: PointerFinalityStatus(wire: status ?? ""),
            counter: try PointerWire.optionalCounter("counter", counter),
            state: state?.toModel(),
            states: (states ?? []).map { $0.toModel() },
            majority: majority?.toModel(),
            transferredTo: PointerWire.nonEmpty(transferredTo)
        )
    }
}

private struct PointerTransferDTO: Decodable {
    let address: String?
    let stateId: String?
    let finality: PointerFinalityDTO?
    let finalityError: String?
}

private struct PointerControllerDTO: Decodable {
    let pointer: String?
    let transfers: [String]?
    let frozen: Bool?
}

private struct SignedQuoteDTO: Decodable {
    let quoteHash: String?
    let quote: String?
    let commitmentSidecar: String?
}

private struct PointerPrepareDTO: Decodable {
    let uploadId: String?
    let op: String?
    let address: String?
    let stateId: String?
    let counter: String?
    let paymentType: String?
    let payments: [PaymentInfoDTO]?
    let totalAmount: String?
    let paymentVaultAddress: String?
    let paymentTokenAddress: String?
    let rpcUrl: String?
    let signedQuotes: [SignedQuoteDTO]?
}

private struct PointerFinalizeDTO: Decodable {
    let address: String?
    let stateId: String?
    let counter: String?
    let finality: PointerFinalityDTO?
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
