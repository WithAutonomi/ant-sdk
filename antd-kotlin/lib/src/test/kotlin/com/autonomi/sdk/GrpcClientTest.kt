package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.ManagedChannel
import io.grpc.Metadata
import io.grpc.Server
import io.grpc.ServerCall
import io.grpc.ServerCallHandler
import io.grpc.ServerInterceptor
import io.grpc.ServerInterceptors
import io.grpc.ForwardingServerCall
import io.grpc.inprocess.InProcessChannelBuilder
import io.grpc.inprocess.InProcessServerBuilder
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * In-process gRPC tests for AntdGrpcClient covering the external-signer
 * prepare/finalize surface added in V2-284. Mirrors the antd-rust /
 * antd-go / antd-py / antd-java suites.
 */
class GrpcClientTest {

    private lateinit var server: Server
    private lateinit var channel: ManagedChannel
    private lateinit var client: AntdGrpcClient

    @BeforeTest
    fun setUp() {
        val name = InProcessServerBuilder.generateName()
        server = InProcessServerBuilder.forName(name)
            .directExecutor()
            .addService(MockChunkService())
            .addService(MockUploadService())
            // The daemon attaches the total plaintext size as the
            // x-content-length response header so the consumer can surface a
            // byte denominator (V2-510); mimic it with a server interceptor.
            .addService(ServerInterceptors.intercept(MockDataService(), ContentLengthInterceptor()))
            .build()
            .start()

        channel = InProcessChannelBuilder.forName(name).directExecutor().build()
        client = AntdGrpcClient(channel)
    }

    @AfterTest
    fun tearDown() {
        client.close()
        channel.shutdownNow()
        server.shutdownNow()
    }

    // --- Mock servicers ---

    // Server-streams the payload in two chunks so the client's chunk-by-chunk
    // collection is exercised, not just a single message.
    class MockDataService : DataServiceGrpcKt.DataServiceCoroutineImplBase() {
        // When include_progress is set, interleave a progress frame between the
        // data chunks so the oneof mapping is exercised; otherwise emit a pure
        // data-frame stream (the pre-progress behaviour).
        override fun stream(request: Data.StreamDataRequest): Flow<Data.DataChunk> =
            if (request.includeProgress) flowOf(
                dataChunk { progress = downloadProgress { phase = "fetching"; fetched = 1; total = 2 } },
                dataChunk { data = ByteString.copyFromUtf8("sec") },
                dataChunk { data = ByteString.copyFromUtf8("ret") },
            ) else flowOf(
                dataChunk { data = ByteString.copyFromUtf8("sec") },
                dataChunk { data = ByteString.copyFromUtf8("ret") },
            )

        override fun streamPublic(request: Data.StreamPublicDataRequest): Flow<Data.DataChunk> =
            if (request.includeProgress) flowOf(
                dataChunk { progress = downloadProgress { phase = "resolved"; fetched = 0; total = 2 } },
                dataChunk { data = ByteString.copyFromUtf8("hel") },
                dataChunk { data = ByteString.copyFromUtf8("lo") },
            ) else flowOf(
                dataChunk { data = ByteString.copyFromUtf8("hel") },
                dataChunk { data = ByteString.copyFromUtf8("lo") },
            )
    }

    // Sets x-content-length initial metadata per data-stream method, matching
    // the daemon's byte-total header: Stream → "secret" (6), StreamPublic →
    // "hello" (5). Headers arrive before the first message.
    class ContentLengthInterceptor : ServerInterceptor {
        override fun <ReqT, RespT> interceptCall(
            call: ServerCall<ReqT, RespT>,
            headers: Metadata,
            next: ServerCallHandler<ReqT, RespT>,
        ): ServerCall.Listener<ReqT> {
            val total = when (call.methodDescriptor.bareMethodName) {
                "Stream" -> "6"
                "StreamPublic" -> "5"
                else -> null
            }
            val wrapped = object : ForwardingServerCall.SimpleForwardingServerCall<ReqT, RespT>(call) {
                override fun sendHeaders(responseHeaders: Metadata) {
                    if (total != null) {
                        responseHeaders.put(
                            Metadata.Key.of("x-content-length", Metadata.ASCII_STRING_MARSHALLER),
                            total,
                        )
                    }
                    super.sendHeaders(responseHeaders)
                }
            }
            return next.startCall(wrapped, headers)
        }
    }

