package com.autonomi.antd;

import com.autonomi.antd.models.*;
import okhttp3.mockwebserver.Dispatcher;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.*;

import java.io.IOException;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

import static org.junit.jupiter.api.Assertions.*;

class AsyncAntdClientTest {

    private MockWebServer server;
    private AsyncAntdClient client;

    @BeforeEach
    void setUp() throws IOException {
        server = new MockWebServer();
        server.setDispatcher(new MockDaemon());
        server.start();
        client = new AsyncAntdClient(server.url("/").toString(), Duration.ofSeconds(10));
    }

    @AfterEach
    void tearDown() throws IOException {
        client.close();
        server.shutdown();
    }

    // -------------------------------------------------------------------------
    // Mock daemon — minimal routes for round-trip smoke tests on every async
    // method. Parsing edge cases are exhaustively covered by AntdClientTest;
    // this file's job is to prove async dispatch works on every method.
    // -------------------------------------------------------------------------

    static class MockDaemon extends Dispatcher {
        @Override
        public MockResponse dispatch(RecordedRequest req) {
            String path = req.getPath();
            String method = req.getMethod();

            if ("GET".equals(method) && "/health".equals(path)) {
                return json("{\"status\":\"ok\",\"network\":\"local\",\"version\":\"0.8.0\","
                        + "\"evm_network\":\"local\",\"uptime_seconds\":42,\"build_commit\":\"deadbeef\","
                        + "\"payment_token_address\":\"0xtoken\",\"payment_vault_address\":\"0xvault\"}");
            }

            // --- Wallet ---
            if ("GET".equals(method) && "/v1/wallet/address".equals(path)) {
                return json("{\"address\":\"0xaddr\"}");
            }
            if ("GET".equals(method) && "/v1/wallet/balance".equals(path)) {
                return json("{\"balance\":\"123\",\"gas_balance\":\"456\"}");
            }
            if ("POST".equals(method) && "/v1/wallet/approve".equals(path)) {
                return json("{\"approved\":true}");
            }

            // --- External-signer prepare/finalize ---
            if ("POST".equals(method) && "/v1/upload/prepare".equals(path)) {
                return json("{\"upload_id\":\"up1\",\"payment_type\":\"wave_batch\","
                        + "\"payments\":[{\"quote_hash\":\"qh1\",\"rewards_address\":\"ra1\",\"amount\":\"100\"}],"
                        + "\"total_amount\":\"100\",\"payment_vault_address\":\"0xvault\","
                        + "\"payment_token_address\":\"0xtoken\",\"rpc_url\":\"http://localhost:8545\"}");
            }
            if ("POST".equals(method) && "/v1/data/prepare".equals(path)) {
                return json("{\"upload_id\":\"dup1\",\"payment_type\":\"wave_batch\","
                        + "\"payments\":[],\"total_amount\":\"0\",\"payment_vault_address\":\"0xv2\","
                        + "\"payment_token_address\":\"0xt2\",\"rpc_url\":\"http://localhost:8545\"}");
            }
            if ("POST".equals(method) && "/v1/upload/finalize".equals(path)) {
                return json("{\"address\":\"addrfin\",\"chunks_stored\":3,"
                        + "\"data_map\":\"dm\",\"data_map_address\":\"dma\"}");
            }

            // --- Chunks ---
            if ("POST".equals(method) && "/v1/chunks".equals(path)) {
                return json("{\"cost\":\"50\",\"address\":\"chk1\"}");
            }
            if ("GET".equals(method) && path.startsWith("/v1/chunks/")) {
                return json("{\"data\":\"" + b64("chunk-bytes") + "\"}");
            }
            if ("POST".equals(method) && "/v1/chunks/prepare".equals(path)) {
                return json("{\"address\":\"chk2\",\"already_stored\":false,\"upload_id\":\"cup1\","
                        + "\"payment_type\":\"wave_batch\","
                        + "\"payments\":[{\"quote_hash\":\"qh2\",\"rewards_address\":\"ra2\",\"amount\":\"75\"}],"
                        + "\"total_amount\":\"75\",\"payment_vault_address\":\"0xv\","
                        + "\"payment_token_address\":\"0xt\",\"rpc_url\":\"http://localhost:8545\"}");
            }
            if ("POST".equals(method) && "/v1/chunks/finalize".equals(path)) {
                return json("{\"address\":\"chkfin\"}");
            }

            // --- Data ---
            if ("POST".equals(method) && "/v1/data".equals(path)) {
                return json("{\"data_map\":\"dmap\",\"chunks_stored\":2,\"payment_mode_used\":\"single\"}");
            }
            if ("POST".equals(method) && "/v1/data/get".equals(path)) {
                return json("{\"data\":\"" + b64("private-bytes") + "\"}");
            }
            if ("POST".equals(method) && "/v1/data/public".equals(path)) {
                return json("{\"address\":\"pubaddr\",\"chunks_stored\":2,\"payment_mode_used\":\"single\"}");
            }
            if ("GET".equals(method) && path.startsWith("/v1/data/public/")) {
                return json("{\"data\":\"" + b64("public-bytes") + "\"}");
            }
            if ("POST".equals(method) && "/v1/data/cost".equals(path)) {
                return json("{\"cost\":\"500\",\"file_size\":100,\"chunk_count\":1,"
                        + "\"estimated_gas_cost_wei\":\"21000\",\"payment_mode\":\"single\"}");
            }

            // --- Files ---
            if ("POST".equals(method) && "/v1/files".equals(path)) {
                return json("{\"data_map\":\"fdmap\",\"storage_cost_atto\":\"1000\","
                        + "\"gas_cost_wei\":\"21000\",\"chunks_stored\":4,\"payment_mode_used\":\"single\"}");
            }
            if ("POST".equals(method) && "/v1/files/get".equals(path)) {
                return json("{}");
            }
            if ("POST".equals(method) && "/v1/files/public".equals(path)) {
                return json("{\"address\":\"fpub\",\"storage_cost_atto\":\"2000\","
                        + "\"gas_cost_wei\":\"21000\",\"chunks_stored\":4,\"payment_mode_used\":\"single\"}");
            }
            if ("POST".equals(method) && "/v1/files/public/get".equals(path)) {
                return json("{}");
            }
            if ("POST".equals(method) && "/v1/files/cost".equals(path)) {
                return json("{\"cost\":\"3000\",\"file_size\":200,\"chunk_count\":2,"
                        + "\"estimated_gas_cost_wei\":\"42000\",\"payment_mode\":\"single\"}");
            }

            return new MockResponse().setResponseCode(404)
                    .setHeader("Content-Type", "application/json")
                    .setBody("{\"error\":\"not found\"}");
        }

