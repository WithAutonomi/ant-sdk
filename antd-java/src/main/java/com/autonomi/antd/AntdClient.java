package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.errors.ExceptionFactory;
import com.autonomi.antd.models.*;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;

/**
 * REST client for the antd daemon — the gateway to the Autonomi decentralized network.
 *
 * <p>Zero external dependencies — uses only {@code java.net.http} and an internal JSON parser.
 *
 * <p>Implements {@link AutoCloseable} so it can be used in try-with-resources blocks.
 *
 * <pre>{@code
 * try (var client = new AntdClient()) {
 *     HealthStatus health = client.health();
 *     System.out.println(health.network());
 * }
 * }</pre>
 */
public class AntdClient implements AutoCloseable {

    /** Default daemon address. */
    public static final String DEFAULT_BASE_URL = "http://localhost:8082";

    /** Default request timeout (5 minutes). */
    public static final Duration DEFAULT_TIMEOUT = Duration.ofMinutes(5);

    private final String baseUrl;
    private final HttpClient httpClient;
    private final Duration timeout;

    /**
     * Creates a client that auto-discovers the daemon via the {@code daemon.port} file.
     * Falls back to {@link #DEFAULT_BASE_URL} if discovery fails.
     *
     * @return a new AntdClient connected to the discovered or default URL
     */
    public static AntdClient autoDiscover() {
        String url = DaemonDiscovery.discoverDaemonUrl();
        if (url.isEmpty()) {
            url = DEFAULT_BASE_URL;
        }
        return new AntdClient(url);
    }

    public AntdClient() {
        this(DEFAULT_BASE_URL, DEFAULT_TIMEOUT);
    }

    public AntdClient(String baseUrl) {
        this(baseUrl, DEFAULT_TIMEOUT);
    }

    public AntdClient(String baseUrl, Duration timeout) {
        this(baseUrl, timeout, HttpClient.newBuilder().connectTimeout(timeout).build());
    }

    public AntdClient(String baseUrl, Duration timeout, HttpClient httpClient) {
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.timeout = timeout;
        this.httpClient = httpClient;
    }

    @Override
    public void close() {
        // HttpClient does not require explicit close in Java 17.
    }

    // ── Internal helpers ──

    private static String b64Encode(byte[] data) {
        return Base64.getEncoder().encodeToString(data);
    }

    private static byte[] b64Decode(String s) {
        return Base64.getDecoder().decode(s);
    }

