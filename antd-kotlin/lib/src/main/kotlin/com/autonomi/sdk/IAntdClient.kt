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

    // Pointers
    suspend fun pointerCreate(ownerSecretKey: String, target: PointerTarget): PutResult
    suspend fun pointerGet(address: String): Pointer
    suspend fun pointerExists(address: String): Boolean
    suspend fun pointerUpdate(ownerSecretKey: String, target: PointerTarget)
    suspend fun pointerCost(publicKey: String): String

    // Scratchpads
    suspend fun scratchpadCreate(ownerSecretKey: String, contentType: ULong, data: ByteArray): PutResult
    suspend fun scratchpadGet(address: String): ScratchpadRecord
    suspend fun scratchpadExists(address: String): Boolean
    suspend fun scratchpadUpdate(ownerSecretKey: String, contentType: ULong, data: ByteArray)
    suspend fun scratchpadCost(publicKey: String): String

    // Graph
    suspend fun graphEntryPut(ownerSecretKey: String, parents: List<String>, content: String, descendants: List<GraphDescendant>): PutResult
    suspend fun graphEntryGet(address: String): GraphEntry
    suspend fun graphEntryExists(address: String): Boolean
    suspend fun graphEntryCost(publicKey: String): String

    // Registers
    suspend fun registerCreate(ownerSecretKey: String, initialValue: String): PutResult
    suspend fun registerGet(address: String): Register
    suspend fun registerUpdate(ownerSecretKey: String, newValue: String): PutResult
    suspend fun registerCost(publicKey: String): String

    // Vaults
    suspend fun vaultGet(secretKey: String): Vault
    suspend fun vaultPut(secretKey: String, data: ByteArray, contentType: ULong): String
    suspend fun vaultCost(secretKey: String, maxSize: ULong): String

    // Files
    suspend fun fileUploadPublic(path: String): PutResult
    suspend fun fileDownloadPublic(address: String, destPath: String)
    suspend fun dirUploadPublic(path: String): PutResult
    suspend fun dirDownloadPublic(address: String, destPath: String)
    suspend fun archiveGetPublic(address: String): Archive
    suspend fun archivePutPublic(archive: Archive): PutResult
    suspend fun fileCost(path: String, isPublic: Boolean = true, includeArchive: Boolean = false): String
}