        private static String b64(String s) {
            return Base64.getEncoder().encodeToString(s.getBytes());
        }

        private MockResponse json(String body) {
            return new MockResponse().setHeader("Content-Type", "application/json").setBody(body);
        }
    }

    // -------------------------------------------------------------------------
    // Sanity: every async method returns a CompletableFuture and resolves
    // -------------------------------------------------------------------------

    @Test
    void healthAsync() {
        HealthStatus h = client.healthAsync().join();
        assertTrue(h.ok());
        assertEquals("local", h.network());
    }

    // --- Wallet (newly added in V2-287) ---

    @Test
    void walletAddressAsync() {
        assertEquals("0xaddr", client.walletAddressAsync().join().address());
    }

    @Test
    void walletBalanceAsync() {
        WalletBalance b = client.walletBalanceAsync().join();
        assertEquals("123", b.balance());
        assertEquals("456", b.gasBalance());
    }

    @Test
    void walletApproveAsync() {
        assertTrue(client.walletApproveAsync().join());
    }

    // --- External-signer prepare/finalize (newly added in V2-287) ---

    @Test
    void prepareUploadAsync() {
        PrepareUploadResult r = client.prepareUploadAsync("/tmp/x").join();
        assertEquals("up1", r.uploadId());
        assertEquals("wave_batch", r.paymentType());
        assertEquals(1, r.payments().size());
    }

    @Test
    void prepareUploadAsyncWithVisibility() {
        PrepareUploadResult r = client.prepareUploadAsync("/tmp/x", "public").join();
        assertEquals("up1", r.uploadId());
    }

    @Test
    void prepareUploadPublicAsync() {
        PrepareUploadResult r = client.prepareUploadPublicAsync("/tmp/x").join();
        assertEquals("up1", r.uploadId());
    }

