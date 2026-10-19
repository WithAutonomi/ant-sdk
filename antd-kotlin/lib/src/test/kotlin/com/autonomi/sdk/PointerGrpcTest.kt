package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.ManagedChannel
import io.grpc.Metadata
import io.grpc.Server
import io.grpc.Status
import io.grpc.StatusException
import io.grpc.inprocess.InProcessChannelBuilder
import io.grpc.inprocess.InProcessServerBuilder
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The gRPC pointer surface against an in-process PointerService: the proto's
 * unset values ("" and absent messages) mapping to null, counters up to
 * u64::MAX, and the x-antd-error-code trailer deciding the typed exception
 * only when it agrees with the status code.
 */
class PointerGrpcTest {

    private lateinit var server: Server
    private lateinit var channel: ManagedChannel
    private lateinit var client: AntdGrpcClient
    private lateinit var pointers: MockPointerService
    private lateinit var chunks: MockChunkService

    companion object {
        val A = "aa".repeat(32)
        val B = "bb".repeat(32)
        val T1 = "11".repeat(32)
        val SID = "cd".repeat(32)
        const val MAX = "18446744073709551615"

        private val CODE_KEY: Metadata.Key<String> =
            Metadata.Key.of("x-antd-error-code", Metadata.ASCII_STRING_MARSHALLER)

        /** A failed status as the daemon sends it, optionally tagged with its antd code. */
        fun failure(status: Status, message: String, tag: String? = null): StatusException {
            val trailers = Metadata()
            if (tag != null) trailers.put(CODE_KEY, tag)
            return status.withDescription(message).asException(trailers)
        }

        fun finalState(target: String, holders: Int, transferredTo: String = "") = pointerFinalState {
            stateId = SID
            kind = "pointer"
            kindTag = 1
            this.target = target
            this.holders = holders
            this.transferredTo = transferredTo
        }
    }

    /** Answers every RPC from fields a test sets; records the last request of each kind. */
    class MockPointerService : PointerServiceGrpcKt.PointerServiceCoroutineImplBase() {
        var failWith: StatusException? = null
        var counter = "0"
        var finality: Pointers.PointerFinality? = null
        var record: Pointers.PointerRecord = pointerRecord {}
        val calls = mutableMapOf<String, Int>()
        var lastWrite: Pointers.PointerWriteRequest? = null
        var lastTransfer: Pointers.PointerTransferRequest? = null
        var lastPrepare: Pointers.PreparePointerRequest? = null
        var lastFinalize: Pointers.FinalizePointerRequest? = null

        private fun call(name: String) {
            calls[name] = (calls[name] ?: 0) + 1
            failWith?.let { throw it }
        }

        override suspend fun listKeys(request: Pointers.ListPointerKeysRequest): Pointers.ListPointerKeysResponse {
            call("listKeys")
            return listPointerKeysResponse {
                keys += pointerKey { address = A }
                keys += pointerKey { address = B }
            }
        }

        private fun written(request: Pointers.PointerWriteRequest): Pointers.PointerWriteResponse {
            lastWrite = request
            return pointerWriteResponse {
                address = request.owner
                stateId = SID
                counter = this@MockPointerService.counter
            }
        }

        override suspend fun create(request: Pointers.PointerWriteRequest): Pointers.PointerWriteResponse {
            call("create")
            return written(request)
        }

        override suspend fun update(request: Pointers.PointerWriteRequest): Pointers.PointerWriteResponse {
            call("update")
            return written(request)
        }

        override suspend fun transfer(request: Pointers.PointerTransferRequest): Pointers.PointerTransferResponse {
            call("transfer")
            lastTransfer = request
            return pointerTransferResponse {
                address = request.owner
                stateId = SID
                this@MockPointerService.finality?.let { finality = it } ?: run { finalityError = "close group did not answer" }
            }
        }

        override suspend fun get(request: Pointers.GetPointerRequest): Pointers.PointerRecord {
            call("get")
            return record
        }

