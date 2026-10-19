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

/// A fetch-progress update emitted during a streaming download when progress is
/// requested. Counts are in *chunks*, not bytes — the byte denominator is the
/// download's total size (the `x-content-length` header over gRPC, the leading
/// NDJSON `meta` frame over REST). `total` is 0 while still unknown (mid
/// DataMap-resolution).
///
/// `phase` is one of:
/// - `"resolving_map"` — walking the hierarchical DataMap to learn the count
/// - `"resolved"` — DataMap resolved, `total` now holds the real chunk count
/// - `"fetching"` — fetching data chunks; `fetched`/`total` advance the bar
public struct DownloadProgress: Sendable, Equatable {
    public let phase: String
    public let fetched: UInt64
    public let total: UInt64

    public init(phase: String, fetched: UInt64, total: UInt64) {
        self.phase = phase
        self.fetched = fetched
        self.total = total
    }
}

/// One frame of a progress-enabled streaming download: the total size, a
/// plaintext data chunk, or a ``DownloadProgress`` update. Yielded by the
/// `*WithProgress` streaming methods; the plain `dataStream` methods stay a pure
/// `Data` stream for callers that don't need progress.
public enum DownloadFrame: Sendable, Equatable {
    /// Total download size in *bytes* — the progress denominator, surfaced from
    /// the gRPC `x-content-length` response metadata or the REST NDJSON `meta`
    /// frame. Emitted at most once, before any data.
    case meta(UInt64)
    case data(Data)
    case progress(DownloadProgress)

    /// True if this frame carries a progress update rather than data bytes.
    public var isProgress: Bool {
        if case .progress = self { return true }
        return false
    }

    /// True if this frame carries the total-size denominator.
    public var isMeta: Bool {
        if case .meta = self { return true }
        return false
    }
}

