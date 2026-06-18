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
import java.io.InputStream;
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
                return json("{\"status\":\"ok\",\"network\":\"local\"," +
                        "\"version\":\"0.4.0\"," +
                        "\"evm_network\":\"local\"," +
                        "\"uptime_seconds\":42," +
                        "\"build_commit\":\"abcdef123456\"," +
                        "\"payment_token_address\":\"0xtoken\"," +
                        "\"payment_vault_address\":\"0xvault\"}");
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
            if ("POST".equals(method) && "/v1/data".equals(path)) {
                return json("{\"data_map\":\"dm123\",\"chunks_stored\":2,\"payment_mode_used\":\"auto\"}");
            }
            // Data get private
            if ("POST".equals(method) && "/v1/data/get".equals(path)) {
                return json("{\"data\":\"" + b64("secret") + "\"}");
            }
            boolean wantsNdjson = "application/x-ndjson".equals(request.getHeader("Accept"));

            // Data stream private — raw decrypted bytes, or NDJSON frames when
            // Accept: application/x-ndjson is sent.
            if ("POST".equals(method) && "/v1/data/stream".equals(path)) {
                if (wantsNdjson) {
                    return ndjson(
                            "{\"type\":\"meta\",\"total_size\":6}",
                            "{\"type\":\"progress\",\"phase\":\"fetching\",\"fetched\":1,\"total\":2}",
                            "{\"type\":\"data\",\"chunk\":\"" + b64("sec") + "\"}",
                            "{\"type\":\"data\",\"chunk\":\"" + b64("ret") + "\"}");
                }
                return new MockResponse()
                        .setHeader("Content-Type", "application/octet-stream")
                        .setBody("secret");
            }
            // Data stream public — raw decrypted bytes, or NDJSON frames.
            if ("GET".equals(method) && "/v1/data/public/abc123/stream".equals(path)) {
                if (wantsNdjson) {
                    return ndjson(
                            "{\"type\":\"meta\",\"total_size\":5}",
                            "{\"type\":\"progress\",\"phase\":\"fetching\",\"fetched\":1,\"total\":2}",
                            "{\"type\":\"data\",\"chunk\":\"" + b64("hel") + "\"}",
                            "{\"type\":\"data\",\"chunk\":\"" + b64("lo") + "\"}");
                }
                return new MockResponse()
                        .setHeader("Content-Type", "application/octet-stream")
                        .setBody("hello");
            }
            // NDJSON stream that ends with a terminal error frame.
            if ("GET".equals(method) && "/v1/data/public/errstream/stream".equals(path)) {
                return ndjson(
                        "{\"type\":\"meta\",\"total_size\":0}",
                        "{\"type\":\"progress\",\"phase\":\"fetching\",\"fetched\":1,\"total\":2}",
                        "{\"type\":\"error\",\"message\":\"chunk fetch failed\"}");
            }

            // Data cost
            if ("POST".equals(method) && "/v1/data/cost".equals(path)) {
                return json("{\"cost\":\"50\",\"file_size\":4,\"chunk_count\":3,\"estimated_gas_cost_wei\":\"150000000000000\",\"payment_mode\":\"single\"}");
            }

            // Chunks
            if ("POST".equals(method) && "/v1/chunks".equals(path)) {
                return json("{\"cost\":\"10\",\"address\":\"chunk1\"}");
            }
            if ("GET".equals(method) && "/v1/chunks/chunk1".equals(path)) {
                return json("{\"data\":\"" + b64("chunkdata") + "\"}");
            }

            // Files
            if ("POST".equals(method) && "/v1/files/public".equals(path)) {
                return json("{\"address\":\"file1\",\"storage_cost_atto\":\"1000\",\"gas_cost_wei\":\"42\",\"chunks_stored\":3,\"payment_mode_used\":\"auto\"}");
            }
            if ("POST".equals(method) && "/v1/files/public/get".equals(path)) {
                return new MockResponse().setResponseCode(200);
            }
            if ("POST".equals(method) && "/v1/files/cost".equals(path)) {
                return json("{\"cost\":\"1000\",\"file_size\":4096,\"chunk_count\":3,\"estimated_gas_cost_wei\":\"150000000000000\",\"payment_mode\":\"auto\"}");
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

        private static MockResponse ndjson(String... lines) {
            return new MockResponse()
                    .setHeader("Content-Type", "application/x-ndjson")
                    .setBody(String.join("\n", lines) + "\n");
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
        assertEquals("0.4.0", h.version());
        assertEquals("local", h.evmNetwork());
        assertEquals(42L, h.uptimeSeconds());
        assertEquals("abcdef123456", h.buildCommit());
        assertEquals("0xtoken", h.paymentTokenAddress());
        assertEquals("0xvault", h.paymentVaultAddress());
    }

    @Test
    void testHealthBackwardCompatConstructor() {
        // Pre-0.4.0 callers used new HealthStatus(ok, network); the diagnostic
        // fields default to empty so the constructor stays usable.
        HealthStatus h = new HealthStatus(true, "default");
        assertTrue(h.ok());
        assertEquals("default", h.network());
        assertEquals("", h.version());
        assertEquals(0L, h.uptimeSeconds());
        assertEquals("", h.paymentTokenAddress());
    }

    @Test
    void testDataPublic() {
        DataPutPublicResult put = client.dataPutPublic("hello".getBytes());
        assertEquals("abc123", put.address());

        byte[] data = client.dataGetPublic("abc123");
        assertEquals("hello", new String(data));
    }

    @Test
    void testDataPrivate() {
        DataPutResult put = client.dataPut("secret".getBytes());
        assertEquals("dm123", put.dataMap());

        byte[] data = client.dataGet("dm123");
        assertEquals("secret", new String(data));
    }

    @Test
    void testDataStreamPrivate() throws IOException {
        try (InputStream in = client.dataStream("dm123")) {
            assertEquals("secret", new String(in.readAllBytes()));
        }
    }

    @Test
    void testDataStreamPublic() throws IOException {
        try (InputStream in = client.dataStreamPublic("abc123")) {
            assertEquals("hello", new String(in.readAllBytes()));
        }
    }

    @Test
    void testDataStreamErrorMapping() throws IOException {
        // A non-2xx status with a JSON {"error"} body must map to the typed
        // exception before any stream is returned.
        try (MockWebServer errServer = new MockWebServer()) {
            errServer.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    return new MockResponse()
                            .setResponseCode(404)
                            .setHeader("Content-Type", "application/json")
                            .setBody("{\"error\":\"data map not found\"}");
                }
            });
            errServer.start();

            try (AntdClient errClient = new AntdClient(errServer.url("/").toString())) {
                AntdException ex = assertThrows(AntdException.class,
                        () -> errClient.dataStream("missing"));
                assertInstanceOf(NotFoundException.class, ex);
                assertEquals(404, ex.getStatusCode());
                assertTrue(ex.getMessage().contains("data map not found"));
            }
        }
    }

    @Test
    void testDataStreamWithProgressPrivate() {
        java.util.Iterator<DownloadFrame> frames = client.dataStreamWithProgress("dm123");
        StringBuilder data = new StringBuilder();
        int progressCount = 0;
        Long metaTotal = null;
        boolean dataSeen = false;
        while (frames.hasNext()) {
            DownloadFrame f = frames.next();
            if (f.isMeta()) {
                // Meta (byte total) must surface before any data.
                assertFalse(dataSeen, "meta frame must precede data frames");
                metaTotal = f.totalSize();
            } else if (f.isProgress()) {
                progressCount++;
                assertEquals("fetching", f.progress().phase());
                assertEquals(1L, f.progress().fetched());
                assertEquals(2L, f.progress().total());
            } else {
                dataSeen = true;
                data.append(new String(f.data()));
            }
        }
        // "meta" frame surfaces the byte total; the two data frames reassemble;
        // one progress frame.
        assertEquals(Long.valueOf(6L), metaTotal);
        assertEquals("secret", data.toString());
        assertEquals(1, progressCount);
    }

    @Test
    void testDataStreamWithProgressPublic() {
        java.util.Iterator<DownloadFrame> frames = client.dataStreamPublicWithProgress("abc123");
        StringBuilder data = new StringBuilder();
        int progressCount = 0;
        Long metaTotal = null;
        while (frames.hasNext()) {
            DownloadFrame f = frames.next();
            if (f.isMeta()) {
                metaTotal = f.totalSize();
            } else if (f.isProgress()) {
                progressCount++;
            } else {
                data.append(new String(f.data()));
            }
        }
        assertEquals(Long.valueOf(5L), metaTotal);
        assertEquals("hello", data.toString());
        assertEquals(1, progressCount);
    }

    @Test
    void testDataStreamWithProgressErrorFrameThrows() {
        java.util.Iterator<DownloadFrame> frames = client.dataStreamPublicWithProgress("errstream");
        // Drains the leading progress frame, then the error frame throws.
        AntdException ex = assertThrows(AntdException.class, () -> {
            while (frames.hasNext()) {
                frames.next();
            }
        });
        assertTrue(ex.getMessage().contains("chunk fetch failed"));
    }

    @Test
    void testDataCost() {
        UploadCostEstimate est = client.dataCost("test".getBytes());
        assertEquals("50", est.cost());
        assertEquals(4L, est.fileSize());
        assertEquals(3, est.chunkCount());
        assertEquals("150000000000000", est.estimatedGasCostWei());
        assertEquals("single", est.paymentMode());
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
        FilePutPublicResult put = client.filePutPublic("/tmp/test.txt");
        assertEquals("file1", put.address());
        assertEquals("1000", put.storageCostAtto());
        assertEquals("42", put.gasCostWei());
        assertEquals(3L, put.chunksStored());
        assertEquals("auto", put.paymentModeUsed());
    }

    @Test
    void testFileDownloadPublic() {
        assertDoesNotThrow(() -> client.fileGetPublic("file1", "/tmp/out.txt"));
    }

    @Test
    void testFileCost() {
        UploadCostEstimate est = client.fileCost("/tmp/test.txt", true);
        assertEquals("1000", est.cost());
        assertEquals(4096L, est.fileSize());
        assertEquals(3, est.chunkCount());
        assertEquals("150000000000000", est.estimatedGasCostWei());
        assertEquals("auto", est.paymentMode());
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
                        + "\"total_chunks\":128,"
                        + "\"already_stored_count\":4,"
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

                // already-stored preflight (added in antd 0.10.0)
                assertEquals(128L, res.totalChunks());
                assertEquals(4L, res.alreadyStoredCount());
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

    // -------------------------------------------------------------------------
    // V2-249 PR4: visibility / data_map_address
    // -------------------------------------------------------------------------

    @Test
    void testPrepareUploadOmitsVisibilityWhenNull() throws IOException {
        // Default prepareUpload(path) must NOT send a `visibility` key, so
        // pre-0.6.1 daemons keep working.
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    return new MockResponse()
                            .setHeader("Content-Type", "application/json")
                            .setBody(
                                "{\"upload_id\":\"up-priv-1\","
                                + "\"payment_type\":\"wave_batch\","
                                + "\"payments\":[{\"quote_hash\":\"qh1\",\"rewards_address\":\"ra1\",\"amount\":\"100\"}],"
                                + "\"total_amount\":\"100\","
                                + "\"payment_vault_address\":\"dp1\","
                                + "\"payment_token_address\":\"pt1\","
                                + "\"rpc_url\":\"http://localhost:8545\"}"
                            );
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                PrepareUploadResult res = c.prepareUpload("/tmp/private.bin");
                assertEquals("up-priv-1", res.uploadId());

                RecordedRequest req = srv.takeRequest();
                String body = req.getBody().readUtf8();
                assertFalse(body.contains("visibility"),
                        "private prepareUpload must NOT include `visibility` key: " + body);
                assertTrue(body.contains("\"path\""), "should still include `path`: " + body);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("interrupted: " + e);
            }
        }
    }

    @Test
    void testPrepareUploadPublicSendsVisibility() throws IOException {
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("POST".equals(request.getMethod()) && "/v1/upload/prepare".equals(request.getPath())) {
                        return new MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody(
                                    "{\"upload_id\":\"up-pub-1\","
                                    + "\"payment_type\":\"wave_batch\","
                                    + "\"payments\":[{\"quote_hash\":\"qh1\",\"rewards_address\":\"ra1\",\"amount\":\"100\"}],"
                                    + "\"total_amount\":\"100\","
                                    + "\"payment_vault_address\":\"dp1\","
                                    + "\"payment_token_address\":\"pt1\","
                                    + "\"rpc_url\":\"http://localhost:8545\"}"
                                );
                    }
                    return new MockResponse().setResponseCode(404);
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                PrepareUploadResult res = c.prepareUploadPublic("/tmp/public.bin");
                assertEquals("up-pub-1", res.uploadId());

                RecordedRequest req = srv.takeRequest();
                String body = req.getBody().readUtf8();
                assertTrue(body.contains("\"visibility\":\"public\""),
                        "prepareUploadPublic must send visibility=public: " + body);
                assertTrue(body.contains("\"path\":\"/tmp/public.bin\""),
                        "should include path: " + body);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("interrupted: " + e);
            }
        }
    }

    @Test
    void testFinalizeUploadSurfacesDataMapAddress() throws IOException {
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("POST".equals(request.getMethod()) && "/v1/upload/finalize".equals(request.getPath())) {
                        return new MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody("{\"data_map\":\"deadbeef\","
                                        + "\"data_map_address\":\"cafebabe\","
                                        + "\"chunks_stored\":4}");
                    }
                    return new MockResponse().setResponseCode(404);
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                FinalizeUploadResult res = c.finalizeUpload("up1", Map.of("qh1", "tx1"));
                assertEquals("deadbeef", res.dataMap());
                assertEquals("cafebabe", res.dataMapAddress());
                assertEquals("", res.address(),
                        "legacy address must be empty when daemon returned only data_map_address");
                assertEquals(4L, res.chunksStored());
            }
        }
    }

    @Test
    void testFinalizeUploadOmitsDataMapAddressForPrivate() throws IOException {
        // Pre-0.6.1 daemons don't return data_map / data_map_address; both
        // default to empty strings via the parser.
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("POST".equals(request.getMethod()) && "/v1/upload/finalize".equals(request.getPath())) {
                        return new MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody("{\"address\":\"addr-priv\",\"chunks_stored\":2}");
                    }
                    return new MockResponse().setResponseCode(404);
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                FinalizeUploadResult res = c.finalizeUpload("up1", Map.of("qh1", "tx1"));
                assertEquals("addr-priv", res.address());
                assertEquals(2L, res.chunksStored());
                assertEquals("", res.dataMap());
                assertEquals("", res.dataMapAddress());
            }
        }
    }

    @Test
    void testFinalizeUploadResultBackwardCompatConstructor() {
        // The two-arg constructor must still work for callers that build
        // synthetic results in tests / code.
        FinalizeUploadResult r = new FinalizeUploadResult("addr", 7L);
        assertEquals("addr", r.address());
        assertEquals(7L, r.chunksStored());
        assertEquals("", r.dataMap());
        assertEquals("", r.dataMapAddress());
    }

    // -------------------------------------------------------------------------
    // V2-274: single-chunk external-signer (antd >= 0.7.0)
    // -------------------------------------------------------------------------

    @Test
    void testPrepareChunkUploadWaveBatch() throws IOException {
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("POST".equals(request.getMethod()) && "/v1/chunks/prepare".equals(request.getPath())) {
                        return new MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody(
                                    "{\"address\":\"aa00000000000000000000000000000000000000000000000000000000000000\","
                                    + "\"already_stored\":false,"
                                    + "\"upload_id\":\"chunk-1\","
                                    + "\"payment_type\":\"wave_batch\","
                                    + "\"payments\":["
                                    + "{\"quote_hash\":\"qh1\",\"rewards_address\":\"ra1\",\"amount\":\"100\"},"
                                    + "{\"quote_hash\":\"qh2\",\"rewards_address\":\"ra2\",\"amount\":\"100\"}],"
                                    + "\"total_amount\":\"200\","
                                    + "\"payment_vault_address\":\"0xvault\","
                                    + "\"payment_token_address\":\"0xtoken\","
                                    + "\"rpc_url\":\"http://localhost:8545\"}"
                                );
                    }
                    return new MockResponse().setResponseCode(404);
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                PrepareChunkResult res = c.prepareChunkUpload("hello".getBytes());

                // Request: bytes must arrive base64-encoded under `data`.
                RecordedRequest req = srv.takeRequest();
                String body = req.getBody().readUtf8();
                assertTrue(body.contains("\"data\":\"aGVsbG8=\""),
                        "expected base64-encoded `hello` in body: " + body);

                assertFalse(res.alreadyStored());
                assertEquals("chunk-1", res.uploadId());
                assertEquals("wave_batch", res.paymentType());
                assertEquals(2, res.payments().size());
                assertEquals("qh1", res.payments().get(0).quoteHash());
                assertEquals("100", res.payments().get(1).amount());
                assertEquals("200", res.totalAmount());
                assertEquals("0xvault", res.paymentVaultAddress());
                assertEquals("0xtoken", res.paymentTokenAddress());
                assertEquals("http://localhost:8545", res.rpcUrl());
                assertEquals(64, res.address().length(),
                        "address should be 64 hex chars");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("interrupted: " + e);
            }
        }
    }

    @Test
    void testPrepareChunkUploadAlreadyStored() throws IOException {
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("POST".equals(request.getMethod()) && "/v1/chunks/prepare".equals(request.getPath())) {
                        return new MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody(
                                    "{\"address\":\"bb11111111111111111111111111111111111111111111111111111111111111\","
                                    + "\"already_stored\":true}"
                                );
                    }
                    return new MockResponse().setResponseCode(404);
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                PrepareChunkResult res = c.prepareChunkUpload("already-on-network".getBytes());
                assertTrue(res.alreadyStored());
                assertFalse(res.address().isEmpty(),
                        "address must still be populated for already-stored chunks");
                assertEquals("", res.uploadId());
                assertTrue(res.payments().isEmpty());
                assertEquals("", res.totalAmount());
                assertEquals("", res.paymentType());
            }
        }
    }

    @Test
    void testFinalizeChunkUploadReturnsAddress() throws IOException {
        try (MockWebServer srv = new MockWebServer()) {
            srv.setDispatcher(new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("POST".equals(request.getMethod()) && "/v1/chunks/finalize".equals(request.getPath())) {
                        return new MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody("{\"address\":\"cc22222222222222222222222222222222222222222222222222222222222222\"}");
                    }
                    return new MockResponse().setResponseCode(404);
                }
            });
            srv.start();

            try (AntdClient c = new AntdClient(srv.url("/").toString(), Duration.ofSeconds(10))) {
                String addr = c.finalizeChunkUpload("chunk-1",
                        Map.of("qh1", "tx1", "qh2", "tx2"));

                RecordedRequest req = srv.takeRequest();
                String body = req.getBody().readUtf8();
                assertTrue(body.contains("\"upload_id\":\"chunk-1\""),
                        "upload_id must be sent: " + body);
                assertTrue(body.contains("\"tx_hashes\""), "tx_hashes must be sent: " + body);
                assertTrue(body.contains("\"qh1\":\"tx1\""), "tx_hashes.qh1 missing: " + body);
                assertTrue(body.contains("\"qh2\":\"tx2\""), "tx_hashes.qh2 missing: " + body);

                assertEquals(64, addr.length(),
                        "finalize should return 64-char hex address, got: " + addr);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("interrupted: " + e);
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
