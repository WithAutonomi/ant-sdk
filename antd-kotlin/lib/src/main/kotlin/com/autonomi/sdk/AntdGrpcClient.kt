package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.ManagedChannelBuilder
import io.grpc.StatusRuntimeException
import io.grpc.Status

class AntdGrpcClient(target: String = "localhost:50051") : IAntdClient {

    companion object {
        /**
         * Create a client by auto-discovering the daemon gRPC port from the
         * `daemon.port` file.  Falls back to `localhost:50051` if not found.
         */
        fun autoDiscover(): AntdGrpcClient {
            val target = DaemonDiscovery.discoverGrpcTarget().ifEmpty { "localhost:50051" }
            return AntdGrpcClient(target)
        }
    }

    private val channel = ManagedChannelBuilder.forTarget(target).usePlaintext().build()
    private val healthStub = HealthServiceGrpcKt.HealthServiceCoroutineStub(channel)
    private val dataStub = DataServiceGrpcKt.DataServiceCoroutineStub(channel)
    private val chunkStub = ChunkServiceGrpcKt.ChunkServiceCoroutineStub(channel)
    private val fileStub = FileServiceGrpcKt.FileServiceCoroutineStub(channel)

    override fun close() {
        channel.shutdown()
    }

    private fun wrap(ex: StatusRuntimeException): AntdException = ExceptionMapping.fromGrpcStatus(ex)

    // ── Health ──

    override suspend fun health(): HealthStatus = try {
        val resp = healthStub.check(healthCheckRequest { })
        HealthStatus(
            ok = resp.status == "ok",
            network = resp.network.ifEmpty { "unknown" },
            version = resp.version,
            evmNetwork = resp.evmNetwork,
            uptimeSeconds = resp.uptimeSeconds.toULong(),
            buildCommit = resp.buildCommit,
            paymentTokenAddress = resp.paymentTokenAddress,
            paymentVaultAddress = resp.paymentVaultAddress,
        )
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

    override suspend fun dataPutPublic(data: ByteArray, paymentMode: String?): PutResult = try {
        val resp = dataStub.putPublic(putPublicDataRequest { this.data = ByteString.copyFrom(data) })
        PutResult(resp.cost.attoTokens, resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataGetPublic(address: String): ByteArray = try {
        val resp = dataStub.getPublic(getPublicDataRequest { this.address = address })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataPutPrivate(data: ByteArray, paymentMode: String?): PutResult = try {
        val resp = dataStub.putPrivate(putPrivateDataRequest { this.data = ByteString.copyFrom(data) })
        PutResult(resp.cost.attoTokens, resp.dataMap)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataGetPrivate(dataMap: String): ByteArray = try {
        val resp = dataStub.getPrivate(getPrivateDataRequest { this.dataMap = dataMap })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataCost(data: ByteArray): UploadCostEstimate = try {
        val resp = dataStub.getCost(dataCostRequest { this.data = ByteString.copyFrom(data) })
        UploadCostEstimate(
            resp.attoTokens, resp.fileSize.toULong(), resp.chunkCount.toUInt(),
            resp.estimatedGasCostWei, resp.paymentMode)
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

    override suspend fun prepareChunkUpload(data: ByteArray): PrepareChunkResult {
        throw UnsupportedOperationException("prepareChunkUpload is not yet supported via gRPC")
    }

    override suspend fun finalizeChunkUpload(uploadId: String, txHashes: Map<String, String>): String {
        throw UnsupportedOperationException("finalizeChunkUpload is not yet supported via gRPC")
    }

    // ── Files ──

    override suspend fun fileUploadPublic(path: String, paymentMode: String?): FileUploadResult = try {
        val resp = fileStub.uploadPublic(uploadFileRequest { this.path = path })
        FileUploadResult(
            address = resp.address,
            storageCostAtto = resp.storageCostAtto,
            gasCostWei = resp.gasCostWei,
            chunksStored = resp.chunksStored.toULong(),
            paymentModeUsed = resp.paymentModeUsed,
        )
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileDownloadPublic(address: String, destPath: String) = try {
        fileStub.downloadPublic(downloadPublicRequest { this.address = address; this.destPath = destPath })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dirUploadPublic(path: String, paymentMode: String?): FileUploadResult = try {
        val resp = fileStub.dirUploadPublic(uploadFileRequest { this.path = path })
        FileUploadResult(
            address = resp.address,
            storageCostAtto = resp.storageCostAtto,
            gasCostWei = resp.gasCostWei,
            chunksStored = resp.chunksStored.toULong(),
            paymentModeUsed = resp.paymentModeUsed,
        )
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dirDownloadPublic(address: String, destPath: String) = try {
        fileStub.dirDownloadPublic(downloadPublicRequest { this.address = address; this.destPath = destPath })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileCost(path: String, isPublic: Boolean): UploadCostEstimate = try {
        val resp = fileStub.getFileCost(fileCostRequest {
            this.path = path; this.isPublic = isPublic
        })
        UploadCostEstimate(
            resp.attoTokens, resp.fileSize.toULong(), resp.chunkCount.toUInt(),
            resp.estimatedGasCostWei, resp.paymentMode)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Wallet ──

    override suspend fun walletAddress(): WalletAddress {
        throw UnsupportedOperationException("walletAddress is not yet supported via gRPC")
    }

    override suspend fun walletBalance(): WalletBalance {
        throw UnsupportedOperationException("walletBalance is not yet supported via gRPC")
    }

    override suspend fun walletApprove(): Boolean {
        throw UnsupportedOperationException("walletApprove not available via gRPC")
    }

    // ── External Signer (not yet available via gRPC) ──

    override suspend fun prepareUpload(path: String, visibility: String?): PrepareUploadResult {
        throw UnsupportedOperationException("prepareUpload is not yet supported via gRPC")
    }

    override suspend fun prepareUploadPublic(path: String): PrepareUploadResult {
        throw UnsupportedOperationException("prepareUploadPublic is not yet supported via gRPC")
    }

    override suspend fun prepareDataUpload(data: ByteArray, visibility: String?): PrepareUploadResult {
        throw UnsupportedOperationException("prepareDataUpload is not yet supported via gRPC")
    }

    override suspend fun finalizeUpload(uploadId: String, txHashes: Map<String, String>): FinalizeUploadResult {
        throw UnsupportedOperationException("finalizeUpload is not yet supported via gRPC")
    }

    override suspend fun finalizeMerkleUpload(uploadId: String, winnerPoolHash: String): FinalizeMerkleUploadResult {
        throw UnsupportedOperationException("finalizeMerkleUpload is not yet supported via gRPC")
    }
}
