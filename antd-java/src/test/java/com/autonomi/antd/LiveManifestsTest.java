package com.autonomi.antd;

import com.autonomi.antd.errors.BadRequestException;
import com.autonomi.antd.models.*;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * Live manifest round trip against a running antd with a devnet behind it. It
 * only builds and decodes manifests of data that is already uploaded, so it
 * pays nothing and needs no wallet.
 *
 * <p>Skipped unless {@code ANTD_TEST_URL} and {@code ANTD_TEST_MANIFEST_ADDRESSES}
 * are set:
 * <ul>
 *   <li>{@code ANTD_TEST_URL}: the daemon's REST base URL, e.g. {@code http://127.0.0.1:8082}</li>
 *   <li>{@code ANTD_TEST_MANIFEST_ADDRESSES}: two comma-separated public data addresses</li>
 *   <li>{@code ANTD_TEST_MANIFEST_SIZES}: their plaintext sizes, comma-separated (optional)</li>
 *   <li>{@code ANTD_TEST_MANIFEST_DATA_MAP}, {@code ANTD_TEST_MANIFEST_DATA_MAP_SIZE}: a private
 *       upload's hex DataMap and its size (optional)</li>
 *   <li>{@code ANTD_TEST_MANIFEST_LINK}: an {@code ant://manifest/} link built from those
 *       entries (optional)</li>
 *   <li>{@code ANTD_TEST_GRPC}: the daemon's gRPC target, e.g. {@code 127.0.0.1:50051}, to repeat
 *       the round trip over gRPC (optional)</li>
 * </ul>
 * <pre>
 * ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=&lt;hex&gt;,&lt;hex&gt; \
 *   ./gradlew :test --tests com.autonomi.antd.LiveManifestsTest
 * </pre>
 */
class LiveManifestsTest {

    private static final String NAME = "antd-java-live";

    /** The daemon accepts a 0x prefix but always returns bare hex. */
    private static String norm(String hex) {
        String s = hex.trim().toLowerCase(Locale.ROOT);
        return s.startsWith("0x") ? s.substring(2) : s;
    }

    private static String env(String name) {
        String v = System.getenv(name);
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static Map<String, ManifestEntryInfo> byName(List<ManifestEntryInfo> entries) {
        Map<String, ManifestEntryInfo> m = new HashMap<>();
        entries.forEach(e -> m.put(e.effectiveName(), e));
        assertEquals(entries.size(), m.size(), "effective names must be unique: " + entries);
        return m;
    }

    private static void assertDaemonRefuses(String endpoint, String json, String message) {
        try {
            var http = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpResponse<String> resp = http.send(
                    java.net.http.HttpRequest.newBuilder(java.net.URI.create(endpoint))
                            .header("Content-Type", "application/json")
                            .POST(java.net.http.HttpRequest.BodyPublishers.ofString(json))
                            .build(),
                    java.net.http.HttpResponse.BodyHandlers.ofString());
            assertEquals(400, resp.statusCode(), resp.body());
            assertTrue(resp.body().contains(message), resp.body());
        } catch (java.io.IOException | InterruptedException e) {
            fail(e);
        }
    }

    @Test
    void liveManifestRoundTrip() {
        String url = env("ANTD_TEST_URL");
        String addresses = env("ANTD_TEST_MANIFEST_ADDRESSES");
        assumeTrue(url != null && addresses != null && addresses.contains(","),
                "set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run");
        String[] addr = addresses.split(",");
        String a = norm(addr[0]);
        String b = norm(addr[1]);
        String sizesEnv = env("ANTD_TEST_MANIFEST_SIZES");
        Long sizeA = sizesEnv == null ? null : Long.valueOf(sizesEnv.split(",")[0].trim());
        Long sizeB = sizesEnv == null ? null : Long.valueOf(sizesEnv.split(",")[1].trim());
        String dataMap = env("ANTD_TEST_MANIFEST_DATA_MAP");
        String dataMapSizeEnv = env("ANTD_TEST_MANIFEST_DATA_MAP_SIZE");
        Long dataMapSize = dataMapSizeEnv == null ? null : Long.valueOf(dataMapSizeEnv);
        String fixtureLink = env("ANTD_TEST_MANIFEST_LINK");
        String grpcTarget = env("ANTD_TEST_GRPC");

        // a records its size; b and the DataMap entry record none.
        List<ManifestEntryInput> entries = new ArrayList<>();
        entries.add(ManifestEntryInput.ofAddress(a).withPath("live/one.bin").withSize(sizeA));
        entries.add(ManifestEntryInput.ofAddress(b).withPath("live/two.bin"));
        if (dataMap != null) {
            entries.add(ManifestEntryInput.ofDataMap(dataMap).withPath("live/private.bin"));
        }
        BuildManifestOptions options = BuildManifestOptions.DEFAULT.withName(NAME);

        try (AntdClient rest = new AntdClient(url, Duration.ofMinutes(5));
             AsyncAntdClient async = new AsyncAntdClient(url, Duration.ofMinutes(5))) {

            // ── Build ──
            BuiltManifest built = rest.buildManifest(entries, options);
            assertTrue(built.manifest().length > 5, "no .ant bytes");
            assertEquals((byte) 0xC1, built.manifest()[0]);
            assertEquals("ANT", new String(built.manifest(), 1, 3, java.nio.charset.StandardCharsets.US_ASCII));
            assertNotNull(built.link(), "a three-entry manifest fits a link");
            assertTrue(built.link().startsWith("ant://manifest/"), built.link());
            assertEquals(entries.size(), built.entries().size());
            Map<String, ManifestEntryInfo> made = byName(built.entries());
            ManifestEntryInfo one = made.get("live/one.bin");
            ManifestEntryInfo two = made.get("live/two.bin");
            assertEquals(ManifestEntryInfo.KIND_PUBLIC, one.kind());
            assertEquals(ManifestEntryInfo.KIND_PUBLIC, two.kind());
            assertEquals("live/one.bin", one.path());
            assertEquals(a, norm(one.contentAddress()));
            assertEquals(b, norm(two.contentAddress()));
            assertEquals(sizeA, one.size());
            assertNull(two.size(), "an unset size must read as null, not 0");
            assertNull(one.dataMap(), "build reports no DataMaps");
            if (dataMap != null) {
                ManifestEntryInfo priv = made.get("live/private.bin");
                assertEquals(ManifestEntryInfo.KIND_EMBEDDED, priv.kind());
                assertNull(priv.size());
                assertEquals(64, priv.contentAddress().length());
            }

            // ── Decode the bytes and the link, resolving ──
            DecodedManifest fromBytes = rest.decodeManifest(built.manifest(), true);
            DecodedManifest fromLink = rest.decodeManifestLink(built.link(), true);
            for (DecodedManifest d : List.of(fromBytes, fromLink)) {
                assertEquals(DecodedManifest.SOURCE_MANIFEST, d.source());
                assertEquals(NAME, d.name());
                assertNull(d.torrentInfoHashV1());
                assertNull(d.torrentInfoHashV2());
                assertEquals(entries.size(), d.entries().size());
                Map<String, ManifestEntryInfo> got = byName(d.entries());
                d.entries().forEach(e -> assertNull(e.error(), "resolve failed: " + e));
                assertEquals(sizeA, got.get("live/one.bin").size());
                assertNull(got.get("live/two.bin").size());
                assertNull(got.get("live/two.bin").dataMap(), "a public entry has no DataMap");
                if (sizeA != null) {
                    assertEquals(sizeA, got.get("live/one.bin").exactSize());
                    assertEquals(sizeB, got.get("live/two.bin").exactSize());
                } else {
                    assertNotNull(got.get("live/one.bin").exactSize());
                }
                if (dataMap != null) {
                    ManifestEntryInfo priv = got.get("live/private.bin");
                    assertEquals(ManifestEntryInfo.KIND_EMBEDDED, priv.kind());
                    assertTrue(priv.isEmbedded());
                    assertNotNull(priv.dataMap());
                    assertFalse(priv.dataMap().isEmpty());
                    if (dataMapSize != null) assertEquals(dataMapSize, priv.exactSize());
                }
            }
            assertEquals(fromBytes, fromLink);

            // Without resolve, public entries have no exact size.
            DecodedManifest unresolved = rest.decodeManifest(built.manifest(), false);
            assertNull(byName(unresolved.entries()).get("live/two.bin").exactSize());

            // ── The fixture link ──
            DecodedManifest fixture = null;
            if (fixtureLink != null) {
                fixture = rest.decodeManifestLink(fixtureLink, true);
                assertEquals(DecodedManifest.SOURCE_MANIFEST, fixture.source());
                Map<String, ManifestEntryInfo> byAddress = new HashMap<>();
                fixture.entries().forEach(e -> byAddress.put(norm(e.contentAddress()), e));
                assertTrue(byAddress.containsKey(a) && byAddress.containsKey(b),
                        "the fixture link should list both addresses: " + fixture.entries());
                if (sizeA != null) {
                    assertEquals(sizeA, byAddress.get(a).exactSize());
                    assertEquals(sizeB, byAddress.get(b).exactSize());
                }
                for (ManifestEntryInfo e : fixture.entries()) {
                    assertNull(e.error(), "resolve failed: " + e);
                    if (e.isEmbedded()) {
                        assertNotNull(e.dataMap());
                        if (dataMapSize != null) assertEquals(dataMapSize, e.exactSize());
                    }
                }
            }

            // ── A bare address decodes as a file link ──
            DecodedManifest file = rest.decodeManifestLink(a, true);
            assertEquals(DecodedManifest.SOURCE_FILE_LINK, file.source());
            assertEquals(1, file.entries().size());
            assertEquals(ManifestEntryInfo.KIND_PUBLIC, file.entries().get(0).kind());
            assertNull(file.entries().get(0).path());
            if (sizeA != null) assertEquals(sizeA, file.entries().get(0).exactSize());

            // ── Bad input ──
            BadRequestException bad = assertThrows(BadRequestException.class,
                    () -> rest.buildManifest(List.of(ManifestEntryInput.ofAddress(a).withPath("../x"))));
            assertTrue(bad.getMessage().contains("entries[0]"), bad.getMessage());
            assertThrows(BadRequestException.class,
                    () -> rest.decodeManifest("not a manifest".getBytes(), false));
            // Client-side refusals are the daemon's own 400, same text.
            String bothMsg = "1 invalid entries: entries[0]: give data_map or address, not both";
            String emptyMsg = "needs a manifest (base64 .ant bytes) or a link";
            BadRequestException local = assertThrows(BadRequestException.class,
                    () -> rest.buildManifest(List.of(new ManifestEntryInput(null, null, "ab", a))));
            assertEquals(400, local.getStatusCode());
            assertEquals("antd error 400: " + bothMsg, local.getMessage());
            BadRequestException emptyLocal = assertThrows(BadRequestException.class,
                    () -> rest.decodeManifestLink("", false));
            assertEquals("antd error 400: " + emptyMsg, emptyLocal.getMessage());
            // The daemon says the same for the same requests, sent past the client's checks.
            assertDaemonRefuses(url + "/v1/manifests/build",
                    "{\"entries\":[{\"data_map\":\"ab\",\"address\":\"" + a + "\"}]}", bothMsg);
            assertDaemonRefuses(url + "/v1/manifests/decode", "{\"resolve\":false}", emptyMsg);

            // ── Async ──
            BuiltManifest asyncBuilt = async.buildManifestAsync(entries, options).join();
            assertEquals(built, asyncBuilt);
            assertEquals(fromBytes, async.decodeManifestAsync(built.manifest(), true).join());

            // ── gRPC ──
            if (grpcTarget != null) {
                try (GrpcAntdClient grpc = new GrpcAntdClient(grpcTarget)) {
                    BuiltManifest g = grpc.buildManifest(entries, options);
                    assertEquals(built, g, "REST and gRPC must build the same manifest");
                    assertEquals(fromBytes, grpc.decodeManifest(g.manifest(), true));
                    assertEquals(fromLink, grpc.decodeManifestLink(g.link(), true));
                    if (fixture != null) {
                        assertEquals(fixture, grpc.decodeManifestLink(fixtureLink, true));
                    }
                    assertEquals(file, grpc.decodeManifestLink(a, true));
                    BadRequestException gbad = assertThrows(BadRequestException.class,
                            () -> grpc.buildManifest(List.of(ManifestEntryInput.ofAddress(a).withPath("../x"))));
                    assertTrue(gbad.getMessage().contains("entries[0]"), gbad.getMessage());
                    assertThrows(BadRequestException.class,
                            () -> grpc.decodeManifest("not a manifest".getBytes(), false));
                }
            }
        }
    }
}
