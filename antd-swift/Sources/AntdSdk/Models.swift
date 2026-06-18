import Foundation

/// Payment mode for upload operations.
///
/// Controls how on-chain payments for stored chunks are bundled. ``auto`` is
/// the recommended default — the daemon picks ``merkle`` for large uploads
/// and ``single`` for small ones based on chunk count. Library consumers
/// only need to override when they specifically want one transaction shape.
public enum PaymentMode: String, Sendable, Equatable {
    /// Let the daemon pick — merkle batch for large uploads, single for small.
    case auto = "auto"
    /// One on-chain transaction with a merkle proof covering all chunks. Requires ≥2 chunks.
    case merkle = "merkle"
    /// N transactions, one per chunk. Works for any chunk count, including 1.
    case single = "single"
}

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

/// Result of a single-chunk put (``AntdClientProtocol/chunkPut(_:)``).
public struct PutResult: Sendable, Equatable {
    public let cost: String
    public let address: String

    public init(cost: String, address: String) {
        self.cost = cost
        self.address = address
    }
}

/// Result of a private data put (``AntdClientProtocol/dataPut(_:paymentMode:)``).
///
/// The DataMap is returned to the caller; it is NOT stored on-network — the
/// caller keeps it as the only retrieval handle.
public struct DataPutResult: Sendable, Equatable {
    public let dataMap: String
    public let chunksStored: UInt64
    public let paymentModeUsed: String

    public init(dataMap: String, chunksStored: UInt64 = 0, paymentModeUsed: String = "") {
        self.dataMap = dataMap
        self.chunksStored = chunksStored
        self.paymentModeUsed = paymentModeUsed
    }
}

/// Result of a public data put (``AntdClientProtocol/dataPutPublic(_:paymentMode:)``).
///
/// The DataMap is stored on-network as an additional chunk; ``address`` is the
/// shareable retrieval handle.
public struct DataPutPublicResult: Sendable, Equatable {
    public let address: String
    public let chunksStored: UInt64
    public let paymentModeUsed: String

    public init(address: String, chunksStored: UInt64 = 0, paymentModeUsed: String = "") {
        self.address = address
        self.chunksStored = chunksStored
        self.paymentModeUsed = paymentModeUsed
    }
}

/// Result of a private file upload (``AntdClientProtocol/filePut(path:paymentMode:)``).
///
/// The DataMap is returned to the caller; it is NOT stored on-network.
public struct FilePutResult: Sendable, Equatable {
    public let dataMap: String
    public let storageCostAtto: String
    public let gasCostWei: String
    public let chunksStored: UInt64
    public let paymentModeUsed: String

    public init(dataMap: String, storageCostAtto: String, gasCostWei: String, chunksStored: UInt64, paymentModeUsed: String) {
        self.dataMap = dataMap
        self.storageCostAtto = storageCostAtto
        self.gasCostWei = gasCostWei
        self.chunksStored = chunksStored
        self.paymentModeUsed = paymentModeUsed
    }
}

/// Result of a public file upload (``AntdClientProtocol/filePutPublic(path:paymentMode:)``).
///
/// The DataMap is stored on-network as an additional chunk; ``address`` is the
/// shareable retrieval handle.
public struct FilePutPublicResult: Sendable, Equatable {
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

    /// Total chunks in this upload, including any already on-network. Added in
    /// antd 0.10.0; 0 against older daemons. The external signer pays for
    /// (`totalChunks` - `alreadyStoredCount`) chunks.
    public let totalChunks: UInt64

    /// Chunks already stored on-network and excluded from payment + PUT (added in antd 0.10.0).
    public let alreadyStoredCount: UInt64

    public init(uploadId: String, payments: [PaymentInfo], totalAmount: String, paymentVaultAddress: String, paymentTokenAddress: String, rpcUrl: String, paymentType: String = "wave_batch", depth: Int? = nil, poolCommitments: [PoolCommitmentEntry]? = nil, merklePaymentTimestamp: UInt64? = nil, totalChunks: UInt64 = 0, alreadyStoredCount: UInt64 = 0) {
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
        self.totalChunks = totalChunks
        self.alreadyStoredCount = alreadyStoredCount
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

/// Pre-upload cost breakdown returned by ``AntdClientProtocol/dataCost(_:paymentMode:)``
/// and ``AntdClientProtocol/fileCost(path:isPublic:paymentMode:)``.
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
