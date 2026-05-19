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
    private lateinit var daemon: MockDaemon

    @BeforeTest
    fun setUp() {
        server = MockWebServer()
        daemon = MockDaemon()
        server.dispatcher = daemon
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
        // Tracks the most recent /v1/upload/prepare request body so tests can
        // assert that `visibility` is forwarded correctly. Set to "public"
        // when the prior prepare carried visibility:"public", so the
        // /v1/upload/finalize stub can echo a data_map_address back.
        var lastPrepareBody: String = ""
        var lastVisibility: String? = null
        // Tracks the most recent /v1/chunks/finalize body for tx_hashes
        // shape assertions.
        var lastChunkFinalizeBody: String = ""

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
            if (method == "POST" && path == "/v1/files/cost") {
                return json("""{"cost":"1000","file_size":4096,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"auto"}""")
            }

            // External-signer file/data prepare. Capture the request body so
            // tests can assert visibility forwarding, and remember whether the
            // current upload was public so /v1/upload/finalize can echo a
            // data_map_address back.
            if (method == "POST" && (path == "/v1/upload/prepare" || path == "/v1/data/prepare")) {
                lastPrepareBody = request.body.readUtf8()
                lastVisibility = "\"visibility\"\\s*:\\s*\"([^\"]+)\"".toRegex()
                    .find(lastPrepareBody)?.groupValues?.get(1)
                return json("""{"upload_id":"up-1","payment_type":"wave_batch","payments":[{"quote_hash":"qh1","rewards_address":"ra1","amount":"100"}],"total_amount":"100","payment_vault_address":"0xvault","payment_token_address":"0xtoken","rpc_url":"http://localhost:8545"}""")
            }

            // External-signer finalize. Echo a data_map_address when the prior
            // prepare carried visibility:"public" (the DataMap chunk was paid
            // and stored in the same external-signer batch).
            if (method == "POST" && path == "/v1/upload/finalize") {
                val dataMapAddress = if (lastVisibility == "public") "cafebabe" else ""
                return json("""{"address":"","chunks_stored":4,"data_map":"deadbeef","data_map_address":"$dataMapAddress"}""")
            }

            // Single-chunk external-signer prepare. We decide which branch to
            // exercise from the payload — bytes "already" trigger the
            // already_stored short-circuit, anything else returns the full
            // wave-batch payment intent.
            if (method == "POST" && path == "/v1/chunks/prepare") {
                val body = request.body.readUtf8()
                val isAlready = body.contains("YWxyZWFkeQ==") // base64("already")
                return if (isAlready) {
                    json("""{"address":"bb${"11".repeat(31)}","already_stored":true}""")
                } else {
                    json("""{"address":"aa${"00".repeat(31)}","already_stored":false,"upload_id":"chunk-1","payment_type":"wave_batch","payments":[{"quote_hash":"qh1","rewards_address":"ra1","amount":"100"},{"quote_hash":"qh2","rewards_address":"ra2","amount":"100"}],"total_amount":"200","payment_vault_address":"0xvault","payment_token_address":"0xtoken","rpc_url":"http://localhost:8545"}""")
                }
            }

            if (method == "POST" && path == "/v1/chunks/finalize") {
                lastChunkFinalizeBody = request.body.readUtf8()
                return json("""{"address":"cc${"22".repeat(31)}"}""")
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

    // -------------------------------------------------------------------------
    // V2-274: public-prepare visibility forwarding + chunk external-signer
    // -------------------------------------------------------------------------

    @Test
    fun `prepareUpload omits visibility when null`() = runTest {
        client.prepareUpload("/tmp/x.txt")
        assertFalse(
            daemon.lastPrepareBody.contains("visibility"),
            "visibility key must be absent when not supplied; body=${daemon.lastPrepareBody}",
        )
    }

    @Test
    fun `prepareUploadPublic forwards visibility public`() = runTest {
        val res = client.prepareUploadPublic("/tmp/x.txt")
        assertTrue(
            daemon.lastPrepareBody.contains("\"visibility\":\"public\""),
            "expected visibility:public in request body; got ${daemon.lastPrepareBody}",
        )
        assertTrue(
            daemon.lastPrepareBody.contains("\"path\":\"/tmp/x.txt\""),
            "expected path forwarded; got ${daemon.lastPrepareBody}",
        )
        assertEquals("up-1", res.uploadId)
    }

    @Test
    fun `finalizeUpload surfaces dataMapAddress after public prepare`() = runTest {
        client.prepareUploadPublic("/tmp/x.txt")
        val res = client.finalizeUpload("up-1", mapOf("qh1" to "tx1"))
        assertEquals("cafebabe", res.dataMapAddress)
        assertEquals("deadbeef", res.dataMap)
        assertEquals(4L, res.chunksStored)
        // Legacy on-network address stays empty when prepare bundled the
        // DataMap chunk into the external-signer batch.
        assertEquals("", res.address)
    }

    @Test
    fun `finalizeUpload leaves dataMapAddress empty for private prepare`() = runTest {
        client.prepareUpload("/tmp/x.txt")
        val res = client.finalizeUpload("up-1", mapOf("qh1" to "tx1"))
        assertEquals("", res.dataMapAddress)
        assertEquals("deadbeef", res.dataMap)
    }

    @Test
    fun `prepareChunkUpload parses wave-batch shape`() = runTest {
        val res = client.prepareChunkUpload("hello".toByteArray())
        assertFalse(res.alreadyStored)
        assertEquals("chunk-1", res.uploadId)
        assertEquals("wave_batch", res.paymentType)
        assertEquals(2, res.payments.size)
        assertEquals("qh1", res.payments[0].quoteHash)
        assertEquals("100", res.payments[1].amount)
        assertEquals("200", res.totalAmount)
        assertEquals("0xvault", res.paymentVaultAddress)
        assertEquals("http://localhost:8545", res.rpcUrl)
        // Address is always populated (64 hex chars = 32 bytes).
        assertEquals(64, res.address.length)
    }

    @Test
    fun `prepareChunkUpload parses already-stored shape`() = runTest {
        val res = client.prepareChunkUpload("already".toByteArray())
        assertTrue(res.alreadyStored)
        assertEquals(64, res.address.length)
        // No payment / finalize plumbing when the chunk is already on-network.
        assertEquals("", res.uploadId)
        assertTrue(res.payments.isEmpty())
        assertEquals("", res.paymentType)
        assertEquals("", res.totalAmount)
    }

    @Test
    fun `finalizeChunkUpload forwards uploadId and txHashes and returns address`() = runTest {
        val addr = client.finalizeChunkUpload("chunk-1", mapOf("qh1" to "tx1", "qh2" to "tx2"))
        assertEquals(64, addr.length)
        assertTrue(
            daemon.lastChunkFinalizeBody.contains("\"upload_id\":\"chunk-1\""),
            "expected upload_id forwarded; got ${daemon.lastChunkFinalizeBody}",
        )
        // Both quote→tx entries must reach the daemon under tx_hashes.
        assertTrue(
            daemon.lastChunkFinalizeBody.contains("\"qh1\":\"tx1\""),
            "missing qh1→tx1: ${daemon.lastChunkFinalizeBody}",
        )
        assertTrue(
            daemon.lastChunkFinalizeBody.contains("\"qh2\":\"tx2\""),
            "missing qh2→tx2: ${daemon.lastChunkFinalizeBody}",
        )
    }
}
