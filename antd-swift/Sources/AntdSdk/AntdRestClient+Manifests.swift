import Foundation

// MARK: - Manifests (REST)
//
// `POST /v1/manifests/build` and `POST /v1/manifests/decode`. The `.ant` bytes
// travel as base64 in the JSON (`manifest` in the build response and the
// decode request); callers only ever see raw `Data`. The daemon omits unset
// fields, so an absent `size` or `exact_size` reads as `nil`. Nothing is
// uploaded or paid for. See ``AntdClientProtocol/buildManifest(entries:options:)``.

extension AntdRestClient {

    /// `POST /v1/manifests/build`. See
    /// ``AntdClientProtocol/buildManifest(entries:options:)``.
    public func buildManifest(entries: [ManifestEntryInput], options: BuildManifestOptions) async throws -> BuiltManifest {
        try ManifestWire.checkEntries(entries)
        var body: [String: Any] = [
            "entries": entries.map(Self.manifestEntryJSON),
            // Always sent, so the default (embed) does not depend on the
            // daemon's.
            "embed_roots": options.embedRoots,
        ]
        if let name = ManifestWire.nonEmpty(options.name) { body["name"] = name }
        if !options.torrentInfoHashes.isEmpty { body["torrent_info_hashes"] = options.torrentInfoHashes }
        let resp: BuildManifestDTO = try await postJSON("/v1/manifests/build", body: body)
        guard let manifest = Data(base64Encoded: resp.manifest ?? "") else {
            throw InternalError("buildManifest: the daemon's manifest is not valid base64")
        }
        return BuiltManifest(
            manifest: manifest,
            link: ManifestWire.nonEmpty(resp.link),
            entries: (resp.entries ?? []).map { $0.toModel() }
        )
    }

    /// `POST /v1/manifests/decode` with the bytes (sent as base64). See
    /// ``AntdClientProtocol/decodeManifest(_:resolve:)``.
    public func decodeManifest(_ manifest: Data, resolve: Bool) async throws -> DecodedManifest {
        try ManifestWire.checkManifest(manifest)
        return try await postManifestDecode(["manifest": manifest.base64EncodedString(), "resolve": resolve])
    }

    /// `POST /v1/manifests/decode` with a link. See
    /// ``AntdClientProtocol/decodeManifestLink(_:resolve:)``.
    public func decodeManifestLink(_ link: String, resolve: Bool) async throws -> DecodedManifest {
        try ManifestWire.checkLink(link)
        return try await postManifestDecode(["link": link, "resolve": resolve])
    }

    private func postManifestDecode(_ body: [String: Any]) async throws -> DecodedManifest {
        let resp: DecodeManifestDTO = try await postJSON("/v1/manifests/decode", body: body)
        return DecodedManifest(
            source: resp.source ?? "",
            name: resp.name,
            torrentInfoHashV1: ManifestWire.nonEmpty(resp.torrentInfoHashV1),
            torrentInfoHashV2: ManifestWire.nonEmpty(resp.torrentInfoHashV2),
            entries: (resp.entries ?? []).map { $0.toModel() }
        )
    }

    /// One entry as the daemon reads it: unset fields are left out, and
    /// exactly one of `data_map` or `address` is sent (checked beforehand).
    private static func manifestEntryJSON(_ entry: ManifestEntryInput) -> [String: Any] {
        var json: [String: Any] = [:]
        if let path = ManifestWire.nonEmpty(entry.path) { json["path"] = path }
        if let size = entry.size { json["size"] = size }
        if let dataMap = ManifestWire.nonEmpty(entry.dataMap) {
            json["data_map"] = dataMap
        } else if let address = ManifestWire.nonEmpty(entry.address) {
            json["address"] = address
        }
        return json
    }
}

// Wire fields are snake_case and decoded with JSONDecoder.snakeCase, so the
// properties are camelCase and there are no CodingKeys (see the note on
// DataPutDTO in AntdRestClient.swift).

private struct ManifestEntryInfoDTO: Decodable {
    let effectiveName: String?
    let path: String?
    let size: UInt64?
    let kind: String?
    let contentAddress: String?
    let dataMap: String?
    let exactSize: UInt64?
    let error: String?

    func toModel() -> ManifestEntryInfo {
        ManifestEntryInfo(
            effectiveName: effectiveName ?? "",
            path: path,
            size: size,
            kind: kind ?? "",
            contentAddress: contentAddress ?? "",
            dataMap: ManifestWire.nonEmpty(dataMap),
            exactSize: exactSize,
            error: ManifestWire.nonEmpty(error)
        )
    }
}

private struct BuildManifestDTO: Decodable {
    /// The `.ant` bytes, base64.
    let manifest: String?
    let link: String?
    let entries: [ManifestEntryInfoDTO]?
}

private struct DecodeManifestDTO: Decodable {
    let source: String?
    let name: String?
    let torrentInfoHashV1: String?
    let torrentInfoHashV2: String?
    let entries: [ManifestEntryInfoDTO]?
}
