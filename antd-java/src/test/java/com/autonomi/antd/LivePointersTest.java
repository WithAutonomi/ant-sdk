package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * Live pointer round trip against a running antd with a devnet behind it.
 *
 * <p>Skipped unless all three are set:
 * <ul>
 *   <li>{@code ANTD_TEST_URL}: the daemon's REST base URL, e.g. {@code http://127.0.0.1:8082}</li>
 *   <li>{@code ANTD_TEST_GRPC}: its gRPC target, e.g. {@code 127.0.0.1:50051}</li>
 *   <li>{@code ANTD_TEST_POINTER_OWNERS}: two comma-separated pointer addresses the
 *       daemon holds keys for ({@code antd --pointer-keys}) and that have <b>never been
 *       written</b>. The test creates both, transfers the first to the second, and
 *       leaves the second with a prepared write awaiting payment, so each pair can be
 *       used once.</li>
 * </ul>
 *
 * <p>Every write is paid by the daemon's wallet (two public data uploads and four
 * pointer writes), so run it against a devnet:
 * <pre>
 * ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
 * ANTD_TEST_POINTER_OWNERS=&lt;hex&gt;,&lt;hex&gt; ./gradlew :test --tests com.autonomi.antd.LivePointersTest
 * </pre>
 */
class LivePointersTest {

    /** The daemon accepts a 0x prefix but always returns bare hex. */
    private static String norm(String address) {
        String s = address.trim().toLowerCase(Locale.ROOT);
        return s.startsWith("0x") ? s.substring(2) : s;
    }

    private static String env(String name) {
        String v = System.getenv(name);
        return v == null || v.isBlank() ? null : v.trim();
    }