    @Test
    void prepareDataUploadAsync() {
        PrepareUploadResult r = client.prepareDataUploadAsync("hello".getBytes()).join();
        assertEquals("dup1", r.uploadId());
        assertEquals(0, r.payments().size());
    }

    @Test
    void finalizeUploadAsync() {
        FinalizeUploadResult r = client.finalizeUploadAsync("up1", Map.of("qh1", "tx1")).join();
        assertEquals("addrfin", r.address());
        assertEquals(3L, r.chunksStored());
        assertEquals("dm", r.dataMap());
        assertEquals("dma", r.dataMapAddress());
    }

    @Test
    void finalizeMerkleUploadAsync() {
        FinalizeUploadResult r = client.finalizeMerkleUploadAsync("up1", "0xwinner").join();
        assertEquals("addrfin", r.address());
        assertEquals(3L, r.chunksStored());
    }

    // --- Existing async methods (smoke coverage — previously untested) ---

    @Test
    void chunkPutAsync() {
        PutResult r = client.chunkPutAsync("hello".getBytes()).join();
        assertEquals("50", r.cost());
        assertEquals("chk1", r.address());
    }

    @Test
    void chunkGetAsync() {
        byte[] b = client.chunkGetAsync("chk1").join();
        assertEquals("chunk-bytes", new String(b));
    }

    @Test
    void prepareChunkUploadAsync() {
        PrepareChunkResult r = client.prepareChunkUploadAsync("hello".getBytes()).join();
        assertEquals("chk2", r.address());
        assertFalse(r.alreadyStored());
        assertEquals("cup1", r.uploadId());
    }

    @Test
    void finalizeChunkUploadAsync() {
        String addr = client.finalizeChunkUploadAsync("cup1", Map.of("qh2", "tx2")).join();
        assertEquals("chkfin", addr);
    }

    @Test
    void dataPutAsync() {
        DataPutResult r = client.dataPutAsync("hello".getBytes()).join();
        assertEquals("dmap", r.dataMap());
        assertEquals(2L, r.chunksStored());
    }

    @Test
    void dataGetAsync() {
        byte[] b = client.dataGetAsync("dmap").join();
        assertEquals("private-bytes", new String(b));
    }

    @Test
    void dataPutPublicAsync() {
        DataPutPublicResult r = client.dataPutPublicAsync("hello".getBytes()).join();
        assertEquals("pubaddr", r.address());
        assertEquals(2L, r.chunksStored());
    }

    @Test
    void dataGetPublicAsync() {
        byte[] b = client.dataGetPublicAsync("pubaddr").join();
        assertEquals("public-bytes", new String(b));
    }

    @Test
    void dataCostAsync() {
        UploadCostEstimate e = client.dataCostAsync("hello".getBytes()).join();
        assertEquals("500", e.cost());
        assertEquals(100L, e.fileSize());
    }

    @Test
    void filePutAsync() {
        FilePutResult r = client.filePutAsync("/tmp/x").join();
        assertEquals("fdmap", r.dataMap());
        assertEquals("1000", r.storageCostAtto());
        assertEquals(4L, r.chunksStored());
    }

    @Test
    void fileGetAsync() {
        assertNull(client.fileGetAsync("dm", "/tmp/dst").join());
    }

    @Test
    void filePutPublicAsync() {
        FilePutPublicResult r = client.filePutPublicAsync("/tmp/x").join();
        assertEquals("fpub", r.address());
        assertEquals("2000", r.storageCostAtto());
    }

    @Test
    void fileGetPublicAsync() {
        assertNull(client.fileGetPublicAsync("addr", "/tmp/dst").join());
    }

    @Test
    void fileCostAsync() {
        UploadCostEstimate e = client.fileCostAsync("/tmp/x", true).join();
        assertEquals("3000", e.cost());
        assertEquals(200L, e.fileSize());
        assertEquals(2, e.chunkCount());
    }

    // -------------------------------------------------------------------------
    // Errors propagate through the future (404 → AntdException via .get())
    // -------------------------------------------------------------------------

    @Test
    void notFoundPropagatesAsAntdException() {
        CompletableFuture<HealthStatus> f = new AsyncAntdClient(
                server.url("/").toString().replaceAll("/$", "") + "/nope", Duration.ofSeconds(5))
                .healthAsync();
        ExecutionException ee = assertThrows(ExecutionException.class, f::get);
        assertNotNull(ee.getCause());
    }
}
