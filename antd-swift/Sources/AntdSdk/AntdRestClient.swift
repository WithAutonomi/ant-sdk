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

    private func postJSON<T: Decodable>(_ path: String, body: Any) async throws -> T {
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
            paymentModeUsed: resp.paymentModeUsed ?? ""
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
            paymentModeUsed: resp.paymentModeUsed ?? ""
        )
    }

    public func dataGetPublic(address: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/data/public/\(address)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
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
            paymentModeUsed: resp.paymentModeUsed
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
            paymentModeUsed: resp.paymentModeUsed
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
    public func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult {
        let body: [String: Any] = ["upload_id": uploadId, "tx_hashes": txHashes]
        let resp: FinalizeUploadDTO = try await postJSON("/v1/upload/finalize", body: body)
        return FinalizeUploadResult(
            address: resp.address ?? "",
            chunksStored: resp.chunksStored,
            dataMap: resp.dataMap ?? "",
            dataMapAddress: resp.dataMapAddress ?? ""
        )
    }

    /// Finalizes a merkle batch upload after the external signer has submitted
    /// the `payForMerkleTree` transaction. `winnerPoolHash` is the bytes32 value
    /// from the `MerklePaymentMade` event (hex with 0x prefix).
    public func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult {
        let body: [String: Any] = ["upload_id": uploadId, "winner_pool_hash": winnerPoolHash]
        let resp: FinalizeUploadDTO = try await postJSON("/v1/upload/finalize", body: body)
        return FinalizeMerkleUploadResult(
            address: resp.address ?? "",
            chunksStored: resp.chunksStored,
            dataMap: resp.dataMap ?? "",
            dataMapAddress: resp.dataMapAddress ?? ""
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
}

private struct DataPutPublicDTO: Decodable {
    let address: String
    let chunksStored: UInt64?
    let paymentModeUsed: String?
}

private struct FilePutDTO: Decodable {
    let dataMap: String
    let storageCostAtto: String
    let gasCostWei: String
    let chunksStored: UInt64
    let paymentModeUsed: String
}

private struct FilePutPublicDTO: Decodable {
    let address: String
    let storageCostAtto: String
    let gasCostWei: String
    let chunksStored: UInt64
    let paymentModeUsed: String
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

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
