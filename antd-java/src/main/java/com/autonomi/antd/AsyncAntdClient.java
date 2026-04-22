package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.errors.ExceptionFactory;
import com.autonomi.antd.models.*;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CompletableFuture;

/**
 * Async REST client for the antd daemon — the gateway to the Autonomi decentralized network.
 *
 * <p>Non-blocking counterpart to {@link AntdClient}. Every method returns a
 * {@link CompletableFuture} and uses {@code HttpClient.sendAsync()} for truly
 * non-blocking I/O — no thread-pool wrappers around blocking calls.
 *
 * <p>Zero external dependencies — uses only {@code java.net.http},
 * {@code java.util.concurrent}, and the internal JSON parser.
 *
 * <p>Implements {@link AutoCloseable} so it can be used in try-with-resources blocks.
 *
 * <pre>{@code
 * try (var client = new AsyncAntdClient()) {
 *     client.healthAsync()
 *           .thenAccept(h -> System.out.println(h.network()))
 *           .join();
 * }
 * }</pre>
 */
public class AsyncAntdClient implements AutoCloseable {

    /** Default daemon address. */
    public static final String DEFAULT_BASE_URL = "http://localhost:8082";

    /** Default request timeout (5 minutes). */
    public static final Duration DEFAULT_TIMEOUT = Duration.ofMinutes(5);

    private final String baseUrl;
    private final HttpClient httpClient;
    private final Duration timeout;

    public AsyncAntdClient() {
        this(DEFAULT_BASE_URL, DEFAULT_TIMEOUT);
    }

    public AsyncAntdClient(String baseUrl) {
        this(baseUrl, DEFAULT_TIMEOUT);
    }

    public AsyncAntdClient(String baseUrl, Duration timeout) {
        this(baseUrl, timeout, HttpClient.newBuilder().connectTimeout(timeout).build());
    }

