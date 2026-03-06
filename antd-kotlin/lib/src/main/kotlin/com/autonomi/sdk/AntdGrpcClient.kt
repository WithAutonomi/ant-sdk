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
    private val pointerStub = PointerServiceGrpcKt.PointerServiceCoroutineStub(channel)
    private val scratchpadStub = ScratchpadServiceGrpcKt.ScratchpadServiceCoroutineStub(channel)
    private val graphStub = GraphServiceGrpcKt.GraphServiceCoroutineStub(channel)
    private val registerStub = RegisterServiceGrpcKt.RegisterServiceCoroutineStub(channel)
    private val vaultStub = VaultServiceGrpcKt.VaultServiceCoroutineStub(channel)
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

    // ── Pointers ──

    override suspend fun pointerCreate(ownerSecretKey: String, target: PointerTarget): PutResult = try {
        val resp = pointerStub.create(createPointerRequest {
            this.ownerSecretKey = ownerSecretKey
            this.target = pointerTarget { kind = target.kind; address = target.address }
        })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun pointerGet(address: String): Pointer = try {
        val resp = pointerStub.get(getPointerRequest { this.address = address })
        Pointer(resp.address, resp.owner, resp.counter.toULong(), PointerTarget(resp.target.kind, resp.target.address))
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun pointerExists(address: String): Boolean = try {
        val resp = pointerStub.checkExistence(checkPointerRequest { this.address = address })
        resp.exists
    } catch (ex: StatusRuntimeException) {
        if (ex.status.code == Status.Code.NOT_FOUND) false else throw wrap(ex)
    }

    override suspend fun pointerUpdate(ownerSecretKey: String, target: PointerTarget) = try {
        pointerStub.update(updatePointerRequest {
            this.ownerSecretKey = ownerSecretKey
            this.target = pointerTarget { kind = target.kind; address = target.address }
        })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun pointerCost(publicKey: String): String = try {
        val resp = pointerStub.getCost(pointerCostRequest { this.publicKey = publicKey })
        resp.attoTokens
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Scratchpads ──

    override suspend fun scratchpadCreate(ownerSecretKey: String, contentType: ULong, data: ByteArray): PutResult = try {
        val resp = scratchpadStub.create(createScratchpadRequest {
            this.ownerSecretKey = ownerSecretKey
            this.contentType = contentType.toLong()
            this.data = ByteString.copyFrom(data)
        })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun scratchpadGet(address: String): ScratchpadRecord = try {
        val resp = scratchpadStub.get(getScratchpadRequest { this.address = address })
        ScratchpadRecord(resp.address, resp.dataEncoding.toULong(), resp.data.toByteArray(), resp.counter.toULong())
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun scratchpadExists(address: String): Boolean = try {
        val resp = scratchpadStub.checkExistence(checkScratchpadRequest { this.address = address })
        resp.exists
    } catch (ex: StatusRuntimeException) {
        if (ex.status.code == Status.Code.NOT_FOUND) false else throw wrap(ex)
    }

    override suspend fun scratchpadUpdate(ownerSecretKey: String, contentType: ULong, data: ByteArray) = try {
        scratchpadStub.update(updateScratchpadRequest {
            this.ownerSecretKey = ownerSecretKey
            this.contentType = contentType.toLong()
            this.data = ByteString.copyFrom(data)
        })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun scratchpadCost(publicKey: String): String = try {
        val resp = scratchpadStub.getCost(scratchpadCostRequest { this.publicKey = publicKey })
        resp.attoTokens
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

    // ── Registers ──

    override suspend fun registerCreate(ownerSecretKey: String, initialValue: String): PutResult = try {
        val resp = registerStub.create(createRegisterRequest {
            this.ownerSecretKey = ownerSecretKey
            this.initialValue = initialValue
        })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun registerGet(address: String): Register = try {
        val resp = registerStub.get(getRegisterRequest { this.address = address })
        Register(resp.value)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun registerUpdate(ownerSecretKey: String, newValue: String): PutResult = try {
        val resp = registerStub.update(updateRegisterRequest {
            this.ownerSecretKey = ownerSecretKey
            this.newValue = newValue
        })
        PutResult(resp.cost.attoTokens, "")
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun registerCost(publicKey: String): String = try {
        val resp = registerStub.getCost(registerCostRequest { this.publicKey = publicKey })
        resp.attoTokens
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Vaults ──

    override suspend fun vaultGet(secretKey: String): Vault = try {
        val resp = vaultStub.get(getVaultRequest { this.secretKey = secretKey })
        Vault(resp.data.toByteArray(), resp.contentType.toULong())
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun vaultPut(secretKey: String, data: ByteArray, contentType: ULong): String = try {
        val resp = vaultStub.put(putVaultRequest {
            this.secretKey = secretKey
            this.data = ByteString.copyFrom(data)
            this.contentType = contentType.toLong()
        })
        resp.cost.attoTokens
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun vaultCost(secretKey: String, maxSize: ULong): String = try {
        val resp = vaultStub.getCost(vaultCostRequest {
            this.secretKey = secretKey
            this.maxSize = maxSize.toLong()
        })
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
