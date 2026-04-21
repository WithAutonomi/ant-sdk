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

/// Result of a public file or directory upload.
public struct FileUploadResult: Sendable, Equatable {
    public let address: String
    public let storageCostAtto: String
    public let gasCostWei: String
    public let chunksStored: UInt64
    public let paymentModeUsed: String

    public init(address: String, storageCostAtto: String, gasCostWei: String, chunksStored: UInt64, paymentModeUsed: String) {
        self.address = address
        self.storageCostAtto = storageCostAtto
        self.gasCostWei = gasCostWei
        self.chunksStored = chunksStored
        self.paymentModeUsed = paymentModeUsed
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

/// A candidate node entry within a merkle pool commitment.
public struct CandidateNodeEntry: Sendable, Equatable {
    public let rewardsAddress: String
    public let amount: String

    public init(rewardsAddress: String, amount: String) {
        self.rewardsAddress = rewardsAddress
        self.amount = amount
    }
}

/// A pool commitment entry containing candidates for merkle batch payments.
public struct PoolCommitmentEntry: Sendable, Equatable {
    public let poolHash: String
    public let candidates: [CandidateNodeEntry]

    public init(poolHash: String, candidates: [CandidateNodeEntry]) {
        self.poolHash = poolHash
        self.candidates = candidates
    }
}

/// Result of preparing an upload for external signing.
///
/// `paymentType` is `"wave_batch"` or `"merkle"` -- determines which fields are populated
/// and which contract call the external signer must make.
public struct PrepareUploadResult: Sendable, Equatable {
    public let uploadId: String
    public let payments: [PaymentInfo]
    public let totalAmount: String
    public let paymentVaultAddress: String
    public let paymentTokenAddress: String
    public let rpcUrl: String

    /// `"wave_batch"` or `"merkle"`.
    public let paymentType: String

    /// Merkle tree depth (1-8). Present when `paymentType == "merkle"`.
    public let depth: Int?

    /// Pool commitments for `payForMerkleTree()`. Present when `paymentType == "merkle"`.
    public let poolCommitments: [PoolCommitmentEntry]?

    /// Unix timestamp for merkle payment. Present when `paymentType == "merkle"`.
    public let merklePaymentTimestamp: UInt64?

    public init(uploadId: String, payments: [PaymentInfo], totalAmount: String, paymentVaultAddress: String, paymentTokenAddress: String, rpcUrl: String, paymentType: String = "wave_batch", depth: Int? = nil, poolCommitments: [PoolCommitmentEntry]? = nil, merklePaymentTimestamp: UInt64? = nil) {
        self.uploadId = uploadId
        self.payments = payments
        self.totalAmount = totalAmount
        self.paymentVaultAddress = paymentVaultAddress
        self.paymentTokenAddress = paymentTokenAddress
        self.rpcUrl = rpcUrl
        self.paymentType = paymentType
        self.depth = depth
        self.poolCommitments = poolCommitments
        self.merklePaymentTimestamp = merklePaymentTimestamp
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

/// Result of finalizing a merkle batch upload.
public struct FinalizeMerkleUploadResult: Sendable, Equatable {
    public let address: String
    public let chunksStored: Int64

    public init(address: String, chunksStored: Int64) {
        self.address = address
        self.chunksStored = chunksStored
    }
}

/// Pre-upload cost breakdown returned by `dataCost` and `fileCost`.
///
/// The server samples up to 5 chunk addresses and extrapolates the storage
/// cost. Gas is an advisory heuristic, not a live gas-oracle query.
public struct UploadCostEstimate: Sendable, Equatable {
    public let cost: String
    public let fileSize: UInt64
    public let chunkCount: UInt32
    public let estimatedGasCostWei: String
    public let paymentMode: String

    public init(cost: String, fileSize: UInt64, chunkCount: UInt32, estimatedGasCostWei: String, paymentMode: String) {
        self.cost = cost
        self.fileSize = fileSize
        self.chunkCount = chunkCount
        self.estimatedGasCostWei = estimatedGasCostWei
        self.paymentMode = paymentMode
    }
}
