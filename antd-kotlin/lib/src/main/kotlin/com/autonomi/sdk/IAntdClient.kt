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
    suspend fun dataPutPublic(data: ByteArray): PutResult
    suspend fun dataGetPublic(address: String): ByteArray
    suspend fun dataPutPrivate(data: ByteArray): PutResult
    suspend fun dataGetPrivate(dataMap: String): ByteArray
    suspend fun dataCost(data: ByteArray): String

    // Chunks
    suspend fun chunkPut(data: ByteArray): PutResult
    suspend fun chunkGet(address: String): ByteArray

    // Graph
    suspend fun graphEntryPut(ownerSecretKey: String, parents: List<String>, content: String, descendants: List<GraphDescendant>): PutResult
    suspend fun graphEntryGet(address: String): GraphEntry
    suspend fun graphEntryExists(address: String): Boolean
    suspend fun graphEntryCost(publicKey: String): String

    // Files
    suspend fun fileUploadPublic(path: String): PutResult
    suspend fun fileDownloadPublic(address: String, destPath: String)
    suspend fun dirUploadPublic(path: String): PutResult
    suspend fun dirDownloadPublic(address: String, destPath: String)
    suspend fun archiveGetPublic(address: String): Archive
    suspend fun archivePutPublic(archive: Archive): PutResult
    suspend fun fileCost(path: String, isPublic: Boolean = true, includeArchive: Boolean = false): String
}