        override suspend fun resolve(request: Pointers.ResolvePointerRequest): Pointers.PointerResolved {
            call("resolve")
            return pointerResolved {
                kind = "chunk"
                kindTag = 0
                target = T1
            }
        }

        override suspend fun finality(request: Pointers.PointerFinalityRequest): Pointers.PointerFinality {
            call("finality")
            return this.finality ?: pointerFinality { address = request.address }
        }

        override suspend fun controller(request: Pointers.PointerControllerRequest): Pointers.PointerController {
            call("controller")
            return pointerController {
                pointer = B
                transfers += B
                frozen = false
            }
        }

        override suspend fun prepare(request: Pointers.PreparePointerRequest): Pointers.PreparePointerResponse {
            call("prepare")
            lastPrepare = request
            return preparePointerResponse {
                uploadId = "pp-1"
                op = request.op
                address = request.owner
                stateId = SID
                counter = this@MockPointerService.counter
                paymentType = "wave_batch"
                payments += paymentEntry {
                    quoteHash = "0xqh"
                    rewardsAddress = "0xra"
                    amount = "7"
                }
                totalAmount = "7"
                paymentVaultAddress = "0xvault"
                paymentTokenAddress = "0xtoken"
                rpcUrl = "http://localhost:8545"
                if (request.includeSignedQuotes) {
                    signedQuotes += signedQuoteEntry {
                        quoteHash = "0xqh"
                        quote = ByteString.copyFromUtf8("quote")
                    }
                    signedQuotes += signedQuoteEntry {
                        quoteHash = "0xqh2"
                        quote = ByteString.copyFromUtf8("q2")
                        commitmentSidecar = ByteString.copyFromUtf8("side")
                    }
                }
            }
        }

        override suspend fun finalize(request: Pointers.FinalizePointerRequest): Pointers.FinalizePointerResponse {
            call("finalize")
            lastFinalize = request
            return finalizePointerResponse {
                address = A
                stateId = SID
                counter = this@MockPointerService.counter
                this@MockPointerService.finality?.let { finality = it }
            }
        }
    }

    /** A non-pointer service, to show the trailer mapping is not pointer-only. */
    class MockChunkService : ChunkServiceGrpcKt.ChunkServiceCoroutineImplBase() {
        var failWith: StatusException? = null

        override suspend fun put(request: Chunks.PutChunkRequest): Chunks.PutChunkResponse {
            failWith?.let { throw it }
            return putChunkResponse { address = T1 }
        }
    }

