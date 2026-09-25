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
}
