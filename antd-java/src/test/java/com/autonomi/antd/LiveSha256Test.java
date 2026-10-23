package com.autonomi.antd;

import com.autonomi.antd.errors.BadRequestException;
import com.autonomi.antd.models.*;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * Live check of the {@code sha256} fields (antd 0.17.0 or later) against a
 * running antd. It decodes a fixture manifest, builds manifests with and
 * without a hash, and makes ONE paid call per transport: a small public data
 * upload whose returned {@code sha256} must equal the hash computed here.
 *
 * <p>Skipped unless {@code ANTD_TEST_URL} and {@code ANTD_TEST_SHA_LINK} are set:
 * <ul>
 *   <li>{@code ANTD_TEST_URL}: the daemon's REST base URL</li>
 *   <li>{@code ANTD_TEST_SHA_LINK}: a manifest link with entries {@code public.txt},
 *       {@code private.txt} (both with a sha256) and {@code nohash.txt} (none)</li>
 *   <li>{@code ANTD_TEST_SHA_PUBLIC_ADDRESS}, {@code ANTD_TEST_SHA_PUBLIC_SHA256}: a public
 *       upload and its plaintext's SHA-256</li>
 *   <li>{@code ANTD_TEST_SHA_DATA_MAP_SHA256}: the private upload's SHA-256</li>
 *   <li>{@code ANTD_TEST_GRPC}: the gRPC target, to repeat everything over gRPC (optional)</li>
 * </ul>
 * <pre>
 * . ~/sha-fanout-daemon/fixtures.env
 * ./gradlew :test --tests com.autonomi.antd.LiveSha256Test --rerun-tasks -i
 * </pre>
 */
class LiveSha256Test {

    private static String env(String name) {
        String v = System.getenv(name);
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String sha256Hex(byte[] data) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
    }

    /** The checks that are the same over either transport; {@code c} is REST or gRPC. */
    private interface Api {
        ManifestEntryInfo[] decodeLink(String link) throws Exception;

        BuiltManifest build(List<ManifestEntryInput> entries) throws Exception;

        DataPutPublicResult putPublic(byte[] data) throws Exception;
    }

    private static void check(String transport, Api api, String link, String publicAddress,
                              String publicSha, String dataMapSha) throws Exception {
        // 1. Decode the fixture manifest (no resolve).
        Map<String, ManifestEntryInfo> byPath = new HashMap<>();
        for (ManifestEntryInfo e : api.decodeLink(link)) byPath.put(e.path(), e);
        assertEquals(publicSha, byPath.get("public.txt").sha256(), transport + " public.txt");
        assertEquals(dataMapSha, byPath.get("private.txt").sha256(), transport + " private.txt");
        assertNull(byPath.get("nohash.txt").sha256(), transport + " nohash.txt has none");

        // 2. Build with a hash: the returned entry carries it.
        BuiltManifest built = api.build(List.of(
                ManifestEntryInput.ofAddress(publicAddress).withPath("a.txt").withSha256(publicSha)));
        assertEquals(publicSha, built.entries().get(0).sha256(), transport + " built entry");

        // 3. A malformed hash is the daemon's bad request.
        BadRequestException bad = assertThrows(BadRequestException.class, () -> api.build(List.of(
                ManifestEntryInput.ofAddress(publicAddress).withPath("a.txt").withSha256("zz"))));
        assertEquals(400, bad.getStatusCode());
        assertTrue(bad.getMessage().contains("entries[0]"), bad.getMessage());
        assertTrue(bad.getMessage().contains("sha256"), bad.getMessage());

        // 4. The one paid call: the returned hash is the plaintext's.
        byte[] payload = ("sha-fanout java " + System.currentTimeMillis() / 1000 + " " + transport)
                .getBytes(StandardCharsets.UTF_8);
        DataPutPublicResult put = api.putPublic(payload);
        assertEquals(sha256Hex(payload), put.sha256(), transport + " upload sha256");
        System.out.println("LiveSha256Test " + transport + ": payload sha256=" + sha256Hex(payload)
                + " returned sha256=" + put.sha256() + " address=" + put.address());
    }

    @Test
    void liveSha256() throws Exception {
        String url = env("ANTD_TEST_URL");
        String link = env("ANTD_TEST_SHA_LINK");
        assumeTrue(url != null && link != null, "set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run");
        String publicAddress = env("ANTD_TEST_SHA_PUBLIC_ADDRESS");
        String publicSha = env("ANTD_TEST_SHA_PUBLIC_SHA256");
        String dataMapSha = env("ANTD_TEST_SHA_DATA_MAP_SHA256");
        assertNotNull(publicAddress, "ANTD_TEST_SHA_PUBLIC_ADDRESS");
        assertNotNull(publicSha, "ANTD_TEST_SHA_PUBLIC_SHA256");
        assertNotNull(dataMapSha, "ANTD_TEST_SHA_DATA_MAP_SHA256");

        try (AntdClient rest = new AntdClient(url, Duration.ofSeconds(60))) {
            check("rest", new Api() {
                public ManifestEntryInfo[] decodeLink(String l) {
                    return rest.decodeManifestLink(l, false).entries().toArray(new ManifestEntryInfo[0]);
                }

                public BuiltManifest build(List<ManifestEntryInput> entries) {
                    return rest.buildManifest(entries);
                }

                public DataPutPublicResult putPublic(byte[] data) {
                    return rest.dataPutPublic(data);
                }
            }, link, publicAddress, publicSha, dataMapSha);
        }

        String grpcTarget = env("ANTD_TEST_GRPC");
        if (grpcTarget != null) {
            try (GrpcAntdClient grpc = new GrpcAntdClient(grpcTarget)) {
                check("grpc", new Api() {
                    public ManifestEntryInfo[] decodeLink(String l) {
                        return grpc.decodeManifestLink(l, false).entries().toArray(new ManifestEntryInfo[0]);
                    }

                    public BuiltManifest build(List<ManifestEntryInput> entries) {
                        return grpc.buildManifest(entries);
                    }

                    public DataPutPublicResult putPublic(byte[] data) {
                        return grpc.dataPutPublic(data);
                    }
                }, link, publicAddress, publicSha, dataMapSha);
            }
        }
    }
}