    @Test
    void livePointerRoundTrip() {
        String url = env("ANTD_TEST_URL");
        String target = env("ANTD_TEST_GRPC");
        String owners = env("ANTD_TEST_POINTER_OWNERS");
        assumeTrue(url != null && target != null && owners != null && owners.contains(","),
                "set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run");
        String[] pair = owners.split(",");
        String a = norm(pair[0]);
        String b = norm(pair[1]);

        try (AntdClient rest = new AntdClient(url, Duration.ofMinutes(5));
             AsyncAntdClient async = new AsyncAntdClient(url, Duration.ofMinutes(5));
             GrpcAntdClient grpc = new GrpcAntdClient(target)) {

            // Both owners must be writable through this daemon.
            Set<String> keys = new HashSet<>();
            rest.pointerKeys().forEach(k -> keys.add(norm(k)));
            assertTrue(keys.contains(a) && keys.contains(b), "daemon holds no key for one of the owners: " + keys);
            Set<String> grpcKeys = new HashSet<>();
            grpc.pointerKeys().forEach(k -> grpcKeys.add(norm(k)));
            assertEquals(keys, grpcKeys);

            // Real targets, so the chain can be followed back to bytes.
            byte[] oneBytes = "antd-java pointer target one".getBytes(StandardCharsets.UTF_8);
            byte[] twoBytes = "antd-java pointer target two".getBytes(StandardCharsets.UTF_8);
            String one = rest.dataPutPublic(oneBytes).address();
            String two = rest.dataPutPublic(twoBytes).address();

            // ── REST: create, read, update ──
            assertThrows(NotFoundException.class, () -> rest.pointerGet(a),
                    "owner " + a + " has been written before; use a fresh pair");
            PointerWriteResult w = rest.pointerCreate(a, one);
            assertEquals(BigInteger.ZERO, w.counter());
            assertEquals(a, norm(w.address()));
            // Refused before anything is paid.
            assertThrows(AlreadyExistsException.class, () -> rest.pointerCreate(a, two));

            PointerRecord r = rest.pointerGet(a);
            assertEquals(BigInteger.ZERO, r.counter());
            assertEquals(norm(one), norm(r.target()));
            assertFalse(r.isFinal());
            assertNull(r.transferredTo());
            assertEquals(PointerTargetKind.CHUNK, r.targetKind().orElseThrow());
            assertEquals(2 * 1952, r.owner().length());

            PointerTarget res = rest.pointerResolve(a);
            assertEquals(norm(one), norm(res.target()));
            assertArrayEquals(oneBytes, rest.dataGetPublic(res.target()));

            w = rest.pointerUpdate(a, two);
            assertEquals(BigInteger.ONE, w.counter());
            assertEquals(norm(two), norm(rest.pointerResolve(a).target()));
            assertEquals(norm(two), norm(async.pointerGetAsync(a).join().target()));
            PointerFinality f = rest.pointerFinality(a);
            assertEquals(PointerFinalityStatus.OPEN, f.status());
            assertEquals(BigInteger.ONE, f.counter());
            assertEquals(f.group(), f.answered());
            assertNull(f.state());

            // ── gRPC: a write, then a read ──
            w = grpc.pointerCreate(b, one);
            assertEquals(BigInteger.ZERO, w.counter());
            r = grpc.pointerGet(b);
            assertEquals(BigInteger.ZERO, r.counter());
            assertEquals(norm(one), norm(r.target()));
            assertNull(r.transferredTo());
            assertThrows(AlreadyExistsException.class, () -> grpc.pointerCreate(b, two));

            // ── transfer a -> b ──
            PointerTransferResult t = rest.pointerTransfer(a, b);
            assertNotNull(t.finality(), "the close group should answer after the transfer: " + t.finalityError());
            assertEquals(PointerFinalityStatus.FINAL, t.finality().status());
            assertEquals(b, norm(t.finality().transferredTo()));
            r = rest.pointerGet(a);
            assertTrue(r.isFinal());
            assertEquals(PointerRecord.FINAL_COUNTER, r.counter());
            assertEquals(b, norm(r.transferredTo()));
            PointerController c = rest.pointerController(a);
            assertEquals(b, norm(c.pointer()));
            assertEquals(List.of(b), c.transfers().stream().map(LivePointersTest::norm).toList());
            assertFalse(c.frozen());
            assertEquals(c, grpc.pointerController(a));
            // a now resolves through b.
            assertEquals(norm(one), norm(grpc.pointerResolve(a).target()));
            PointerFinality gf = grpc.pointerFinality(a);
            assertTrue(gf.isFinal());
            assertNull(gf.counter());
            assertEquals(b, norm(gf.transferredTo()));
            assertEquals(PointerRecord.FINAL_COUNTER, grpc.pointerGet(a).counter());

            // A final pointer refuses every write, before anything is paid.
            assertThrows(PointerFinalException.class, () -> rest.pointerUpdate(a, one));
            assertThrows(PointerFinalException.class, () -> grpc.pointerUpdate(a, one));
            assertThrows(PointerFinalException.class, () -> rest.pointerTransfer(a, b));
            assertThrows(PointerFinalException.class,
                    () -> grpc.pointerPrepare(a, PointerOp.update(one, PointerTargetKind.CHUNK)));

            // ── external signer, up to the quote ──
            // Last: the prepared write blocks b's other writes until it expires.
            PointerPrepareResult p = rest.pointerPrepare(
                    b, PointerOp.update(two, PointerTargetKind.CHUNK), new PointerPrepareOptions(true));
            assertEquals("update", p.op());
            assertEquals(BigInteger.ONE, p.counter());
            assertEquals("wave_batch", p.paymentType());
            assertFalse(p.payments().isEmpty());
            assertFalse(p.uploadId().isEmpty());
            assertFalse(p.signedQuotes().isEmpty());
            Set<String> paid = new HashSet<>();
            p.payments().forEach(q -> paid.add(q.quoteHash()));
            p.signedQuotes().forEach(q -> assertFalse(q.quote().isEmpty()));
            assertTrue(p.signedQuotes().stream().anyMatch(q -> paid.contains(q.quoteHash())));

            assertThrows(ConflictException.class, () -> rest.pointerUpdate(b, two));
            assertThrows(ConflictException.class,
                    () -> grpc.pointerPrepare(b, PointerOp.update(two, PointerTargetKind.CHUNK)));
            // A finalize without the payment is refused and keeps the session.
            assertThrows(BadRequestException.class, () -> rest.pointerFinalize(p.uploadId(), Map.of()));
            assertThrows(ConflictException.class, () -> grpc.pointerUpdate(b, two));
        }
    }
}