    class MockChunkService : ChunkServiceGrpcKt.ChunkServiceCoroutineImplBase() {
        override suspend fun prepareChunk(request: Chunks.PrepareChunkRequest): Chunks.PrepareChunkResponse {
            val d = request.data
            // Inputs starting with "EXISTS" → already-stored short-circuit.
            if (d.size() >= 6 && d.substring(0, 6).toStringUtf8() == "EXISTS") {
                return prepareChunkResponse {
                    address = "0xabc"
                    alreadyStored = true
                }
            }
            return prepareChunkResponse {
                address = "0xnewchunk"
                alreadyStored = false
                uploadId = "upid_chunk_42"
                paymentType = "wave_batch"
                payments.add(paymentEntry {
                    quoteHash = "0xq1"
                    rewardsAddress = "0xr1"
                    amount = "100"
                })
                totalAmount = "100"
                paymentVaultAddress = "0xvault"
                paymentTokenAddress = "0xtoken"
                rpcUrl = "http://localhost:8545"
            }
        }

        override suspend fun finalizeChunk(request: Chunks.FinalizeChunkRequest): Chunks.FinalizeChunkResponse {
            // Echo upload_id into address so the test can verify forwarding.
            return finalizeChunkResponse {
                address = "addr_for_${request.uploadId}"
            }
        }
    }

    class MockUploadService : UploadServiceGrpcKt.UploadServiceCoroutineImplBase() {
        override suspend fun prepareFileUpload(request: Upload.PrepareFileUploadRequest): Upload.PrepareUploadResponse {
            // Encode visibility into upload_id for the test.
            return prepareUploadResponse {
                uploadId = "upid_file_${request.visibility}"
                paymentType = "wave_batch"
                payments.add(paymentEntry {
                    quoteHash = "0xqa"
                    rewardsAddress = "0xra"
                    amount = "1"
                })
                totalAmount = "1"
                paymentVaultAddress = "0xvault"
                paymentTokenAddress = "0xtoken"
                rpcUrl = "http://localhost:8545"
            }
        }

        override suspend fun prepareDataUpload(request: Upload.PrepareDataUploadRequest): Upload.PrepareUploadResponse {
            val uid = "upid_data_${request.visibility}"
            val d = request.data
            if (d.size() >= 6 && d.substring(0, 6).toStringUtf8() == "MERKLE") {
                return prepareUploadResponse {
                    uploadId = uid
                    paymentType = "merkle"
                    depth = 7
                    poolCommitments.add(poolCommitmentEntry {
                        poolHash = "0xpool"
                        candidates.add(candidateNodeEntry {
                            rewardsAddress = "0xc1"
                            amount = "5"
                        })
                    })
                    merklePaymentTimestamp = 1_700_000_000L
                    totalAmount = "0"
                    paymentVaultAddress = "0xvault"
                    paymentTokenAddress = "0xtoken"
                    rpcUrl = "http://localhost:8545"
                }
            }
            return prepareUploadResponse {
                uploadId = uid
                paymentType = "wave_batch"
                payments.add(paymentEntry {
                    quoteHash = "0xqb"
                    rewardsAddress = "0xrb"
                    amount = "2"
                })
                totalAmount = "2"
                paymentVaultAddress = "0xvault"
                paymentTokenAddress = "0xtoken"
                rpcUrl = "http://localhost:8545"
            }
        }

        override suspend fun finalizeUpload(request: Upload.FinalizeUploadRequest): Upload.FinalizeUploadResponse {
            // Merkle: winner_pool_hash populated.
            if (request.winnerPoolHash.isNotEmpty()) {
                return finalizeUploadResponse {
                    dataMap = "dm_merkle"
                    address = if (request.storeDataMap) "stored_on_network" else ""
                    chunksStored = 64L
                }
            }
            // Wave-batch: include data_map_address when visibility was public
            // (encoded into upload_id by the prepare mock).
            val dmAddress = if (request.uploadId.endsWith("public")) "addr_public_dm" else ""
            return finalizeUploadResponse {
                dataMap = "dm_wave"
                dataMapAddress = dmAddress
                chunksStored = 3L
            }
        }
    }

    // --- Tests ---

    @Test
    fun prepareUploadOmitsVisibilityWhenNull() = runTest {
        val r = client.prepareUpload("/tmp/x.bin")
        assertEquals("upid_file_", r.uploadId)
        assertEquals("wave_batch", r.paymentType)
        assertEquals(1, r.payments.size)
        assertEquals("0xqa", r.payments[0].quoteHash)
        assertNull(r.depth)
        assertNull(r.poolCommitments)
        assertNull(r.merklePaymentTimestamp)
    }

    @Test
    fun prepareUploadForwardsVisibilityPublic() = runTest {
        val r = client.prepareUpload("/tmp/x.bin", "public")
        assertEquals("upid_file_public", r.uploadId)
    }

    @Test
    fun prepareUploadPublicConvenience() = runTest {
        val r = client.prepareUploadPublic("/tmp/x.bin")
        assertEquals("upid_file_public", r.uploadId)
    }