// MARK: - Pointers (ADR-0016 / ADR-0018 in ant-node)
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; its target (a chunk, such as
// a public file's data map, or another pointer) can be changed by the owner,
// and the owner can hand the pointer over to another pointer for good. antd
// signs with owner keys it loaded at startup (`--pointer-keys`), so a write
// names the pointer by its address (`owner`), never by a key.
//
// Addresses, state ids and targets are 64 hex characters. The daemon accepts
// a `0x` prefix on input but always returns bare hex.
//
// Every write pays, and every attempt pays again: the SDK never retries a
// create, update, transfer or finalize on its own.

/// What a pointer's target is.
public enum PointerKind: String, Sendable, Equatable, CaseIterable {
    /// An immutable chunk, such as a public file's data map. The default.
    case chunk = "chunk"
    /// Another pointer: a forwarding the owner can still change. Use a
    /// transfer to hand a pointer over for good.
    case pointer = "pointer"

    /// The kind a raw target tag names, if this SDK knows it (`0` chunk,
    /// `1` pointer).
    public init?(tag: UInt8) {
        switch tag {
        case 0: self = .chunk
        case 1: self = .pointer
        default: return nil
        }
    }
}

/// The write a ``AntdClientProtocol/pointerPrepare(owner:op:options:)`` signs
/// for an external signer to pay.
public enum PointerOp: Sendable, Equatable {
    /// Create the pointer at `target`. Refused if it already exists.
    case create(target: String, kind: PointerKind = .chunk)
    /// Point the pointer at `target`, creating it if it does not exist.
    case update(target: String, kind: PointerKind = .chunk)
    /// Hand the pointer over for good to the pointer at `recipient`, which
    /// must already exist. Irreversible once stored.
    case transfer(recipient: String)

    /// The daemon's wire name for the operation.
    public var wireName: String {
        switch self {
        case .create: return "create"
        case .update: return "update"
        case .transfer: return "transfer"
        }
    }
}

/// Options for ``AntdClientProtocol/pointerPrepare(owner:op:options:)``.
public struct PointerPrepareOptions: Sendable, Equatable {
    /// Ask the daemon for the full signed quotes as well
    /// (``PointerPrepareResult/signedQuotes``), for a signer that checks them
    /// before paying.
    public var includeSignedQuotes: Bool

    public init(includeSignedQuotes: Bool = false) {
        self.includeSignedQuotes = includeSignedQuotes
    }
}

/// A pointer the daemon holds an owner key for, so it can write it.
public struct PointerKey: Sendable, Equatable {
    /// The pointer's address, derived from the owner key.
    public let address: String

    public init(address: String) {
        self.address = address
    }
}

/// The state a pointer write stored.
public struct PointerWriteResult: Sendable, Equatable {
    public let address: String
    public let stateId: String
    /// The state's counter. A final state (a transfer) sits at
    /// ``PointerRecord/finalCounter``.
    public let counter: UInt64

    public init(address: String, stateId: String, counter: UInt64) {
        self.address = address
        self.stateId = stateId
        self.counter = counter
    }
}

/// A pointer's current state, as the network serves it.
public struct PointerRecord: Sendable, Equatable {
    /// The counter a final state sits at: `UInt64.max`.
    public static let finalCounter: UInt64 = .max

    public let address: String
    /// The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
    /// derived from it, so it is the proof of who owns the pointer.
    public let owner: String
    public let counter: UInt64
    /// `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not
    /// know; ``kindTag`` carries the raw value either way.
    public let kind: String
    public let kindTag: UInt8
    public let target: String
    public let stateId: String
    /// The state is at the final counter: nothing can replace it. (The wire
    /// field is `is_final`; `final` is a Swift keyword.)
    public let isFinal: Bool
    /// The pointer this one was handed over to, when its final state is a
    /// transfer.
    public let transferredTo: String?

    public init(
        address: String,
        owner: String,
        counter: UInt64,
        kind: String,
        kindTag: UInt8,
        target: String,
        stateId: String,
        isFinal: Bool,
        transferredTo: String? = nil
    ) {
        self.address = address
        self.owner = owner
        self.counter = counter
        self.kind = kind
        self.kindTag = kindTag
        self.target = target
        self.stateId = stateId
        self.isFinal = isFinal
        self.transferredTo = transferredTo
    }

    /// The target's kind, if this SDK knows its tag.
    public var targetKind: PointerKind? { PointerKind(tag: kindTag) }
}

/// Where a chain of pointers ends
/// (``AntdClientProtocol/pointerResolve(address:)``).
public struct PointerTarget: Sendable, Equatable {
    /// `"chunk"`, or `"unknown"` for a target kind the daemon does not know.
    public let kind: String
    /// The raw target kind tag.
    public let kindTag: UInt8
    public let target: String

    public init(kind: String, kindTag: UInt8, target: String) {
        self.kind = kind
        self.kindTag = kindTag
        self.target = target
    }

    /// The target's kind, if this SDK knows its tag.
    public var targetKind: PointerKind? { PointerKind(tag: kindTag) }
}

/// Where a pointer stands with respect to finality, as its whole close group
/// reports it.
public enum PointerFinalityStatus: Sendable, Equatable {
    /// No peer that answered holds a final state: the owner can still move
    /// the pointer. Rules a final state out only when every peer answered.
    case open
    /// One final state, not yet held by a majority: a transfer still
    /// spreading, or a write that fell short.
    case settling
    /// One final state held by a majority, but not every peer answered, so a
    /// rival could still be unseen. Ask again.
    case unconfirmed
    /// One final state held by a majority, every peer answered, no rival.
    /// The only status a recipient should rely on.
    case `final`
    /// The owner signed two or more different final states.
    case forked
    /// A status this SDK does not know (a newer daemon), verbatim.
    case unknown(String)

    /// Parses the daemon's wire string.
    public init(wire: String) {
        switch wire {
        case "open": self = .open
        case "settling": self = .settling
        case "unconfirmed": self = .unconfirmed
        case "final": self = .final
        case "forked": self = .forked
        default: self = .unknown(wire)
        }
    }

    /// The daemon's wire string.
    public var wire: String {
        switch self {
        case .open: return "open"
        case .settling: return "settling"
        case .unconfirmed: return "unconfirmed"
        case .final: return "final"
        case .forked: return "forked"
        case .unknown(let raw): return raw
        }
    }
}

/// One final state, as a finality check reports it.
public struct PointerFinalState: Sendable, Equatable {
    public let stateId: String
    public let kind: String
    public let kindTag: UInt8
    public let target: String
    /// How many peers of the close group hold it.
    public let holders: UInt32
    public let transferredTo: String?

    public init(
        stateId: String,
        kind: String,
        kindTag: UInt8,
        target: String,
        holders: UInt32,
        transferredTo: String? = nil
    ) {
        self.stateId = stateId
        self.kind = kind
        self.kindTag = kindTag
        self.target = target
        self.holders = holders
        self.transferredTo = transferredTo
    }
}

/// The answer to a pointer finality check
/// (``AntdClientProtocol/pointerFinality(address:)``).
///
/// Unset values are `nil` on both transports: REST sends `null`, gRPC an
/// empty string or an absent message.
public struct PointerFinality: Sendable, Equatable {
    public let address: String
    /// Peers in the close group.
    public let group: UInt32
    /// Peers that answered.
    public let answered: UInt32
    public let status: PointerFinalityStatus
    /// ``PointerFinalityStatus/open`` only: the counter a read would return,
    /// if any state is corroborated.
    public let counter: UInt64?
    /// `settling`, `unconfirmed` and `final`: the one final state seen.
    public let state: PointerFinalState?
    /// `forked` only: every final state seen, most-held first.
    public let states: [PointerFinalState]
    /// `forked` only: the state a majority holds, which reads return.
    public let majority: PointerFinalState?
    /// The pointer this one was handed over to, once that is beyond dispute
    /// (status `final`).
    public let transferredTo: String?

    public init(
        address: String,
        group: UInt32,
        answered: UInt32,
        status: PointerFinalityStatus,
        counter: UInt64? = nil,
        state: PointerFinalState? = nil,
        states: [PointerFinalState] = [],
        majority: PointerFinalState? = nil,
        transferredTo: String? = nil
    ) {
        self.address = address
        self.group = group
        self.answered = answered
        self.status = status
        self.counter = counter
        self.state = state
        self.states = states
        self.majority = majority
        self.transferredTo = transferredTo
    }

    /// One final state, held by a majority, with every peer answering and no
    /// rival seen.
    public var isFinal: Bool { status == .final }
}

/// What a transfer stored, and where the close group says it stands.
public struct PointerTransferResult: Sendable, Equatable {
    public let address: String
    public let stateId: String
    /// The close group's view once the write landed. `nil` when that check
    /// failed (see ``finalityError``), which does not undo the transfer: it is
    /// stored and final. Ask again with
    /// ``AntdClientProtocol/pointerFinality(address:)``.
    public let finality: PointerFinality?
    public let finalityError: String?

    public init(address: String, stateId: String, finality: PointerFinality? = nil, finalityError: String? = nil) {
        self.address = address
        self.stateId = stateId
        self.finality = finality
        self.finalityError = finalityError
    }
}

/// Whose pointer decides what an address resolves to, after every transfer.
public struct PointerController: Sendable, Equatable {
    public let pointer: String
    /// Every pointer the address was handed over to, in order.
    public let transfers: [String]
    /// ``pointer`` is final without being handed over: nobody can move it.
    public let frozen: Bool

    public init(pointer: String, transfers: [String], frozen: Bool) {
        self.pointer = pointer
        self.transfers = transfers
        self.frozen = frozen
    }
}

/// One `payments[]` quote in full signed form. The daemon's REST response
/// carries the blobs base64; over gRPC they arrive as bytes and are base64
/// encoded here, so both transports fill this the same way.
public struct SignedQuoteEntry: Sendable, Equatable {
    /// Quote hash (hex with 0x prefix); matches the ``PaymentInfo`` entry.
    public let quoteHash: String
    /// base64(msgpack) signed `PaymentQuote`. Opaque.
    public let quote: String
    /// base64(msgpack) `StorageCommitment` sidecar the quote's commitment pin
    /// resolves to. `nil` for baseline quotes.
    public let commitmentSidecar: String?

    public init(quoteHash: String, quote: String, commitmentSidecar: String? = nil) {
        self.quoteHash = quoteHash
        self.quote = quote
        self.commitmentSidecar = commitmentSidecar
    }
}

/// A pointer write signed by the daemon and quoted for an external signer.
/// Pay ``payments`` with `payForQuotes()`, then call
/// ``AntdClientProtocol/pointerFinalize(uploadId:txHashes:)``.
///
/// While it awaits payment, other writes to the pointer throw
/// ``ConflictError`` until it is finalized or expires (one hour).
public struct PointerPrepareResult: Sendable, Equatable {
    public let uploadId: String
    /// `"create"`, `"update"` or `"transfer"`.
    public let op: String
    public let address: String
    public let stateId: String
    public let counter: UInt64
    /// Always `"wave_batch"`: a pointer state is paid with one quote.
    public let paymentType: String
    public let payments: [PaymentInfo]
    public let totalAmount: String
    public let paymentVaultAddress: String
    public let paymentTokenAddress: String
    public let rpcUrl: String
    /// Populated when requested with
    /// ``PointerPrepareOptions/includeSignedQuotes``.
    public let signedQuotes: [SignedQuoteEntry]

    public init(
        uploadId: String,
        op: String,
        address: String,
        stateId: String,
        counter: UInt64,
        paymentType: String,
        payments: [PaymentInfo],
        totalAmount: String,
        paymentVaultAddress: String,
        paymentTokenAddress: String,
        rpcUrl: String,
        signedQuotes: [SignedQuoteEntry] = []
    ) {
        self.uploadId = uploadId
        self.op = op
        self.address = address
        self.stateId = stateId
        self.counter = counter
        self.paymentType = paymentType
        self.payments = payments
        self.totalAmount = totalAmount
        self.paymentVaultAddress = paymentVaultAddress
        self.paymentTokenAddress = paymentTokenAddress
        self.rpcUrl = rpcUrl
        self.signedQuotes = signedQuotes
    }
}

/// The state a pointer finalize stored.
public struct PointerFinalizeResult: Sendable, Equatable {
    public let address: String
    public let stateId: String
    public let counter: UInt64
    /// Transfers only: where the close group says the transfer stands.
    public let finality: PointerFinality?

    public init(address: String, stateId: String, counter: UInt64, finality: PointerFinality? = nil) {
        self.address = address
        self.stateId = stateId
        self.counter = counter
        self.finality = finality
    }
}

/// Parsing shared by the REST and gRPC pointer methods.
enum PointerWire {
    /// Parses a pointer counter. The daemon sends counters as decimal
    /// strings, since a final state's `UInt64.max` is past what a JSON number
    /// keeps exactly in several languages; Swift reads it into a `UInt64`
    /// losslessly. Only ASCII digits are accepted (no sign, no whitespace),
    /// and an empty, malformed or out-of-range value is an error, never a
    /// silent zero.
    static func counter(_ field: String, _ value: String?) throws -> UInt64 {
        guard let value,
              !value.isEmpty,
              value.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
              let n = UInt64(value)
        else {
            throw InternalError("invalid pointer \(field) \(value.map { "\"\($0)\"" } ?? "null"): expected a decimal UInt64")
        }
        return n
    }

    /// An optional counter: `nil` or `""` (REST `null`, gRPC unset) reads as
    /// absent; anything else must parse.
    static func optionalCounter(_ field: String, _ value: String?) throws -> UInt64? {
        guard let value, !value.isEmpty else { return nil }
        return try counter(field, value)
    }

    /// `nil` for an absent or empty string (REST `null`, gRPC unset).
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// A target kind tag is one byte on the wire, widened by JSON and proto.
    /// A missing value, or one past `UInt8`, cannot come from the daemon and
    /// reads as `UInt8.max`, a tag no kind uses.
    static func kindTag<T: BinaryInteger>(_ tag: T?) -> UInt8 {
        guard let tag else { return .max }
        return UInt8(exactly: tag) ?? .max
    }
}
