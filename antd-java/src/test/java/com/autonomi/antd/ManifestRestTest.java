package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletionException;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The manifest API over REST ({@link AntdClient} and {@link AsyncAntdClient})
 * against a mock daemon: request shapes, the base64 round trip, unset sizes
 * reading as {@code null} (not 0), the checks made before sending, and the
 * error mapping.
 */
class ManifestRestTest {

    /** The five-byte {@code .ant} header; {@code "wUFOVAE="} is its base64. */
    static final byte[] HEADER = {(byte) 0xC1, 'A', 'N', 'T', 0x01};
    static final String HEADER_B64 = "wUFOVAE=";
    static final String LINK = "ant://manifest/wUFOVAE";
    static final String ADDR = "42".repeat(32);

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

    private static Map<String, Object> bodyOf(RecordedRequest r) {
        return Json.parseObject(r.getBody().readUtf8());
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> entriesOf(Map<String, Object> body) {
        return (List<Map<String, Object>>) body.get("entries");
    }

    static final String BUILT = "{\"manifest\":\"" + HEADER_B64 + "\",\"link\":\"" + LINK + "\",\"entries\":["
            + "{\"effective_name\":\"a.txt\",\"path\":\"a.txt\",\"size\":10,\"kind\":\"embedded\","
            + "\"content_address\":\"cc\",\"exact_size\":10},"
            + "{\"effective_name\":\"" + ADDR + "\",\"kind\":\"public\",\"content_address\":\"" + ADDR + "\"}]}";

    static List<ManifestEntryInput> twoEntries() {
        return List.of(
                ManifestEntryInput.ofDataMap("abcd").withPath("a.txt").withSize(10L),
                ManifestEntryInput.ofAddress(ADDR));
    }

    // ── Build ──

    @Test
    void buildSendsEntriesAndOptions() throws Exception {
        reply(BUILT);
        client.buildManifest(twoEntries(), new BuildManifestOptions("album", null, true));
        RecordedRequest r = taken();
        assertEquals("POST", r.getMethod());
        assertEquals("/v1/manifests/build", r.getPath());
        Map<String, Object> body = bodyOf(r);
        assertEquals("album", body.get("name"));
        assertEquals(false, body.get("embed_roots"));
        assertFalse(body.containsKey("torrent_info_hashes"), "empty hashes must be omitted: " + body);
        List<Map<String, Object>> entries = entriesOf(body);
        assertEquals(2, entries.size());
        assertEquals(Map.of("path", "a.txt", "size", 10, "data_map", "abcd"), entries.get(0));
        // No path and no size: omitted, not sent as "" or 0.
        assertEquals(Map.of("address", ADDR), entries.get(1));
    }

    @Test
    void buildDecodesTheBase64ManifestAndReadsUnsetSizesAsNull() {
        reply(BUILT);
        BuiltManifest b = client.buildManifest(twoEntries());
        assertArrayEquals(HEADER, b.manifest());
        assertEquals(LINK, b.link());
        assertEquals(2, b.entries().size());

        ManifestEntryInfo a = b.entries().get(0);
        assertEquals(new ManifestEntryInfo("a.txt", "a.txt", 10L, "embedded", "cc", null, 10L, null), a);
        assertTrue(a.isEmbedded());

        ManifestEntryInfo p = b.entries().get(1);
        assertEquals(ADDR, p.effectiveName());
        assertEquals(ManifestEntryInfo.KIND_PUBLIC, p.kind());
        assertFalse(p.isEmbedded());
        assertNull(p.path());
        assertNull(p.size(), "an unset size must read as null, not 0");
        assertNull(p.exactSize(), "an unset exact_size must read as null, not 0");
        assertNull(p.dataMap());
        assertNull(p.error());
    }

    @Test
    void aZeroSizeIsZeroNotUnset() {
        reply("{\"manifest\":\"" + HEADER_B64 + "\",\"entries\":["
                + "{\"effective_name\":\"e\",\"path\":\"e\",\"size\":0,\"kind\":\"embedded\","
                + "\"content_address\":\"cc\",\"exact_size\":0},"
                + "{\"effective_name\":\"n\",\"path\":\"n\",\"size\":null,\"kind\":\"public\","
                + "\"content_address\":\"dd\",\"exact_size\":null}]}");
        BuiltManifest b = client.buildManifest(List.of(ManifestEntryInput.ofDataMap("ab").withSize(0L)));
        assertEquals(0L, b.entries().get(0).size());
        assertEquals(0L, b.entries().get(0).exactSize());
        assertNull(b.entries().get(1).size());
        assertNull(b.entries().get(1).exactSize());
    }

    @Test
    void sizesPastIntRangeKeepTheirValue() throws Exception {
        long big = 5_000_000_000L;
        reply("{\"manifest\":\"" + HEADER_B64 + "\",\"entries\":[{\"effective_name\":\"v\",\"path\":\"v\","
                + "\"size\":" + big + ",\"kind\":\"public\",\"content_address\":\"dd\",\"exact_size\":" + big + "}]}");
        BuiltManifest b = client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withSize(big)));
        assertEquals(big, ((Number) entriesOf(bodyOf(taken())).get(0).get("size")).longValue());
        assertEquals(big, b.entries().get(0).size());
        assertEquals(big, b.entries().get(0).exactSize());
    }

    @Test
    void buildEmbedsRootsByDefault() throws Exception {
        reply("{\"manifest\":\"\",\"entries\":[]}");
        BuiltManifest b = client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR)));
        Map<String, Object> body = bodyOf(taken());
        assertEquals(true, body.get("embed_roots"), "embed_roots should default to true: " + body);
        assertFalse(body.containsKey("name"), "an unset name must be omitted: " + body);
        assertFalse(body.containsKey("torrent_info_hashes"));
        assertEquals(0, b.manifest().length);
        assertNull(b.link(), "a link that does not fit is absent and reads as null");
        assertTrue(b.entries().isEmpty());

        // null options and an empty name mean the same.
        reply("{\"manifest\":\"\",\"entries\":[]}");
        client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR)), null);
        body = bodyOf(taken());
        assertEquals(true, body.get("embed_roots"));
        reply("{\"manifest\":\"\",\"entries\":[]}");
        client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR)), BuildManifestOptions.DEFAULT.withName(""));
        body = bodyOf(taken());
        assertEquals(true, body.get("embed_roots"));
        assertFalse(body.containsKey("name"));
    }

    @Test
    void buildSendsTorrentInfoHashes() throws Exception {
        reply("{\"manifest\":\"\",\"entries\":[]}");
        List<String> hashes = List.of("aa".repeat(20), "bb".repeat(32));
        client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR)),
                BuildManifestOptions.DEFAULT.withTorrentInfoHashes(hashes).withName("t"));
        Map<String, Object> body = bodyOf(taken());
        assertEquals(hashes, body.get("torrent_info_hashes"));
        assertEquals("t", body.get("name"));
        assertEquals(true, body.get("embed_roots"));
    }

    @Test
    void anEmptyPathIsNotSent() throws Exception {
        reply("{\"manifest\":\"\",\"entries\":[]}");
        client.buildManifest(List.of(new ManifestEntryInput("", null, "", ADDR)));
        assertEquals(Map.of("address", ADDR), entriesOf(bodyOf(taken())).get(0));
    }

    /** The refusal a daemon 400 would be: same type, status 400, and the daemon's text. */
    static void assertRefused(String message, Throwable t) {
        assertInstanceOf(BadRequestException.class, t);
        assertEquals(400, ((AntdException) t).getStatusCode());
        assertEquals("antd error 400: " + message, t.getMessage());
    }

    @Test
    void ambiguousEntriesAreRefusedLikeTheDaemonBeforeSending() {
        String neither = "needs a data_map or an address";
        String both = "give data_map or address, not both";
        List<Object[]> cases = List.of(
                new Object[] {new ManifestEntryInput(null, null, null, null), neither},
                new Object[] {new ManifestEntryInput("p", null, "", ""), neither},
                new Object[] {new ManifestEntryInput(null, null, "aa", ADDR), both});
        for (Object[] c : cases) {
            List<ManifestEntryInput> entries = List.of(ManifestEntryInput.ofAddress(ADDR), (ManifestEntryInput) c[0]);
            String msg = "1 invalid entries: entries[1]: " + c[1];
            assertRefused(msg, assertThrows(BadRequestException.class, () -> client.buildManifest(entries)));
            // The async client's future completes exceptionally with the same error.
            CompletionException ce = assertThrows(CompletionException.class,
                    () -> async.buildManifestAsync(entries).join());
            assertRefused(msg, ce.getCause());
        }
        assertEquals(0, server.getRequestCount(), "nothing may be sent for an invalid entry");
    }

    @Test
    void everyBadEntryIsReportedTogether() {
        List<ManifestEntryInput> entries = List.of(
                new ManifestEntryInput(null, null, "aa", ADDR),
                ManifestEntryInput.ofAddress(ADDR),
                new ManifestEntryInput(null, null, null, null));
        assertRefused("2 invalid entries: entries[0]: give data_map or address, not both; "
                        + "entries[2]: needs a data_map or an address",
                assertThrows(BadRequestException.class, () -> client.buildManifest(entries)));
        assertEquals(0, server.getRequestCount());
    }

    @Test
    void moreThanTwentyBadEntriesAreCutShort() {
        List<ManifestEntryInput> entries = new ArrayList<>();
        for (int i = 0; i < 23; i++) entries.add(new ManifestEntryInput(null, null, null, null));
        StringBuilder shown = new StringBuilder();
        for (int i = 0; i < 20; i++) {
            if (i > 0) shown.append("; ");
            shown.append("entries[").append(i).append("]: needs a data_map or an address");
        }
        assertRefused("23 invalid entries: " + shown + "; and 3 more",
                assertThrows(BadRequestException.class, () -> client.buildManifest(entries)));
    }

    @Test
    void nullEntriesAndNegativeSizesAreRefusedBeforeSending() {
        assertRefused("entries must not be null",
                assertThrows(BadRequestException.class, () -> client.buildManifest(null)));
        List<ManifestEntryInput> withNull = new ArrayList<>();
        withNull.add(null);
        assertRefused("1 invalid entries: entries[0]: entry is null",
                assertThrows(BadRequestException.class, () -> client.buildManifest(withNull)));
        assertRefused("1 invalid entries: entries[0]: size must not be negative, got -1",
                assertThrows(BadRequestException.class,
                        () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withSize(-1L)))));
        CompletionException ce = assertThrows(CompletionException.class,
                () -> async.buildManifestAsync(List.of(ManifestEntryInput.ofAddress(ADDR).withSize(-1L))).join());
        assertRefused("1 invalid entries: entries[0]: size must not be negative, got -1", ce.getCause());
        assertEquals(0, server.getRequestCount());
    }

    @Test
    void anInvalidEntryIsABadRequestWithTheDaemonsMessage() {
        String msg = "Bad request: 1 invalid entries: entries[0]: invalid path \\\"../x\\\": "
                + "a component is \\\"..\\\"";
        reply(400, "{\"error\":\"" + msg + "\",\"code\":\"BAD_REQUEST\"}");
        BadRequestException e = assertThrows(BadRequestException.class,
                () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withPath("../x"))));
        assertEquals(400, e.getStatusCode());
        assertTrue(e.getMessage().contains("entries[0]: invalid path \"../x\""), e.getMessage());
    }

    @Test
    void anInvalidBase64ManifestIsAnError() {
        reply("{\"manifest\":\"not base64!\",\"entries\":[]}");
        AntdException e = assertThrows(AntdException.class,
                () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR))));
        assertTrue(e.getMessage().contains("base64"), e.getMessage());
    }

    // ── Decode ──

    static final String DECODED = "{\"source\":\"manifest\",\"name\":\"album\",\"torrent_info_hash_v2\":\"bb\","
            + "\"entries\":["
            + "{\"effective_name\":\"a.txt\",\"path\":\"a.txt\",\"kind\":\"embedded\",\"content_address\":\"cc\","
            + "\"data_map\":\"abcd\",\"exact_size\":3},"
            + "{\"effective_name\":\"b\",\"path\":\"b\",\"kind\":\"public\",\"content_address\":\"dd\","
            + "\"error\":\"Record not found: gone\"}]}";

    @Test
    void decodeSendsTheBytesAsBase64() throws Exception {
        reply(DECODED);
        DecodedManifest d = client.decodeManifest(HEADER, true);
        RecordedRequest r = taken();
        assertEquals("POST", r.getMethod());
        assertEquals("/v1/manifests/decode", r.getPath());
        assertEquals(Map.of("manifest", HEADER_B64, "resolve", true), bodyOf(r));

        assertEquals(DecodedManifest.SOURCE_MANIFEST, d.source());
        assertEquals("album", d.name());
        assertNull(d.torrentInfoHashV1());
        assertEquals("bb", d.torrentInfoHashV2());
        assertEquals(2, d.entries().size());
        ManifestEntryInfo a = d.entries().get(0);
        assertEquals("abcd", a.dataMap());
        assertEquals(3L, a.exactSize());
        assertNull(a.size());
        assertNull(a.error());
        // One entry's resolve failure is in its error, not a failed call.
        ManifestEntryInfo b = d.entries().get(1);
        assertEquals("Record not found: gone", b.error());
        assertNull(b.exactSize());
        assertNull(b.dataMap());
    }

    @Test
    void theBase64RoundTripIsLossless() throws Exception {
        byte[] all = new byte[256];
        for (int i = 0; i < all.length; i++) all[i] = (byte) i;
        String b64 = java.util.Base64.getEncoder().encodeToString(all);
        reply("{\"manifest\":\"" + b64 + "\",\"entries\":[]}");
        assertArrayEquals(all, client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR))).manifest());
        taken();

        reply(DECODED);
        client.decodeManifest(all, false);
        assertArrayEquals(all, java.util.Base64.getDecoder().decode((String) bodyOf(taken()).get("manifest")));
    }

    @Test
    void decodeLinkSendsTheLinkOnly() throws Exception {
        reply("{\"source\":\"file_link\",\"entries\":[{\"effective_name\":\"" + ADDR + "\",\"kind\":\"public\","
                + "\"content_address\":\"" + ADDR + "\",\"exact_size\":46}]}");
        DecodedManifest d = client.decodeManifestLink(ADDR, false);
        assertEquals(Map.of("link", ADDR, "resolve", false), bodyOf(taken()));
        assertEquals(DecodedManifest.SOURCE_FILE_LINK, d.source());
        assertNull(d.name());
        assertNull(d.torrentInfoHashV1());
        assertNull(d.torrentInfoHashV2());
        assertEquals(1, d.entries().size());
        assertNull(d.entries().get(0).path());
        assertEquals(46L, d.entries().get(0).exactSize());
    }

    @Test
    void emptyInputsAreRefusedLikeTheDaemonBeforeSending() {
        String msg = "needs a manifest (base64 .ant bytes) or a link";
        assertRefused(msg, assertThrows(BadRequestException.class, () -> client.decodeManifest(new byte[0], false)));
        assertRefused(msg, assertThrows(BadRequestException.class, () -> client.decodeManifest(null, false)));
        assertRefused(msg, assertThrows(BadRequestException.class, () -> client.decodeManifestLink("", false)));
        assertRefused(msg, assertThrows(BadRequestException.class, () -> client.decodeManifestLink(null, true)));
        assertRefused(msg, assertThrows(CompletionException.class,
                () -> async.decodeManifestAsync(new byte[0], false).join()).getCause());
        assertRefused(msg, assertThrows(CompletionException.class,
                () -> async.decodeManifestLinkAsync("", false).join()).getCause());
        assertEquals(0, server.getRequestCount());
    }

    @Test
    void notAManifestIsABadRequest() {
        reply(400, "{\"error\":\"Bad request: not a manifest: missing or invalid header\",\"code\":\"BAD_REQUEST\"}");
        BadRequestException e = assertThrows(BadRequestException.class,
                () -> client.decodeManifest("nope".getBytes(), false));
        assertTrue(e.getMessage().contains("not a manifest"), e.getMessage());
    }

    // ── Async ──

    @Test
    void asyncBuildAndDecode() throws Exception {
        reply(BUILT);
        BuiltManifest b = async.buildManifestAsync(twoEntries(), BuildManifestOptions.DEFAULT.withName("album")).join();
        Map<String, Object> body = bodyOf(taken());
        assertEquals(true, body.get("embed_roots"));
        assertEquals("album", body.get("name"));
        assertArrayEquals(HEADER, b.manifest());
        assertNull(b.entries().get(1).size());

        reply(DECODED);
        DecodedManifest d = async.decodeManifestAsync(b.manifest(), true).join();
        assertEquals(Map.of("manifest", HEADER_B64, "resolve", true), bodyOf(taken()));
        assertEquals("abcd", d.entries().get(0).dataMap());

        reply(DECODED);
        async.decodeManifestLinkAsync(LINK, false).join();
        assertEquals(Map.of("link", LINK, "resolve", false), bodyOf(taken()));
    }

    @Test
    void asyncBadRequestIsTyped() {
        reply(400, "{\"error\":\"Bad request: 1 invalid entries: entries[0]: needs a data_map or an address\","
                + "\"code\":\"BAD_REQUEST\"}");
        CompletionException e = assertThrows(CompletionException.class,
                () -> async.buildManifestAsync(List.of(ManifestEntryInput.ofAddress(ADDR))).join());
        assertInstanceOf(BadRequestException.class, e.getCause());
        assertTrue(e.getCause().getMessage().contains("entries[0]"), e.getCause().getMessage());
    }

    // ── Models ──

    @Test
    void builtManifestComparesBytesByContent() {
        BuiltManifest a = new BuiltManifest(HEADER.clone(), LINK, List.of());
        BuiltManifest b = new BuiltManifest(Arrays.copyOf(HEADER, HEADER.length), LINK, List.of());
        assertEquals(a, b);
        assertEquals(a.hashCode(), b.hashCode());
        assertNotEquals(a, new BuiltManifest(new byte[] {1}, LINK, List.of()));
        assertTrue(a.toString().contains("5 bytes"), a.toString());
    }

    @Test
    void optionsDefaultToEmbeddingRoots() {
        assertFalse(BuildManifestOptions.DEFAULT.keepShrunkDataMaps());
        assertNull(BuildManifestOptions.DEFAULT.name());
        assertEquals(List.of(), new BuildManifestOptions(null, null, false).torrentInfoHashes());
        assertTrue(BuildManifestOptions.DEFAULT.withKeepShrunkDataMaps(true).keepShrunkDataMaps());
    }
}
