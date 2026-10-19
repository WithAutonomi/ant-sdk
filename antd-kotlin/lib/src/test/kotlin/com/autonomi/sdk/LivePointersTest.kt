package com.autonomi.sdk

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Live pointer round trip against a running antd with a devnet behind it.
 *
 * Skipped unless all three are set:
 *
 * - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
 * - `ANTD_TEST_GRPC`: its gRPC target, e.g. `127.0.0.1:50051`
 * - `ANTD_TEST_POINTER_OWNERS`: two comma-separated pointer addresses the
 *   daemon holds keys for (`antd --pointer-keys`) and that have **never been
 *   written**. The test creates both, transfers the first to the second, and
 *   leaves the second with a prepared write awaiting payment, so each pair can
 *   be used once.
 *
 * Every write is paid by the daemon's wallet, so run it against a devnet:
 *
 * ```text
 * ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
 * ANTD_TEST_POINTER_OWNERS=<hex>,<hex> ./gradlew :lib:test --tests '*LivePointersTest*'
 * ```
 */
class LivePointersTest {

    private fun env(name: String): String? = System.getenv(name)?.trim()?.takeIf { it.isNotEmpty() }

    /** Bare lowercase hex: the daemon accepts a `0x` prefix but always returns bare hex. */
    private fun norm(address: String) = address.trim().lowercase().removePrefix("0x")

    @Test
    fun `live pointer round trip`() = runBlocking {
        val restUrl = env("ANTD_TEST_URL")
        val grpcTarget = env("ANTD_TEST_GRPC")?.removePrefix("http://")
        val owners = env("ANTD_TEST_POINTER_OWNERS")?.split(',')?.map { norm(it) }?.filter { it.isNotEmpty() }
        assumeTrue(
            restUrl != null && grpcTarget != null && owners != null && owners.size == 2,
            "set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run",
        )
        val (a, b) = owners!!
        val rest = AntdRestClient(restUrl!!)
        val grpc = AntdGrpcClient(grpcTarget!!)
        try {
            // Both owners must be writable through this daemon.
            val keys = rest.pointerKeys().map { norm(it) }
            assertTrue(a in keys && b in keys, "daemon holds no key for one of the owners: $keys")
            assertEquals(keys.toSet(), grpc.pointerKeys().map { norm(it) }.toSet())

            // Real targets, so the chain can be followed back to bytes.
            val bytesOne = "antd-kotlin pointer target one".toByteArray()
            val one = rest.dataPutPublic(bytesOne).address
            val two = rest.dataPutPublic("antd-kotlin pointer target two".toByteArray()).address

            // ── REST: create, read, update ──
            assertFailsWith<NotFoundException>("owner $a has been written before; use a fresh pair") {
                rest.pointerGet(a)
            }
            val created = rest.pointerCreate(a, one)
            assertEquals(0uL, created.counter)
            assertEquals(a, created.address)
            assertFailsWith<AlreadyExistsException> { rest.pointerCreate(a, two) }
            val r0 = rest.pointerGet(a)
            assertEquals(0uL, r0.counter)
            assertEquals(one, r0.target)
            assertFalse(r0.isFinal)
            assertEquals(PointerKind.CHUNK, r0.targetKind)
            assertEquals(2 * 1952, r0.owner.length)
            val res = rest.pointerResolve(a)
            assertEquals(one, res.target)
            assertContentEquals(bytesOne, rest.dataGetPublic(res.target))

            val updated = rest.pointerUpdate(a, two)
            assertEquals(1uL, updated.counter)
            assertEquals(two, rest.pointerResolve(a).target)
            val open = rest.pointerFinality(a)
            assertEquals(PointerFinalityStatus.Open, open.status)
            assertEquals(1uL, open.counter)
            assertEquals(open.group, open.answered)

            // ── gRPC: a write, then reads ──
            val gw = grpc.pointerCreate(b, one)
            assertEquals(0uL, gw.counter)
            val gr = grpc.pointerGet(b)
            assertEquals(0uL, gr.counter)
            assertEquals(one, gr.target)
            assertEquals(null, gr.transferredTo)
            val gOpen = grpc.pointerFinality(a)
            assertEquals(PointerFinalityStatus.Open, gOpen.status)
            assertEquals(1uL, gOpen.counter)

            // ── transfer a -> b ──
            val t = rest.pointerTransfer(a, b)
            val tf = assertNotNull(t.finality, "the close group should answer after the transfer: ${t.finalityError}")
            assertEquals(PointerFinalityStatus.Final, tf.status)
            assertEquals(b, tf.transferredTo)
            val rf = rest.pointerGet(a)
            assertTrue(rf.isFinal)
            assertEquals(ULong.MAX_VALUE, rf.counter)
            assertEquals(b, rf.transferredTo)
            val c = rest.pointerController(a)
            assertEquals(b, c.pointer)
            assertEquals(listOf(b), c.transfers)
            assertFalse(c.frozen)
            // a now resolves through b.
            assertEquals(one, grpc.pointerResolve(a).target)
            val gf = grpc.pointerFinality(a)
            assertTrue(gf.isFinal)
            assertEquals(b, gf.transferredTo)
            assertEquals(ULong.MAX_VALUE, grpc.pointerGet(a).counter)

            // A final pointer refuses every write, before anything is paid.
            assertFailsWith<PointerFinalException> { rest.pointerUpdate(a, one) }
            assertFailsWith<PointerFinalException> { grpc.pointerUpdate(a, one) }
            assertFailsWith<PointerFinalException> { rest.pointerTransfer(a, b) }

            // ── external signer, up to the quote ──
            // Last: the prepared write blocks b's other writes until it expires.
            val p = rest.pointerPrepare(b, PointerOp.Update(two))
            assertEquals("update", p.op)
            assertEquals(1uL, p.counter)
            assertEquals("wave_batch", p.paymentType)
            assertTrue(p.payments.isNotEmpty() && p.uploadId.isNotEmpty())
            assertFailsWith<ConflictException> { rest.pointerUpdate(b, two) }
            assertFailsWith<ConflictException> { grpc.pointerPrepare(b, PointerOp.Update(two)) }
            // A finalize without the payment is refused and keeps the session.
            assertFailsWith<BadRequestException> { rest.pointerFinalize(p.uploadId, emptyMap()) }
            assertFailsWith<BadRequestException> { grpc.pointerFinalize(p.uploadId, emptyMap()) }
            assertFailsWith<ConflictException> { rest.pointerUpdate(b, two) }
            Unit
        } finally {
            rest.close()
            grpc.close()
        }
    }
}
