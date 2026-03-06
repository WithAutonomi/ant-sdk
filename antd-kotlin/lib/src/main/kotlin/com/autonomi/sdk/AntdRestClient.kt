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
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.time.Duration
import java.util.Base64

class AntdRestClient(
    baseUrl: String = "http://localhost:8080",
    timeout: Duration = Duration.ofSeconds(300),
) : IAntdClient {

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

    private suspend inline fun <reified T> putJson(path: String, body: String): T = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$baseUrl$path")
            .put(body.toRequestBody(jsonMediaType))
            .build()
        val response = http.newCall(request).execute()
        ensureSuccess(response)
        json.decodeFromString<T>(response.body!!.string())
    }

    private suspend fun putJsonNoResult(path: String, body: String) = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$baseUrl$path")
            .put(body.toRequestBody(jsonMediaType))
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

    override suspend fun dataPutPublic(data: ByteArray): PutResult {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/data/public", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun dataGetPublic(address: String): ByteArray {
        val resp = getJson<DataGetDto>("/v1/data/public/$address")
        return fromB64(resp.data)
    }

    override suspend fun dataPutPrivate(data: ByteArray): PutResult {
        val body = buildJsonObject { put("data", b64(data)) }.toString()
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

    // ── Pointers ──

    override suspend fun pointerCreate(ownerSecretKey: String, target: PointerTarget): PutResult {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            putJsonObject("target") {
                put("kind", target.kind)
                put("address", target.address)
            }
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/pointers", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun pointerGet(address: String): Pointer {
        val resp = getJson<PointerDto>("/v1/pointers/$address")
        return Pointer(resp.address, resp.owner, resp.counter, PointerTarget(resp.target.kind, resp.target.address))
    }

    override suspend fun pointerExists(address: String): Boolean = headExists("/v1/pointers/$address")

    override suspend fun pointerUpdate(ownerSecretKey: String, target: PointerTarget) {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            putJsonObject("target") {
                put("kind", target.kind)
                put("address", target.address)
            }
        }.toString()
        putJsonNoResult("/v1/pointers/$ownerSecretKey", body)
    }

    override suspend fun pointerCost(publicKey: String): String {
        val body = buildJsonObject { put("public_key", publicKey) }.toString()
        val resp = postJson<CostDto>("/v1/pointers/cost", body)
        return resp.cost
    }

    // ── Scratchpads ──

    override suspend fun scratchpadCreate(ownerSecretKey: String, contentType: ULong, data: ByteArray): PutResult {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            put("content_type", contentType.toLong())
            put("data", b64(data))
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/scratchpads", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun scratchpadGet(address: String): ScratchpadRecord {
        val resp = getJson<ScratchpadDto>("/v1/scratchpads/$address")
        return ScratchpadRecord(resp.address, resp.dataEncoding, fromB64(resp.data), resp.counter)
    }

    override suspend fun scratchpadExists(address: String): Boolean = headExists("/v1/scratchpads/$address")

    override suspend fun scratchpadUpdate(ownerSecretKey: String, contentType: ULong, data: ByteArray) {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            put("content_type", contentType.toLong())
            put("data", b64(data))
        }.toString()
        putJsonNoResult("/v1/scratchpads/$ownerSecretKey", body)
    }

    override suspend fun scratchpadCost(publicKey: String): String {
        val body = buildJsonObject { put("public_key", publicKey) }.toString()
        val resp = postJson<CostDto>("/v1/scratchpads/cost", body)
        return resp.cost
    }

    // ── Graph ──

    override suspend fun graphEntryPut(
        ownerSecretKey: String,
        parents: List<String>,
        content: String,
        descendants: List<GraphDescendant>,
    ): PutResult {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            putJsonArray("parents") { parents.forEach { add(JsonPrimitive(it)) } }
            put("content", content)
            putJsonArray("descendants") {
                descendants.forEach { d ->
                    add(buildJsonObject {
                        put("public_key", d.publicKey)
                        put("content", d.content)
                    })
                }
            }
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/graph", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun graphEntryGet(address: String): GraphEntry {
        val resp = getJson<GraphEntryDto>("/v1/graph/$address")
        val descendants = resp.descendants?.map { GraphDescendant(it.publicKey, it.content) } ?: emptyList()
        return GraphEntry(resp.owner, resp.parents ?: emptyList(), resp.content, descendants)
    }

    override suspend fun graphEntryExists(address: String): Boolean = headExists("/v1/graph/$address")

    override suspend fun graphEntryCost(publicKey: String): String {
        val body = buildJsonObject { put("public_key", publicKey) }.toString()
        val resp = postJson<CostDto>("/v1/graph/cost", body)
        return resp.cost
    }

    // ── Registers ──

    override suspend fun registerCreate(ownerSecretKey: String, initialValue: String): PutResult {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            put("initial_value", initialValue)
        }.toString()
        val resp = postJson<DataPutPublicDto>("/v1/registers", body)
        return PutResult(resp.cost, resp.address)
    }

    override suspend fun registerGet(address: String): Register {
        val resp = getJson<RegisterDto>("/v1/registers/$address")
        return Register(resp.value)
    }

    override suspend fun registerUpdate(ownerSecretKey: String, newValue: String): PutResult {
        val body = buildJsonObject {
            put("owner_secret_key", ownerSecretKey)
            put("new_value", newValue)
        }.toString()
        val resp = putJson<RegisterUpdateDto>("/v1/registers/$ownerSecretKey", body)
        return PutResult(resp.cost, "")
    }

    override suspend fun registerCost(publicKey: String): String {
        val body = buildJsonObject { put("public_key", publicKey) }.toString()
        val resp = postJson<CostDto>("/v1/registers/cost", body)
        return resp.cost
    }

    // ── Vaults ──

    override suspend fun vaultGet(secretKey: String): Vault {
        val resp = getJson<VaultDto>("/v1/vaults?secret_key=$secretKey")
        return Vault(fromB64(resp.data), resp.contentType)
    }

    override suspend fun vaultPut(secretKey: String, data: ByteArray, contentType: ULong): String {
        val body = buildJsonObject {
            put("secret_key", secretKey)
            put("data", b64(data))
            put("content_type", contentType.toLong())
        }.toString()
        val resp = postJson<CostDto>("/v1/vaults", body)
        return resp.cost
    }

    override suspend fun vaultCost(secretKey: String, maxSize: ULong): String {
        val body = buildJsonObject {
            put("secret_key", secretKey)
            put("max_size", maxSize.toLong())
        }.toString()
        val resp = postJson<CostDto>("/v1/vaults/cost", body)
        return resp.cost
    }

    // ── Files ──

    override suspend fun fileUploadPublic(path: String): PutResult {
        val body = buildJsonObject { put("path", path) }.toString()
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

    override suspend fun dirUploadPublic(path: String): PutResult {
        val body = buildJsonObject { put("path", path) }.toString()
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
}
