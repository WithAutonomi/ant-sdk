package com.autonomi.antd;

import com.autonomi.antd.errors.ExceptionFactory;
import com.autonomi.antd.models.*;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CompletableFuture;

/**
 * Async REST client for the antd daemon.
 *
 * <p>Non-blocking counterpart to {@link AntdClient}. Every method returns a
 * {@link CompletableFuture} and uses {@code HttpClient.sendAsync()} for truly
 * non-blocking I/O.
 */
public class AsyncAntdClient implements AutoCloseable {

    public static final String DEFAULT_BASE_URL = "http://localhost:8082";
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

    // Internal helpers

    private static String b64Encode(byte[] data) {
        return Base64.getEncoder().encodeToString(data);
    }

    private static byte[] b64Decode(String s) {
        return Base64.getDecoder().decode(s);
    }

    private String url(String path) {
        return baseUrl + path;
    }

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

    private static String str(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v != null ? v.toString() : "";
    }

    private static long num(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof Number n) return n.longValue();
        return 0L;
    }

    // Health

    public CompletableFuture<HealthStatus> healthAsync() {
        return doJsonAsync("GET", "/health", null)
                .thenApply(AntdClient::parseHealthStatus);
    }

    // Data

    public CompletableFuture<DataPutResult> dataPutAsync(byte[] data, PaymentMode paymentMode) {
        String body = Json.object("data", b64Encode(data), "payment_mode", paymentMode.wireValue());
        return doJsonAsync("POST", "/v1/data", body)
                .thenApply(j -> new DataPutResult(
                        str(j, "data_map"),
                        num(j, "chunks_stored"),
                        str(j, "payment_mode_used")));
    }

    public CompletableFuture<DataPutResult> dataPutAsync(byte[] data) {
        return dataPutAsync(data, PaymentMode.AUTO);
    }

    public CompletableFuture<byte[]> dataGetAsync(String dataMap) {
        String body = Json.object("data_map", dataMap);
        return doJsonAsync("POST", "/v1/data/get", body)
                .thenApply(j -> b64Decode(str(j, "data")));
    }

    public CompletableFuture<DataPutPublicResult> dataPutPublicAsync(byte[] data, PaymentMode paymentMode) {
        String body = Json.object("data", b64Encode(data), "payment_mode", paymentMode.wireValue());
        return doJsonAsync("POST", "/v1/data/public", body)
                .thenApply(j -> new DataPutPublicResult(
                        str(j, "address"),
                        num(j, "chunks_stored"),
                        str(j, "payment_mode_used")));
    }

    public CompletableFuture<DataPutPublicResult> dataPutPublicAsync(byte[] data) {
        return dataPutPublicAsync(data, PaymentMode.AUTO);
    }

    public CompletableFuture<byte[]> dataGetPublicAsync(String address) {
        return doJsonAsync("GET", "/v1/data/public/" + address, null)
                .thenApply(j -> b64Decode(str(j, "data")));
    }

    public CompletableFuture<UploadCostEstimate> dataCostAsync(byte[] data, PaymentMode paymentMode) {
        String body = Json.object("data", b64Encode(data), "payment_mode", paymentMode.wireValue());
        return doJsonAsync("POST", "/v1/data/cost", body)
                .thenApply(j -> new UploadCostEstimate(
                        str(j, "cost"),
                        num(j, "file_size"),
                        (int) num(j, "chunk_count"),
                        str(j, "estimated_gas_cost_wei"),
                        str(j, "payment_mode")));
    }

    public CompletableFuture<UploadCostEstimate> dataCostAsync(byte[] data) {
        return dataCostAsync(data, PaymentMode.AUTO);
    }

    // Chunks

    public CompletableFuture<PutResult> chunkPutAsync(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        return doJsonAsync("POST", "/v1/chunks", body)
                .thenApply(j -> new PutResult(str(j, "cost"), str(j, "address")));
    }

    public CompletableFuture<byte[]> chunkGetAsync(String address) {
        return doJsonAsync("GET", "/v1/chunks/" + address, null)
                .thenApply(j -> b64Decode(str(j, "data")));
    }

    public CompletableFuture<PrepareChunkResult> prepareChunkUploadAsync(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        return doJsonAsync("POST", "/v1/chunks/prepare", body)
                .thenApply(AntdClient::parsePrepareChunkResult);
    }

    public CompletableFuture<String> finalizeChunkUploadAsync(String uploadId, Map<String, String> txHashes) {
        String body = Json.object("upload_id", uploadId, "tx_hashes", txHashes);
        return doJsonAsync("POST", "/v1/chunks/finalize", body)
                .thenApply(j -> str(j, "address"));
    }

    // Files

    public CompletableFuture<FilePutResult> filePutAsync(String path, PaymentMode paymentMode) {
        String body = Json.object("path", path, "payment_mode", paymentMode.wireValue());
        return doJsonAsync("POST", "/v1/files", body)
                .thenApply(AsyncAntdClient::parseFilePutResult);
    }

    public CompletableFuture<FilePutResult> filePutAsync(String path) {
        return filePutAsync(path, PaymentMode.AUTO);
    }

    public CompletableFuture<Void> fileGetAsync(String dataMap, String destPath) {
        String body = Json.object("data_map", dataMap, "dest_path", destPath);
        return doJsonAsync("POST", "/v1/files/get", body).thenApply(j -> null);
    }

    public CompletableFuture<FilePutPublicResult> filePutPublicAsync(String path, PaymentMode paymentMode) {
        String body = Json.object("path", path, "payment_mode", paymentMode.wireValue());
        return doJsonAsync("POST", "/v1/files/public", body)
                .thenApply(AsyncAntdClient::parseFilePutPublicResult);
    }

    public CompletableFuture<FilePutPublicResult> filePutPublicAsync(String path) {
        return filePutPublicAsync(path, PaymentMode.AUTO);
    }

    public CompletableFuture<Void> fileGetPublicAsync(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        return doJsonAsync("POST", "/v1/files/public/get", body).thenApply(j -> null);
    }

    private static FilePutResult parseFilePutResult(Map<String, Object> j) {
        return new FilePutResult(
                str(j, "data_map"),
                str(j, "storage_cost_atto"),
                str(j, "gas_cost_wei"),
                num(j, "chunks_stored"),
                str(j, "payment_mode_used"));
    }

    private static FilePutPublicResult parseFilePutPublicResult(Map<String, Object> j) {
        return new FilePutPublicResult(
                str(j, "address"),
                str(j, "storage_cost_atto"),
                str(j, "gas_cost_wei"),
                num(j, "chunks_stored"),
                str(j, "payment_mode_used"));
    }

    public CompletableFuture<UploadCostEstimate> fileCostAsync(String path, boolean isPublic, PaymentMode paymentMode) {
        String body = Json.object("path", path, "is_public", isPublic, "payment_mode", paymentMode.wireValue());
        return doJsonAsync("POST", "/v1/files/cost", body)
                .thenApply(j -> new UploadCostEstimate(
                        str(j, "cost"),
                        num(j, "file_size"),
                        (int) num(j, "chunk_count"),
                        str(j, "estimated_gas_cost_wei"),
                        str(j, "payment_mode")));
    }

    public CompletableFuture<UploadCostEstimate> fileCostAsync(String path, boolean isPublic) {
        return fileCostAsync(path, isPublic, PaymentMode.AUTO);
    }
}
