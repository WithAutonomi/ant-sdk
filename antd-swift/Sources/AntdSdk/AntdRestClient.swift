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
        let url = URL(string: "\(baseURL)\(path)")!
        let (data, response) = try await session.data(from: url)
        try ensureSuccess(response, data: data)
        return try JSONDecoder.snakeCase.decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(_ path: String, body: Any) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response, data: data)
        return try JSONDecoder.snakeCase.decode(T.self, from: data)
    }

    private func postJSONNoResult(_ path: String, body: Any) async throws {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response, data: data)
    }

    private func headExists(_ path: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)\(path)")!
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

    public func dataPutPublic(_ data: Data) async throws -> PutResult {
        let resp: CostAddressDTO = try await postJSON("/v1/data/public", body: ["data": data.base64EncodedString()])
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func dataGetPublic(address: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/data/public/\(address)")
        guard let decoded = Data(base64Encoded: resp.data) else { throw BadRequestError("Invalid base64 data") }
        return decoded
    }

    public func dataPutPrivate(_ data: Data) async throws -> PutResult {
        let resp: CostDataMapDTO = try await postJSON("/v1/data/private", body: ["data": data.base64EncodedString()])
        return PutResult(cost: resp.cost, address: resp.dataMap)
    }

    public func dataGetPrivate(dataMap: String) async throws -> Data {
        let resp: DataDTO = try await getJSON("/v1/data/private?data_map=\(dataMap)")
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

    // MARK: - Graph

    public func graphEntryPut(ownerSecretKey: String, parents: [String], content: String, descendants: [GraphDescendant]) async throws -> PutResult {
        let body: [String: Any] = [
            "owner_secret_key": ownerSecretKey,
            "parents": parents,
            "content": content,
            "descendants": descendants.map { ["public_key": $0.publicKey, "content": $0.content] },
        ]
        let resp: CostAddressDTO = try await postJSON("/v1/graph", body: body)
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func graphEntryGet(address: String) async throws -> GraphEntry {
        let resp: GraphEntryDTO = try await getJSON("/v1/graph/\(address)")
        let desc = (resp.descendants ?? []).map { GraphDescendant(publicKey: $0.publicKey, content: $0.content) }
        return GraphEntry(owner: resp.owner, parents: resp.parents ?? [], content: resp.content, descendants: desc)
    }

    public func graphEntryExists(address: String) async throws -> Bool {
        try await headExists("/v1/graph/\(address)")
    }

    public func graphEntryCost(publicKey: String) async throws -> String {
        let resp: CostDTO = try await postJSON("/v1/graph/cost", body: ["public_key": publicKey])
        return resp.cost
    }

    // MARK: - Files

    public func fileUploadPublic(path: String) async throws -> PutResult {
        let resp: CostAddressDTO = try await postJSON("/v1/files/upload/public", body: ["path": path])
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func fileDownloadPublic(address: String, destPath: String) async throws {
        try await postJSONNoResult("/v1/files/download/public", body: ["address": address, "dest_path": destPath])
    }

    public func dirUploadPublic(path: String) async throws -> PutResult {
        let resp: CostAddressDTO = try await postJSON("/v1/dirs/upload/public", body: ["path": path])
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func dirDownloadPublic(address: String, destPath: String) async throws {
        try await postJSONNoResult("/v1/dirs/download/public", body: ["address": address, "dest_path": destPath])
    }

    public func archiveGetPublic(address: String) async throws -> Archive {
        let resp: ArchiveDTO = try await getJSON("/v1/archives/public/\(address)")
        let entries = (resp.entries ?? []).map { ArchiveEntry(path: $0.path, address: $0.address, created: $0.created, modified: $0.modified, size: $0.size) }
        return Archive(entries: entries)
    }

    public func archivePutPublic(archive: Archive) async throws -> PutResult {
        let body: [String: Any] = [
            "entries": archive.entries.map { [
                "path": $0.path, "address": $0.address,
                "created": $0.created, "modified": $0.modified, "size": $0.size,
            ] as [String: Any] },
        ]
        let resp: CostAddressDTO = try await postJSON("/v1/archives/public", body: body)
        return PutResult(cost: resp.cost, address: resp.address)
    }

    public func fileCost(path: String, isPublic: Bool = true, includeArchive: Bool = false) async throws -> String {
        let body: [String: Any] = ["path": path, "is_public": isPublic, "include_archive": includeArchive]
        let resp: CostDTO = try await postJSON("/v1/cost/file", body: body)
        return resp.cost
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

private struct GraphDescendantDTO: Decodable {
    let publicKey: String
    let content: String
}

private struct GraphEntryDTO: Decodable {
    let owner: String
    let parents: [String]?
    let content: String
    let descendants: [GraphDescendantDTO]?
}

private struct ArchiveEntryDTO: Decodable {
    let path: String
    let address: String
    let created: UInt64
    let modified: UInt64
    let size: UInt64
}

private struct ArchiveDTO: Decodable {
    let entries: [ArchiveEntryDTO]?
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
