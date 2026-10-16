package com.autonomi.sdk

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * The pointer methods were added to [IAntdClient] with default bodies, so an
 * implementation written before them keeps compiling and throws
 * [UnsupportedOperationException] only if a pointer method is called.
 *
 * That [AntdRestClient] and [AntdGrpcClient] override all ten is shown by
 * PointerRestTest and PointerGrpcTest, which call every pointer method on
 * each client and would get this exception from a missing override.
 */
class PointerInterfaceCompatTest {

    /** An implementation from before the pointer API: it declares none of the pointer methods. */
    private class PrePointerClient : IAntdClient {
        private fun no(): Nothing = throw NotImplementedError()

        override fun close() {}
        override suspend fun health(): HealthStatus = no()
        override suspend fun dataPutPublic(data: ByteArray, paymentMode: PaymentMode): DataPutPublicResult = no()
        override suspend fun dataGetPublic(address: String): ByteArray = no()
        override suspend fun dataPut(data: ByteArray, paymentMode: PaymentMode): DataPutResult = no()
        override suspend fun dataGet(dataMap: String): ByteArray = no()
        override suspend fun dataCost(data: ByteArray, paymentMode: PaymentMode): UploadCostEstimate = no()
        override suspend fun chunkPut(data: ByteArray): PutResult = no()
        override suspend fun chunkGet(address: String): ByteArray = no()
        override suspend fun prepareChunkUpload(data: ByteArray): PrepareChunkResult = no()
        override suspend fun finalizeChunkUpload(uploadId: String, txHashes: Map<String, String>): String = no()
        override suspend fun filePutPublic(path: String, paymentMode: PaymentMode): FilePutPublicResult = no()
        override suspend fun fileGetPublic(address: String, destPath: String): Unit = no()
        override suspend fun filePut(path: String, paymentMode: PaymentMode): FilePutResult = no()
        override suspend fun fileGet(dataMap: String, destPath: String): Unit = no()
        override suspend fun fileCost(path: String, isPublic: Boolean, paymentMode: PaymentMode): UploadCostEstimate = no()
        override suspend fun walletAddress(): WalletAddress = no()
        override suspend fun walletBalance(): WalletBalance = no()
        override suspend fun walletApprove(): Boolean = no()
        override suspend fun prepareUpload(path: String, visibility: String?): PrepareUploadResult = no()
        override suspend fun prepareUploadPublic(path: String): PrepareUploadResult = no()
        override suspend fun prepareDataUpload(data: ByteArray, visibility: String?): PrepareUploadResult = no()
        override suspend fun finalizeUpload(uploadId: String, txHashes: Map<String, String>): FinalizeUploadResult = no()
        override suspend fun finalizeMerkleUpload(uploadId: String, winnerPoolHash: String): FinalizeMerkleUploadResult = no()
    }

    @Test
    fun `pointer methods default to UnsupportedOperationException naming the method`() = runTest {
        val client: IAntdClient = PrePointerClient()
        val a = "aa".repeat(32)
        suspend fun expectUnsupported(name: String, call: suspend () -> Any) {
            val ex = assertFailsWith<UnsupportedOperationException>(name) { call() }
            assertEquals("$name is not implemented by this IAntdClient", ex.message)
        }
        expectUnsupported("pointerKeys") { client.pointerKeys() }
        expectUnsupported("pointerCreate") { client.pointerCreate(a, a) }
        expectUnsupported("pointerUpdate") { client.pointerUpdate(a, a, PointerKind.POINTER) }
        expectUnsupported("pointerTransfer") { client.pointerTransfer(a, a) }
        expectUnsupported("pointerGet") { client.pointerGet(a) }
        expectUnsupported("pointerResolve") { client.pointerResolve(a) }
        expectUnsupported("pointerFinality") { client.pointerFinality(a) }
        expectUnsupported("pointerController") { client.pointerController(a) }
        expectUnsupported("pointerPrepare") { client.pointerPrepare(a, PointerOp.Transfer(a)) }
        expectUnsupported("pointerFinalize") { client.pointerFinalize("pp-1", emptyMap()) }
    }
}
