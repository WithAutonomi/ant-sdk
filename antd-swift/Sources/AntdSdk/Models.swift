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

/// Wallet address result.
public struct WalletAddress: Sendable, Equatable {
    public let address: String

    public init(address: String) {
        self.address = address
    }
}

/// Wallet balance result.
public struct WalletBalance: Sendable, Equatable {
    public let balance: String
    public let gasBalance: String

    public init(balance: String, gasBalance: String) {
        self.balance = balance
        self.gasBalance = gasBalance
    }
}

/// A single payment required for an upload.
public struct PaymentInfo: Sendable, Equatable {
    public let quoteHash: String
    public let rewardsAddress: String
    public let amount: String

    public init(quoteHash: String, rewardsAddress: String, amount: String) {
        self.quoteHash = quoteHash
        self.rewardsAddress = rewardsAddress
        self.amount = amount
    }
}

/// Result of preparing an upload for external signing.
public struct PrepareUploadResult: Sendable, Equatable {
    public let uploadId: String
    public let payments: [PaymentInfo]
    public let totalAmount: String
    public let dataPaymentsAddress: String
    public let paymentTokenAddress: String
    public let rpcUrl: String

    public init(uploadId: String, payments: [PaymentInfo], totalAmount: String, dataPaymentsAddress: String, paymentTokenAddress: String, rpcUrl: String) {
        self.uploadId = uploadId
        self.payments = payments
        self.totalAmount = totalAmount
        self.dataPaymentsAddress = dataPaymentsAddress
        self.paymentTokenAddress = paymentTokenAddress
        self.rpcUrl = rpcUrl
    }
}

/// Result of finalizing an externally-signed upload.
public struct FinalizeUploadResult: Sendable, Equatable {
    public let address: String
    public let chunksStored: Int64

    public init(address: String, chunksStored: Int64) {
        self.address = address
        self.chunksStored = chunksStored
    }
}
