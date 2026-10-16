import Foundation

/// Client protocol for the Autonomi network via the antd daemon.
///
/// All methods are async. Use ``AntdClient/createRest(baseURL:timeout:)`` or
/// ``AntdClient/createGrpc(target:)`` to create an instance.
public protocol AntdClientProtocol: Sendable {

    // Health
    func health() async throws -> HealthStatus

    // Data
    func dataPut(_ data: Data, paymentMode: PaymentMode) async throws -> DataPutResult
    func dataGet(dataMap: String) async throws -> Data
    func dataPutPublic(_ data: Data, paymentMode: PaymentMode) async throws -> DataPutPublicResult
    func dataGetPublic(address: String) async throws -> Data
    func dataCost(_ data: Data, paymentMode: PaymentMode) async throws -> UploadCostEstimate

    // Chunks
    func chunkPut(_ data: Data) async throws -> PutResult
    func chunkGet(address: String) async throws -> Data
    func prepareChunkUpload(_ data: Data) async throws -> PrepareChunkResult
    func finalizeChunkUpload(uploadId: String, txHashes: [String: String]) async throws -> String

    // Files
    func filePut(path: String, paymentMode: PaymentMode) async throws -> FilePutResult
    func fileGet(dataMap: String, destPath: String) async throws
    func filePutPublic(path: String, paymentMode: PaymentMode) async throws -> FilePutPublicResult
    func fileGetPublic(address: String, destPath: String) async throws
    func fileCost(path: String, isPublic: Bool, paymentMode: PaymentMode) async throws -> UploadCostEstimate

    // Manifests (the antd release after 0.15.0)
    //
    // ADR-0006 `.ant` manifests and `ant://` links, built and decoded by the
    // daemon. Nothing is uploaded or paid for; the root-embedding policy and
    // `resolve` read from the network, so a call can time out and is safe to
    // retry. The `.ant` bytes are raw `Data` on both transports.
    //
    // These are requirements, so ``AntdRestClient`` and ``AntdGrpcClient``
    // dispatch dynamically through the protocol. They also have default
    // implementations (in Manifests.swift) that throw ``NotSupportedError``,
    // so a type that conformed to this protocol before the manifest API keeps
    // compiling.

    /// Builds a `.ant` manifest from DataMaps and public addresses already in
    /// hand. An entry that sets both or neither of `dataMap` and `address` is
    /// a ``BadRequestError`` before anything is sent; an entry the daemon
    /// refuses (a bad path, say) is a ``BadRequestError`` whose message names
    /// `entries[i]`.
    func buildManifest(entries: [ManifestEntryInput], options: BuildManifestOptions) async throws -> BuiltManifest

    /// Decodes `.ant` bytes. With `resolve`, the daemon fetches each entry's
    /// DataMap (and wrapper records) to report ``ManifestEntryInfo/exactSize``
    /// and confirm the DataMap is on the network; content chunks are not
    /// fetched, and one entry's failure is reported in its
    /// ``ManifestEntryInfo/error``, not as a failed call.
    func decodeManifest(_ manifest: Data, resolve: Bool) async throws -> DecodedManifest

    /// Decodes an `ant://` manifest link, a file link or a bare 64-hex
    /// address. A file link or address decodes as one public entry with no
    /// path (`source == "file_link"`). See ``decodeManifest(_:resolve:)`` for
    /// `resolve`.
    func decodeManifestLink(_ link: String, resolve: Bool) async throws -> DecodedManifest

    // Wallet
    func walletAddress() async throws -> WalletAddress
    func walletBalance() async throws -> WalletBalance
    func walletApprove() async throws -> Bool

    // External Signer (Two-Phase Upload)
    func prepareUpload(path: String, visibility: String?) async throws -> PrepareUploadResult
    func prepareUploadPublic(path: String) async throws -> PrepareUploadResult
    func prepareDataUpload(_ data: Data) async throws -> PrepareUploadResult

