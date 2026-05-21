package com.autonomi.sdk

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.time.Duration
import java.util.Base64

class AntdRestClient(
    baseUrl: String = "http://localhost:8082",
    timeout: Duration = Duration.ofSeconds(300),
) : IAntdClient {

    companion object {
        /**
         * Create a client by auto-discovering the daemon port from the
         * `daemon.port` file.  Falls back to `http://localhost:8082` if not found.
         */
        fun autoDiscover(timeout: Duration = Duration.ofSeconds(300)): AntdRestClient {
            val url = DaemonDiscovery.discoverDaemonUrl().ifEmpty { "http://localhost:8082" }
            return AntdRestClient(url, timeout)
        }
    }

    private val baseUrl = baseUrl.trimEnd('/')
    private val http = OkHttpClient.Builder()
        .callTimeout(timeout)
        .readTimeout(timeout)
        .writeTimeout(timeout)
        .build()
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    override fun close() {
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }

    // ── Helpers ──

    private suspend inline fun <reified T> getJson(path: String): T = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("$baseUrl$path").get().build()
        val response = http.newCall(request).execute()
        ensureSuccess(response)
        json.decodeFromString<T>(( response.body?.string() ?: "" ))
    }

    private suspend inline fun <reified T> postJson(path: String, body: String): T = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$baseUrl$path")
            .post(body.toRequestBody(jsonMediaType))
            .build()
        val response = http.newCall(request).execute()
        ensureSuccess(response)
        json.decodeFromString<T>(( response.body?.string() ?: "" ))
    }

    private suspend fun postJsonNoResult(path: String, body: String) = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$baseUrl$path")
            .post(body.toRequestBody(jsonMediaType))
            .build()
        val response = http.newCall(request).execute()
        ensureSuccess(response)
    }

    private fun ensureSuccess(response: Response) {
        if (response.isSuccessful) return
        val body = response.body?.string() ?: ""
        throw ExceptionMapping.fromHttpStatus(response.code, body)
    }

    private fun b64(data: ByteArray): String = Base64.getEncoder().encodeToString(data)
    private fun fromB64(s: String): ByteArray = Base64.getDecoder().decode(s)

    // ── Health ──

    override suspend fun health(): HealthStatus = try {
        getJson<HealthResponseDto>("/health").toHealthStatus()
    } catch (_: Exception) {
        HealthStatus(false, "unknown")
    }

    // ── Data ──

    override suspend fun dataPutPublic(data: ByteArray, paymentMode: PaymentMode): DataPutPublicResult {
        val body = buildJsonObject {
            put("data", b64(data))
            put("payment_mode", paymentMode.wire)
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/data/public", body)
        return DataPutPublicResult(resp.address, resp.chunksStored, resp.paymentModeUsed)
    }

    override suspend fun dataGetPublic(address: String): ByteArray {
        val resp = getJson<DataGetDto>("/v1/data/public/$address")
        return fromB64(resp.data)
    }

    override suspend fun dataPut(data: ByteArray, paymentMode: PaymentMode): DataPutResult {
        val body = buildJsonObject {
            put("data", b64(data))
            put("payment_mode", paymentMode.wire)
        }.toString()
        val resp = postJson<DataPutDto>("/v1/data", body)
        return DataPutResult(resp.dataMap, resp.chunksStored, resp.paymentModeUsed)
    }

    override suspend fun dataGet(dataMap: String): ByteArray {
        val body = buildJsonObject { put("data_map", dataMap) }.toString()
        val resp = postJson<DataGetDto>("/v1/data/get", body)
        return fromB64(resp.data)
    }

    override suspend fun dataCost(data: ByteArray, paymentMode: PaymentMode): UploadCostEstimate {
        val body = buildJsonObject {
            put("data", b64(data))
            put("payment_mode", paymentMode.wire)
        }.toString()
        val resp = postJson<CostDto>("/v1/data/cost", body)
        return UploadCostEstimate(resp.cost, resp.fileSize, resp.chunkCount, resp.estimatedGasCostWei, resp.paymentMode)
    }

    // ── Chunks ──

    override suspend fun chunkPut(data: ByteArray): PutResult {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
        val resp = postJson<ChunkPutDto>("/v1/chunks", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun chunkGet(address: String): ByteArray {
        val resp = getJson<DataGetDto>("/v1/chunks/$address")
        return fromB64(resp.data)
    }

    /**
     * Prepares a single chunk for external-signer publish via
     * `POST /v1/chunks/prepare`.
     *
     * Returns either `alreadyStored=true` (no payment needed, finalize is
     * unnecessary) or a wave-batch payment intent. After the external signer
     * pays via `payForQuotes`, call [finalizeChunkUpload] with the resulting
     * tx hashes.
     *
     * Requires antd >= 0.7.0.
     */
    override suspend fun prepareChunkUpload(data: ByteArray): PrepareChunkResult {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
        val resp = postJson<PrepareChunkDto>("/v1/chunks/prepare", body)
        val payments = resp.payments?.map {
            PaymentInfo(it.quoteHash, it.rewardsAddress, it.amount)
        } ?: emptyList()
        return PrepareChunkResult(
            address = resp.address,
            alreadyStored = resp.alreadyStored,
            uploadId = resp.uploadId ?: "",
            paymentType = resp.paymentType ?: "",
            payments = payments,
            totalAmount = resp.totalAmount ?: "",
            paymentVaultAddress = resp.paymentVaultAddress ?: "",
            paymentTokenAddress = resp.paymentTokenAddress ?: "",
            rpcUrl = resp.rpcUrl ?: "",
        )
    }

    /**
     * Submits a prepared single chunk to the network after the external signer
     * has paid, via `POST /v1/chunks/finalize`.
     *
     * Returns the network address of the stored chunk (matches
     * [PrepareChunkResult.address]).
     *
     * Requires antd >= 0.7.0.
     */
    override suspend fun finalizeChunkUpload(uploadId: String, txHashes: Map<String, String>): String {
        val body = buildJsonObject {
            put("upload_id", uploadId)
            put("tx_hashes", buildJsonObject {
                txHashes.forEach { (k, v) -> put(k, v) }
            })
        }.toString()
        val resp = postJson<FinalizeChunkDto>("/v1/chunks/finalize", body)
        return resp.address
    }

    // ── Files ──

    override suspend fun filePutPublic(path: String, paymentMode: PaymentMode): FilePutPublicResult {
        val body = buildJsonObject {
            put("path", path)
            put("payment_mode", paymentMode.wire)
        }.toString()
        val resp = postJson<FilePutPublicDto>("/v1/files/public", body)
        return FilePutPublicResult(
            address = resp.address,
            storageCostAtto = resp.storageCostAtto,
            gasCostWei = resp.gasCostWei,
            chunksStored = resp.chunksStored,
            paymentModeUsed = resp.paymentModeUsed,
        )
    }

    override suspend fun fileGetPublic(address: String, destPath: String) {
        val body = buildJsonObject {
            put("address", address)
            put("dest_path", destPath)
        }.toString()
        postJsonNoResult("/v1/files/public/get", body)
    }

    override suspend fun filePut(path: String, paymentMode: PaymentMode): FilePutResult {
        val body = buildJsonObject {
            put("path", path)
            put("payment_mode", paymentMode.wire)
        }.toString()
        val resp = postJson<FilePutDto>("/v1/files", body)
        return FilePutResult(
            dataMap = resp.dataMap,
            storageCostAtto = resp.storageCostAtto,
            gasCostWei = resp.gasCostWei,
            chunksStored = resp.chunksStored,
            paymentModeUsed = resp.paymentModeUsed,
        )
    }

    override suspend fun fileGet(dataMap: String, destPath: String) {
        val body = buildJsonObject {
            put("data_map", dataMap)
            put("dest_path", destPath)
        }.toString()
        postJsonNoResult("/v1/files/get", body)
    }

    override suspend fun fileCost(path: String, isPublic: Boolean, paymentMode: PaymentMode): UploadCostEstimate {
        val body = buildJsonObject {
            put("path", path)
            put("is_public", isPublic)
            put("payment_mode", paymentMode.wire)
        }.toString()
        val resp = postJson<CostDto>("/v1/files/cost", body)
        return UploadCostEstimate(resp.cost, resp.fileSize, resp.chunkCount, resp.estimatedGasCostWei, resp.paymentMode)
    }

    // ── Wallet ──

    override suspend fun walletAddress(): WalletAddress {
        val resp = getJson<WalletAddressDto>("/v1/wallet/address")
        return WalletAddress(resp.address)
    }

    override suspend fun walletBalance(): WalletBalance {
        val resp = getJson<WalletBalanceDto>("/v1/wallet/balance")
        return WalletBalance(resp.balance, resp.gasBalance)
    }

    /** Approves the wallet to spend tokens on payment contracts (one-time operation). */
    override suspend fun walletApprove(): Boolean {
        val body = buildJsonObject {}.toString()
        val resp = postJson<WalletApproveDto>("/v1/wallet/approve", body)
        return resp.approved
    }

    // ── External Signer (Two-Phase Upload) ──

    /**
     * Prepares a file upload for external signing.
     *
     * Pass `visibility = "public"` to bundle the DataMap chunk into the same
     * external-signer payment batch — the resulting `dataMapAddress` on
     * finalize is the shareable retrieval handle. `null` (default) or
     * `"private"` keeps the existing private-only behaviour.
     */
    override suspend fun prepareUpload(path: String, visibility: String?): PrepareUploadResult {
        val body = buildJsonObject {
            put("path", path)
            if (visibility != null) put("visibility", visibility)
        }.toString()
        val resp = postJson<PrepareUploadDto>("/v1/upload/prepare", body)
        return mapPrepareUpload(resp)
    }

    /**
     * Convenience wrapper: prepares a *public* file upload for external
     * signing. Equivalent to [prepareUpload] with `visibility="public"`.
     *
     * Requires antd >= 0.6.1.
     */
    override suspend fun prepareUploadPublic(path: String): PrepareUploadResult =
        prepareUpload(path, visibility = "public")

    /**
     * Prepares a data upload for external signing.
     *
     * Note: `visibility="public"` returns 501 from the daemon until upstream
     * `data_prepare_upload_with_visibility` lands; use [prepareUploadPublic]
     * with a file path until then.
     */
    override suspend fun prepareDataUpload(data: ByteArray, visibility: String?): PrepareUploadResult {
        val body = buildJsonObject {
            put("data", b64(data))
            if (visibility != null) put("visibility", visibility)
        }.toString()
        val resp = postJson<PrepareUploadDto>("/v1/data/prepare", body)
        return mapPrepareUpload(resp)
    }

    /** Finalizes an upload after an external signer has submitted payment transactions. */
    override suspend fun finalizeUpload(uploadId: String, txHashes: Map<String, String>): FinalizeUploadResult {
        val body = buildJsonObject {
            put("upload_id", uploadId)
            put("tx_hashes", buildJsonObject {
                txHashes.forEach { (k, v) -> put(k, v) }
            })
        }.toString()
        val resp = postJson<FinalizeUploadDto>("/v1/upload/finalize", body)
        return FinalizeUploadResult(
            address = resp.address,
            chunksStored = resp.chunksStored,
            dataMap = resp.dataMap,
            dataMapAddress = resp.dataMapAddress,
        )
    }

    /** Finalizes a merkle batch upload by selecting a winner pool. */
    override suspend fun finalizeMerkleUpload(uploadId: String, winnerPoolHash: String): FinalizeMerkleUploadResult {
        val body = buildJsonObject {
            put("upload_id", uploadId)
            put("winner_pool_hash", winnerPoolHash)
        }.toString()
        val resp = postJson<FinalizeUploadDto>("/v1/upload/finalize", body)
        return FinalizeMerkleUploadResult(
            address = resp.address,
            chunksStored = resp.chunksStored,
            dataMap = resp.dataMap,
            dataMapAddress = resp.dataMapAddress,
        )
    }

    private fun mapPrepareUpload(resp: PrepareUploadDto): PrepareUploadResult {
        val payments = resp.payments?.map { PaymentInfo(it.quoteHash, it.rewardsAddress, it.amount) } ?: emptyList()
        val poolCommitments = resp.poolCommitments?.map { pc ->
            PoolCommitmentEntry(pc.poolHash, pc.candidates.map { CandidateNodeEntry(it.rewardsAddress, it.amount) })
        }
        return PrepareUploadResult(
            uploadId = resp.uploadId,
            payments = payments,
            totalAmount = resp.totalAmount,
            paymentVaultAddress = resp.paymentVaultAddress,
            paymentTokenAddress = resp.paymentTokenAddress,
            rpcUrl = resp.rpcUrl,
            paymentType = resp.paymentType ?: "wave_batch",
            depth = resp.depth,
            poolCommitments = poolCommitments,
            merklePaymentTimestamp = resp.merklePaymentTimestamp,
        )
    }
}
