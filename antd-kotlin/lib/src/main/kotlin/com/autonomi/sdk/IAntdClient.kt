package com.autonomi.sdk

import java.io.Closeable

/**
 * Client interface for the Autonomi network via the antd daemon.
 *
 * All methods are suspend functions for async operation.
 * Use [AntdClient.createRest] or [AntdClient.createGrpc] to create an instance.
 */
interface IAntdClient : Closeable {

    // Health
    suspend fun health(): HealthStatus

    // Data
    suspend fun dataPutPublic(data: ByteArray, paymentMode: String? = null): PutResult
    suspend fun dataGetPublic(address: String): ByteArray
    suspend fun dataPutPrivate(data: ByteArray, paymentMode: String? = null): PutResult
    suspend fun dataGetPrivate(dataMap: String): ByteArray
    suspend fun dataCost(data: ByteArray): String

    // Chunks
    suspend fun chunkPut(data: ByteArray): PutResult
    suspend fun chunkGet(address: String): ByteArray

    // Files
    suspend fun fileUploadPublic(path: String, paymentMode: String? = null): PutResult
    suspend fun fileDownloadPublic(address: String, destPath: String)
    suspend fun dirUploadPublic(path: String, paymentMode: String? = null): PutResult
    suspend fun dirDownloadPublic(address: String, destPath: String)
    suspend fun fileCost(path: String, isPublic: Boolean = true): String

    // Wallet
    suspend fun walletAddress(): WalletAddress
    suspend fun walletBalance(): WalletBalance
    suspend fun walletApprove(): Boolean

    // External Signer (Two-Phase Upload)
    suspend fun prepareUpload(path: String): PrepareUploadResult
    suspend fun prepareDataUpload(data: ByteArray): PrepareUploadResult
    suspend fun finalizeUpload(uploadId: String, txHashes: Map<String, String>): FinalizeUploadResult
}