    @BeforeTest
    fun setUp() {
        val name = InProcessServerBuilder.generateName()
        pointers = MockPointerService()
        chunks = MockChunkService()
        server = InProcessServerBuilder.forName(name)
            .directExecutor()
            .addService(pointers)
            .addService(chunks)
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

    // ── Methods ──

    @Test
    fun `pointerKeys lists the addresses`() = runTest {
        assertEquals(listOf(A, B), client.pointerKeys())
    }

    @Test
    fun `pointerCreate and pointerUpdate send owner, target and kind`() = runTest {
        val w = client.pointerCreate(A, T1)
        assertEquals(PointerWriteResult(A, SID, 0uL), w)
        assertEquals(A, pointers.lastWrite!!.owner)
        assertEquals(T1, pointers.lastWrite!!.target)
        assertEquals("chunk", pointers.lastWrite!!.kind)

        pointers.counter = "12"
        val u = client.pointerUpdate(A, B, PointerKind.POINTER)
        assertEquals(12uL, u.counter)
        assertEquals("pointer", pointers.lastWrite!!.kind)
        assertEquals(1, pointers.calls["create"])
        assertEquals(1, pointers.calls["update"])
    }

    @Test
    fun `pointerGet reads a final record and maps empty strings to null`() = runTest {
        pointers.record = pointerRecord {
            address = A
            owner = "ab"
            counter = MAX
            kind = "chunk"
            kindTag = 0
            target = T1
            stateId = SID
            isFinal = true
            transferredTo = B
        }
        val r = client.pointerGet(A)
        assertEquals(ULong.MAX_VALUE, r.counter)
        assertTrue(r.isFinal)
        assertEquals(B, r.transferredTo)
        assertEquals(PointerKind.CHUNK, r.targetKind)

        pointers.record = pointerRecord {
            address = A
            counter = "2"
            kind = "unknown"
            kindTag = 9
        }
        val open = client.pointerGet(A)
        assertEquals(2uL, open.counter)
        assertFalse(open.isFinal)
        assertNull(open.transferredTo)
        assertEquals(9u, open.kindTag)
        assertNull(open.targetKind)
    }

    @Test
    fun `pointerResolve and pointerController`() = runTest {
        assertEquals(PointerTarget("chunk", 0u, T1), client.pointerResolve(A))
        assertEquals(PointerController(B, listOf(B), false), client.pointerController(A))
    }

    @Test
    fun `pointerFinality maps unset fields to null`() = runTest {
        pointers.finality = pointerFinality {
            address = A
            group = 7
            answered = 6
            status = "open"
        }
        val f = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Open, f.status)
        assertEquals(7u, f.group)
        assertEquals(6u, f.answered)
        assertNull(f.counter)
        assertNull(f.state)
        assertNull(f.majority)
        assertNull(f.transferredTo)
        assertTrue(f.states.isEmpty())
    }

    @Test
    fun `pointerFinality reads the counter, states and majority`() = runTest {
        pointers.finality = pointerFinality {
            address = A
            status = "open"
            counter = "4"
        }
        assertEquals(4uL, client.pointerFinality(A).counter)

        pointers.finality = pointerFinality {
            address = A
            status = "forked"
            states += finalState(T1, 4)
            states += finalState(B, 2)
            majority = finalState(T1, 4)
        }
        val forked = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Forked, forked.status)
        assertEquals(listOf(4u, 2u), forked.states.map { it.holders })
        assertEquals(T1, forked.majority!!.target)
        assertNull(forked.states[0].transferredTo)

        pointers.finality = pointerFinality {
            address = A
            status = "final"
            state = finalState(B, 7, B)
            transferredTo = B
        }
        val fin = client.pointerFinality(A)
        assertTrue(fin.isFinal)
        assertEquals(PointerFinalState(SID, "pointer", 1u, B, 7u, B), fin.state)
        assertEquals(B, fin.transferredTo)