    public AsyncAntdClient(String baseUrl, Duration timeout, HttpClient httpClient) {
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

    /**
     * Async equivalent of {@code AntdClient.doJson()} — sends an HTTP request and
     * parses the JSON response body, all non-blocking via {@code sendAsync()}.
     */
    @SuppressWarnings("unchecked")
    private CompletableFuture<Map<String, Object>> doJsonAsync(String method, String path, String body) {
        HttpRequest.Builder reqBuilder = HttpRequest.newBuilder()
                .uri(URI.create(url(path)))
                .timeout(timeout);

        if (body != null) {
            reqBuilder.header("Content-Type", "application/json")
                    .method(method, HttpRequest.BodyPublishers.ofString(body));
        } else {
            reqBuilder.method(method, HttpRequest.BodyPublishers.noBody());
        }

        return httpClient.sendAsync(reqBuilder.build(), HttpResponse.BodyHandlers.ofString())
                .thenApply(resp -> {
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
                });
    }

    /**
     * Async equivalent of {@code AntdClient.doHead()} — sends a HEAD request
     * and returns the status code, all non-blocking.
     */
    private CompletableFuture<Integer> doHeadAsync(String path) {
        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(url(path)))
                .timeout(timeout)
                .method("HEAD", HttpRequest.BodyPublishers.noBody())
                .build();
        return httpClient.sendAsync(req, HttpResponse.BodyHandlers.discarding())
                .thenApply(HttpResponse::statusCode);
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

    /** Async variant of {@link AntdClient#health()}. */
    public CompletableFuture<HealthStatus> healthAsync() {
        return doJsonAsync("GET", "/health", null)
                .thenApply(j -> new HealthStatus("ok".equals(str(j, "status")), str(j, "network")));
    }

    // ── Data (Immutable) ──

    /** Async variant of {@link AntdClient#dataPutPublic(byte[])}. */
    public CompletableFuture<PutResult> dataPutPublicAsync(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        return doJsonAsync("POST", "/v1/data/public", body)
                .thenApply(j -> new PutResult(str(j, "cost"), str(j, "address")));
    }

    /** Async variant of {@link AntdClient#dataGetPublic(String)}. */
    public CompletableFuture<byte[]> dataGetPublicAsync(String address) {
        return doJsonAsync("GET", "/v1/data/public/" + address, null)
                .thenApply(j -> b64Decode(str(j, "data")));
    }

    /** Async variant of {@link AntdClient#dataPutPrivate(byte[])}. */
    public CompletableFuture<PutResult> dataPutPrivateAsync(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        return doJsonAsync("POST", "/v1/data/private", body)
                .thenApply(j -> new PutResult(str(j, "cost"), str(j, "data_map")));
    }

    /** Async variant of {@link AntdClient#dataGetPrivate(String)}. */
    public CompletableFuture<byte[]> dataGetPrivateAsync(String dataMap) {
        String encoded = URLEncoder.encode(dataMap, StandardCharsets.UTF_8);
        return doJsonAsync("GET", "/v1/data/private?data_map=" + encoded, null)
                .thenApply(j -> b64Decode(str(j, "data")));
    }

    /** Async variant of {@link AntdClient#dataCost(byte[])}. */
    public CompletableFuture<UploadCostEstimate> dataCostAsync(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        return doJsonAsync("POST", "/v1/data/cost", body)
                .thenApply(j -> new UploadCostEstimate(
                        str(j, "cost"),
                        num(j, "file_size"),
                        (int) num(j, "chunk_count"),
                        str(j, "estimated_gas_cost_wei"),
                        str(j, "payment_mode")));
    }

    // ── Chunks ──

    /** Async variant of {@link AntdClient#chunkPut(byte[])}. */
    public CompletableFuture<PutResult> chunkPutAsync(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        return doJsonAsync("POST", "/v1/chunks", body)
                .thenApply(j -> new PutResult(str(j, "cost"), str(j, "address")));
    }

    /** Async variant of {@link AntdClient#chunkGet(String)}. */
    public CompletableFuture<byte[]> chunkGetAsync(String address) {
        return doJsonAsync("GET", "/v1/chunks/" + address, null)
                .thenApply(j -> b64Decode(str(j, "data")));
    }

    // ── Files & Directories ──

    /** Async variant of {@link AntdClient#fileUploadPublic(String)}. */
    public CompletableFuture<FileUploadResult> fileUploadPublicAsync(String path) {
        String body = Json.object("path", path);
        return doJsonAsync("POST", "/v1/files/upload/public", body)
                .thenApply(AsyncAntdClient::parseFileUploadResult);
    }

    /** Async variant of {@link AntdClient#fileDownloadPublic(String, String)}. */
    public CompletableFuture<Void> fileDownloadPublicAsync(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        return doJsonAsync("POST", "/v1/files/download/public", body)
                .thenApply(j -> null);
    }

    /** Async variant of {@link AntdClient#dirUploadPublic(String)}. */
    public CompletableFuture<FileUploadResult> dirUploadPublicAsync(String path) {
        String body = Json.object("path", path);
        return doJsonAsync("POST", "/v1/dirs/upload/public", body)
                .thenApply(AsyncAntdClient::parseFileUploadResult);
    }

    private static FileUploadResult parseFileUploadResult(Map<String, Object> j) {
        return new FileUploadResult(
                str(j, "address"),
                str(j, "storage_cost_atto"),
                str(j, "gas_cost_wei"),
                num(j, "chunks_stored"),
                str(j, "payment_mode_used"));
    }

    /** Async variant of {@link AntdClient#dirDownloadPublic(String, String)}. */
    public CompletableFuture<Void> dirDownloadPublicAsync(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        return doJsonAsync("POST", "/v1/dirs/download/public", body)
                .thenApply(j -> null);
    }

    /** Async variant of {@link AntdClient#fileCost(String, boolean)}. */
    public CompletableFuture<UploadCostEstimate> fileCostAsync(String path, boolean isPublic) {
        String body = Json.object("path", path, "is_public", isPublic);
        return doJsonAsync("POST", "/v1/files/cost", body)
                .thenApply(j -> new UploadCostEstimate(
                        str(j, "cost"),
                        num(j, "file_size"),
                        (int) num(j, "chunk_count"),
                        str(j, "estimated_gas_cost_wei"),
                        str(j, "payment_mode")));
    }
}