    @Test
    fun prepareDataUploadWaveBatch() = runTest {
        val r = client.prepareDataUpload("small".toByteArray())
        assertEquals("upid_data_", r.uploadId)
        assertEquals("wave_batch", r.paymentType)
        assertNull(r.depth)
    }

    @Test
    fun prepareDataUploadMerkle() = runTest {
        val r = client.prepareDataUpload("MERKLE-large-payload".toByteArray())
        assertEquals("merkle", r.paymentType)
        assertEquals(7, r.depth)
        assertEquals(1_700_000_000L, r.merklePaymentTimestamp)
        assertEquals(1, r.poolCommitments?.size)
        assertEquals("0xpool", r.poolCommitments!![0].poolHash)
        assertEquals("0xc1", r.poolCommitments!![0].candidates[0].rewardsAddress)
    }

    @Test
    fun finalizeUploadWaveBatchPrivateOmitsDataMapAddress() = runTest {
        val r = client.finalizeUpload("upid_file_", mapOf("0xq1" to "0xtx1"))
        assertEquals("dm_wave", r.dataMap)
        assertEquals("", r.dataMapAddress)
        assertEquals(3L, r.chunksStored)
    }

    @Test
    fun finalizeUploadWaveBatchPublicReturnsDataMapAddress() = runTest {
        val r = client.finalizeUpload("upid_file_public", mapOf("0xq1" to "0xtx1"))
        assertEquals("addr_public_dm", r.dataMapAddress)
    }

    @Test
    fun finalizeMerkleUploadReturnsMerkleResult() = runTest {
        val r = client.finalizeMerkleUpload("upid_data_", "0xwinpool")
        assertEquals("dm_merkle", r.dataMap)
        // store_data_map defaults to false on the wire (proto3 bool default),
        // so address is empty here.
        assertEquals("", r.address)
        assertEquals(64L, r.chunksStored)
    }

    @Test
    fun prepareChunkUploadNewChunk() = runTest {
        val r = client.prepareChunkUpload("newchunk".toByteArray())
        assertFalse(r.alreadyStored)
        assertEquals("0xnewchunk", r.address)
        assertEquals("upid_chunk_42", r.uploadId)
        assertEquals("wave_batch", r.paymentType)
        assertEquals(1, r.payments.size)
        assertEquals("0xq1", r.payments[0].quoteHash)
        assertEquals("100", r.totalAmount)
        assertEquals("http://localhost:8545", r.rpcUrl)
    }

    @Test
    fun prepareChunkUploadAlreadyStoredShortCircuit() = runTest {
        val r = client.prepareChunkUpload("EXISTS-data".toByteArray())
        assertTrue(r.alreadyStored)
        assertEquals("0xabc", r.address)
        assertEquals("", r.uploadId)
        assertTrue(r.payments.isEmpty())
    }

    @Test
    fun finalizeChunkUploadReturnsAddressAndForwardsBody() = runTest {
        val addr = client.finalizeChunkUpload("upid_chunk_42", mapOf("0xq1" to "0xtxabc"))
        assertEquals("addr_for_upid_chunk_42", addr)
    }

    @Test
    fun dataStreamPrivate() = runTest {
        val chunks = client.dataStream("dm123").toList()
        assertEquals("secret", chunks.joinToString("") { String(it) })
    }

    @Test
    fun dataStreamPublic() = runTest {
        val chunks = client.dataStreamPublic("abc123").toList()
        assertEquals("hello", chunks.joinToString("") { String(it) })
    }

    @Test
    fun dataStreamWithProgressPrivate() = runTest {
        val frames = client.dataStreamWithProgress("dm123").toList()
        // meta (x-content-length) + 1 progress frame + 2 data frames.
        assertEquals(4, frames.size)
        assertTrue(frames[0].isMeta)
        assertEquals(6UL, frames[0].totalSize)
        val progress = frames[1]
        assertTrue(progress.isProgress)
        assertEquals("fetching", progress.progress!!.phase)
        assertEquals(1UL, progress.progress!!.fetched)
        assertEquals(2UL, progress.progress!!.total)
        val data = frames.drop(2).joinToString("") { String(it.data!!) }
        assertEquals("secret", data)
        assertFalse(frames[2].isProgress)
    }

    @Test
    fun dataStreamWithProgressPublic() = runTest {
        val frames = client.dataStreamPublicWithProgress("abc123").toList()
        assertEquals(4, frames.size)
        assertTrue(frames[0].isMeta)
        assertEquals(5UL, frames[0].totalSize)
        assertTrue(frames[1].isProgress)
        assertEquals("resolved", frames[1].progress!!.phase)
        assertEquals(2UL, frames[1].progress!!.total)
        val data = frames.drop(2).joinToString("") { String(it.data!!) }
        assertEquals("hello", data)
    }
}
