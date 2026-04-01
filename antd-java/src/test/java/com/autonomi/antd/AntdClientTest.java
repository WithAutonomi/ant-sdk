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
                return json("{\"cost\":\"1000\",\"address\":\"file1\"}");
            }
            if ("POST".equals(method) && "/v1/files/download/public".equals(path)) {
                return new MockResponse().setResponseCode(200);
            }
            if ("POST".equals(method) && "/v1/dirs/upload/public".equals(path)) {
                return json("{\"cost\":\"2000\",\"address\":\"dir1\"}");
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
        PutResult put = client.fileUploadPublic("/tmp/test.txt");
        assertEquals("file1", put.address());
        assertEquals("1000", put.cost());
    }

    @Test
    void testFileDownloadPublic() {
        assertDoesNotThrow(() -> client.fileDownloadPublic("file1", "/tmp/out.txt"));
    }

    @Test
    void testDirUploadPublic() {
        PutResult put = client.dirUploadPublic("/tmp/mydir");
        assertEquals("dir1", put.address());
        assertEquals("2000", put.cost());
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
}
