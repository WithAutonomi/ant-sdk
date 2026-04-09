import Foundation

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
            return HealthStatus(ok: resp.status == "ok", network: resp.network ?? "unknown")
        } catch {
            return HealthStatus(ok: false, network: "unknown")
        }
    }

    // MARK: - Data

    public func dataPutPublic(_ data: Data, paymentMode: String? = nil) async throws -> PutResult {
        var body: [String: Any] = ["data": data.base64EncodedString()]
        if let mode = paymentMode { body["payment_mode"] = mode }
        let resp: CostAddressDTO = try await postJSON("/v1/data/public", body: body)
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func dataGetPublic(address: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/data/public/\(address)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    public func dataPutPrivate(_ data: Data, paymentMode: String? = nil) async throws -> PutResult {
        var body: [String: Any] = ["data": data.base64EncodedString()]
        if let mode = paymentMode { body["payment_mode"] = mode }
        let resp: CostDataMapDTO = try await postJSON("/v1/data/private", body: body)
        return PutResult(cost: resp.cost, address: resp.dataMap)
    }

    public func dataGetPrivate(dataMap: String) async throws -> Data {
        let encodedMap = dataMap.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dataMap
        let resp: DataDTO = try await getJSON("/v1/data/private?data_map=\(encodedMap)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    public func dataCost(_ data: Data) async throws -> String {
        let resp: CostDTO = try await postJSON("/v1/data/cost", body: ["data": data.base64EncodedString()])
        return resp.cost
    }

    // MARK: - Chunks

    public func chunkPut(_ data: Data) async throws -> PutResult {
        let resp: CostAddressDTO = try await postJSON("/v1/chunks", body: ["data": data.base64EncodedString()])
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func chunkGet(address: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/chunks/\(address)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    // MARK: - Files

    public func fileUploadPublic(path: String, paymentMode: String? = nil) async throws -> PutResult {
        var body: [String: Any] = ["path": path]
        if let mode = paymentMode { body["payment_mode"] = mode }
        let resp: CostAddressDTO = try await postJSON("/v1/files/upload/public", body: body)
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func fileDownloadPublic(address: String, destPath: String) async throws {
        try await postJSONNoResult("/v1/files/download/public", body: ["address": address, "dest_path": destPath])
    }

    public func dirUploadPublic(path: String, paymentMode: String? = nil) async throws -> PutResult {
        var body: [String: Any] = ["path": path]
        if let mode = paymentMode { body["payment_mode"] = mode }
        let resp: CostAddressDTO = try await postJSON("/v1/dirs/upload/public", body: body)
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func dirDownloadPublic(address: String, destPath: String) async throws {
        try await postJSONNoResult("/v1/dirs/download/public", body: ["address": address, "dest_path": destPath])
    }

    public func fileCost(path: String, isPublic: Bool = true) async throws -> String {
        let body: [String: Any] = ["path": path, "is_public": isPublic]
        let resp: CostDTO = try await postJSON("/v1/cost/file", body: body)
        return resp.cost
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
    public func prepareUpload(path: String) async throws -> PrepareUploadResult {
        let resp: PrepareUploadDTO = try await postJSON("/v1/upload/prepare", body: ["path": path])
        return mapPrepareDTO(resp)
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
        return FinalizeUploadResult(address: resp.address, chunksStored: resp.chunksStored)
    }

    /// Finalizes a merkle batch upload after the external signer has submitted
    /// the `payForMerkleTree` transaction. `winnerPoolHash` is the bytes32 value
    /// from the `MerklePaymentMade` event (hex with 0x prefix).
    public func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult {
        let body: [String: Any] = ["upload_id": uploadId, "winner_pool_hash": winnerPoolHash]
        let resp: FinalizeUploadDTO = try await postJSON("/v1/upload/finalize", body: body)
        return FinalizeMerkleUploadResult(address: resp.address, chunksStored: resp.chunksStored)
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
            merklePaymentTimestamp: resp.merklePaymentTimestamp
        )
    }
}

// MARK: - Internal DTOs

private struct HealthResponseDTO: Decodable {
    let status: String?
    let network: String?
}

private struct CostAddressDTO: Decodable {
    let cost: String
    let address: String
}

private struct CostDataMapDTO: Decodable {
    let cost: String
    let dataMap: String
}

private struct DataDTO: Decodable {
    let data: String
}

private struct CostDTO: Decodable {
    let cost: String
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
}

private struct FinalizeUploadDTO: Decodable {
    let address: String
    let chunksStored: Int64
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