    /// Finalizes a wave-batch upload after the external signer has paid.
    ///
    /// Throws ``PartialUploadError`` when some chunks stayed unstored after the
    /// daemon's retries. The on-chain payment persists and the stored chunks
    /// stay on the network; how to finish depends on
    /// ``PartialUploadError/retryable`` and
    /// ``PartialUploadError/retentionKnown``:
    ///
    /// - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt under
    ///   the same `uploadId`. Call this method again with the **same**
    ///   arguments (same `uploadId`, same payment artefacts) to store the
    ///   remainder against the same payment — no re-prepare, no second
    ///   signature, no double payment. Bound that loop: a persistent failure
    ///   throws on every call, so cap the attempts and treat a
    ///   ``PartialUploadError/chunksFailed`` that stops shrinking as stuck.
    /// - `retentionKnown && !retryable`: the daemon confirmed nothing was
    ///   retained (for example a merkle finalize with deliberately unpaid
    ///   batches). Re-prepare the same content; already stored chunks are
    ///   skipped, so the retry pays only for the remainder.
    /// - `!retentionKnown`: retention is unknown, and the daemon may still
    ///   hold the paid attempt. Stop automatic recovery, keep the `uploadId`
    ///   and the original payment artefacts, and reconcile before
    ///   re-preparing or paying again. Never pay again on this signal alone.
    ///   Daemons older than 0.14.0 never send `retryable`, so their REST
    ///   partial uploads read as unknown. Over gRPC, a status message
    ///   without a readable closing retention hint (missing, truncated or
    ///   unrecognised) also reads as unknown.
    ///
    /// See `docs/external-signer-flow.md` §6.
    func finalizeUpload(uploadId: String, txHashes: [String: String]) async throws -> FinalizeUploadResult

    /// Finalizes a merkle batch upload after the external signer has paid.
    /// Same partial-upload contract as ``finalizeUpload(uploadId:txHashes:)``:
    /// a ``PartialUploadError`` with `retryable` is resumed by calling this
    /// method again with the same arguments; `retentionKnown && !retryable`
    /// means the daemon kept nothing, so re-prepare (a merkle finalize with
    /// deliberately unpaid batches never retains the attempt); without
    /// `retentionKnown` retention is unknown, so stop automatic recovery, keep
    /// the `uploadId` and `winnerPoolHash`, and reconcile before re-preparing
    /// or paying again.
    func finalizeMerkleUpload(uploadId: String, winnerPoolHash: String) async throws -> FinalizeMerkleUploadResult

    // Pointers (antd with the pointer API, after 0.15.0)
    //
    // Owner-signed, paid, mutable references. antd signs with the owner keys
    // it loaded at startup (`--pointer-keys`); a write names the pointer by
    // its address (`owner`), never by a key, and an owner the daemon holds no
    // key for is a ``BadRequestError``.
    //
    // Every write pays, about the price of one chunk, and every attempt pays
    // again. The SDK never retries `pointerCreate`, `pointerUpdate`,
    // `pointerTransfer` or `pointerFinalize` on its own, and callers should
    // not either (the one exception is a ``CloseGroupShortfallError`` with
    // `retryable` from `pointerFinalize`, which reuses the payment). Reads
    // are free to retry; a ``CloseGroupShortfallError`` on a read usually
    // clears once an update in flight settles.
    //
    // These are requirements, so ``AntdRestClient`` and ``AntdGrpcClient``
    // dispatch dynamically through the protocol. They also have default
    // implementations (below) that throw ``NotSupportedError``, so a type
    // that conformed to this protocol before the pointer API keeps compiling.

    /// The pointers this daemon holds owner keys for (`GET /v1/pointers/keys`).
    /// Only these can be written through this daemon.
    func pointerKeys() async throws -> [PointerKey]

    /// Creates the pointer at `owner`, pointing at `target`, paid by the
    /// daemon wallet. Pays once; never retried. Throws ``AlreadyExistsError``,
    /// before anything is paid, if the pointer exists: use
    /// ``pointerUpdate(owner:target:kind:)``.
    func pointerCreate(owner: String, target: String, kind: PointerKind) async throws -> PointerWriteResult

    /// Points the pointer at `owner` at `target`, paid by the daemon wallet,
    /// creating it (at counter 0) if it does not exist. Pays once; never
    /// retried. Throws ``PointerFinalError``, before anything is paid, if the
    /// pointer has been transferred or frozen.
    func pointerUpdate(owner: String, target: String, kind: PointerKind) async throws -> PointerWriteResult

    /// Hands the pointer at `owner` over to the pointer at `recipient`, for
    /// good, paid by the daemon wallet. Readers of the address are redirected
    /// to the recipient's pointer, which only its owner can move. Irreversible
    /// once stored. Pays once; never retried.
    ///
    /// Refused before paying if the pointer is already final
    /// (``PointerFinalError``), if `recipient` does not exist or leads back
    /// (``BadRequestError``), or if not every peer of the close group answered
    /// (``CloseGroupShortfallError``; try again later).
    func pointerTransfer(owner: String, recipient: String) async throws -> PointerTransferResult

