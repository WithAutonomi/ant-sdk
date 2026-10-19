package com.autonomi.sdk

import java.io.Closeable

/**
 * Client interface for the Autonomi network via the antd daemon.
 *
 * All methods are suspend functions for async operation.
 * Use [AntdClient.createRest] or [AntdClient.createGrpc] to create an instance.
 *
 * Naming convention (post v1.0):
 *   - Unqualified verb (`dataPut`, `dataGet`, `filePut`, `fileGet`) = private —
 *     the DataMap is returned to the caller and NOT stored on-network.
 *   - `_public` suffix (`dataPutPublic`, ...) = public — the DataMap is stored
 *     on-network as an extra chunk; the call returns the shareable address.
 */
interface IAntdClient : Closeable {

    // Health
    suspend fun health(): HealthStatus

    // Data
    suspend fun dataPutPublic(data: ByteArray, paymentMode: PaymentMode = PaymentMode.AUTO): DataPutPublicResult
    suspend fun dataGetPublic(address: String): ByteArray
    suspend fun dataPut(data: ByteArray, paymentMode: PaymentMode = PaymentMode.AUTO): DataPutResult
    suspend fun dataGet(dataMap: String): ByteArray
    suspend fun dataCost(data: ByteArray, paymentMode: PaymentMode = PaymentMode.AUTO): UploadCostEstimate

    // Chunks
    suspend fun chunkPut(data: ByteArray): PutResult
    suspend fun chunkGet(address: String): ByteArray
    suspend fun prepareChunkUpload(data: ByteArray): PrepareChunkResult
    suspend fun finalizeChunkUpload(uploadId: String, txHashes: Map<String, String>): String

    // Files
    suspend fun filePutPublic(path: String, paymentMode: PaymentMode = PaymentMode.AUTO): FilePutPublicResult
    suspend fun fileGetPublic(address: String, destPath: String)
    suspend fun filePut(path: String, paymentMode: PaymentMode = PaymentMode.AUTO): FilePutResult
    suspend fun fileGet(dataMap: String, destPath: String)
    suspend fun fileCost(path: String, isPublic: Boolean = true, paymentMode: PaymentMode = PaymentMode.AUTO): UploadCostEstimate

    // Wallet
    suspend fun walletAddress(): WalletAddress
    suspend fun walletBalance(): WalletBalance
    suspend fun walletApprove(): Boolean

    // External Signer (Two-Phase Upload)
    suspend fun prepareUpload(path: String, visibility: String? = null): PrepareUploadResult
    suspend fun prepareUploadPublic(path: String): PrepareUploadResult
    suspend fun prepareDataUpload(data: ByteArray, visibility: String? = null): PrepareUploadResult
    suspend fun finalizeUpload(uploadId: String, txHashes: Map<String, String>): FinalizeUploadResult
    suspend fun finalizeMerkleUpload(uploadId: String, winnerPoolHash: String): FinalizeMerkleUploadResult

    // Pointers (the antd release after 0.15.0, the first with pointers)
    //
    // Owner-signed, paid, mutable references. The daemon holds the owner keys
    // (`antd --pointer-keys`), so a write names the pointer by its address
    // (`owner`), never by a key; an owner the daemon holds no key for is a
    // BadRequestException. Addresses are 64 hex characters; the daemon accepts
    // a `0x` prefix but always returns bare hex.
    //
    // Every write pays (about the price of one chunk), and every attempt pays
    // again. Neither client retries pointerCreate, pointerUpdate,
    // pointerTransfer or pointerFinalize; do not wrap them in an automatic
    // retry. Reads are free to retry.
    //
    // Each method has a default body that throws UnsupportedOperationException,
    // so an implementation of this interface written before the pointer API
    // keeps compiling. AntdRestClient and AntdGrpcClient override all ten.

    /** The addresses of the pointers this daemon holds owner keys for. Only these can be written. */
    suspend fun pointerKeys(): List<String> =
        notImplemented("pointerKeys")

