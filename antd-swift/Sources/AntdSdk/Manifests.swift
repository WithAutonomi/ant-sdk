import Foundation

// MARK: - Manifests (ADR-0006)
//
// A manifest is a `.ant` file (or an `ant://manifest/` link) that describes a
// set of files, each with an optional path and size and either an embedded
// DataMap or a public DataMap address. The daemon builds and decodes it
// through ant-core, so callers never re-implement the format.
//
// Nothing is uploaded or paid for. The network is read only to resolve
// DataMaps: the root-embedding policy on build, and `resolve` on decode. So a
// call can time out, and retrying one is safe.
//
// The `.ant` bytes are raw `Data` in this API on both transports: REST
// carries them as base64 in JSON, gRPC as `bytes`, and the clients convert.
// Sizes are `UInt64?`, and an unset size is `nil`, never `0`.
//
// Requires the antd release after 0.15.0.

/// One file for ``AntdClientProtocol/buildManifest(entries:options:)``. Set
/// exactly one of ``dataMap`` or ``address``; an entry with both or neither is
/// refused with a ``BadRequestError`` before anything is sent. An empty string
/// counts as unset, as it does for the daemon.
public struct ManifestEntryInput: Sendable, Equatable {
    /// The relative path the entry extracts under, subject to the portable
    /// path rules. `nil` (or empty): it extracts under its content address.
    public var path: String?
    /// The plaintext size to record, as given (the creator's claim). `nil`:
    /// none is recorded; readers take the exact size from an embedded root
    /// DataMap.
    public var size: UInt64?
    /// A hex DataMap, as the upload methods return it. The entry embeds it:
    /// the manifest is the key to the file.
    public var dataMap: String?
    /// A public file's DataMap address (hex, 32 bytes), as
    /// ``AntdClientProtocol/dataPutPublic(_:paymentMode:)`` returns it.
    public var address: String?

    public init(path: String? = nil, size: UInt64? = nil, dataMap: String? = nil, address: String? = nil) {
        self.path = path
        self.size = size
        self.dataMap = dataMap
        self.address = address
    }
}

/// The optional parts of a ``AntdClientProtocol/buildManifest(entries:options:)``
/// call. `BuildManifestOptions()` embeds roots, with no name and no torrent
/// info hashes.
public struct BuildManifestOptions: Sendable, Equatable {
    /// A suggested root directory name (one portable path component). `nil`
    /// or empty: none.
    public var name: String?
    /// BitTorrent info hashes of the same files: hex, 40 characters for v1
    /// and/or 64 for v2.
    public var torrentInfoHashes: [String]
    /// Resolve each shrunk DataMap's root (fetching its wrapper records) and
    /// embed the root when it is at most 64 KiB, so recipients skip that
    /// fetch (ADR-0006's policy). The default, `true`, is the daemon's
    /// default too. `false` embeds shrunk DataMaps exactly as given (antd-go's
    /// `KeepShrunkDataMaps`). Sent as `embed_roots`.
    public var embedRoots: Bool

    public init(name: String? = nil, torrentInfoHashes: [String] = [], embedRoots: Bool = true) {
        self.name = name
        self.torrentInfoHashes = torrentInfoHashes
        self.embedRoots = embedRoots
    }
}

/// What a manifest says about one entry.
public struct ManifestEntryInfo: Sendable, Equatable {
    /// ``path``, or the content address in hex when there is none.
    public let effectiveName: String
    public let path: String?
    /// The size recorded in the manifest: the creator's claim. `nil` when
    /// none was recorded.
    public let size: UInt64?
    /// `"embedded"` or `"public"`.
    public let kind: String
    /// Hex. The file's public DataMap address, whether or not it was ever
    /// made public; the same for private and public uploads of one file.
    public let contentAddress: String
    /// The embedded DataMap in the hex form the download methods accept.
    /// Decode only; `nil` for public entries and in a build's entries.
    public let dataMap: String?
    /// The exact plaintext size: from an embedded root DataMap, or after a
    /// resolving decode. `nil` when unknown.
    public let exactSize: UInt64?
    /// Why a resolving decode failed for this entry; `nil` when it did not.
    /// One entry's failure is reported here, not as a failed call.
    public let error: String?

