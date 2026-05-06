package com.autonomi.sdk

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import java.util.Base64
import kotlin.test.*

class RestClientTest {

    private lateinit var server: MockWebServer
    private lateinit var client: AntdRestClient

    @BeforeTest
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = MockDaemon()
        server.start()
        client = AntdRestClient(baseUrl = server.url("/").toString())
    }

    @AfterTest
    fun tearDown() {
        client.close()
        server.shutdown()
    }

    // -------------------------------------------------------------------------
    // Mock daemon
    // -------------------------------------------------------------------------

    class MockDaemon : Dispatcher() {
        override fun dispatch(request: RecordedRequest): MockResponse {
            val path = request.path ?: ""
            val method = request.method ?: ""

            // Health
            if (method == "GET" && path == "/health") {
                return json("""{"status":"ok","network":"local","version":"0.4.0","evm_network":"local","uptime_seconds":42,"build_commit":"abcdef123456","payment_token_address":"0xtoken","payment_vault_address":"0xvault"}""")
            }

            // Data put public
            if (method == "POST" && path == "/v1/data/public") {
                return json("""{"cost":"100","address":"abc123"}""")
            }
            // Data get public
            if (method == "GET" && path == "/v1/data/public/abc123") {
                return json("""{"data":"${b64("hello")}"}""")
            }

            // Data put private
            if (method == "POST" && path == "/v1/data/private") {
                return json("""{"cost":"200","data_map":"dm123"}""")
            }
            // Data get private
            if (method == "GET" && path.startsWith("/v1/data/private")) {
                return json("""{"data":"${b64("secret")}"}""")
            }

            // Data cost
            if (method == "POST" && path == "/v1/data/cost") {
                return json("""{"cost":"50","file_size":4,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"single"}""")
            }

            // Chunks
            if (method == "POST" && path == "/v1/chunks") {
                return json("""{"cost":"10","address":"chunk1"}""")
            }
            if (method == "GET" && path == "/v1/chunks/chunk1") {
                return json("""{"data":"${b64("chunkdata")}"}""")
            }

            // Files
            if (method == "POST" && path == "/v1/files/upload/public") {
                return json("""{"address":"file1","storage_cost_atto":"1000","gas_cost_wei":"42","chunks_stored":3,"payment_mode_used":"auto"}""")
            }
            if (method == "POST" && path == "/v1/files/download/public") {
                return MockResponse().setResponseCode(200)
            }
            if (method == "POST" && path == "/v1/dirs/upload/public") {
                return json("""{"address":"dir1","storage_cost_atto":"2000","gas_cost_wei":"100","chunks_stored":5,"payment_mode_used":"merkle"}""")
            }
            if (method == "POST" && path == "/v1/dirs/download/public") {
                return MockResponse().setResponseCode(200)
            }
            if (method == "POST" && path == "/v1/files/cost") {
                return json("""{"cost":"1000","file_size":4096,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"auto"}""")
            }

            // 404 fallback
            return MockResponse()
                .setResponseCode(404)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"not found"}""")
        }

        companion object {
            fun json(body: String): MockResponse =
                MockResponse()
                    .setHeader("Content-Type", "application/json")
                    .setBody(body)

            fun b64(s: String): String =
                Base64.getEncoder().encodeToString(s.toByteArray())
        }
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    @Test
    fun `health returns HealthStatus`() = runTest {
        val status = client.health()
        assertTrue(status.ok)
        assertEquals("local", status.network)
        assertEquals("0.4.0", status.version)
        assertEquals("local", status.evmNetwork)
        assertEquals(42UL, status.uptimeSeconds)
        assertEquals("abcdef123456", status.buildCommit)
        assertEquals("0xtoken", status.paymentTokenAddress)
        assertEquals("0xvault", status.paymentVaultAddress)
    }

    @Test
    fun `HealthStatus defaults stay empty for pre-0_4_0 daemon shape`() {
        // Older daemons reply with just status + network; the data class
        // defaults populate the diagnostic fields so callers don't NPE.
        val s = HealthStatus(ok = true, network = "default")
        assertEquals("", s.version)
        assertEquals("", s.evmNetwork)
        assertEquals(0UL, s.uptimeSeconds)
        assertEquals("", s.buildCommit)
        assertEquals("", s.paymentTokenAddress)
        assertEquals("", s.paymentVaultAddress)
    }

    @Test
    fun `dataPutPublic returns PutResult`() = runTest {
        val result = client.dataPutPublic("hello".toByteArray())
        assertEquals("abc123", result.address)
        assertEquals("100", result.cost)
    }

    @Test
    fun `dataGetPublic returns bytes`() = runTest {
        val data = client.dataGetPublic("abc123")
        assertEquals("hello", String(data))
    }

    @Test
    fun `dataPutPrivate returns PutResult`() = runTest {
        val result = client.dataPutPrivate("secret".toByteArray())
        assertEquals("dm123", result.address)
        assertEquals("200", result.cost)
    }

    @Test
    fun `dataGetPrivate returns bytes`() = runTest {
        val data = client.dataGetPrivate("dm123")
        assertEquals("secret", String(data))
    }

    @Test
    fun `dataCost returns full breakdown`() = runTest {
        val est = client.dataCost("test".toByteArray())
        assertEquals("50", est.cost)
        assertEquals(4uL, est.fileSize)
        assertEquals(3u, est.chunkCount)
        assertEquals("150000000000000", est.estimatedGasCostWei)
        assertEquals("single", est.paymentMode)
    }

    @Test
    fun `chunkPut returns PutResult`() = runTest {
        val result = client.chunkPut("chunkdata".toByteArray())
        assertEquals("chunk1", result.address)
        assertEquals("10", result.cost)
    }

    @Test
    fun `chunkGet returns bytes`() = runTest {
        val data = client.chunkGet("chunk1")
        assertEquals("chunkdata", String(data))
    }

    @Test
    fun `fileUploadPublic returns FileUploadResult`() = runTest {
        val result = client.fileUploadPublic("/tmp/test.txt")
        assertEquals("file1", result.address)
        assertEquals("1000", result.storageCostAtto)
        assertEquals("42", result.gasCostWei)
        assertEquals(3UL, result.chunksStored)
        assertEquals("auto", result.paymentModeUsed)
    }

    @Test
    fun `fileDownloadPublic succeeds`() = runTest {
        client.fileDownloadPublic("file1", "/tmp/out.txt")
    }

    @Test
    fun `dirUploadPublic returns FileUploadResult`() = runTest {
        val result = client.dirUploadPublic("/tmp/mydir")
        assertEquals("dir1", result.address)
        assertEquals("2000", result.storageCostAtto)
        assertEquals("100", result.gasCostWei)
        assertEquals(5UL, result.chunksStored)
        assertEquals("merkle", result.paymentModeUsed)
    }

    @Test
    fun `dirDownloadPublic succeeds`() = runTest {
        client.dirDownloadPublic("dir1", "/tmp/outdir")
    }

    @Test
    fun `fileCost returns full breakdown`() = runTest {
        val est = client.fileCost("/tmp/test.txt", true)
        assertEquals("1000", est.cost)
        assertEquals(4096uL, est.fileSize)
        assertEquals(3u, est.chunkCount)
        assertEquals("150000000000000", est.estimatedGasCostWei)
        assertEquals("auto", est.paymentMode)
    }

    // -------------------------------------------------------------------------
    // Error mapping
    // -------------------------------------------------------------------------

    @Test
    fun `404 maps to NotFoundException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(404)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"not found"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<NotFoundException> {
                errClient.dataGetPublic("nonexistent")
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }

    @Test
    fun `402 maps to PaymentException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(402)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"insufficient funds"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<PaymentException> {
                errClient.dataPutPublic("data".toByteArray())
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }

    @Test
    fun `400 maps to BadRequestException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(400)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"bad request"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<BadRequestException> {
                errClient.dataPutPublic("data".toByteArray())
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }

    @Test
    fun `409 maps to AlreadyExistsException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(409)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"already exists"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<AlreadyExistsException> {
                errClient.dataPutPublic("data".toByteArray())
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }

    @Test
    fun `413 maps to TooLargeException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(413)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"too large"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<TooLargeException> {
                errClient.dataPutPublic("data".toByteArray())
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }

    @Test
    fun `500 maps to InternalException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(500)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"internal error"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<InternalException> {
                errClient.dataPutPublic("data".toByteArray())
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }

    @Test
    fun `502 maps to NetworkException`() = runTest {
        val errServer = MockWebServer()
        errServer.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse()
                .setResponseCode(502)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"network error"}""")
        }
        errServer.start()

        val errClient = AntdRestClient(baseUrl = errServer.url("/").toString())
        try {
            assertFailsWith<NetworkException> {
                errClient.dataPutPublic("data".toByteArray())
            }
        } finally {
            errClient.close()
            errServer.shutdown()
        }
    }
}
