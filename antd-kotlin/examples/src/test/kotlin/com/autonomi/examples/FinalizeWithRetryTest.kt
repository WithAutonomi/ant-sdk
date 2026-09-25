package com.autonomi.examples

import com.autonomi.sdk.PartialUploadException
import kotlinx.coroutines.test.runTest
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
}
