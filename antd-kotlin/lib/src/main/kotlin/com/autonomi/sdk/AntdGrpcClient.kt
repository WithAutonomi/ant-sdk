package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.ManagedChannelBuilder
import io.grpc.StatusRuntimeException
import io.grpc.Status

class AntdGrpcClient(target: String = "localhost:50051") : IAntdClient {

    private val channel = ManagedChannelBuilder.forTarget(target).usePlaintext().build()
    private val healthStub = HealthServiceGrpcKt.HealthServiceCoroutineStub(channel)
    private val dataStub = DataServiceGrpcKt.DataServiceCoroutineStub(channel)
    private val chunkStub = ChunkServiceGrpcKt.ChunkServiceCoroutineStub(channel)
    private val graphStub = GraphServiceGrpcKt.GraphServiceCoroutineStub(channel)
    private val fileStub = FileServiceGrpcKt.FileServiceCoroutineStub(channel)

    override fun close() {
        channel.shutdown()
    }

    private fun wrap(ex: StatusRuntimeException): AntdException = ExceptionMapping.fromGrpcStatus(ex)

    // ── Health ──

    override suspend fun health(): HealthStatus = try {
        val resp = healthStub.check(healthCheckRequest { })
        HealthStatus(resp.status == "ok", resp.network.ifEmpty { "unknown" })
    } catch (ex: StatusRuntimeException) {
        if (ex.status.code == Status.Code.UNAVAILABLE) {
            HealthStatus(false, "unknown")
        } else {
            HealthStatus(true, "unknown")
        }
    } catch (_: Exception) {
        HealthStatus(false, "unknown")
    }

    // ── Data ──

    override suspend fun dataPutPublic(data: ByteArray): PutResult = try {
        val resp = dataStub.putPublic(putPublicDataRequest { this.data = ByteString.copyFrom(data) })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataGetPublic(address: String): ByteArray = try {
        val resp = dataStub.getPublic(getPublicDataRequest { this.address = address })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataPutPrivate(data: ByteArray): PutResult = try {
        val resp = dataStub.putPrivate(putPrivateDataRequest { this.data = ByteString.copyFrom(data) })
        PutResult(resp.cost.attoTokens, resp.dataMap)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataGetPrivate(dataMap: String): ByteArray = try {
        val resp = dataStub.getPrivate(getPrivateDataRequest { this.dataMap = dataMap })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataCost(data: ByteArray): String = try {
        val resp = dataStub.getCost(dataCostRequest { this.data = ByteString.copyFrom(data) })
        resp.attoTokens
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Chunks ──

    override suspend fun chunkPut(data: ByteArray): PutResult = try {
        val resp = chunkStub.put(putChunkRequest { this.data = ByteString.copyFrom(data) })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun chunkGet(address: String): ByteArray = try {
        val resp = chunkStub.get(getChunkRequest { this.address = address })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Graph ──

    override suspend fun graphEntryPut(
        ownerSecretKey: String,
        parents: List<String>,
        content: String,
        descendants: List<GraphDescendant>,
    ): PutResult = try {
        val resp = graphStub.put(putGraphEntryRequest {
            this.ownerSecretKey = ownerSecretKey
            this.content = content
            this.parents.addAll(parents)
            this.descendants.addAll(descendants.map { d ->
                graphDescendant { publicKey = d.publicKey; this.content = d.content }
            })
        })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun graphEntryGet(address: String): GraphEntry = try {
        val resp = graphStub.get(getGraphEntryRequest { this.address = address })
        val desc = resp.descendantsList.map { GraphDescendant(it.publicKey, it.content) }
        GraphEntry(resp.owner, resp.parentsList, resp.content, desc)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun graphEntryExists(address: String): Boolean = try {
        val resp = graphStub.checkExistence(checkGraphEntryRequest { this.address = address })
        resp.exists
    } catch (ex: StatusRuntimeException) {
        if (ex.status.code == Status.Code.NOT_FOUND) false else throw wrap(ex)
    }

    override suspend fun graphEntryCost(publicKey: String): String = try {
        val resp = graphStub.getCost(graphEntryCostRequest { this.publicKey = publicKey })
        resp.attoTokens
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Files ──

    override suspend fun fileUploadPublic(path: String): PutResult = try {
        val resp = fileStub.uploadPublic(uploadFileRequest { this.path = path })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileDownloadPublic(address: String, destPath: String) = try {
        fileStub.downloadPublic(downloadPublicRequest { this.address = address; this.destPath = destPath })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dirUploadPublic(path: String): PutResult = try {
        val resp = fileStub.dirUploadPublic(uploadFileRequest { this.path = path })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dirDownloadPublic(address: String, destPath: String) = try {
        fileStub.dirDownloadPublic(downloadPublicRequest { this.address = address; this.destPath = destPath })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun archiveGetPublic(address: String): Archive = try {
        val resp = fileStub.archiveGetPublic(archiveGetRequest { this.address = address })
        val entries = resp.entriesList.map { ArchiveEntry(it.path, it.address, it.created.toULong(), it.modified.toULong(), it.size.toULong()) }
        Archive(entries)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun archivePutPublic(archive: Archive): PutResult = try {
        val resp = fileStub.archivePutPublic(archivePutRequest {
            this.entries.addAll(archive.entries.map { e ->
                archiveEntry {
                    path = e.path; address = e.address
                    created = e.created.toLong(); modified = e.modified.toLong(); size = e.size.toLong()
                }
            })
        })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileCost(path: String, isPublic: Boolean, includeArchive: Boolean): String = try {
        val resp = fileStub.getFileCost(fileCostRequest {
            this.path = path; this.isPublic = isPublic; this.includeArchive = includeArchive
        })
        resp.attoTokens
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }
}
