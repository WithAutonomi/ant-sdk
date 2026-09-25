package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.errors.NetworkException;
import com.autonomi.antd.errors.PartialUploadException;
import com.autonomi.antd.models.FinalizeUploadResult;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Direct tests of {@link Example07ExternalSigner#finalizeWithRetry}: it
 * retries only an attempt the daemon retained, always with the same
 * arguments, never prepares or pays, and whenever it stops it rethrows the
 * original {@link PartialUploadException}.
 */
class FinalizeWithRetryTest {

    private static final String UPLOAD_ID = "up-1";
    private static final Map<String, String> TX_HASHES = Map.of("0xq1", "0xt1", "0xq2", "0xt1");
    private static final FinalizeUploadResult OK = new FinalizeUploadResult("", 12L, "dm", "dma");

    /** Records every backoff pause instead of sleeping. */
    private final List<Long> pauses = new ArrayList<>();
    private final Example07ExternalSigner.Backoff recordPause = pauses::add;

    /** Plays back scripted outcomes and records the arguments of every call. */
    private static final class ScriptedFinalize implements Example07ExternalSigner.FinalizeCall {
        private final Deque<Object> outcomes;
        final List<String> uploadIds = new ArrayList<>();
        final List<Map<String, String>> txHashes = new ArrayList<>();

        ScriptedFinalize(Object... outcomes) {
            this.outcomes = new ArrayDeque<>(List.of(outcomes));
        }

        @Override
        public FinalizeUploadResult call(String uploadId, Map<String, String> tx) {
            uploadIds.add(uploadId);
            txHashes.add(tx);
            Object next = outcomes.removeFirst(); // NoSuchElementException on an unexpected call
            if (next instanceof RuntimeException e) throw e;
            return (FinalizeUploadResult) next;
        }

        int calls() {
            return uploadIds.size();
        }

        void assertIdenticalArguments() {
            for (int i = 0; i < calls(); i++) {
                assertEquals(UPLOAD_ID, uploadIds.get(i), "upload_id of call " + (i + 1));
                assertSame(TX_HASHES, txHashes.get(i), "tx hashes of call " + (i + 1));
            }
        }
    }

    private static PartialUploadException retained(long stored, long failed) {
        return new PartialUploadException("partial", stored, failed, stored + failed, true, true);
    }

    @Test
    void retriesARetainedAttemptWithIdenticalArgumentsUntilItSucceeds() {
        ScriptedFinalize fin = new ScriptedFinalize(retained(2, 10), retained(8, 4), OK);
        FinalizeUploadResult r = Example07ExternalSigner.finalizeWithRetry(
                fin, UPLOAD_ID, TX_HASHES, 5, recordPause);
        assertSame(OK, r);
        assertEquals(3, fin.calls());
        fin.assertIdenticalArguments();
        assertEquals(List.of(2_000L, 4_000L), pauses);
    }

    @Test
    void exhaustionRethrowsTheLastPartialUploadException() {
        PartialUploadException last = retained(3, 7);
        ScriptedFinalize fin = new ScriptedFinalize(retained(1, 9), retained(2, 8), last);
        PartialUploadException ex = assertThrows(PartialUploadException.class,
                () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 3, recordPause));
        assertSame(last, ex, "the typed error the daemon returned, not a wrapper");
        assertEquals(3, fin.calls());
        fin.assertIdenticalArguments();
        assertEquals(List.of(2_000L, 4_000L), pauses);
    }

    @Test
    void stalledProgressRethrowsWithoutFurtherAttempts() {
        // chunksFailed did not shrink between attempts: stuck, stop early.
        PartialUploadException second = retained(5, 5);
        ScriptedFinalize fin = new ScriptedFinalize(retained(5, 5), second);
        PartialUploadException ex = assertThrows(PartialUploadException.class,
                () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 5, recordPause));
        assertSame(second, ex);
        assertEquals(2, fin.calls());
        fin.assertIdenticalArguments();
        assertEquals(List.of(2_000L), pauses);

        // A count that grows is stalled too.
        pauses.clear();
        PartialUploadException worse = retained(4, 6);
        ScriptedFinalize fin2 = new ScriptedFinalize(retained(5, 5), worse);
        assertSame(worse, assertThrows(PartialUploadException.class,
                () -> Example07ExternalSigner.finalizeWithRetry(fin2, UPLOAD_ID, TX_HASHES, 5, recordPause)));
        assertEquals(2, fin2.calls());
    }

    @Test
    void confirmedNonRetentionIsRethrownWithoutRetry() {
        PartialUploadException notRetained = new PartialUploadException("partial", 1, 2, 3, false, true);
        ScriptedFinalize fin = new ScriptedFinalize(notRetained);
        assertSame(notRetained, assertThrows(PartialUploadException.class,
                () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 5, recordPause)));
        assertEquals(1, fin.calls());
        assertTrue(pauses.isEmpty());
    }

    @Test
    void unknownRetentionStopsWithoutRetry() {
        // Unreadable counts with the retained hint: retention unknown, not
        // retryable. The helper must stop at once and hand back the typed error.
        PartialUploadException unknown = PartialUploadException.fromMessage(
                "Partial upload: 0/9223372036854775808 chunks stored, 9223372036854775808 failed "
                        + "(paid attempt retained)");
        assertFalse(unknown.isRetentionKnown());
        ScriptedFinalize fin = new ScriptedFinalize(unknown);
        assertSame(unknown, assertThrows(PartialUploadException.class,
                () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 5, recordPause)));
        assertEquals(1, fin.calls());
        assertTrue(pauses.isEmpty());
    }

    // --- gRPC status text through the SDK parser into the helper ---

    private static final String GRPC_COUNTS =
            "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum";

    /**
     * Runs the helper on a finalize that throws {@code partial} once, asserts
     * it stopped after that one call with the same exception, and returns what
     * it printed to stderr.
     */
    private String stopOn(PartialUploadException partial) {
        ScriptedFinalize fin = new ScriptedFinalize(partial);
        PrintStream original = System.err;
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        System.setErr(new PrintStream(err, true, StandardCharsets.UTF_8));
        try {
            assertSame(partial, assertThrows(PartialUploadException.class,
                    () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 5, recordPause)));
        } finally {
            System.setErr(original);
        }
        assertEquals(1, fin.calls(), "one finalize, no retry");
        assertTrue(pauses.isEmpty());
        return err.toString(StandardCharsets.UTF_8);
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {
            GRPC_COUNTS,
            GRPC_COUNTS + " (paid attempt retai",
            GRPC_COUNTS + " (paid attempt retained: call finalize again",
            GRPC_COUNTS + " (stored chunks persist; re-prepare the same con",
            GRPC_COUNTS + " (something else)",
            GRPC_COUNTS + " (paid attempt retained) trailing",
            "Partial upload: 1/3 chunks stored, 2 failed after retries: "
                    + "peer said (paid attempt retained) (connection reset)",
    })
    void grpcPartialWithoutAReadableHintStopsForReconciliation(String message) {
        // The counts read but the daemon's closing hint does not: the helper
        // must stop at once and warn to reconcile, never retry and never
        // treat it as "nothing retained".
        PartialUploadException partial = PartialUploadException.fromMessage(message);
        String err = stopOn(partial);
        assertTrue(err.contains("unknown retention") && err.contains("reconcile"), err);
        assertFalse(partial.isRetentionKnown(), "retention unknown, not confirmed non-retention");
        assertFalse(partial.isRetryable());
        assertEquals(2L, partial.getChunksFailed(), "the counts still read");
    }

    @Test
    void grpcPartialWithTheNotRetainedHintIsConfirmedNonRetention() {
        // Only the daemon's explicit not-retained hint is confirmed
        // non-retention: the helper stops without the reconcile warning and
        // the caller may re-prepare.
        PartialUploadException partial = PartialUploadException.fromMessage(GRPC_COUNTS
                + " (stored chunks persist; re-prepare the same content to retry only the remainder)");
        String err = stopOn(partial);
        assertFalse(err.contains("unknown retention"), err);
        assertTrue(partial.isRetentionKnown());
        assertFalse(partial.isRetryable());
    }

    @Test
    void interruptionDuringBackoffRethrowsThePartialAndKeepsTheInterrupt() {
        // Real Thread::sleep backoff: the finalize stub interrupts the thread,
        // so the sleep throws at once.
        PartialUploadException partial = retained(1, 2);
        int[] calls = {0};
        Example07ExternalSigner.FinalizeCall fin = (id, tx) -> {
            calls[0]++;
            Thread.currentThread().interrupt();
            throw partial;
        };
        try {
            PartialUploadException ex = assertThrows(PartialUploadException.class,
                    () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 5, Thread::sleep));
            assertSame(partial, ex);
            assertEquals(1, calls[0], "no attempt after the interrupt");
            assertTrue(Thread.currentThread().isInterrupted(), "interrupt status restored");
            assertEquals(1, ex.getSuppressed().length);
            assertInstanceOf(InterruptedException.class, ex.getSuppressed()[0]);
        } finally {
            Thread.interrupted(); // clear for the next test
        }
    }

    @Test
    void nonPartialErrorPropagatesWithoutRetry() {
        NetworkException down = new NetworkException("upstream unreachable");
        ScriptedFinalize fin = new ScriptedFinalize(down);
        assertSame(down, assertThrows(NetworkException.class,
                () -> Example07ExternalSigner.finalizeWithRetry(fin, UPLOAD_ID, TX_HASHES, 5, recordPause)));
        assertEquals(1, fin.calls());
        assertTrue(pauses.isEmpty());
    }

    // --- Through the real AntdClient against a mock daemon ---

    private static MockResponse partial502(String retryableField, long stored, long failed) {
        return new MockResponse()
                .setResponseCode(502)
                .setHeader("Content-Type", "application/json")
                .setBody("{\"error\":\"Partial upload\",\"code\":\"PARTIAL_UPLOAD\","
                        + "\"chunks_stored\":" + stored + ",\"chunks_failed\":" + failed
                        + ",\"total_chunks\":" + (stored + failed) + retryableField + "}");
    }

    @Test
    void realClientRetriesWithIdenticalRequestsAndStopsOnUnknownRetention() throws Exception {
        try (MockWebServer srv = new MockWebServer()) {
            srv.enqueue(partial502(",\"retryable\":true", 8, 4));
            // A daemon (or proxy) that drops the flag: retention unknown.
            srv.enqueue(partial502("", 10, 2));
            srv.start();
            try (AntdClient client = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                PartialUploadException ex = assertThrows(PartialUploadException.class,
                        () -> Example07ExternalSigner.finalizeWithRetry(
                                client::finalizeUpload, UPLOAD_ID, TX_HASHES, 5, recordPause));
                assertFalse(ex.isRetentionKnown());
                assertFalse(ex.isRetryable());
                assertEquals(2L, ex.getChunksFailed());
            }
            assertEquals(2, srv.getRequestCount(), "two finalize calls, no prepare, nothing else");
            RecordedRequest first = srv.takeRequest(1, TimeUnit.SECONDS);
            RecordedRequest second = srv.takeRequest(1, TimeUnit.SECONDS);
            assertEquals("/v1/upload/finalize", first.getPath());
            assertEquals("/v1/upload/finalize", second.getPath());
            assertEquals(first.getBody().readUtf8(), second.getBody().readUtf8(),
                    "the retry must send the identical upload_id and tx hashes");
            assertEquals(List.of(2_000L), pauses);
        }
    }

    @Test
    void productionOverloadStopsOnUnknownRetentionWithoutSleeping() throws Exception {
        // The AntdClient overload wires client::finalizeUpload, the real attempt
        // cap and Thread::sleep; an older daemon's partial (no `retryable`)
        // must come straight back as the typed error.
        try (MockWebServer srv = new MockWebServer()) {
            srv.enqueue(partial502("", 3, 9));
            srv.start();
            try (AntdClient client = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                PartialUploadException ex = assertThrows(PartialUploadException.class,
                        () -> Example07ExternalSigner.finalizeWithRetry(client, UPLOAD_ID, TX_HASHES));
                assertFalse(ex.isRetentionKnown());
                assertEquals(9L, ex.getChunksFailed());
            }
            assertEquals(1, srv.getRequestCount());
        }
    }
}
