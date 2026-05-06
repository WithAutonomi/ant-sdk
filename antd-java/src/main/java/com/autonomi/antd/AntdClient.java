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
        return parseHealthStatus(doJson("GET", "/health", null));
    }

    /**
     * Convert a /health JSON response to a typed HealthStatus. Diagnostic
     * fields default to empty / 0 when talking to a pre-0.4.0 daemon. Package-
     * private so AsyncAntdClient can share the parser.
     */
    static HealthStatus parseHealthStatus(Map<String, Object> j) {
        return new HealthStatus(
                "ok".equals(str(j, "status")),
                str(j, "network"),
                str(j, "version"),
                str(j, "evm_network"),
                num(j, "uptime_seconds"),
                str(j, "build_commit"),
                str(j, "payment_token_address"),
                str(j, "payment_vault_address"));
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

    /**
     * Pre-upload cost breakdown for the given bytes.
     *
     * <p>The server samples a small number of chunk addresses and extrapolates,
     * much faster than quoting every chunk on slow networks. Gas is advisory.
     */
    public UploadCostEstimate dataCost(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/data/cost", body);
        return new UploadCostEstimate(
            str(j, "cost"),
            num(j, "file_size"),
            (int) num(j, "chunk_count"),
            str(j, "estimated_gas_cost_wei"),
            str(j, "payment_mode"));
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

    // ── Files & Directories ──

    public FileUploadResult fileUploadPublic(String path) {
        return fileUploadPublic(path, null);
    }

    public FileUploadResult fileUploadPublic(String path, String paymentMode) {
        String body = paymentMode != null
                ? Json.object("path", path, "payment_mode", paymentMode)
                : Json.object("path", path);
        Map<String, Object> j = doJson("POST", "/v1/files/upload/public", body);
        return parseFileUploadResult(j);
    }

    public void fileDownloadPublic(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        doJson("POST", "/v1/files/download/public", body);
    }

    public FileUploadResult dirUploadPublic(String path) {
        return dirUploadPublic(path, null);
    }

    public FileUploadResult dirUploadPublic(String path, String paymentMode) {
        String body = paymentMode != null
                ? Json.object("path", path, "payment_mode", paymentMode)
                : Json.object("path", path);
        Map<String, Object> j = doJson("POST", "/v1/dirs/upload/public", body);
        return parseFileUploadResult(j);
    }

    private static FileUploadResult parseFileUploadResult(Map<String, Object> j) {
        return new FileUploadResult(
                str(j, "address"),
                str(j, "storage_cost_atto"),
                str(j, "gas_cost_wei"),
                num(j, "chunks_stored"),
                str(j, "payment_mode_used"));
    }

    public void dirDownloadPublic(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        doJson("POST", "/v1/dirs/download/public", body);
    }

    /**
     * Pre-upload cost breakdown for the file at {@code path}.
     */
    public UploadCostEstimate fileCost(String path, boolean isPublic) {
        String body = Json.object("path", path, "is_public", isPublic);
        Map<String, Object> j = doJson("POST", "/v1/files/cost", body);
        return new UploadCostEstimate(
            str(j, "cost"),
            num(j, "file_size"),
            (int) num(j, "chunk_count"),
            str(j, "estimated_gas_cost_wei"),
            str(j, "payment_mode"));
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

    /**
     * Approves the wallet to spend tokens on payment contracts.
     * This is a one-time operation required before any storage operations.
     *
     * @return true if the wallet was approved
     * @throws AntdException if no wallet is configured (HTTP 400) or on other errors
     */
    public boolean walletApprove() {
        Map<String, Object> j = doJson("POST", "/v1/wallet/approve", "{}");
        Object approved = j.get("approved");
        return approved instanceof Boolean b && b;
    }

    // ── External Signer (Two-Phase Upload) ──

    /**
     * Parses a prepare-upload JSON response into a PrepareUploadResult.
     * Handles both wave_batch and merkle payment types.
     */
    private static PrepareUploadResult parsePrepareResponse(Map<String, Object> j) {
        String paymentType = str(j, "payment_type");
        if (paymentType.isEmpty()) {
            paymentType = "wave_batch";
        }

        // Parse wave-batch payments
        List<PaymentInfo> payments = new ArrayList<>();
        for (Map<String, Object> pm : listOfMaps(j, "payments")) {
            payments.add(new PaymentInfo(str(pm, "quote_hash"), str(pm, "rewards_address"), str(pm, "amount")));
        }

        // Parse merkle fields
        Integer depth = null;
        List<PoolCommitmentEntry> poolCommitments = null;
        Long merklePaymentTimestamp = null;

        if ("merkle".equals(paymentType)) {
            long depthVal = num(j, "depth");
            depth = (int) depthVal;
            merklePaymentTimestamp = num(j, "merkle_payment_timestamp");

            poolCommitments = new ArrayList<>();
            for (Map<String, Object> pcm : listOfMaps(j, "pool_commitments")) {
                List<CandidateNodeEntry> candidates = new ArrayList<>();
                for (Map<String, Object> cm : listOfMaps(pcm, "candidates")) {
                    candidates.add(new CandidateNodeEntry(str(cm, "rewards_address"), str(cm, "amount")));
                }
                poolCommitments.add(new PoolCommitmentEntry(str(pcm, "pool_hash"), Collections.unmodifiableList(candidates)));
            }
            poolCommitments = Collections.unmodifiableList(poolCommitments);
        }

        return new PrepareUploadResult(
                str(j, "upload_id"),
                paymentType,
                Collections.unmodifiableList(payments),
                str(j, "total_amount"),
                str(j, "payment_vault_address"),
                str(j, "payment_token_address"),
                str(j, "rpc_url"),
                depth,
                poolCommitments,
                merklePaymentTimestamp
        );
    }

    /**
     * Prepares a file upload for external signing.
     * Returns payment details that an external signer must process before calling
     * {@link #finalizeUpload} (wave_batch) or {@link #finalizeMerkleUpload} (merkle).
     *
     * @param path local file path to upload
     * @return PrepareUploadResult with upload_id, payments, and contract details
     */
    public PrepareUploadResult prepareUpload(String path) {
        String body = Json.object("path", path);
        Map<String, Object> j = doJson("POST", "/v1/upload/prepare", body);
        return parsePrepareResponse(j);
    }

    /**
     * Prepares a data upload for external signing.
     * Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
     * Returns payment details that an external signer must process before calling
     * {@link #finalizeUpload} (wave_batch) or {@link #finalizeMerkleUpload} (merkle).
     *
     * @param data raw bytes to upload
     * @return PrepareUploadResult with upload_id, payments, and contract details
     */
    public PrepareUploadResult prepareDataUpload(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/data/prepare", body);
        return parsePrepareResponse(j);
    }

    /**
     * Finalizes a wave-batch upload after an external signer has submitted payment transactions.
     *
     * @param uploadId the upload ID returned by {@link #prepareUpload}
     * @param txHashes map of quote_hash to tx_hash for each payment
     * @return FinalizeUploadResult with address and chunks_stored
     */
    public FinalizeUploadResult finalizeUpload(String uploadId, Map<String, String> txHashes) {
        String body = Json.object("upload_id", uploadId, "tx_hashes", txHashes);
        Map<String, Object> j = doJson("POST", "/v1/upload/finalize", body);
        return new FinalizeUploadResult(str(j, "address"), num(j, "chunks_stored"));
    }

    /**
     * Finalizes a merkle upload after the external signer has submitted the
     * payForMerkleTree transaction. The winnerPoolHash is the bytes32 value from
     * the MerklePaymentMade event (hex with 0x prefix).
     *
     * @param uploadId       the upload ID returned by {@link #prepareUpload}
     * @param winnerPoolHash bytes32 pool hash from MerklePaymentMade event
     * @return FinalizeUploadResult with address and chunks_stored
     */
    public FinalizeUploadResult finalizeMerkleUpload(String uploadId, String winnerPoolHash) {
        String body = Json.object("upload_id", uploadId, "winner_pool_hash", winnerPoolHash);
        Map<String, Object> j = doJson("POST", "/v1/upload/finalize", body);
        return new FinalizeUploadResult(str(j, "address"), num(j, "chunks_stored"));
    }
}