    /**
     * Creates the pointer at [owner], pointing at [target], paid by the daemon
     * wallet. Each call pays; never retried.
     *
     * @throws AlreadyExistsException if the pointer exists, before anything is paid.
     */
    suspend fun pointerCreate(owner: String, target: String, kind: PointerKind = PointerKind.CHUNK): PointerWriteResult =
        notImplemented("pointerCreate")

    /**
     * Points the pointer at [owner] at [target], paid by the daemon wallet,
     * creating it at counter 0 if it does not exist. Each call pays; never
     * retried.
     *
     * @throws PointerFinalException if the pointer was transferred or frozen, before anything is paid.
     * @throws ConflictException while a prepared write to the pointer awaits payment.
     */
    suspend fun pointerUpdate(owner: String, target: String, kind: PointerKind = PointerKind.CHUNK): PointerWriteResult =
        notImplemented("pointerUpdate")

    /**
     * Hands the pointer at [owner] over for good to the pointer at [recipient],
     * which must already exist, paid by the daemon wallet. Readers of the
     * address are redirected to the recipient's pointer, which only its owner
     * can move. Irreversible once stored. Each call pays; never retried.
     *
     * @throws PointerFinalException if the pointer is already final, before anything is paid.
     * @throws BadRequestException if [recipient] does not exist or leads back.
     * @throws CloseGroupShortfallException if not every peer of the close group
     *   answered, before anything is paid; retry later.
     */
    suspend fun pointerTransfer(owner: String, recipient: String): PointerTransferResult =
        notImplemented("pointerTransfer")

    /**
     * Reads the pointer at [address].
     *
     * @throws NotFoundException if there is none.
     */
    suspend fun pointerGet(address: String): PointerRecord =
        notImplemented("pointerGet")

    /**
     * Follows a chain of pointers from [address], through forwardings and
     * transfers, to the target at its end.
     *
     * @throws NotFoundException if a pointer on the chain does not exist.
     */
    suspend fun pointerResolve(address: String): PointerTarget =
        notImplemented("pointerResolve")

    /**
     * Asks the whole close group where the pointer at [address] stands. Check
     * [PointerFinality.isFinal] before relying on a transfer.
     */
    suspend fun pointerFinality(address: String): PointerFinality =
        notImplemented("pointerFinality")

    /** Follows the transfers of [address] to the pointer whose owner now decides what it resolves to. */
    suspend fun pointerController(address: String): PointerController =
        notImplemented("pointerController")

    /**
     * External signer: the daemon signs [op] on the pointer at [owner] with its
     * loaded key and quotes it. Pay [PointerPrepareResult.payments] with
     * `payForQuotes()`, then call [pointerFinalize]. Needs no daemon wallet.
     * [includeSignedQuotes] fills [PointerPrepareResult.signedQuotes].
     *
     * Every check the daemon-wallet writes make before paying is made here.
     * While the prepared write awaits payment, other writes to the pointer
     * throw [ConflictException] until it is finalized or expires (one hour).
     */
    suspend fun pointerPrepare(owner: String, op: PointerOp, includeSignedQuotes: Boolean = false): PointerPrepareResult =
        notImplemented("pointerPrepare")

    /**
     * External signer: stores a prepared pointer write once paid. [txHashes]
     * maps each `quoteHash` from the prepare's payments to its
     * `payForQuotes()` transaction hash. Never retried.
     *
     * A write that falls short after payment throws
     * [CloseGroupShortfallException] with `retryable == true`: the daemon kept
     * the paid state, so calling this again with the same [uploadId] stores it
     * against the same payment ([txHashes] is then ignored). Bound that loop.
     * A finalize without the payment's hashes is a [BadRequestException] and
     * keeps the session, so it can be corrected.
     */
    suspend fun pointerFinalize(uploadId: String, txHashes: Map<String, String>): PointerFinalizeResult =
        notImplemented("pointerFinalize")

    /** The default body of the pointer methods, for implementations that predate them. */
    private fun notImplemented(method: String): Nothing =
        throw UnsupportedOperationException("$method is not implemented by this IAntdClient")
}
