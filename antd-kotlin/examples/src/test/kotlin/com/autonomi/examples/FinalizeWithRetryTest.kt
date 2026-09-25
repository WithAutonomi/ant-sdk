package com.autonomi.examples

import com.autonomi.sdk.PartialUploadException
import kotlinx.coroutines.test.runTest
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Direct tests for the external-signer example's bounded finalize retry.
 * Whenever it stops it must rethrow the original [PartialUploadException],
 * and it must call finalize again only for a retryable partial store. The
 * backoff `delay` runs on runTest's virtual clock.
 */
class FinalizeWithRetryTest {

    private fun partial(failed: Long, retryable: Boolean, retentionKnown: Boolean = retryable) =
        PartialUploadException(
            "Partial upload: ${10 - failed}/10 chunks stored, $failed failed",
            chunksStored = 10 - failed,
            chunksFailed = failed,
            totalChunks = 10,
            retryable = retryable,
            retentionKnown = retentionKnown,
        )

    @Test
    fun retryableProgressFinishesAgainstTheSamePayment() = runTest {
        var calls = 0
        val result = finalizeWithRetry("up-1") {
            calls++
            if (calls < 3) throw partial(failed = 4L - calls, retryable = true)
            "stored"
        }
        assertEquals("stored", result)
        assertEquals(3, calls)
    }

    @Test
    fun exhaustedAttemptsRethrowTheLastPartialUnchanged() = runTest {
        var calls = 0
        val thrown = mutableListOf<PartialUploadException>()
        val ex = assertFailsWith<PartialUploadException> {
            finalizeWithRetry("up-1", maxAttempts = 3) {
                calls++
                // Progress on every call, so only the attempt cap stops it.
                throw partial(failed = 10L - calls, retryable = true).also { thrown += it }
            }
        }
        assertEquals(3, calls)
        assertSame(thrown.last(), ex)
        assertTrue(ex.retryable)
    }

    @Test
    fun stalledProgressRethrowsTheLastPartialUnchanged() = runTest {
        var calls = 0
        val thrown = mutableListOf<PartialUploadException>()
        val ex = assertFailsWith<PartialUploadException> {
            finalizeWithRetry("up-1") {
                calls++
                // chunksFailed never shrinks: the second call is stuck.
                throw partial(failed = 5, retryable = true).also { thrown += it }
            }
        }
        assertEquals(2, calls)
        assertSame(thrown.last(), ex)
    }

    @Test
    fun unknownRetentionStopsAtOnceWithoutAnotherFinalize() = runTest {
        // Retention unknown: the daemon may still hold the paid attempt, so
        // the helper must not call finalize again, and (having no prepare or
        // pay step) cannot re-prepare or pay; it hands the original back.
        val original = partial(failed = 3, retryable = false, retentionKnown = false)
        var calls = 0
        val ex = assertFailsWith<PartialUploadException> {
            finalizeWithRetry("up-1") {
                calls++
                throw original
            }
        }
        assertEquals(1, calls)
        assertSame(original, ex)
        assertFalse(ex.retentionKnown)
    }

    @Test
    fun knownNotRetainedIsRethrownAtOnceForTheCallerToRePrepare() = runTest {
        val original = partial(failed = 3, retryable = false, retentionKnown = true)
        var calls = 0
        val ex = assertFailsWith<PartialUploadException> {
            finalizeWithRetry("up-1") {
                calls++
                throw original
            }
        }
        assertEquals(1, calls)
        assertSame(original, ex)
        assertTrue(ex.retentionKnown)
        assertFalse(ex.retryable)
    }

    // --- End to end from gRPC status text ---

    /**
     * The SDK's gRPC message parser (`ExceptionMapping.partialUploadFromMessage`)
     * is internal to :lib, so reach it reflectively: these tests feed daemon
     * status text through the same code the gRPC client uses.
     */
    private fun fromGrpcMessage(message: String): PartialUploadException {
        val mapping = Class.forName("com.autonomi.sdk.ExceptionMapping")
        val instance = mapping.getField("INSTANCE").get(null)
        return mapping.getMethod("partialUploadFromMessage", String::class.java)
            .invoke(instance, message) as PartialUploadException
    }

    /** Runs [block] and returns what it printed to stdout. */
    private inline fun capturingStdout(block: () -> Unit): String {
        val original = System.out
        val buffer = ByteArrayOutputStream()
        System.setOut(PrintStream(buffer, true, Charsets.UTF_8))
        try {
            block()
        } finally {
            System.setOut(original)
        }
        return buffer.toString(Charsets.UTF_8)
    }

    private val grpcCounts = "Partial upload: 6/10 chunks stored, 4 failed after retries: quorum"

    @Test
    fun grpcMessageWithoutAReadableHintStopsToReconcileNeverRePrepare() = runTest {
        // The SDK parser's flags must steer the helper to "stop and
        // reconcile", never to "the daemon kept nothing; re-prepare",
        // whenever the daemon's answer on retention could not be read: no
        // hint, the review's truncated retained hint, a truncated
        // not-retained hint.
        for (tail in listOf("", " (paid attempt retai", " (stored chunks persist; re-prepare the same con")) {
            val original = fromGrpcMessage(grpcCounts + tail)
            var calls = 0
            val out = capturingStdout {
                val ex = assertFailsWith<PartialUploadException>(tail) {
                    finalizeWithRetry("up-1") {
                        calls++
                        throw original
                    }
                }
                assertSame(original, ex, tail)
            }
            assertEquals(1, calls, tail)
            assertEquals(listOf(6L, 4L, 10L), listOf(original.chunksStored, original.chunksFailed, original.totalChunks), tail)
            assertFalse(original.retentionKnown, tail)
            assertFalse(original.retryable, tail)
            assertTrue("retention unknown: stopping" in out, "[$tail] $out")
            assertFalse("kept nothing" in out, "[$tail] $out")
        }
    }

    @Test
    fun grpcMessageWithTheNotRetainedHintIsRethrownForRePrepare() = runTest {
        val original = fromGrpcMessage(
            "$grpcCounts (stored chunks persist; re-prepare the same content to retry only the remainder)",
        )
        var calls = 0
        val out = capturingStdout {
            val ex = assertFailsWith<PartialUploadException> {
                finalizeWithRetry("up-1") {
                    calls++
                    throw original
                }
            }
            assertSame(original, ex)
        }
        assertEquals(1, calls)
        assertTrue(original.retentionKnown)
        assertFalse(original.retryable)
        assertTrue("kept nothing" in out, out)
        assertFalse("retention unknown" in out, out)
    }
}