    public init(
        effectiveName: String,
        path: String? = nil,
        size: UInt64? = nil,
        kind: String,
        contentAddress: String,
        dataMap: String? = nil,
        exactSize: UInt64? = nil,
        error: String? = nil
    ) {
        self.effectiveName = effectiveName
        self.path = path
        self.size = size
        self.kind = kind
        self.contentAddress = contentAddress
        self.dataMap = dataMap
        self.exactSize = exactSize
        self.error = error
    }
}

/// The result of ``AntdClientProtocol/buildManifest(entries:options:)``.
public struct BuiltManifest: Sendable, Equatable {
    /// The `.ant` bytes.
    public let manifest: Data
    /// The `ant://manifest/` link, only when it fits the recommended 1,500
    /// bytes; `nil` otherwise. Share ``manifest`` itself then.
    public let link: String?
    /// In encoded order (sorted by effective name).
    public let entries: [ManifestEntryInfo]

    public init(manifest: Data, link: String? = nil, entries: [ManifestEntryInfo]) {
        self.manifest = manifest
        self.link = link
        self.entries = entries
    }
}

/// The result of ``AntdClientProtocol/decodeManifest(_:resolve:)`` and
/// ``AntdClientProtocol/decodeManifestLink(_:resolve:)``.
public struct DecodedManifest: Sendable, Equatable {
    /// `"manifest"`, or `"file_link"` for a file link or bare address
    /// (reported as one public entry with no path).
    public let source: String
    /// The suggested root directory name, when the manifest has one.
    public let name: String?
    /// BitTorrent info hashes (hex), when the manifest carries them.
    public let torrentInfoHashV1: String?
    public let torrentInfoHashV2: String?
    public let entries: [ManifestEntryInfo]

    public init(
        source: String,
        name: String? = nil,
        torrentInfoHashV1: String? = nil,
        torrentInfoHashV2: String? = nil,
        entries: [ManifestEntryInfo]
    ) {
        self.source = source
        self.name = name
        self.torrentInfoHashV1 = torrentInfoHashV1
        self.torrentInfoHashV2 = torrentInfoHashV2
        self.entries = entries
    }
}

/// Client-side checks and wire helpers shared by the REST and gRPC clients.
enum ManifestWire {
    /// `nil` for an unset or empty string. proto3 strings have no presence,
    /// and the daemon treats an empty string as "not given".
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Refuses, before anything is sent, an entry that sets both or neither
    /// of `dataMap` and `address` (antd-go's `checkManifestEntries`). The
    /// message names `entries[i]`, as the daemon's does.
    static func checkEntries(_ entries: [ManifestEntryInput]) throws {
        for (i, entry) in entries.enumerated() {
            let hasDataMap = nonEmpty(entry.dataMap) != nil
            let hasAddress = nonEmpty(entry.address) != nil
            if hasDataMap == hasAddress {
                let found = hasDataMap ? "both are set" : "neither is set"
                throw BadRequestError("buildManifest: entries[\(i)]: set exactly one of dataMap or address (\(found))")
            }
        }
    }

    static func checkManifest(_ manifest: Data) throws {
        if manifest.isEmpty {
            throw BadRequestError("decodeManifest: manifest is empty")
        }
    }

    static func checkLink(_ link: String) throws {
        if link.isEmpty {
            throw BadRequestError("decodeManifestLink: link is empty")
        }
    }
}

// MARK: - Protocol conveniences and defaults

extension AntdClientProtocol {
    /// ``buildManifest(entries:options:)`` with the default options: embed
    /// roots, no name, no torrent info hashes.
    public func buildManifest(entries: [ManifestEntryInput]) async throws -> BuiltManifest {
        try await buildManifest(entries: entries, options: BuildManifestOptions())
    }
}

// Default implementations of the manifest requirements, for conformers that
// predate the manifest API. Each throws NotSupportedError; AntdRestClient and
// AntdGrpcClient replace all of them with real implementations.
extension AntdClientProtocol {
    private func manifestsNotSupported(_ method: String) -> NotSupportedError {
        NotSupportedError("\(method) is not supported by \(type(of: self)): it does not implement the manifest API")
    }

    public func buildManifest(entries: [ManifestEntryInput], options: BuildManifestOptions) async throws -> BuiltManifest {
        throw manifestsNotSupported("buildManifest")
    }

    public func decodeManifest(_ manifest: Data, resolve: Bool) async throws -> DecodedManifest {
        throw manifestsNotSupported("decodeManifest")
    }

    public func decodeManifestLink(_ link: String, resolve: Bool) async throws -> DecodedManifest {
        throw manifestsNotSupported("decodeManifestLink")
    }
}
