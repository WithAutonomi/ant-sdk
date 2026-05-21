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
}
