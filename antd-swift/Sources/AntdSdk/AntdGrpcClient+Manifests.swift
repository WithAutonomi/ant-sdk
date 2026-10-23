import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf

// MARK: - Manifests (gRPC)
//
// `ManifestService` Build and Decode, the twins of the REST methods on
// ``AntdRestClient``. The `.ant` bytes are proto `bytes`, so no base64 is
// involved. Unset sizes are proto3 `optional`, read by presence
// (`hasSize`, `hasExactSize`), never by their zero value. INVALID_ARGUMENT
// (a bad entry, named `entries[i]`) maps to ``BadRequestError`` like every
// other call. Nothing is uploaded or paid for.

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension AntdGrpcClient {

    /// The message-size ceiling for manifest calls, both ways: 256 MiB, as
    /// antd-go's `maxManifestGrpcMessage`. A manifest can be 64 MiB, a Build
    /// response carries it, a Decode request sends it, and a Decode response
    /// carries its DataMaps in hex. grpc-swift's default is 4 MiB.
    static var maxManifestMessageBytes: Int { 256 * 1024 * 1024 }

    /// The per-call options for every manifest RPC: both message limits
    /// raised to ``maxManifestMessageBytes``. Only the manifest calls get
    /// them; every other call keeps grpc-swift's defaults.
    ///
    /// Both limits are set because the HTTP/2 transport
    /// (grpc-swift-nio-transport 1.x) applies `maxRequestMessageBytes`, not
    /// `maxResponseMessageBytes`, as the limit on the messages a client
    /// stream *receives*, and enforces no send limit of its own. Setting both
    /// keeps the raised limit in force if a later transport reads the
    /// response option as its name says.
    static var manifestCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.maxRequestMessageBytes = maxManifestMessageBytes
        options.maxResponseMessageBytes = maxManifestMessageBytes
        return options
    }

    /// `ManifestService.Build`. See
    /// ``AntdClientProtocol/buildManifest(entries:options:)``.
    public func buildManifest(entries: [ManifestEntryInput], options: BuildManifestOptions) async throws -> BuiltManifest {
        try ManifestWire.checkEntries(entries)
        var req = Antd_V1_BuildManifestRequest()
        // Always set, so the default (embed) does not depend on the daemon's.
        req.embedRoots = options.embedRoots
        if let name = ManifestWire.nonEmpty(options.name) { req.name = name }
        req.torrentInfoHashes = options.torrentInfoHashes
        req.entries = entries.map(Self.pbManifestEntry)
        let request = req
        return try await withGRPC { client in
            let resp = try await Antd_V1_ManifestService.Client(wrapping: client)
                .build(request, options: Self.manifestCallOptions)
            return BuiltManifest(
                manifest: resp.manifest,
                link: ManifestWire.nonEmpty(resp.link),
                entries: resp.entries.map(Self.fromPbManifestEntry)
            )
        }
    }

    /// `ManifestService.Decode` with the bytes. See
    /// ``AntdClientProtocol/decodeManifest(_:resolve:)``.
    public func decodeManifest(_ manifest: Data, resolve: Bool) async throws -> DecodedManifest {
        try ManifestWire.checkManifest(manifest)
        var req = Antd_V1_DecodeManifestRequest()
        req.manifest = manifest
        req.resolve = resolve
        return try await callManifestDecode(req)
    }

    /// `ManifestService.Decode` with a link. See
    /// ``AntdClientProtocol/decodeManifestLink(_:resolve:)``.
    public func decodeManifestLink(_ link: String, resolve: Bool) async throws -> DecodedManifest {
        try ManifestWire.checkLink(link)
        var req = Antd_V1_DecodeManifestRequest()
        req.link = link
        req.resolve = resolve
        return try await callManifestDecode(req)
    }

    private func callManifestDecode(_ request: Antd_V1_DecodeManifestRequest) async throws -> DecodedManifest {
        try await withGRPC { client in
            let resp = try await Antd_V1_ManifestService.Client(wrapping: client)
                .decode(request, options: Self.manifestCallOptions)
            return DecodedManifest(
                source: resp.source,
                name: resp.hasName ? resp.name : nil,
                torrentInfoHashV1: ManifestWire.nonEmpty(resp.torrentInfoHashV1),
                torrentInfoHashV2: ManifestWire.nonEmpty(resp.torrentInfoHashV2),
                entries: resp.entries.map(Self.fromPbManifestEntry)
            )
        }
    }

    /// One entry as the daemon reads it: unset fields keep no presence, and
    /// the `source` oneof carries exactly one of `data_map` or `address`
    /// (checked beforehand).
    private static func pbManifestEntry(_ entry: ManifestEntryInput) -> Antd_V1_ManifestEntryInput {
        var pb = Antd_V1_ManifestEntryInput()
        if let path = ManifestWire.nonEmpty(entry.path) { pb.path = path }
        if let size = entry.size { pb.size = size }
        if let dataMap = ManifestWire.nonEmpty(entry.dataMap) {
            pb.source = .dataMap(dataMap)
        } else if let address = ManifestWire.nonEmpty(entry.address) {
            pb.source = .address(address)
        }
        // proto3 optional: set only when given, so presence is meaningful.
        if let sha256 = ManifestWire.nonEmpty(entry.sha256) { pb.sha256 = sha256 }
        return pb
    }

    private static func fromPbManifestEntry(_ e: Antd_V1_ManifestEntryInfo) -> ManifestEntryInfo {
        ManifestEntryInfo(
            effectiveName: e.effectiveName,
            path: e.hasPath ? e.path : nil,
            size: e.hasSize ? e.size : nil,
            kind: e.kind,
            contentAddress: e.contentAddress,
            dataMap: ManifestWire.nonEmpty(e.dataMap),
            exactSize: e.hasExactSize ? e.exactSize : nil,
            error: ManifestWire.nonEmpty(e.error),
            sha256: ManifestWire.nonEmpty(e.sha256)
        )
    }
}