        pointers.finality = pointerFinality { status = "contested" }
        assertEquals(PointerFinalityStatus.Unknown("contested"), client.pointerFinality(A).status)
    }

    @Test
    fun `pointerTransfer carries the finality, or why it is missing`() = runTest {
        pointers.finality = pointerFinality {
            address = A
            status = "final"
            transferredTo = B
        }
        val t = client.pointerTransfer(A, B)
        assertEquals(A, pointers.lastTransfer!!.owner)
        assertEquals(B, pointers.lastTransfer!!.recipient)
        assertTrue(t.finality!!.isFinal)
        assertNull(t.finalityError)

        pointers.finality = null
        val missing = client.pointerTransfer(A, B)
        assertNull(missing.finality)
        assertEquals("close group did not answer", missing.finalityError)
    }

    @Test
    fun `pointerPrepare sends the op fields and base64-encodes signed quotes`() = runTest {
        pointers.counter = "3"
        val p = client.pointerPrepare(A, PointerOp.Update(T1, PointerKind.POINTER), includeSignedQuotes = true)
        val req = pointers.lastPrepare!!
        assertEquals("update", req.op)
        assertEquals(T1, req.target)
        assertEquals("pointer", req.kind)
        assertEquals("", req.recipient)
        assertTrue(req.includeSignedQuotes)
        assertEquals("pp-1", p.uploadId)
        assertEquals("update", p.op)
        assertEquals(3uL, p.counter)
        assertEquals("wave_batch", p.paymentType)
        assertEquals(listOf(PaymentInfo("0xqh", "0xra", "7")), p.payments)
        assertEquals("http://localhost:8545", p.rpcUrl)
        assertEquals(
            listOf(SignedQuoteEntry("0xqh", "cXVvdGU=", null), SignedQuoteEntry("0xqh2", "cTI=", "c2lkZQ==")),
            p.signedQuotes,
        )

        client.pointerPrepare(A, PointerOp.Transfer(B))
        assertEquals("transfer", pointers.lastPrepare!!.op)
        assertEquals(B, pointers.lastPrepare!!.recipient)
        assertEquals("", pointers.lastPrepare!!.target)
        assertFalse(pointers.lastPrepare!!.includeSignedQuotes)
    }

    @Test
    fun `pointerFinalize sends the tx hashes and reads a transfer's finality`() = runTest {
        pointers.counter = MAX
        pointers.finality = pointerFinality { status = "settling" }
        val r = client.pointerFinalize("pp-1", mapOf("0xqh" to "0xtx"))
        assertEquals("pp-1", pointers.lastFinalize!!.uploadId)
        assertEquals(mapOf("0xqh" to "0xtx"), pointers.lastFinalize!!.txHashesMap)
        assertEquals(ULong.MAX_VALUE, r.counter)
        assertEquals(PointerFinalityStatus.Settling, r.finality!!.status)

        pointers.finality = null
        assertNull(client.pointerFinalize("pp-1", emptyMap()).finality)
    }

    @Test
    fun `a malformed counter is an error, never zero`() = runTest {
        for (bad in listOf("", "-1", "+1", "1.5", "18446744073709551616", "١")) {
            pointers.counter = bad
            assertFailsWith<InternalException>("counter \"$bad\"") { client.pointerCreate(A, T1) }
        }
        pointers.finality = pointerFinality { counter = "x" }
        assertFailsWith<InternalException> { client.pointerFinality(A) }
    }

    // ── Errors from the x-antd-error-code trailer ──

    @Test
    fun `tagged FAILED_PRECONDITION maps to the pointer exceptions`() = runTest {
        pointers.failWith = failure(Status.FAILED_PRECONDITION, "Pointer is final: transferred", "POINTER_FINAL")
        val final = assertFailsWith<PointerFinalException> { client.pointerUpdate(A, T1) }
        assertEquals("Pointer is final: transferred", final.message)

        pointers.failWith = failure(Status.FAILED_PRECONDITION, "Pointer is forked", "POINTER_FORKED")
        val forked = assertFailsWith<PointerForkedException> { client.pointerGet(A) }
        assertIs<ForkException>(forked)
    }

    @Test
    fun `FAILED_PRECONDITION without a tag is still a payment error`() = runTest {
        pointers.failWith = failure(Status.FAILED_PRECONDITION, "wallet not funded")
        assertFailsWith<PaymentException> { client.pointerCreate(A, T1) }
    }

    @Test
    fun `tagged ABORTED is a ConflictException, untagged keeps the old mapping`() = runTest {
        pointers.failWith = failure(Status.ABORTED, "Conflict: a prepared write awaits payment", "CONFLICT")
        assertFailsWith<ConflictException> { client.pointerPrepare(A, PointerOp.Update(T1)) }

        pointers.failWith = failure(Status.ABORTED, "something else")
        val untagged = assertFailsWith<ForkException> { client.pointerUpdate(A, T1) }
        assertFalse(untagged is PointerForkedException)

        pointers.failWith = failure(
            Status.ABORTED,
            "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retained: call finalize again)",
        )
        assertFailsWith<PartialUploadException> { client.pointerUpdate(A, T1) }
    }

    @Test
    fun `tagged UNAVAILABLE is a CloseGroupShortfallException, retryable from the closing hint`() = runTest {
        pointers.failWith = failure(
            Status.UNAVAILABLE,
            "Close group shortfall: 4/7 stored (paid attempt retained: call finalize again with the same " +
                "upload_id to store it against the same payment)",
            "CLOSE_GROUP_SHORTFALL",
        )
        val retained = assertFailsWith<CloseGroupShortfallException> { client.pointerFinalize("pp-1", emptyMap()) }
        assertTrue(retained.retryable)
        assertEquals(1, pointers.calls["finalize"], "a paid write is never retried")

        pointers.failWith = failure(Status.UNAVAILABLE, "Close group shortfall: 3/7 answered", "CLOSE_GROUP_SHORTFALL")
        assertFalse(assertFailsWith<CloseGroupShortfallException> { client.pointerFinality(A) }.retryable)

        // The hint quoted mid-message, not closing it, does not count.
        pointers.failWith = failure(
            Status.UNAVAILABLE,
            "Close group shortfall: (paid attempt retained) then more",
            "CLOSE_GROUP_SHORTFALL",
        )
        assertFalse(assertFailsWith<CloseGroupShortfallException> { client.pointerFinality(A) }.retryable)

        pointers.failWith = failure(Status.UNAVAILABLE, "network unreachable")
        assertFailsWith<NetworkException> { client.pointerFinality(A) }
    }

    @Test
    fun `a tag on the wrong status code is ignored`() = runTest {
        pointers.failWith = failure(Status.UNAVAILABLE, "net", "POINTER_FINAL")
        assertFailsWith<NetworkException> { client.pointerGet(A) }
        pointers.failWith = failure(Status.FAILED_PRECONDITION, "pay", "CONFLICT")
        assertFailsWith<PaymentException> { client.pointerGet(A) }
        pointers.failWith = failure(Status.FAILED_PRECONDITION, "pay", "SOMETHING_NEW")
        assertFailsWith<PaymentException> { client.pointerGet(A) }
        pointers.failWith = failure(Status.ALREADY_EXISTS, "Already exists: pointer", "ALREADY_EXISTS")
        assertFailsWith<AlreadyExistsException> { client.pointerCreate(A, T1) }
    }

    @Test
    fun `paid writes are sent once, never retried`() = runTest {
        pointers.failWith = failure(Status.UNAVAILABLE, "Close group shortfall", "CLOSE_GROUP_SHORTFALL")
        assertFailsWith<CloseGroupShortfallException> { client.pointerCreate(A, T1) }
        assertFailsWith<CloseGroupShortfallException> { client.pointerUpdate(A, T1) }
        assertFailsWith<CloseGroupShortfallException> { client.pointerTransfer(A, B) }
        assertFailsWith<CloseGroupShortfallException> { client.pointerFinalize("pp-1", emptyMap()) }
        for (rpc in listOf("create", "update", "transfer", "finalize")) {
            assertEquals(1, pointers.calls[rpc], rpc)
        }
    }

    @Test
    fun `the trailer mapping applies to every call, not only pointers`() = runTest {
        chunks.failWith = failure(Status.UNAVAILABLE, "Close group shortfall: chunk store", "CLOSE_GROUP_SHORTFALL")
        assertFailsWith<CloseGroupShortfallException> { client.chunkPut("x".toByteArray()) }
    }

    @Test
    fun `StatusRuntimeException keeps its trailers through the mapper`() {
        val trailers = Metadata().apply { put(CODE_KEY, "POINTER_FINAL") }
        val ex = Status.FAILED_PRECONDITION.withDescription("final").asRuntimeException(trailers)
        assertIs<PointerFinalException>(ExceptionMapping.fromGrpcStatus(ex))
        assertIs<PaymentException>(
            ExceptionMapping.fromGrpcStatus(Status.FAILED_PRECONDITION.withDescription("pay").asRuntimeException()),
        )
    }
}