    /// Reads the pointer at `address`. Throws ``NotFoundError`` if there is
    /// none.
    func pointerGet(address: String) async throws -> PointerRecord

    /// Follows a chain of pointers from `address` to the target at its end,
    /// through forwardings and transfers alike. Throws ``NotFoundError`` if a
    /// pointer on the chain does not exist.
    func pointerResolve(address: String) async throws -> PointerTarget

    /// Asks the whole close group where the pointer at `address` stands.
    /// Check it before relying on a transfer: only
    /// ``PointerFinalityStatus/final`` means one final state, held by a
    /// majority, with no rival seen.
    func pointerFinality(address: String) async throws -> PointerFinality

    /// Follows the transfers of the pointer at `address` to the pointer whose
    /// owner now decides what it resolves to.
    func pointerController(address: String) async throws -> PointerController

    /// Has the daemon sign `op` on the pointer at `owner` with its loaded key
    /// and quote it for an external signer. Pay
    /// ``PointerPrepareResult/payments`` with `payForQuotes()`, then call
    /// ``pointerFinalize(uploadId:txHashes:)``. Needs no daemon wallet.
    ///
    /// Every check the daemon-wallet writes make before paying is made here,
    /// before anything is quoted. While the prepared write awaits payment
    /// (up to an hour), other writes to the pointer throw ``ConflictError``.
    func pointerPrepare(owner: String, op: PointerOp, options: PointerPrepareOptions) async throws -> PointerPrepareResult

    /// Stores a prepared pointer write once its external signer has paid.
    /// `txHashes` maps each `quoteHash` from the prepare's payments to the
    /// `payForQuotes()` transaction hash.
    ///
    /// A write that falls short after payment throws
    /// ``CloseGroupShortfallError`` with `retryable == true`: the daemon kept
    /// the paid state under the same `uploadId`, and calling this method
    /// again with the same `uploadId` stores it against the same payment
    /// (`txHashes` is then ignored). Bound that loop; the SDK never runs it
    /// for you. A finalize without the payment's hashes is a
    /// ``BadRequestError`` and keeps the session, so it can be corrected.
    func pointerFinalize(uploadId: String, txHashes: [String: String]) async throws -> PointerFinalizeResult
}

extension AntdClientProtocol {
    /// ``pointerPrepare(owner:op:options:)`` with default options (no signed
    /// quotes).
    public func pointerPrepare(owner: String, op: PointerOp) async throws -> PointerPrepareResult {
        try await pointerPrepare(owner: owner, op: op, options: PointerPrepareOptions())
    }
}

// Default implementations of the pointer requirements, for conformers that
// predate the pointer API. Each throws NotSupportedError; AntdRestClient and
// AntdGrpcClient replace all of them with real implementations.
extension AntdClientProtocol {
    private func pointersNotSupported(_ method: String) -> NotSupportedError {
        NotSupportedError("\(method) is not supported by \(type(of: self)): it does not implement the pointer API")
    }

    public func pointerKeys() async throws -> [PointerKey] {
        throw pointersNotSupported("pointerKeys")
    }

    public func pointerCreate(owner: String, target: String, kind: PointerKind) async throws -> PointerWriteResult {
        throw pointersNotSupported("pointerCreate")
    }

    public func pointerUpdate(owner: String, target: String, kind: PointerKind) async throws -> PointerWriteResult {
        throw pointersNotSupported("pointerUpdate")
    }

    public func pointerTransfer(owner: String, recipient: String) async throws -> PointerTransferResult {
        throw pointersNotSupported("pointerTransfer")
    }

    public func pointerGet(address: String) async throws -> PointerRecord {
        throw pointersNotSupported("pointerGet")
    }

    public func pointerResolve(address: String) async throws -> PointerTarget {
        throw pointersNotSupported("pointerResolve")
    }

    public func pointerFinality(address: String) async throws -> PointerFinality {
        throw pointersNotSupported("pointerFinality")
    }

    public func pointerController(address: String) async throws -> PointerController {
        throw pointersNotSupported("pointerController")
    }

    public func pointerPrepare(owner: String, op: PointerOp, options: PointerPrepareOptions) async throws -> PointerPrepareResult {
        throw pointersNotSupported("pointerPrepare")
    }

    public func pointerFinalize(uploadId: String, txHashes: [String: String]) async throws -> PointerFinalizeResult {
        throw pointersNotSupported("pointerFinalize")
    }
}
