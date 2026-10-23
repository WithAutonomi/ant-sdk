package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.errors.BadRequestException;
import com.autonomi.antd.models.*;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The {@code sha256} fields (antd 0.17.0) over REST against a mock daemon:
 * every upload result reads it when present and {@code null} when absent or
 * empty, a manifest entry sends it only when set, and a manifest entry reads
 * it back (or {@code null}).
 */
class Sha256RestTest {

    static final String SHA = "ab".repeat(32);
    static final String ADDR = ManifestRestTest.ADDR;

    private MockWebServer server;
    private AntdClient client;
    private AsyncAntdClient async;

    @BeforeEach
    void setUp() throws IOException {
        server = new MockWebServer();
        server.start();
        client = new AntdClient(server.url("/").toString(), Duration.ofSeconds(10));
        async = new AsyncAntdClient(server.url("/").toString(), Duration.ofSeconds(10));
    }

    @AfterEach
    void tearDown() throws IOException {
        client.close();
        async.close();
        server.shutdown();
    }

    private void reply(String body) {
        reply(200, body);
    }

    private void reply(int status, String body) {
        server.enqueue(new MockResponse()
                .setResponseCode(status)
                .setHeader("Content-Type", "application/json")
                .setBody(body));
    }

    private RecordedRequest taken() throws InterruptedException {
        RecordedRequest r = server.takeRequest(5, TimeUnit.SECONDS);
        assertNotNull(r, "no request reached the mock daemon");
        return r;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> entriesOf(RecordedRequest r) {
        return (List<Map<String, Object>>) Json.parseObject(r.getBody().readUtf8()).get("entries");
    }

    // ── Upload results ──

    @Test
    void dataPutReadsSha256() {
        reply("{\"data_map\":\"dm\",\"chunks_stored\":3,\"payment_mode_used\":\"single\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, client.dataPut("x".getBytes()).sha256());
    }

    @Test
    void dataPutPublicReadsSha256() {
        reply("{\"address\":\"a\",\"chunks_stored\":3,\"payment_mode_used\":\"single\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, client.dataPutPublic("x".getBytes()).sha256());
    }

    @Test
    void filePutReadsSha256() {
        reply("{\"data_map\":\"dm\",\"storage_cost_atto\":\"1\",\"gas_cost_wei\":\"2\",\"chunks_stored\":3,"
                + "\"payment_mode_used\":\"single\",\"sha256\":\"" + SHA + "\"}");
        FilePutResult r = client.filePut("/tmp/x");
        assertEquals(SHA, r.sha256());
        assertEquals("dm", r.dataMap());
    }

    @Test
    void filePutPublicReadsSha256() {
        reply("{\"address\":\"a\",\"storage_cost_atto\":\"1\",\"gas_cost_wei\":\"2\",\"chunks_stored\":3,"
                + "\"payment_mode_used\":\"single\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, client.filePutPublic("/tmp/x").sha256());
    }

    @Test
    void finalizeReadsSha256() {
        reply("{\"address\":\"\",\"chunks_stored\":2,\"data_map\":\"dm\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, client.finalizeUpload("up1", Map.of("q", "t")).sha256());
        reply("{\"address\":\"\",\"chunks_stored\":2,\"data_map\":\"dm\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, client.finalizeMerkleUpload("up1", "0xwin").sha256());
    }

    @Test
    void asyncUploadsReadSha256() {
        reply("{\"data_map\":\"dm\",\"chunks_stored\":3,\"payment_mode_used\":\"single\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, async.dataPutAsync("x".getBytes()).join().sha256());
        reply("{\"address\":\"a\",\"chunks_stored\":3,\"payment_mode_used\":\"single\",\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, async.dataPutPublicAsync("x".getBytes()).join().sha256());
        reply("{\"data_map\":\"dm\",\"chunks_stored\":3,\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, async.filePutAsync("/tmp/x").join().sha256());
        reply("{\"address\":\"a\",\"chunks_stored\":3,\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, async.filePutPublicAsync("/tmp/x").join().sha256());
        reply("{\"chunks_stored\":2,\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, async.finalizeUploadAsync("up1", Map.of("q", "t")).join().sha256());
        reply("{\"chunks_stored\":2,\"sha256\":\"" + SHA + "\"}");
        assertEquals(SHA, async.finalizeMerkleUploadAsync("up1", "0xwin").join().sha256());
    }

    @Test
    void uploadResultsReadNoneWhenAbsentOrEmpty() {
        // An older daemon omits the key; a mapper must never turn that into "".
        reply("{\"data_map\":\"dm\",\"chunks_stored\":3}");
        assertNull(client.dataPut("x".getBytes()).sha256());
        reply("{\"address\":\"a\",\"chunks_stored\":3}");
        assertNull(client.dataPutPublic("x".getBytes()).sha256());
        reply("{\"data_map\":\"dm\",\"chunks_stored\":3}");
        assertNull(client.filePut("/tmp/x").sha256());
        reply("{\"address\":\"a\",\"chunks_stored\":3}");
        assertNull(client.filePutPublic("/tmp/x").sha256());
        reply("{\"chunks_stored\":2}");
        assertNull(client.finalizeUpload("up1", Map.of("q", "t")).sha256());
        reply("{\"chunks_stored\":2}");
        assertNull(client.finalizeMerkleUpload("up1", "0xwin").sha256());
        // Empty string and null also read as none.
        reply("{\"data_map\":\"dm\",\"chunks_stored\":3,\"sha256\":\"\"}");
        assertNull(client.dataPut("x".getBytes()).sha256());
        reply("{\"address\":\"a\",\"chunks_stored\":3,\"sha256\":null}");
        assertNull(client.dataPutPublic("x".getBytes()).sha256());
        reply("{\"chunks_stored\":2,\"sha256\":\"\"}");
        assertNull(async.finalizeUploadAsync("up1", Map.of("q", "t")).join().sha256());
    }

    @Test
    void resultsBuiltWithTheOldConstructorsHaveNoSha256() {
        assertNull(new DataPutResult("dm").sha256());
        assertNull(new DataPutResult("dm", 1L, "single").sha256());
        assertNull(new DataPutPublicResult("a").sha256());
        assertNull(new DataPutPublicResult("a", 1L, "single").sha256());
        assertNull(new FilePutResult("dm", "1", "2", 3L, "single").sha256());
        assertNull(new FilePutPublicResult("a", "1", "2", 3L, "single").sha256());
        assertNull(new FinalizeUploadResult("a", 1L).sha256());
        assertNull(new FinalizeUploadResult("a", 1L, "dm", "dma").sha256());
        assertNull(new ManifestEntryInfo("e", null, null, "public", ADDR, null, null, null).sha256());
        assertNull(new ManifestEntryInput(null, null, null, ADDR).sha256());
    }

    // ── Manifest entry input ──

    @Test
    void buildSendsSha256OnlyWhenSet() throws Exception {
        reply(ManifestRestTest.BUILT);
        client.buildManifest(List.of(
                ManifestEntryInput.ofAddress(ADDR).withPath("a.txt").withSha256(SHA),
                ManifestEntryInput.ofAddress(ADDR).withPath("b.txt"),
                ManifestEntryInput.ofAddress(ADDR).withPath("c.txt").withSha256(""),
                ManifestEntryInput.ofDataMap("abcd").withSha256(null)));
        List<Map<String, Object>> entries = entriesOf(taken());
        assertEquals(Map.of("path", "a.txt", "address", ADDR, "sha256", SHA), entries.get(0));
        assertEquals(Map.of("path", "b.txt", "address", ADDR), entries.get(1));
        assertEquals(Map.of("path", "c.txt", "address", ADDR), entries.get(2), "an empty sha256 is omitted");
        assertEquals(Map.of("data_map", "abcd"), entries.get(3));
    }

    @Test
    void buildPassesSha256ThroughUnchanged() throws Exception {
        // No client-side hex, length or case handling: the daemon validates.
        reply(ManifestRestTest.BUILT);
        client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withSha256("ZZ")));
        assertEquals("ZZ", entriesOf(taken()).get(0).get("sha256"));
    }

    @Test
    void withSha256KeepsTheOtherFields() {
        ManifestEntryInput e = ManifestEntryInput.ofDataMap("ab").withPath("p").withSize(5L).withSha256(SHA);
        assertEquals(new ManifestEntryInput("p", 5L, "ab", null, SHA), e);
        assertEquals(e, e.withPath("p").withSize(5L));
        assertEquals(SHA, e.withPath("q").sha256());
    }

    // ── Manifest entry info ──

    private static final String WITH_AND_WITHOUT = "{\"manifest\":\"" + ManifestRestTest.HEADER_B64 + "\","
            + "\"link\":\"" + ManifestRestTest.LINK + "\",\"source\":\"manifest\",\"entries\":["
            + "{\"effective_name\":\"a.txt\",\"path\":\"a.txt\",\"kind\":\"public\",\"content_address\":\"" + ADDR
            + "\",\"sha256\":\"" + SHA + "\"},"
            + "{\"effective_name\":\"b.txt\",\"path\":\"b.txt\",\"kind\":\"public\",\"content_address\":\"" + ADDR + "\"},"
            + "{\"effective_name\":\"c.txt\",\"path\":\"c.txt\",\"kind\":\"public\",\"content_address\":\"" + ADDR
            + "\",\"sha256\":\"\"}]}";

    @Test
    void buildAndDecodeReadSha256OrNone() {
        reply(WITH_AND_WITHOUT);
        List<ManifestEntryInfo> built = client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR))).entries();
        assertEquals(SHA, built.get(0).sha256());
        assertNull(built.get(1).sha256());
        assertNull(built.get(2).sha256());

        reply(WITH_AND_WITHOUT);
        List<ManifestEntryInfo> decoded = client.decodeManifestLink(ManifestRestTest.LINK, false).entries();
        assertEquals(SHA, decoded.get(0).sha256());
        assertNull(decoded.get(1).sha256());
        assertNull(decoded.get(2).sha256());

        reply(WITH_AND_WITHOUT);
        assertEquals(SHA, client.decodeManifest(ManifestRestTest.HEADER, false).entries().get(0).sha256());
    }

    // ── Errors ──

    @Test
    void aBadSha256IsTheDaemonsBadRequest() {
        String msg = "Bad request: entries[0]: invalid hex sha256: Invalid character at position 0";
        reply(400, "{\"error\":\"" + msg + "\",\"code\":\"BAD_REQUEST\"}");
        BadRequestException e = assertThrows(BadRequestException.class,
                () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withSha256("zz"))));
        assertEquals(400, e.getStatusCode());
        assertTrue(e.getMessage().contains("entries[0]: invalid hex sha256"), e.getMessage());
        assertInstanceOf(AntdException.class, e);
    }
}
