import Foundation

/// Health check result from the antd daemon.
///
/// The diagnostic fields (`version`, `evmNetwork`, `uptimeSeconds`,
/// `buildCommit`, `paymentTokenAddress`, `paymentVaultAddress`) were added in
/// antd 0.4.0. They default to `""` / `0` so the struct stays usable when
/// talking to a pre-0.4.0 daemon that doesn't report them.
public struct HealthStatus: Sendable, Equatable {
    public let ok: Bool
    public let network: String
    public let version: String
    public let evmNetwork: String
    public let uptimeSeconds: UInt64
    public let buildCommit: String
    public let paymentTokenAddress: String
    public let paymentVaultAddress: String

    public init(
        ok: Bool,
        network: String,
        version: String = "",
        evmNetwork: String = "",
        uptimeSeconds: UInt64 = 0,
        buildCommit: String = "",
        paymentTokenAddress: String = "",
        paymentVaultAddress: String = ""
    ) {
        self.ok = ok
        self.network = network
        self.version = version
        self.evmNetwork = evmNetwork
        self.uptimeSeconds = uptimeSeconds
        self.buildCommit = buildCommit
        self.paymentTokenAddress = paymentTokenAddress
        self.paymentVaultAddress = paymentVaultAddress
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
///
/// `dataMap` is the hex-encoded msgpack DataMap (always returned by the
/// daemon). `dataMapAddress` is populated only when prepare was called with
/// ``visibility`` `"public"` — the DataMap chunk was bundled into the same
/// external-signer payment batch and stored on-network, so this is the
/// shareable retrieval handle. For private prepares it is `""`.
public struct FinalizeUploadResult: Sendable, Equatable {
    public let address: String
    public let chunksStored: Int64
    public let dataMap: String
    public let dataMapAddress: String

    public init(
        address: String,
        chunksStored: Int64,
        dataMap: String = "",
        dataMapAddress: String = ""
    ) {
        self.address = address
        self.chunksStored = chunksStored
        self.dataMap = dataMap
        self.dataMapAddress = dataMapAddress
    }
}

/// Result of finalizing a merkle batch upload.
public struct FinalizeMerkleUploadResult: Sendable, Equatable {
    public let address: String
    public let chunksStored: Int64
    public let dataMap: String
    public let dataMapAddress: String

    public init(
        address: String,
        chunksStored: Int64,
        dataMap: String = "",
        dataMapAddress: String = ""
    ) {
        self.address = address
        self.chunksStored = chunksStored
        self.dataMap = dataMap
        self.dataMapAddress = dataMapAddress
    }
}

/// Result of preparing a single-chunk external-signer publish via
/// `POST /v1/chunks/prepare`.
///
/// When ``alreadyStored`` is `true` the chunk is already on-network and no
/// payment or finalize step is needed — ``uploadId`` and the payment fields
/// are empty. Otherwise the daemon returns a wave-batch payment intent the
/// external signer must execute before calling `finalizeChunkUpload`.
public struct PrepareChunkResult: Sendable, Equatable {
    public let address: String
    public let alreadyStored: Bool
    public let uploadId: String
    public let paymentType: String
    public let payments: [PaymentInfo]
    public let totalAmount: String
    public let paymentVaultAddress: String
    public let paymentTokenAddress: String
    public let rpcUrl: String

    public init(
        address: String,
        alreadyStored: Bool = false,
        uploadId: String = "",
        paymentType: String = "",
        payments: [PaymentInfo] = [],
        totalAmount: String = "",
        paymentVaultAddress: String = "",
        paymentTokenAddress: String = "",
        rpcUrl: String = ""
    ) {
        self.address = address
        self.alreadyStored = alreadyStored
        self.uploadId = uploadId
        self.paymentType = paymentType
        self.payments = payments
        self.totalAmount = totalAmount
        self.paymentVaultAddress = paymentVaultAddress
        self.paymentTokenAddress = paymentTokenAddress
        self.rpcUrl = rpcUrl
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
