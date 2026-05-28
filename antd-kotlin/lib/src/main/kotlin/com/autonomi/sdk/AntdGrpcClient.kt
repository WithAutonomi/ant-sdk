package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.ManagedChannelBuilder
import io.grpc.StatusException
import io.grpc.StatusRuntimeException
import io.grpc.Status

class AntdGrpcClient internal constructor(private val channel: io.grpc.ManagedChannel) : IAntdClient {

    constructor(target: String = "localhost:50051") : this(
        ManagedChannelBuilder.forTarget(target).usePlaintext().build()
    )

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
    private val healthStub = HealthServiceGrpcKt.HealthServiceCoroutineStub(channel)
    private val dataStub = DataServiceGrpcKt.DataServiceCoroutineStub(channel)
    private val chunkStub = ChunkServiceGrpcKt.ChunkServiceCoroutineStub(channel)
    private val fileStub = FileServiceGrpcKt.FileServiceCoroutineStub(channel)
    private val walletStub = WalletServiceGrpcKt.WalletServiceCoroutineStub(channel)

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

    override suspend fun dataPutPublic(data: ByteArray, paymentMode: PaymentMode): DataPutPublicResult = try {
        val resp = dataStub.putPublic(putPublicDataRequest {
            this.data = ByteString.copyFrom(data)
            this.paymentMode = paymentMode.wire
        })
        DataPutPublicResult(address = resp.address)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataGetPublic(address: String): ByteArray = try {
        val resp = dataStub.getPublic(getPublicDataRequest { this.address = address })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataPut(data: ByteArray, paymentMode: PaymentMode): DataPutResult = try {
        val resp = dataStub.put(putDataRequest {
            this.data = ByteString.copyFrom(data)
            this.paymentMode = paymentMode.wire
        })
        DataPutResult(dataMap = resp.dataMap)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataGet(dataMap: String): ByteArray = try {
        val resp = dataStub.get(getDataRequest { this.dataMap = dataMap })
        resp.data.toByteArray()
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun dataCost(data: ByteArray, paymentMode: PaymentMode): UploadCostEstimate = try {
        val resp = dataStub.cost(dataCostRequest {
            this.data = ByteString.copyFrom(data)
            this.paymentMode = paymentMode.wire
        })
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

    override suspend fun filePutPublic(path: String, paymentMode: PaymentMode): FilePutPublicResult = try {
        val resp = fileStub.putPublic(putFileRequest {
            this.path = path
            this.paymentMode = paymentMode.wire
        })
        FilePutPublicResult(
            address = resp.address,
            storageCostAtto = resp.storageCostAtto,
            gasCostWei = resp.gasCostWei,
            chunksStored = resp.chunksStored.toULong(),
            paymentModeUsed = resp.paymentModeUsed,
        )
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileGetPublic(address: String, destPath: String) = try {
        fileStub.getPublic(getFilePublicRequest { this.address = address; this.destPath = destPath })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun filePut(path: String, paymentMode: PaymentMode): FilePutResult = try {
        val resp = fileStub.put(putFileRequest {
            this.path = path
            this.paymentMode = paymentMode.wire
        })
        FilePutResult(
            dataMap = resp.dataMap,
            storageCostAtto = resp.storageCostAtto,
            gasCostWei = resp.gasCostWei,
            chunksStored = resp.chunksStored.toULong(),
            paymentModeUsed = resp.paymentModeUsed,
        )
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileGet(dataMap: String, destPath: String) = try {
        fileStub.get(getFileRequest { this.dataMap = dataMap; this.destPath = destPath })
        Unit
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    override suspend fun fileCost(path: String, isPublic: Boolean, paymentMode: PaymentMode): UploadCostEstimate = try {
        val resp = fileStub.cost(fileCostRequest {
            this.path = path
            this.isPublic = isPublic
            this.paymentMode = paymentMode.wire
        })
        UploadCostEstimate(
            resp.attoTokens, resp.fileSize.toULong(), resp.chunkCount.toUInt(),
            resp.estimatedGasCostWei, resp.paymentMode)
    } catch (ex: StatusRuntimeException) { throw wrap(ex) }

    // ── Wallet ──

    // V2-286: parity with REST wallet surface. A missing daemon wallet emits
    // gRPC FailedPrecondition which wrap() surfaces as PaymentException
    // (established FailedPrecondition->Payment convention across all SDKs).
    override suspend fun walletAddress(): WalletAddress = try {
        val resp = walletStub.getAddress(getWalletAddressRequest {})
        WalletAddress(address = resp.address)
    } catch (e: StatusException) {
        throw ExceptionMapping.fromGrpcStatus(e.status.asRuntimeException())
    } catch (e: StatusRuntimeException) {
        throw wrap(e)
    }

    override suspend fun walletBalance(): WalletBalance = try {
        val resp = walletStub.getBalance(getWalletBalanceRequest {})
        WalletBalance(balance = resp.balance, gasBalance = resp.gasBalance)
    } catch (e: StatusException) {
        throw ExceptionMapping.fromGrpcStatus(e.status.asRuntimeException())
    } catch (e: StatusRuntimeException) {
        throw wrap(e)
    }

    override suspend fun walletApprove(): Boolean = try {
        val resp = walletStub.approve(walletApproveRequest {})
        resp.approved
    } catch (e: StatusException) {
        throw ExceptionMapping.fromGrpcStatus(e.status.asRuntimeException())
    } catch (e: StatusRuntimeException) {
        throw wrap(e)
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
