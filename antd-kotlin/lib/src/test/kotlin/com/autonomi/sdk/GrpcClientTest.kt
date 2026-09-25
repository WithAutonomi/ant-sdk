package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.Context
import io.grpc.ManagedChannel
import io.grpc.Metadata
import io.grpc.Server
import io.grpc.ServerCall
import io.grpc.ServerCallHandler
import io.grpc.ServerInterceptor
import io.grpc.ServerInterceptors
import io.grpc.ForwardingServerCall
import io.grpc.Status
import io.grpc.inprocess.InProcessChannelBuilder
import io.grpc.inprocess.InProcessServerBuilder
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
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
    private lateinit var healthService: MockHealthService
    private lateinit var healthRequests: RequestCountingInterceptor

    @BeforeTest
    fun setUp() {
        val name = InProcessServerBuilder.generateName()
        healthService = MockHealthService()
        healthRequests = RequestCountingInterceptor()
        server = InProcessServerBuilder.forName(name)
            .directExecutor()
            // Counts the health checks that actually reach the server, so a
            // test can tell a daemon answer from a client-side failure.
            .addService(ServerInterceptors.intercept(healthService, healthRequests))
            .addService(MockChunkService())
            .addService(MockUploadService())
            .addService(MockFileService())
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

    companion object {
        // The daemon's PARTIAL_UPLOAD status descriptions: counts in the fixed
        // prefix, and a "paid attempt retained" hint when the same-upload_id
        // retry applies.
        const val PARTIAL_RETAINED_MSG =
            "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " +
                "(paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"
        const val PARTIAL_NOT_RETAINED_MSG =
            "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum " +
                "(stored chunks persist; re-prepare the same content to retry only the remainder)"
        // Carries the fixed prefix but not the count layout: still a partial
        // upload, just one whose counts cannot be recovered.
        const val PARTIAL_GARBLED_MSG = "Partial upload: counts unavailable"
        // Matches the count layout and carries the hint, but two counts are
        // one past Long.MAX_VALUE and do not convert.
        const val PARTIAL_OVERFLOW_MSG =
            "Partial upload: 0/9223372036854775808 chunks stored, 9223372036854775808 failed (paid attempt retained)"
        // An ABORTED that is not a partial upload at all.
        const val OTHER_ABORTED_MSG = "register fork: concurrent update detected"
    }

    // --- Mock servicers ---

    // The failing unary mocks below throw StatusException (`asException()`),
    // which is also what grpc-kotlin's coroutine stubs surface client-side
    // for any failed unary call; the client must map it, never leak it.

    class MockHealthService : HealthServiceGrpcKt.HealthServiceCoroutineImplBase() {
        // When set, every check() fails with this status.
        var failWith: Status? = null
        // When set, every check() hangs until the call is cancelled.
        var hang = false
        // Released when a check() starts, i.e. the request reached the server.
        val arrived = CountDownLatch(1)

        override suspend fun check(request: Health.HealthCheckRequest): Health.HealthCheckResponse {
            arrived.countDown()
            if (hang) awaitCancellation()
            failWith?.let { throw it.asException() }
            return healthCheckResponse {
                status = "ok"
                network = "testnet"
                version = "0.0.0-test"
            }
        }
    }

    // Server-streams the payload in two chunks so the client's chunk-by-chunk
    // collection is exercised, not just a single message.
    class MockDataService : DataServiceGrpcKt.DataServiceCoroutineImplBase() {
        override suspend fun getPublic(request: Data.GetPublicDataRequest): Data.GetPublicDataResponse {
            throw Status.NOT_FOUND.withDescription("no data at ${request.address}").asException()
        }

        override suspend fun put(request: Data.PutDataRequest): Data.PutDataResponse {
            throw Status.UNAVAILABLE.withDescription("network unreachable").asException()
        }

        override suspend fun cost(request: Data.DataCostRequest): Common.Cost {
            throw Status.INTERNAL.withDescription("cost estimation failed").asException()
        }

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

    // A deadline scheduler that holds the expiry task a Context deadline
    // schedules instead of running it on a clock, so a test decides when the
    // deadline passes. Everything else delegates to [backing].
    class ManualDeadlineScheduler(
        private val backing: ScheduledExecutorService,
    ) : ScheduledExecutorService by backing {
        @Volatile var expiry: Runnable? = null

        override fun schedule(command: Runnable, delay: Long, unit: TimeUnit): ScheduledFuture<*> {
            expiry = command
            // A placeholder that never comes due during the test; the
            // Context cancels it once the deadline has fired.
            return backing.schedule({}, 1, TimeUnit.HOURS)
        }
    }

    class RequestCountingInterceptor : ServerInterceptor {
        val count = AtomicInteger()

        override fun <ReqT, RespT> interceptCall(
            call: ServerCall<ReqT, RespT>,
            headers: Metadata,
            next: ServerCallHandler<ReqT, RespT>,
        ): ServerCall.Listener<ReqT> {
            count.incrementAndGet()
            return next.startCall(call, headers)
        }
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
        override suspend fun get(request: Chunks.GetChunkRequest): Chunks.GetChunkResponse {
            throw Status.NOT_FOUND.withDescription("no chunk at ${request.address}").asException()
        }

        override suspend fun put(request: Chunks.PutChunkRequest): Chunks.PutChunkResponse {
            throw Status.RESOURCE_EXHAUSTED.withDescription("chunk too large").asException()
        }

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
            // Magic id: simulate a quorum-shortfall finalize (PARTIAL_UPLOAD)
            // where the daemon retained the paid attempt.
            if (request.uploadId == "partial") {
                throw Status.ABORTED
                    .withDescription(PARTIAL_RETAINED_MSG)
                    .asRuntimeException()
            }
            // Echo upload_id into address so the test can verify forwarding.
            return finalizeChunkResponse {
                address = "addr_for_${request.uploadId}"
            }
        }
    }

    class MockFileService : FileServiceGrpcKt.FileServiceCoroutineImplBase() {
        override suspend fun get(request: Files.GetFileRequest): Files.GetFileResponse {
            throw Status.NOT_FOUND.withDescription("no file for ${request.dataMap}").asException()
        }

        override suspend fun putPublic(request: Files.PutFileRequest): Files.PutFilePublicResponse {
            throw Status.INVALID_ARGUMENT.withDescription("path is not a file: ${request.path}").asException()
        }
    }

    class MockUploadService : UploadServiceGrpcKt.UploadServiceCoroutineImplBase() {
        override suspend fun prepareFileUpload(request: Upload.PrepareFileUploadRequest): Upload.PrepareUploadResponse {
            // Magic path: the daemon could not read the file.
            if (request.path == "/missing") {
                throw Status.NOT_FOUND.withDescription("file not found: /missing").asException()
            }
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
                totalChunks = 3
                alreadyStoredCount = 1
            }
        }

        override suspend fun prepareDataUpload(request: Upload.PrepareDataUploadRequest): Upload.PrepareUploadResponse {
            val uid = "upid_data_${request.visibility}"
            val d = request.data
            // Inputs starting with "NOFUNDS" → the daemon refuses to quote.
            if (d.size() >= 7 && d.substring(0, 7).toStringUtf8() == "NOFUNDS") {
                throw Status.FAILED_PRECONDITION.withDescription("insufficient funds").asException()
            }
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
            // Magic id: simulate a quorum-shortfall finalize (PARTIAL_UPLOAD)
            // where the daemon retained the paid attempt.
            if (request.uploadId == "partial") {
                throw Status.ABORTED.withDescription(PARTIAL_RETAINED_MSG).asRuntimeException()
            }
            // Magic id: a partial upload the daemon did NOT retain (unpaid
            // merkle batches, or an older daemon's message).
            if (request.uploadId == "partial-final") {
                throw Status.ABORTED.withDescription(PARTIAL_NOT_RETAINED_MSG).asRuntimeException()
            }
            // Magic id: the prefix is present but the counts are garbled.
            if (request.uploadId == "partial-garbled") {
                throw Status.ABORTED.withDescription(PARTIAL_GARBLED_MSG).asRuntimeException()
            }
            // Magic id: the counts match the layout but overflow a Long.
            if (request.uploadId == "partial-overflow") {
                throw Status.ABORTED.withDescription(PARTIAL_OVERFLOW_MSG).asRuntimeException()
            }
            // Magic id: an ABORTED that is not a partial upload.
            if (request.uploadId == "aborted-other") {
                throw Status.ABORTED.withDescription(OTHER_ABORTED_MSG).asRuntimeException()
            }
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
        assertEquals(3L, r.totalChunks)
        assertEquals(1L, r.alreadyStoredCount)
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

    // --- PARTIAL_UPLOAD (ABORTED) → PartialUploadException ---

    @Test
    fun finalizeUploadPartialRetainedMapsToPartialUploadException() = runTest {
        val ex = assertFailsWith<PartialUploadException> {
            client.finalizeUpload("partial", mapOf("0xq1" to "0xtx1"))
        }
        // Counts and the retained hint are parsed from the status message, so
        // the gRPC client matches the REST client's typed exception.
        assertEquals(300L, ex.chunksStored)
        assertEquals(12L, ex.chunksFailed)
        assertEquals(312L, ex.totalChunks)
        assertTrue(ex.retryable, "expected retryable from the retained hint")
        assertTrue(ex.retentionKnown)
        assertEquals(502, ex.statusCode)
        assertEquals(PARTIAL_RETAINED_MSG, ex.message)
        // A 502 has always been a NetworkException; existing catch blocks keep working.
        assertIs<NetworkException>(ex)
    }

    @Test
    fun finalizeMerkleUploadPartialNotRetainedIsNotRetryable() = runTest {
        val ex = assertFailsWith<PartialUploadException> {
            client.finalizeMerkleUpload("partial-final", "0xwinpool")
        }
        assertEquals(300L, ex.chunksStored)
        assertEquals(12L, ex.chunksFailed)
        assertEquals(312L, ex.totalChunks)
        assertFalse(ex.retryable, "no retained hint must read as not retryable")
        assertTrue(ex.retentionKnown, "readable counts without the hint: the daemon kept nothing")
    }

    @Test
    fun finalizeChunkUploadPartialMapsToPartialUploadException() = runTest {
        val ex = assertFailsWith<PartialUploadException> {
            client.finalizeChunkUpload("partial", mapOf("0xq1" to "0xtxabc"))
        }
        assertEquals(300L, ex.chunksStored)
        assertTrue(ex.retryable)
    }

    @Test
    fun finalizeUploadPartialPrefixWithGarbledCountsStillMapsToPartialUpload() = runTest {
        val ex = assertFailsWith<PartialUploadException> {
            client.finalizeUpload("partial-garbled", mapOf("0xq1" to "0xtx1"))
        }
        // The prefix alone decides the type; unparseable counts read as zero
        // and never as retryable.
        assertEquals(0L, ex.chunksStored)
        assertEquals(0L, ex.chunksFailed)
        assertEquals(0L, ex.totalChunks)
        assertFalse(ex.retryable)
        assertFalse(ex.retentionKnown)
        assertEquals(PARTIAL_GARBLED_MSG, ex.message)
    }

    @Test
    fun finalizeUploadPartialWithOverflowingCountsIsNotRetryable() = runTest {
        val ex = assertFailsWith<PartialUploadException> {
            client.finalizeUpload("partial-overflow", mapOf("0xq1" to "0xtx1"))
        }
        // The layout matches and the hint is present, but counts that do not
        // convert must not enable a retry: all three read as zero.
        assertEquals(0L, ex.chunksStored)
        assertEquals(0L, ex.chunksFailed)
        assertEquals(0L, ex.totalChunks)
        assertFalse(ex.retryable)
        assertFalse(ex.retentionKnown)
        assertEquals(PARTIAL_OVERFLOW_MSG, ex.message)
    }

    @Test
    fun finalizeUploadUnrelatedAbortedStaysForkException() = runTest {
        // An ABORTED without the daemon's "Partial upload:" prefix keeps the
        // pre-existing mapping rather than being misreported as a partial upload.
        val ex = assertFailsWith<ForkException> {
            client.finalizeUpload("aborted-other", mapOf("0xq1" to "0xtx1"))
        }
        assertEquals(OTHER_ABORTED_MSG, ex.message)
    }

    @Test
    fun abortedMappingGatesOnPartialUploadPrefix() {
        fun map(msg: String) = ExceptionMapping.fromGrpcStatus(Status.ABORTED.withDescription(msg).asRuntimeException())
        assertIs<PartialUploadException>(map(PARTIAL_RETAINED_MSG))
        assertIs<PartialUploadException>(map(PARTIAL_GARBLED_MSG))
        // Anchored at the start of the description, matching antd-rust: an
        // ABORTED that merely quotes the phrase further in is not a partial
        // upload (the daemon never wraps its own message).
        assertIs<ForkException>(map("finalize failed: $PARTIAL_NOT_RETAINED_MSG"))
        assertIs<ForkException>(map("conflict while handling \"$PARTIAL_RETAINED_MSG\""))
        assertIs<ForkException>(map(" $PARTIAL_RETAINED_MSG"))
        assertIs<ForkException>(map(OTHER_ABORTED_MSG))
        assertIs<ForkException>(map("something else entirely"))
    }

    @Test
    fun partialUploadMessageParserCases() {
        // `known` is retentionKnown: true only when the counts read; the
        // retained hint then decides `retryable`.
        data class Case(
            val msg: String, val stored: Long, val failed: Long, val total: Long,
            val retryable: Boolean, val known: Boolean,
        )
        val cases = listOf(
            // Well-formed with the hint: known and retryable.
            Case(PARTIAL_RETAINED_MSG, 300, 12, 312, true, true),
            // Well-formed without the hint: known, the daemon kept nothing.
            Case(PARTIAL_NOT_RETAINED_MSG, 300, 12, 312, false, true),
            Case("Partial upload: 300/312 chunks stored, 12 failed after retries", 300, 12, 312, false, true),
            // Prefix present, counts garbled: zero counts, unknown.
            Case(PARTIAL_GARBLED_MSG, 0, 0, 0, false, false),
            // Counts garbled AND the retained hint present: still not
            // retryable, and retention unknown — a loop that cannot watch
            // chunksFailed shrink cannot tell progress from a stuck upload,
            // and an unread message says nothing about what was kept.
            Case("$PARTIAL_GARBLED_MSG (paid attempt retained: call finalize again with the same upload_id)", 0, 0, 0, false, false),
            // Counts that match the layout but overflow a Long, with the
            // hint present: none of the three counts is trusted and the
            // hint alone never enables a retry. One overflow per position,
            // plus the two-position message from review.
            Case(PARTIAL_OVERFLOW_MSG, 0, 0, 0, false, false),
            Case("Partial upload: 9223372036854775808/312 chunks stored, 12 failed (paid attempt retained)", 0, 0, 0, false, false),
            Case("Partial upload: 300/9223372036854775808 chunks stored, 12 failed (paid attempt retained)", 0, 0, 0, false, false),
            Case("Partial upload: 300/312 chunks stored, 9223372036854775808 failed (paid attempt retained)", 0, 0, 0, false, false),
            // The largest counts that do convert still read, and with the
            // hint the message is retryable.
            Case("Partial upload: 9223372036854775807/9223372036854775807 chunks stored, 0 failed (paid attempt retained)", Long.MAX_VALUE, 0, Long.MAX_VALUE, true, true),
            // The count layout is anchored like the gate: quoted further in,
            // it does not read.
            Case("finalize failed: Partial upload: 300/312 chunks stored, 12 failed (paid attempt retained)", 0, 0, 0, false, false),
            // The parser itself never decides the exception type; the
            // mapping-level gate does (see abortedMappingGatesOnPartialUploadPrefix).
            Case("something else entirely", 0, 0, 0, false, false),
        )
        for (c in cases) {
            val ex = ExceptionMapping.partialUploadFromMessage(c.msg)
            assertEquals(c.stored, ex.chunksStored, c.msg)
            assertEquals(c.failed, ex.chunksFailed, c.msg)
            assertEquals(c.total, ex.totalChunks, c.msg)
            assertEquals(c.retryable, ex.retryable, c.msg)
            assertEquals(c.known, ex.retentionKnown, c.msg)
            assertEquals(c.msg, ex.message)
        }
    }

    // --- gRPC StatusException → typed AntdException on every method group ---
    //
    // grpc-kotlin's coroutine stubs throw StatusException on a failed unary
    // call. Only the wallet and finalize methods used to catch it; every other
    // method leaked the raw gRPC exception. Each group below asserts the typed
    // exception the REST client would throw for the same daemon error.

    @Test
    fun dataGetPublicNotFoundMapsToNotFoundException() = runTest {
        val ex = assertFailsWith<NotFoundException> { client.dataGetPublic("0xmissing") }
        assertEquals("no data at 0xmissing", ex.message)
        assertEquals(404, ex.statusCode)
    }

    @Test
    fun dataPutUnavailableMapsToNetworkException() = runTest {
        val ex = assertFailsWith<NetworkException> { client.dataPut(byteArrayOf(1, 2, 3), PaymentMode.AUTO) }
        assertEquals("network unreachable", ex.message)
    }

    @Test
    fun dataCostInternalMapsToInternalException() = runTest {
        assertFailsWith<InternalException> { client.dataCost(byteArrayOf(1), PaymentMode.AUTO) }
    }

    @Test
    fun chunkGetNotFoundMapsToNotFoundException() = runTest {
        val ex = assertFailsWith<NotFoundException> { client.chunkGet("0xnochunk") }
        assertEquals("no chunk at 0xnochunk", ex.message)
    }

    @Test
    fun chunkPutResourceExhaustedMapsToTooLargeException() = runTest {
        assertFailsWith<TooLargeException> { client.chunkPut(byteArrayOf(9)) }
    }

    @Test
    fun fileGetNotFoundMapsToNotFoundException() = runTest {
        val ex = assertFailsWith<NotFoundException> { client.fileGet("dm_missing", "/tmp/out") }
        assertEquals("no file for dm_missing", ex.message)
    }

    @Test
    fun filePutPublicInvalidArgumentMapsToBadRequestException() = runTest {
        val ex = assertFailsWith<BadRequestException> { client.filePutPublic("/dev/null", PaymentMode.AUTO) }
        assertEquals("path is not a file: /dev/null", ex.message)
    }

    @Test
    fun prepareUploadNotFoundMapsToNotFoundException() = runTest {
        val ex = assertFailsWith<NotFoundException> { client.prepareUpload("/missing", null) }
        assertEquals("file not found: /missing", ex.message)
    }

    @Test
    fun prepareDataUploadFailedPreconditionMapsToPaymentException() = runTest {
        val ex = assertFailsWith<PaymentException> { client.prepareDataUpload("NOFUNDS".toByteArray(), null) }
        assertEquals("insufficient funds", ex.message)
    }

    @Test
    fun healthOkParsesResponse() = runTest {
        val h = client.health()
        assertTrue(h.ok)
        assertEquals("testnet", h.network)
        assertEquals("0.0.0-test", h.version)
    }

    @Test
    fun healthUnavailableReportsDaemonDown() = runTest {
        healthService.failWith = Status.UNAVAILABLE.withDescription("connection refused")
        val h = client.health()
        assertFalse(h.ok)
        assertEquals("unknown", h.network)
    }

    @Test
    fun healthOtherStatusReportsDaemonUp() = runTest {
        // Any non-UNAVAILABLE status still came from the daemon, so it is
        // reachable; before the shared helper a StatusException here fell
        // through to the generic catch and read as down.
        healthService.failWith = Status.INTERNAL.withDescription("degraded")
        val h = client.health()
        assertTrue(h.ok)
        assertEquals("unknown", h.network)
        assertEquals(1, healthRequests.count.get())
    }

    @Test
    fun healthUnimplementedReportsDaemonUp() = runTest {
        // A daemon without the health service still answered the call.
        healthService.failWith = Status.UNIMPLEMENTED.withDescription("no health service")
        assertTrue(client.health().ok)
        assertEquals(1, healthRequests.count.get())
    }

    @Test
    fun healthInCancelledContextReportsDaemonDown() {
        // gRPC fails the call with CANCELLED on the client side, before any
        // request is sent: that says nothing about the daemon, so the check
        // must not fall into the "any other status means up" branch.
        val ctx = Context.current().withCancellation()
        ctx.cancel(null)
        val h = ctx.call { runBlocking { client.health() } }
        assertFalse(h.ok)
        assertEquals("unknown", h.network)
        assertEquals(0, healthRequests.count.get())
    }

    @Test
    fun healthDeadlineExceededReportsDaemonDown() {
        // The daemon takes the request but never answers; the client's
        // deadline expires and gRPC fails the call with DEADLINE_EXCEEDED,
        // which is not an answer from the daemon.
        //
        // No clock decides the ordering: the deadline is far off (so the call
        // cannot fail locally at start) and its expiry task is held until the
        // server has the request, then run. A slow dispatch can therefore
        // never expire the call before it is sent and turn this into the
        // zero-request case.
        healthService.hang = true
        val backing = Executors.newSingleThreadScheduledExecutor()
        val deadlines = ManualDeadlineScheduler(backing)
        val caller = Executors.newSingleThreadExecutor()
        try {
            val ctx = Context.current().withDeadlineAfter(1, TimeUnit.HOURS, deadlines)
            val pending = caller.submit(Callable { ctx.call { runBlocking { client.health() } } })
            assertTrue(
                healthService.arrived.await(10, TimeUnit.SECONDS),
                "the health check never reached the server",
            )
            assertEquals(1, healthRequests.count.get())
            // The deadline passes now, after the server has the request.
            assertNotNull(deadlines.expiry, "the Context deadline scheduled no expiry").run()
            val h = pending.get(10, TimeUnit.SECONDS)
            assertFalse(h.ok)
            assertEquals("unknown", h.network)
            assertEquals(1, healthRequests.count.get())
        } finally {
            caller.shutdownNow()
            backing.shutdownNow()
        }
    }

    @Test
    fun healthExpiredDeadlineReportsDaemonDown() {
        // A deadline that has already passed fails the call locally with
        // DEADLINE_EXCEEDED; no request reaches the daemon.
        val scheduler = Executors.newSingleThreadScheduledExecutor()
        try {
            val ctx = Context.current().withDeadlineAfter(-1, TimeUnit.SECONDS, scheduler)
            val h = ctx.call { runBlocking { client.health() } }
            assertFalse(h.ok)
            assertEquals(0, healthRequests.count.get())
        } finally {
            scheduler.shutdownNow()
        }
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
