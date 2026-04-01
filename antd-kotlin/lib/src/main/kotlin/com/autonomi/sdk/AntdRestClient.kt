package com.autonomi.sdk

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
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
        json.decodeFromString<T>(response.body!!.string())
    }

    private suspend inline fun <reified T> postJson(path: String, body: String): T = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$baseUrl$path")
            .post(body.toRequestBody(jsonMediaType))
            .build()
        val response = http.newCall(request).execute()
        ensureSuccess(response)
        json.decodeFromString<T>(response.body!!.string())
    }

    private suspend fun postJsonNoResult(path: String, body: String) = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$baseUrl$path")
            .post(body.toRequestBody(jsonMediaType))
            .build()
        val response = http.newCall(request).execute()
        ensureSuccess(response)
    }

    private suspend fun headExists(path: String): Boolean = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("$baseUrl$path").head().build()
        val response = http.newCall(request).execute()
        if (response.code == 404) return@withContext false
        ensureSuccess(response)
        true
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
        val resp = getJson<HealthResponseDto>("/health")
        HealthStatus(resp.status == "ok", resp.network ?: "unknown")
    } catch (_: Exception) {
        HealthStatus(false, "unknown")
    }

    // ── Data ──

    override suspend fun dataPutPublic(data: ByteArray, paymentMode: String?): PutResult {
        val body = buildJsonObject {
            put("data", b64(data))
            if (paymentMode != null) put("payment_mode", paymentMode)
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/data/public", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun dataGetPublic(address: String): ByteArray {
        val resp = getJson<DataGetDto>("/v1/data/public/$address")
        return fromB64(resp.data)
    }

    override suspend fun dataPutPrivate(data: ByteArray, paymentMode: String?): PutResult {
        val body = buildJsonObject {
            put("data", b64(data))
            if (paymentMode != null) put("payment_mode", paymentMode)
        }.toString()
        val resp = postJson<DataPutPrivateDto>("/v1/data/private", body)
        return PutResult(resp.cost, resp.dataMap)
    }

    override suspend fun dataGetPrivate(dataMap: String): ByteArray {
        val resp = getJson<DataGetDto>("/v1/data/private?data_map=$dataMap")
        return fromB64(resp.data)
    }

    override suspend fun dataCost(data: ByteArray): String {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
        val resp = postJson<CostDto>("/v1/data/cost", body)
        return resp.cost
    }

    // ── Chunks ──

    override suspend fun chunkPut(data: ByteArray): PutResult {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/chunks", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun chunkGet(address: String): ByteArray {
        val resp = getJson<DataGetDto>("/v1/chunks/$address")
        return fromB64(resp.data)
    }

    // ── Files ──

    override suspend fun fileUploadPublic(path: String, paymentMode: String?): PutResult {
        val body = buildJsonObject {
            put("path", path)
            if (paymentMode != null) put("payment_mode", paymentMode)
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/files/upload/public", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun fileDownloadPublic(address: String, destPath: String) {
        val body = buildJsonObject {
            put("address", address)
            put("dest_path", destPath)
        }.toString()
        postJsonNoResult("/v1/files/download/public", body)
    }

    override suspend fun dirUploadPublic(path: String, paymentMode: String?): PutResult {
        val body = buildJsonObject {
            put("path", path)
            if (paymentMode != null) put("payment_mode", paymentMode)
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/dirs/upload/public", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun dirDownloadPublic(address: String, destPath: String) {
        val body = buildJsonObject {
            put("address", address)
            put("dest_path", destPath)
        }.toString()
        postJsonNoResult("/v1/dirs/download/public", body)
    }

    override suspend fun archiveGetPublic(address: String): Archive {
        val resp = getJson<ArchiveDto>("/v1/archives/public/$address")
        val entries = resp.entries?.map { ArchiveEntry(it.path, it.address, it.created, it.modified, it.size) } ?: emptyList()
        return Archive(entries)
    }

    override suspend fun archivePutPublic(archive: Archive): PutResult {
        val body = buildJsonObject {
            putJsonArray("entries") {
                archive.entries.forEach { e ->
                    add(buildJsonObject {
                        put("path", e.path)
                        put("address", e.address)
                        put("created", e.created.toLong())
                        put("modified", e.modified.toLong())
                        put("size", e.size.toLong())
                    })
                }
            }
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/archives/public", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun fileCost(path: String, isPublic: Boolean, includeArchive: Boolean): String {
        val body = buildJsonObject {
            put("path", path)
            put("is_public", isPublic)
            put("include_archive", includeArchive)
        }.toString()
        val resp = postJson<CostDto>("/v1/cost/file", body)
        return resp.cost
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

    /** Prepares a file upload for external signing. */
    override suspend fun prepareUpload(path: String): PrepareUploadResult {
        val body = buildJsonObject { put("path", path) }.toString()
        val resp = postJson<PrepareUploadDto>("/v1/upload/prepare", body)
        val payments = resp.payments?.map { PaymentInfo(it.quoteHash, it.rewardsAddress, it.amount) } ?: emptyList()
        return PrepareUploadResult(resp.uploadId, payments, resp.totalAmount, resp.dataPaymentsAddress, resp.paymentTokenAddress, resp.rpcUrl)
    }

    /** Prepares a data upload for external signing. */
    override suspend fun prepareDataUpload(data: ByteArray): PrepareUploadResult {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
        val resp = postJson<PrepareUploadDto>("/v1/data/prepare", body)
        val payments = resp.payments?.map { PaymentInfo(it.quoteHash, it.rewardsAddress, it.amount) } ?: emptyList()
        return PrepareUploadResult(resp.uploadId, payments, resp.totalAmount, resp.dataPaymentsAddress, resp.paymentTokenAddress, resp.rpcUrl)
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
        return FinalizeUploadResult(resp.address, resp.chunksStored)
    }
}
