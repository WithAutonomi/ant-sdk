package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.errors.ExceptionFactory;
import com.autonomi.antd.models.*;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
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

    // Health

    public HealthStatus health() {
        return parseHealthStatus(doJson("GET", "/health", null));
    }

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

    // Data

    /** Stores private encrypted data. Returns the caller-held DataMap (hex). */
    public DataPutResult dataPut(byte[] data, PaymentMode paymentMode) {
        String body = Json.object("data", b64Encode(data), "payment_mode", paymentMode.wireValue());
        Map<String, Object> j = doJson("POST", "/v1/data", body);
        return new DataPutResult(
                str(j, "data_map"),
                num(j, "chunks_stored"),
                str(j, "payment_mode_used"));
    }

    public DataPutResult dataPut(byte[] data) {
        return dataPut(data, PaymentMode.AUTO);
    }

    /** Retrieves private data from a caller-held DataMap (hex). */
    public byte[] dataGet(String dataMap) {
        String body = Json.object("data_map", dataMap);
        Map<String, Object> j = doJson("POST", "/v1/data/get", body);
        return b64Decode(str(j, "data"));
    }

    /** Stores public data. Returns the on-network DataMap address. */
    public DataPutPublicResult dataPutPublic(byte[] data, PaymentMode paymentMode) {
        String body = Json.object("data", b64Encode(data), "payment_mode", paymentMode.wireValue());
        Map<String, Object> j = doJson("POST", "/v1/data/public", body);
        return new DataPutPublicResult(
                str(j, "address"),
                num(j, "chunks_stored"),
                str(j, "payment_mode_used"));
    }

    public DataPutPublicResult dataPutPublic(byte[] data) {
        return dataPutPublic(data, PaymentMode.AUTO);
    }

    /** Retrieves public data by address. */
    public byte[] dataGetPublic(String address) {
        Map<String, Object> j = doJson("GET", "/v1/data/public/" + address, null);
        return b64Decode(str(j, "data"));
    }

    /** Pre-upload cost breakdown for the given bytes. */
    public UploadCostEstimate dataCost(byte[] data, PaymentMode paymentMode) {
        String body = Json.object("data", b64Encode(data), "payment_mode", paymentMode.wireValue());
        Map<String, Object> j = doJson("POST", "/v1/data/cost", body);
        return new UploadCostEstimate(
                str(j, "cost"),
                num(j, "file_size"),
                (int) num(j, "chunk_count"),
                str(j, "estimated_gas_cost_wei"),
                str(j, "payment_mode"));
    }

    public UploadCostEstimate dataCost(byte[] data) {
        return dataCost(data, PaymentMode.AUTO);
    }

    // Chunks

    public PutResult chunkPut(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/chunks", body);
        return new PutResult(str(j, "cost"), str(j, "address"));
    }

    public byte[] chunkGet(String address) {
        Map<String, Object> j = doJson("GET", "/v1/chunks/" + address, null);
        return b64Decode(str(j, "data"));
    }

    /**
     * Prepare a single chunk for external-signer publish.
     * Requires antd &gt;= 0.7.0.
     */
    public PrepareChunkResult prepareChunkUpload(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/chunks/prepare", body);
        return parsePrepareChunkResult(j);
    }

    /**
     * Submit a single chunk after external payment.
     * Requires antd &gt;= 0.7.0.
     */
    public String finalizeChunkUpload(String uploadId, Map<String, String> txHashes) {
        String body = Json.object("upload_id", uploadId, "tx_hashes", txHashes);
        Map<String, Object> j = doJson("POST", "/v1/chunks/finalize", body);
        return str(j, "address");
    }

    static PrepareChunkResult parsePrepareChunkResult(Map<String, Object> j) {
        Object alreadyObj = j.get("already_stored");
        boolean alreadyStored = alreadyObj instanceof Boolean b && b;

        List<PaymentInfo> payments = new ArrayList<>();
        for (Map<String, Object> pm : listOfMaps(j, "payments")) {
            payments.add(new PaymentInfo(
                    str(pm, "quote_hash"),
                    str(pm, "rewards_address"),
                    str(pm, "amount")));
        }

        return new PrepareChunkResult(
                str(j, "address"),
                alreadyStored,
                str(j, "upload_id"),
                str(j, "payment_type"),
                Collections.unmodifiableList(payments),
                str(j, "total_amount"),
                str(j, "payment_vault_address"),
                str(j, "payment_token_address"),
                str(j, "rpc_url"));
    }

    // Files

    /** Uploads a file privately. Returns the caller-held DataMap (hex). */
    public FilePutResult filePut(String path, PaymentMode paymentMode) {
        String body = Json.object("path", path, "payment_mode", paymentMode.wireValue());
        Map<String, Object> j = doJson("POST", "/v1/files", body);
        return parseFilePutResult(j);
    }

    public FilePutResult filePut(String path) {
        return filePut(path, PaymentMode.AUTO);
    }

    /** Downloads a private file from a caller-held DataMap into {@code destPath}. */
    public void fileGet(String dataMap, String destPath) {
        String body = Json.object("data_map", dataMap, "dest_path", destPath);
        doJson("POST", "/v1/files/get", body);
    }

    /** Uploads a file publicly. Returns the on-network DataMap address. */
    public FilePutPublicResult filePutPublic(String path, PaymentMode paymentMode) {
        String body = Json.object("path", path, "payment_mode", paymentMode.wireValue());
        Map<String, Object> j = doJson("POST", "/v1/files/public", body);
        return parseFilePutPublicResult(j);
    }

    public FilePutPublicResult filePutPublic(String path) {
        return filePutPublic(path, PaymentMode.AUTO);
    }

    /** Downloads a public file from an on-network DataMap address. */
    public void fileGetPublic(String address, String destPath) {
        String body = Json.object("address", address, "dest_path", destPath);
        doJson("POST", "/v1/files/public/get", body);
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

    /** Pre-upload cost breakdown for the file at {@code path}. */
    public UploadCostEstimate fileCost(String path, boolean isPublic, PaymentMode paymentMode) {
        String body = Json.object("path", path, "is_public", isPublic, "payment_mode", paymentMode.wireValue());
        Map<String, Object> j = doJson("POST", "/v1/files/cost", body);
        return new UploadCostEstimate(
                str(j, "cost"),
                num(j, "file_size"),
                (int) num(j, "chunk_count"),
                str(j, "estimated_gas_cost_wei"),
                str(j, "payment_mode"));
    }

    public UploadCostEstimate fileCost(String path, boolean isPublic) {
        return fileCost(path, isPublic, PaymentMode.AUTO);
    }

    // Wallet

    public WalletAddress walletAddress() {
        Map<String, Object> j = doJson("GET", "/v1/wallet/address", null);
        return new WalletAddress(str(j, "address"));
    }

    public WalletBalance walletBalance() {
        Map<String, Object> j = doJson("GET", "/v1/wallet/balance", null);
        return new WalletBalance(str(j, "balance"), str(j, "gas_balance"));
    }

    public boolean walletApprove() {
        Map<String, Object> j = doJson("POST", "/v1/wallet/approve", "{}");
        Object approved = j.get("approved");
        return approved instanceof Boolean b && b;
    }

    // External Signer (Two-Phase Upload)

    static PrepareUploadResult parsePrepareResponse(Map<String, Object> j) {
        String paymentType = str(j, "payment_type");
        if (paymentType.isEmpty()) {
            paymentType = "wave_batch";
        }

        List<PaymentInfo> payments = new ArrayList<>();
        for (Map<String, Object> pm : listOfMaps(j, "payments")) {
            payments.add(new PaymentInfo(str(pm, "quote_hash"), str(pm, "rewards_address"), str(pm, "amount")));
        }

        Integer depth = null;
        List<PoolCommitmentEntry> poolCommitments = null;
        Long merklePaymentTimestamp = null;

        if ("merkle".equals(paymentType)) {
            depth = (int) num(j, "depth");
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

    public PrepareUploadResult prepareUpload(String path) {
        return prepareUpload(path, null);
    }

    public PrepareUploadResult prepareUpload(String path, String visibility) {
        String body = visibility != null
                ? Json.object("path", path, "visibility", visibility)
                : Json.object("path", path);
        Map<String, Object> j = doJson("POST", "/v1/upload/prepare", body);
        return parsePrepareResponse(j);
    }

    public PrepareUploadResult prepareUploadPublic(String path) {
        return prepareUpload(path, "public");
    }

    public PrepareUploadResult prepareDataUpload(byte[] data) {
        String body = Json.object("data", b64Encode(data));
        Map<String, Object> j = doJson("POST", "/v1/data/prepare", body);
        return parsePrepareResponse(j);
    }

    static FinalizeUploadResult parseFinalizeUploadResult(Map<String, Object> j) {
        return new FinalizeUploadResult(
                str(j, "address"),
                num(j, "chunks_stored"),
                str(j, "data_map"),
                str(j, "data_map_address"));
    }

    public FinalizeUploadResult finalizeUpload(String uploadId, Map<String, String> txHashes) {
        String body = Json.object("upload_id", uploadId, "tx_hashes", txHashes);
        Map<String, Object> j = doJson("POST", "/v1/upload/finalize", body);
        return parseFinalizeUploadResult(j);
    }

    public FinalizeUploadResult finalizeMerkleUpload(String uploadId, String winnerPoolHash) {
        String body = Json.object("upload_id", uploadId, "winner_pool_hash", winnerPoolHash);
        Map<String, Object> j = doJson("POST", "/v1/upload/finalize", body);
        return parseFinalizeUploadResult(j);
    }
}
