import Foundation

/// Health check result from the antd daemon.
public struct HealthStatus: Sendable, Equatable {
    public let ok: Bool
    public let network: String

    public init(ok: Bool, network: String) {
        self.ok = ok
        self.network = network
    }
}

/// Result of a put/create operation that stores data on the network.
public struct PutResult: Sendable, Equatable {
    public let cost: String
    public let address: String

    public init(cost: String, address: String) {
        self.cost = cost
        self.address = address
    }
}

/// Target of a pointer — identifies both the kind and address of the target.
public struct PointerTarget: Sendable, Equatable {
    public let kind: String
    public let address: String

    public init(kind: String, address: String) {
        self.kind = kind
        self.address = address
    }
}

/// A pointer record retrieved from the network.
public struct Pointer: Sendable, Equatable {
    public let address: String
    public let owner: String
    public let counter: UInt64
    public let target: PointerTarget

    public init(address: String, owner: String, counter: UInt64, target: PointerTarget) {
        self.address = address
        self.owner = owner
        self.counter = counter
        self.target = target
    }
}

/// A scratchpad record retrieved from the network.
public struct ScratchpadRecord: Sendable, Equatable {
    public let address: String
    public let dataEncoding: UInt64
    public let data: Data
    public let counter: UInt64

    public init(address: String, dataEncoding: UInt64, data: Data, counter: UInt64) {
        self.address = address
        self.dataEncoding = dataEncoding
        self.data = data
        self.counter = counter
    }
}

/// A descendant entry in a graph node.
public struct GraphDescendant: Sendable, Equatable {
    public let publicKey: String
    public let content: String

    public init(publicKey: String, content: String) {
        self.publicKey = publicKey
        self.content = content
    }
}

/// A graph entry retrieved from the network.
public struct GraphEntry: Sendable, Equatable {
    public let owner: String
    public let parents: [String]
    public let content: String
    public let descendants: [GraphDescendant]

    public init(owner: String, parents: [String], content: String, descendants: [GraphDescendant]) {
        self.owner = owner
        self.parents = parents
        self.content = content
        self.descendants = descendants
    }
}

/// A register value retrieved from the network.
public struct Register: Sendable, Equatable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

/// A vault record retrieved from the network.
public struct Vault: Sendable, Equatable {
    public let data: Data
    public let contentType: UInt64

    public init(data: Data, contentType: UInt64) {
        self.data = data
        self.contentType = contentType
    }
}

/// A single entry in an archive manifest.
public struct ArchiveEntry: Sendable, Equatable {
    public let path: String
    public let address: String
    public let created: UInt64
    public let modified: UInt64
    public let size: UInt64

    public init(path: String, address: String, created: UInt64, modified: UInt64, size: UInt64) {
        self.path = path
        self.address = address
        self.created = created
        self.modified = modified
        self.size = size
    }
}

/// An archive manifest containing file entries.
public struct Archive: Sendable, Equatable {
    public let entries: [ArchiveEntry]

    public init(entries: [ArchiveEntry]) {
        self.entries = entries
    }
}
