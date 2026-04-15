package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.errors.NotFoundException;
import com.autonomi.antd.models.*;
import okhttp3.mockwebserver.Dispatcher;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.*;

import java.io.IOException;
import java.time.Duration;
import java.util.Base64;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class AntdClientTest {

    private MockWebServer server;
    private AntdClient client;

    @BeforeEach
    void setUp() throws IOException {
        server = new MockWebServer();
        server.setDispatcher(new MockDaemon());
        server.start();
        client = new AntdClient(server.url("/").toString(), Duration.ofSeconds(10));
    }

    @AfterEach
    void tearDown() throws IOException {
        client.close();
        server.shutdown();
    }

    // -------------------------------------------------------------------------
    // Mock daemon
    // -------------------------------------------------------------------------

    static class MockDaemon extends Dispatcher {
        @Override
        public MockResponse dispatch(RecordedRequest request) {
            String path = request.getPath();
            String method = request.getMethod();

            // Health
            if ("GET".equals(method) && "/health".equals(path)) {
                return json("{\"status\":\"ok\",\"network\":\"local\"}");
            }

            // Data put public
            if ("POST".equals(method) && "/v1/data/public".equals(path)) {
                return json("{\"cost\":\"100\",\"address\":\"abc123\"}");
            }
            // Data get public
            if ("GET".equals(method) && "/v1/data/public/abc123".equals(path)) {
                return json("{\"data\":\"" + b64("hello") + "\"}");
            }

            // Data put private
            if ("POST".equals(method) && "/v1/data/private".equals(path)) {
                return json("{\"cost\":\"200\",\"data_map\":\"dm123\"}");
            }
            // Data get private
            if ("GET".equals(method) && path != null && path.startsWith("/v1/data/private")) {
                return json("{\"data\":\"" + b64("secret") + "\"}");
            }

            // Data cost
            if ("POST".equals(method) && "/v1/data/cost".equals(path)) {
                return json("{\"cost\":\"50\"}");
            }

            // Chunks
            if ("POST".equals(method) && "/v1/chunks".equals(path)) {
                return json("{\"cost\":\"10\",\"address\":\"chunk1\"}");
            }
            if ("GET".equals(method) && "/v1/chunks/chunk1".equals(path)) {
                return json("{\"data\":\"" + b64("chunkdata") + "\"}");
            }

            // Files
            if ("POST".equals(method) && "/v1/files/upload/public".equals(path)) {
                return json("{\"address\":\"file1\",\"storage_cost_atto\":\"1000\",\"gas_cost_wei\":\"42\",\"chunks_stored\":3,\"payment_mode_used\":\"auto\"}");
            }
            if ("POST".equals(method) && "/v1/files/download/public".equals(path)) {
                return new MockResponse().setResponseCode(200);
            }
            if ("POST".equals(method) && "/v1/dirs/upload/public".equals(path)) {
                return json("{\"address\":\"dir1\",\"storage_cost_atto\":\"2000\",\"gas_cost_wei\":\"100\",\"chunks_stored\":5,\"payment_mode_used\":\"merkle\"}");
            }
            if ("POST".equals(method) && "/v1/dirs/download/public".equals(path)) {
                return new MockResponse().setResponseCode(200);
            }
            if ("POST".equals(method) && "/v1/cost/file".equals(path)) {
                return json("{\"cost\":\"1000\"}");
            }

            // 404 fallback
            return new MockResponse()
                    .setResponseCode(404)
                    .setHeader("Content-Type", "application/json")
                    .setBody("{\"error\":\"not found\"}");
        }

        private static MockResponse json(String body) {
            return new MockResponse()
                    .setHeader("Content-Type", "application/json")
                    .setBody(body);
        }

        private static String b64(String s) {
            return Base64.getEncoder().encodeToString(s.getBytes());
        }
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    @Test
    void testHealth() {
        HealthStatus h = client.health();
        assertTrue(h.ok());
        assertEquals("local", h.network());
    }

    @Test
    void testDataPublic() {
        PutResult put = client.dataPutPublic("hello".getBytes());
        assertEquals("abc123", put.address());
        assertEquals("100", put.cost());

        byte[] data = client.dataGetPublic("abc123");
        assertEquals("hello", new String(data));
    }

    @Test
    void testDataPrivate() {
        PutResult put = client.dataPutPrivate("secret".getBytes());
        assertEquals("dm123", put.address());
        assertEquals("200", put.cost());

        byte[] data = client.dataGetPrivate("dm123");
        assertEquals("secret", new String(data));
    }

    @Test
    void testDataCost() {
        String cost = client.dataCost("test".getBytes());
        assertEquals("50", cost);
    }

    @Test
    void testChunks() {
        PutResult put = client.chunkPut("chunkdata".getBytes());
        assertEquals("chunk1", put.address());

        byte[] data = client.chunkGet("chunk1");
        assertEquals("chunkdata", new String(data));
    }

    @Test
    void testFileUploadPublic() {
        FileUploadResult put = client.fileUploadPublic("/tmp/test.txt");
        assertEquals("file1", put.address());
        assertEquals("1000", put.storageCostAtto());
        assertEquals("42", put.gasCostWei());
        assertEquals(3L, put.chunksStored());
        assertEquals("auto", put.paymentModeUsed());
    }

    @Test
    void testFileDownloadPublic() {
        assertDoesNotThrow(() -> client.fileDownloadPublic("file1", "/tmp/out.txt"));
    }

    @Test
    void testDirUploadPublic() {
        FileUploadResult put = client.dirUploadPublic("/tmp/mydir");
        assertEquals("dir1", put.address());
        assertEquals("2000", put.storageCostAtto());
        assertEquals("100", put.gasCostWei());
        assertEquals(5L, put.chunksStored());
        assertEquals("merkle", put.paymentModeUsed());
    }

    @Test
    void testDirDownloadPublic() {
        assertDoesNotThrow(() -> client.dirDownloadPublic("dir1", "/tmp/outdir"));
    }

    @Test
    void testFileCost() {
        String cost = client.fileCost("/tmp/test.txt", true);
        assertEquals("1000", cost);
    }

    @Test
    void testErrorMapping() throws IOException {
        // Stand up a dedicated server that always returns 404
        try (MockWebServer errServer = new MockWebServer()) {
            errServer.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    return new MockResponse()
                            .setResponseCode(404)
                            .setHeader("Content-Type", "application/json")
                            .setBody("{\"error\":\"not found\"}");
                }
            });
            errServer.start();

            try (AntdClient errClient = new AntdClient(errServer.url("/").toString())) {
                AntdException ex = assertThrows(AntdException.class, errClient::health);
                assertInstanceOf(NotFoundException.class, ex);
                assertEquals(404, ex.getStatusCode());
            }
        }
    }

    // -------------------------------------------------------------------------
    // Merkle payment tests
    // -------------------------------------------------------------------------

    /** Returns a mock server that responds with merkle payment type. */
    private MockWebServer startMerkleDaemon() throws IOException {
        MockWebServer srv = new MockWebServer();
        srv.setDispatcher(new Dispatcher() {
            @Override
            public MockResponse dispatch(RecordedRequest request) {
                String path = request.getPath();
                String method = request.getMethod();

                if ("POST".equals(method) && "/v1/upload/prepare".equals(path)) {
                    return json(
                        "{\"upload_id\":\"mup1\","
                        + "\"payment_type\":\"merkle\","
                        + "\"depth\":5,"
                        + "\"pool_commitments\":[{\"pool_hash\":\"0xaabbccdd\","
                        + "\"candidates\":[{\"rewards_address\":\"0x1111\",\"amount\":\"500\"},"
                        + "{\"rewards_address\":\"0x2222\",\"amount\":\"600\"}]}],"
                        + "\"merkle_payment_timestamp\":1712150400,"
                        + "\"payment_vault_address\":\"0xmerkle\","
                        + "\"total_amount\":\"0\","
                        + "\"payment_token_address\":\"0xtoken\","
                        + "\"rpc_url\":\"http://localhost:8545\"}"
                    );
                }

                if ("POST".equals(method) && "/v1/data/prepare".equals(path)) {
                    return json(
                        "{\"upload_id\":\"mup2\","
                        + "\"payment_type\":\"merkle\","
                        + "\"depth\":3,"
                        + "\"pool_commitments\":[{\"pool_hash\":\"0xeeff\",\"candidates\":[]}],"
                        + "\"merkle_payment_timestamp\":1712150500,"
                        + "\"payment_vault_address\":\"0xmerkle2\","
                        + "\"total_amount\":\"0\","
                        + "\"payment_token_address\":\"0xtoken2\","
                        + "\"rpc_url\":\"http://localhost:8546\"}"
                    );
                }

                if ("POST".equals(method) && "/v1/upload/finalize".equals(path)) {
                    return json("{\"address\":\"addr_merkle\",\"chunks_stored\":100}");
                }

                return new MockResponse()
                        .setResponseCode(404)
                        .setHeader("Content-Type", "application/json")
                        .setBody("{\"error\":\"not found\"}");
            }

            private MockResponse json(String body) {
                return new MockResponse()
                        .setHeader("Content-Type", "application/json")
                        .setBody(body);
            }
        });
        srv.start();
        return srv;
    }

    @Test
    void testPrepareUploadMerkle() throws IOException {
        try (MockWebServer merkleSrv = startMerkleDaemon()) {
            try (AntdClient mc = new AntdClient(merkleSrv.url("/").toString(), Duration.ofSeconds(10))) {
                PrepareUploadResult res = mc.prepareUpload("/tmp/bigfile.bin");

                assertEquals("mup1", res.uploadId());
                assertEquals("merkle", res.paymentType());
                assertEquals(Integer.valueOf(5), res.depth());
                assertEquals(Long.valueOf(1712150400L), res.merklePaymentTimestamp());
                assertEquals("0xmerkle", res.paymentVaultAddress());
                assertEquals("0xtoken", res.paymentTokenAddress());
                assertEquals("http://localhost:8545", res.rpcUrl());
                assertEquals("0", res.totalAmount());

                // Pool commitments
                assertNotNull(res.poolCommitments());
                assertEquals(1, res.poolCommitments().size());
                PoolCommitmentEntry pc = res.poolCommitments().get(0);
                assertEquals("0xaabbccdd", pc.poolHash());
                assertEquals(2, pc.candidates().size());
                assertEquals("0x1111", pc.candidates().get(0).rewardsAddress());
                assertEquals("500", pc.candidates().get(0).amount());
                assertEquals("0x2222", pc.candidates().get(1).rewardsAddress());
                assertEquals("600", pc.candidates().get(1).amount());

                // Wave-batch fields should be empty
                assertTrue(res.payments().isEmpty());
            }
        }
    }

    @Test
    void testFinalizeMerkleUpload() throws IOException {
        try (MockWebServer merkleSrv = startMerkleDaemon()) {
            try (AntdClient mc = new AntdClient(merkleSrv.url("/").toString(), Duration.ofSeconds(10))) {
                FinalizeUploadResult res = mc.finalizeMerkleUpload("mup1", "0xwinnerhash");

                assertEquals("addr_merkle", res.address());
                assertEquals(100L, res.chunksStored());
            }
        }
    }

    @Test
    void testPrepareUploadBackwardCompat() throws IOException {
        // Simulate an older daemon that doesn't send payment_type
        try (MockWebServer oldSrv = new MockWebServer()) {
            oldSrv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    return new MockResponse()
                            .setHeader("Content-Type", "application/json")
                            .setBody(
                                "{\"upload_id\":\"old1\","
                                + "\"payments\":[{\"quote_hash\":\"qh1\",\"rewards_address\":\"ra1\",\"amount\":\"50\"}],"
                                + "\"total_amount\":\"50\","
                                + "\"payment_vault_address\":\"dp_old\","
                                + "\"payment_token_address\":\"pt_old\","
                                + "\"rpc_url\":\"http://localhost:8545\"}"
                            );
                }
            });
            oldSrv.start();

            try (AntdClient oc = new AntdClient(oldSrv.url("/").toString(), Duration.ofSeconds(10))) {
                PrepareUploadResult res = oc.prepareUpload("/tmp/test.txt");

                // Should default to wave_batch when payment_type is missing
                assertEquals("wave_batch", res.paymentType());
                assertEquals("old1", res.uploadId());
                assertEquals(1, res.payments().size());
                assertEquals("qh1", res.payments().get(0).quoteHash());
                assertEquals("ra1", res.payments().get(0).rewardsAddress());
                assertEquals("50", res.payments().get(0).amount());

                // Merkle fields should be null
                assertNull(res.depth());
                assertNull(res.poolCommitments());
                assertNull(res.merklePaymentTimestamp());
            }
        }
    }
}