    private String url(String path) {
        return baseUrl + path;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> doJson(String method, String path, String body) {
        try {
            HttpRequest.Builder reqBuilder = HttpRequest.newBuilder()
                    .uri(URI.create(url(path)))
                    .timeout(timeout);

            if (body != null) {
                reqBuilder.header("Content-Type", "application/json")
                        .method(method, HttpRequest.BodyPublishers.ofString(body));
            } else {
                reqBuilder.method(method, HttpRequest.BodyPublishers.noBody());
            }

            HttpResponse<String> resp = httpClient.send(reqBuilder.build(),
                    HttpResponse.BodyHandlers.ofString());

            int status = resp.statusCode();
            String respBody = resp.body();

            if (status < 200 || status >= 300) {
                String msg = respBody;
                try {
                    Map<String, Object> parsed = Json.parseObject(respBody);
                    Object err = parsed.get("error");
                    if (err != null) msg = err.toString();
                } catch (Exception ignored) {}
                throw ExceptionFactory.fromHttpStatus(status, msg);
            }

            if (respBody == null || respBody.isBlank()) return null;
            return Json.parseObject(respBody);

        } catch (AntdException e) {
            throw e;
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            throw new AntdException(0, "HTTP request failed: " + e.getMessage());
        }
    }

    private int doHead(String path) {
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(url(path)))
                    .timeout(timeout)
                    .method("HEAD", HttpRequest.BodyPublishers.noBody())
                    .build();
            HttpResponse<Void> resp = httpClient.send(req, HttpResponse.BodyHandlers.discarding());
            return resp.statusCode();
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            throw new AntdException(0, "HTTP request failed: " + e.getMessage());
        }
    }

    private static String str(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v != null ? v.toString() : "";
    }

    private static long num(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof Number n) return n.longValue();
        return 0L;
    }

    @SuppressWarnings("unchecked")
    private static List<String> strList(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof List<?> list) {
            List<String> result = new ArrayList<>(list.size());
            for (Object item : list) result.add(item.toString());
            return Collections.unmodifiableList(result);
        }
        return Collections.emptyList();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapAt(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof Map<?, ?> map ? (Map<String, Object>) map : null;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> listOfMaps(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof List<?> list) {
            List<Map<String, Object>> result = new ArrayList<>();
            for (Object item : list) {
                if (item instanceof Map<?, ?> map) result.add((Map<String, Object>) map);
            }
            return result;
        }
        return Collections.emptyList();
    }

    // ── Health ──

    public HealthStatus health() {
        Map<String, Object> j = doJson("GET", "/health", null);
        return new HealthStatus("ok".equals(str(j, "status")), str(j, "network"));
    }

    // ── Data (Immutable) ──

    public PutResult dataPutPublic(byte[] data) {
        return dataPutPublic(data, null);
    }

    public PutResult dataPutPublic(byte[] data, String paymentMode) {
        String body = paymentMode != null
                ? Json.object("data", b64Encode(data), "payment_mode", paymentMode)
                : Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/data/public", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public byte[] dataGetPublic(String address) {
        Map<String, Object> j = doJson("GET", "/v1/data/public/" + address, null);
        return b64Decode(str(j, "data"));
    }

    public PutResult dataPutPrivate(byte[] data) {
        return dataPutPrivate(data, null);
    }

    public PutResult dataPutPrivate(byte[] data, String paymentMode) {
        String body = paymentMode != null
                ? Json.object("data", b64Encode(data), "payment_mode", paymentMode)
                : Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/data/private", body);
        return new PutResult(str(j, "cost"), str(j, "data_map"));
    }

    public byte[] dataGetPrivate(String dataMap) {
        String encoded = URLEncoder.encode(dataMap, StandardCharsets.UTF_8);
        Map<String, Object> j = doJson("GET", "/v1/data/private?data_map=" + encoded, null);
        return b64Decode(str(j, "data"));
    }

    public String dataCost(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/data/cost", body);
        return str(j, "cost");
    }

    // ── Chunks ──

    public PutResult chunkPut(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/chunks", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public byte[] chunkGet(String address) {
        Map<String, Object> j = doJson("GET", "/v1/chunks/" + address, null);
        return b64Decode(str(j, "data"));
    }

    // ── Graph Entries (DAG Nodes) ──

    public PutResult graphEntryPut(String ownerSecretKey, List<String> parents,
                                   String content, List<GraphDescendant> descendants) {
        List<Map<String, Object>> descs = new ArrayList<>();
        for (GraphDescendant d : descendants) {
            descs.add(Map.of("public_key", d.publicKey(), "content", d.content()));
        }
        String body = Json.object(
                "owner_secret_key", ownerSecretKey,
                "parents", parents,
                "content", content,
                "descendants", descs
        );
        Map<String, Object> j = doJson("POST", "/v1/graph", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public GraphEntry graphEntryGet(String address) {
        Map<String, Object> j = doJson("GET", "/v1/graph/" + address, null);
        List<GraphDescendant> descs = new ArrayList<>();
        for (Map<String, Object> dm : listOfMaps(j, "descendants")) {
            descs.add(new GraphDescendant(str(dm, "public_key"), str(dm, "content")));
        }
        return new GraphEntry(str(j, "owner"), strList(j, "parents"), str(j, "content"),
                Collections.unmodifiableList(descs));
    }

    public boolean graphEntryExists(String address) {
        int code = doHead("/v1/graph/" + address);
        if (code == 404) return false;
        if (code >= 300) throw ExceptionFactory.fromHttpStatus(code, "graph entry exists check failed");
        return true;
    }

    public String graphEntryCost(String publicKey) {
        String body = Json.object("public_key", publicKey);
        Map<String, Object> j = doJson("POST", "/v1/graph/cost", body);
        return str(j, "cost");
    }

    // ── Files & Directories ──

    public PutResult fileUploadPublic(String path) {
        return fileUploadPublic(path, null);
    }

    public PutResult fileUploadPublic(String path, String paymentMode) {
        String body = paymentMode != null
                ? Json.object("path", path, "payment_mode", paymentMode)
                : Json.object("path", path);
        Map<String, Object> j = doJson("POST", "/v1/files/upload/public", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public void fileDownloadPublic(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        doJson("POST", "/v1/files/download/public", body);
    }

    public PutResult dirUploadPublic(String path) {
        return dirUploadPublic(path, null);
    }

    public PutResult dirUploadPublic(String path, String paymentMode) {
        String body = paymentMode != null
                ? Json.object("path", path, "payment_mode", paymentMode)
                : Json.object("path", path);
        Map<String, Object> j = doJson("POST", "/v1/dirs/upload/public", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public void dirDownloadPublic(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        doJson("POST", "/v1/dirs/download/public", body);
    }

    public Archive archiveGetPublic(String address) {
        Map<String, Object> j = doJson("GET", "/v1/archives/public/" + address, null);
        List<ArchiveEntry> entries = new ArrayList<>();
        for (Map<String, Object> em : listOfMaps(j, "entries")) {
            entries.add(new ArchiveEntry(str(em, "path"), str(em, "address"),
                    num(em, "created"), num(em, "modified"), num(em, "size")));
        }
        return new Archive(Collections.unmodifiableList(entries));
    }

    public PutResult archivePutPublic(Archive archive) {
        List<Map<String, Object>> entries = new ArrayList<>();
        for (ArchiveEntry e : archive.entries()) {
            entries.add(Map.of(
                    "path", e.path(), "address", e.address(),
                    "created", e.created(), "modified", e.modified(), "size", e.size()
            ));
        }
        String body = Json.object("entries", entries);
        Map<String, Object> j = doJson("POST", "/v1/archives/public", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public String fileCost(String path, boolean isPublic, boolean includeArchive) {
        String body = Json.object("path", path, "is_public", isPublic, "include_archive", includeArchive);
        Map<String, Object> j = doJson("POST", "/v1/cost/file", body);
        return str(j, "cost");
    }

    // ── Wallet ──

    public WalletAddress walletAddress() {
        Map<String, Object> j = doJson("GET", "/v1/wallet/address", null);
        return new WalletAddress(str(j, "address"));
    }

    public WalletBalance walletBalance() {
        Map<String, Object> j = doJson("GET", "/v1/wallet/balance", null);
        return new WalletBalance(str(j, "balance"), str(j, "gas_balance"));
    }
}
