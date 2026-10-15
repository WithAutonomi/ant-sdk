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

    // Manifests (the antd release after 0.15.0)
    //
    // ADR-0006 `.ant` files and `ant://` links, built and read by the daemon.
    // Nothing is uploaded or paid for; the calls are free to retry. `resolve`
    // and the default root embedding read from the network, so they can time
    // out. The `.ant` bytes are always raw here; the clients handle the wire
    // form. An invalid entry or input is a BadRequestException whose message
    // names `entries[i]`.
    //
    // Each method has a default body that throws UnsupportedOperationException,
    // so an implementation of this interface written before the manifest API
    // keeps compiling. AntdRestClient and AntdGrpcClient override all three.

    /**
     * Builds a `.ant` manifest from DataMaps and public addresses already in
     * hand. Each entry sets exactly one of [ManifestEntryInput.dataMap]
     * (embedded) or [ManifestEntryInput.address] (public). [options] embeds
     * resolved roots by default ([BuildManifestOptions.embedRoots]).
     *
     * @throws IllegalArgumentException if an entry sets both or neither, before anything is sent.
     * @throws BadRequestException if the daemon rejects an entry (a path such as `../x`, a malformed DataMap).
     */
    suspend fun buildManifest(entries: List<ManifestEntryInput>, options: BuildManifestOptions = BuildManifestOptions()): BuiltManifest =
        throw UnsupportedOperationException("buildManifest is not implemented by this IAntdClient")

    /**
     * Decodes `.ant` bytes. With [resolve], the daemon fetches each entry's
     * DataMap (and wrapper records) to report [ManifestEntryInfo.exactSize]
     * and confirm the DataMap is on the network; content chunks are not
     * fetched, and one entry's failure is reported in its
     * [ManifestEntryInfo.error], not as a failed call.
     *
     * @throws IllegalArgumentException if [manifest] is empty, before anything is sent.
     * @throws BadRequestException if the bytes are not a manifest.
     */
    suspend fun decodeManifest(manifest: ByteArray, resolve: Boolean = false): DecodedManifest =
        throw UnsupportedOperationException("decodeManifest is not implemented by this IAntdClient")

    /**
     * Decodes an `ant://` manifest link, a file link or a bare 64-hex address
     * (the last two as [DecodedManifest.source] "file_link", one public entry
     * with no path). See [decodeManifest] for [resolve].
     *
     * @throws IllegalArgumentException if [link] is empty, before anything is sent.
     * @throws BadRequestException if it is not a link the daemon can read.
     */
    suspend fun decodeManifestLink(link: String, resolve: Boolean = false): DecodedManifest =
        throw UnsupportedOperationException("decodeManifestLink is not implemented by this IAntdClient")

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
