package com.autonomi.sdk

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The `sha256` fields antd 0.17.0 added, over REST against a mock daemon:
 * every upload result reads it when present and as null when the key is
 * absent (an older daemon) or empty; a manifest entry input sends it only
 * when set and non-empty; a manifest entry info reads it from build and
 * decode; a bad hash is the daemon's 400 as a [BadRequestException].
 */
class Sha256RestTest {

    private lateinit var server: MockWebServer
    private lateinit var client: AntdRestClient
    private lateinit var daemon: Daemon

    companion object {
        val SHA = "ab".repeat(32)
        val ADDR = "11".repeat(32)
        val CA = "cc".repeat(32)
        const val HEADER_B64 = "wUFOVAE="

        fun json(body: String, code: Int = 200): MockResponse =
            MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body)
    }

    class Daemon : Dispatcher() {
        val responses = mutableMapOf<String, MockResponse>()
        val requests = mutableListOf<Pair<String, String>>()

        override fun dispatch(request: RecordedRequest): MockResponse {
            val key = "${request.method} ${request.path}"
            requests += key to request.body.readUtf8()
            return responses[key] ?: json("""{"error":"no route $key","code":"NOT_FOUND"}""", 404)
        }

        fun on(key: String, body: String, code: Int = 200) {
            responses[key] = json(body, code)
        }

        fun body(key: String): JsonObject = Json.parseToJsonElement(requests.last { it.first == key }.second).jsonObject
    }

    @BeforeTest
    fun setUp() {
        server = MockWebServer()
        daemon = Daemon()
        server.dispatcher = daemon
        server.start()
        client = AntdRestClient(baseUrl = server.url("/").toString())
    }

    @AfterTest
    fun tearDown() {
        client.close()
        server.shutdown()
    }

    // ── upload results ──

    @Test
    fun `dataPutPublic and dataPut read sha256`() = runTest {
        daemon.on("POST /v1/data/public", """{"address":"$ADDR","chunks_stored":3,"payment_mode_used":"single","sha256":"$SHA"}""")
        daemon.on("POST /v1/data", """{"data_map":"abcd","chunks_stored":3,"payment_mode_used":"single","sha256":"$SHA"}""")
        assertEquals(SHA, client.dataPutPublic("x".toByteArray()).sha256)
        assertEquals(SHA, client.dataPut("x".toByteArray()).sha256)
    }

    @Test
    fun `filePutPublic and filePut read sha256`() = runTest {
        val tail = """"storage_cost_atto":"1","gas_cost_wei":"2","chunks_stored":3,"payment_mode_used":"single","sha256":"$SHA""""
        daemon.on("POST /v1/files/public", """{"address":"$ADDR",$tail}""")
        daemon.on("POST /v1/files", """{"data_map":"abcd",$tail}""")
        assertEquals(SHA, client.filePutPublic("/tmp/x").sha256)
        assertEquals(SHA, client.filePut("/tmp/x").sha256)
    }

    @Test
    fun `finalizeUpload and finalizeMerkleUpload read sha256`() = runTest {
        daemon.on("POST /v1/upload/finalize", """{"address":"","chunks_stored":4,"data_map":"abcd","data_map_address":"$ADDR","sha256":"$SHA"}""")
        assertEquals(SHA, client.finalizeUpload("up-1", mapOf("q" to "t")).sha256)
        assertEquals(SHA, client.finalizeMerkleUpload("up-1", "0xwinner").sha256)
    }

    @Test
    fun `upload results read sha256 as null when the key is absent or empty`() = runTest {
        val tail = """"storage_cost_atto":"1","gas_cost_wei":"2","chunks_stored":3,"payment_mode_used":"single""""
        daemon.on("POST /v1/data/public", """{"address":"$ADDR","chunks_stored":3,"payment_mode_used":"single"}""")
        daemon.on("POST /v1/data", """{"data_map":"abcd","sha256":""}""")
        daemon.on("POST /v1/files/public", """{"address":"$ADDR",$tail}""")
        daemon.on("POST /v1/files", """{"data_map":"abcd",$tail,"sha256":""}""")
        daemon.on("POST /v1/upload/finalize", """{"address":"","chunks_stored":4}""")
        assertNull(client.dataPutPublic("x".toByteArray()).sha256)
        assertNull(client.dataPut("x".toByteArray()).sha256)
        assertNull(client.filePutPublic("/tmp/x").sha256)
        assertNull(client.filePut("/tmp/x").sha256)
        assertNull(client.finalizeUpload("up-1", mapOf("q" to "t")).sha256)
        assertNull(client.finalizeMerkleUpload("up-1", "0xwinner").sha256)
    }

    @Test
    fun `result constructors still compile without sha256, which defaults to null`() {
        assertNull(DataPutResult("dm").sha256)
        assertNull(DataPutResult("dm", 1u, "single").sha256)
        assertNull(DataPutPublicResult(ADDR, 1u, "single").sha256)
        assertNull(FilePutResult("dm", "1", "2", 3u, "single").sha256)
        assertNull(FilePutPublicResult(ADDR, "1", "2", 3u, "single").sha256)
        assertNull(FinalizeUploadResult("", 4, "dm", ADDR).sha256)
        assertNull(FinalizeMerkleUploadResult("", 4, "dm", ADDR).sha256)
        assertNull(ManifestEntryInput("a", 1u, "aa", null).sha256)
        assertNull(ManifestEntryInfo("a", "public", CA, "a", 1u, "dm", 2u, "err").sha256)
    }

    // ── manifest entry input ──

    @Test
    fun `buildManifest sends sha256 only on an entry that sets it, non-empty`() = runTest {
        daemon.on("POST /v1/manifests/build", """{"manifest":"$HEADER_B64","entries":[]}""")
        client.buildManifest(
            listOf(
                ManifestEntryInput(path = "a.txt", address = ADDR, sha256 = SHA),
                ManifestEntryInput(path = "b.txt", address = ADDR),
                ManifestEntryInput(path = "c.txt", address = ADDR, sha256 = ""),
            ),
        )
        val entries = daemon.body("POST /v1/manifests/build")["entries"]!!.jsonArray.map { it.jsonObject }
        assertEquals(SHA, entries[0]["sha256"]!!.jsonPrimitive.content)
        assertFalse("sha256" in entries[1], "unset sha256 must be omitted: ${entries[1]}")
        assertFalse("sha256" in entries[2], "an empty sha256 must be omitted, never sent as an empty string: ${entries[2]}")
    }

    @Test
    fun `buildManifest passes sha256 through exactly as given`() = runTest {
        daemon.on("POST /v1/manifests/build", """{"manifest":"$HEADER_B64","entries":[]}""")
        client.buildManifest(listOf(ManifestEntryInput(address = ADDR, sha256 = "ZZ")))
        val entry = daemon.body("POST /v1/manifests/build")["entries"]!!.jsonArray.single().jsonObject
        assertEquals("ZZ", entry["sha256"]!!.jsonPrimitive.content)
    }

    // ── manifest entry info ──

    @Test
    fun `build and decode read sha256 on entries, and null when absent or empty`() = runTest {
        val entries = """[
          {"effective_name":"a.txt","path":"a.txt","kind":"public","content_address":"$CA","sha256":"$SHA"},
          {"effective_name":"b.txt","path":"b.txt","kind":"public","content_address":"$CA"},
          {"effective_name":"c.txt","path":"c.txt","kind":"public","content_address":"$CA","sha256":""}
        ]"""
        daemon.on("POST /v1/manifests/build", """{"manifest":"$HEADER_B64","entries":$entries}""")
        daemon.on("POST /v1/manifests/decode", """{"source":"manifest","entries":$entries}""")

        val built = client.buildManifest(listOf(ManifestEntryInput(address = ADDR)))
        assertEquals(listOf(SHA, null, null), built.entries.map { it.sha256 })
        val decoded = client.decodeManifest(byteArrayOf(1))
        assertEquals(listOf(SHA, null, null), decoded.entries.map { it.sha256 })
        val linked = client.decodeManifestLink("ant://manifest/wUFOVAE")
        assertEquals(listOf(SHA, null, null), linked.entries.map { it.sha256 })
    }

    // ── errors ──

    @Test
    fun `a 400 for a bad sha256 is a BadRequestException keeping the daemon's message`() = runTest {
        daemon.on(
            "POST /v1/manifests/build",
            """{"error":"Bad request: entries[0]: invalid hex sha256: Invalid character 'z' at position 0","code":"BAD_REQUEST"}""",
            400,
        )
        val ex = assertFailsWith<BadRequestException> {
            client.buildManifest(listOf(ManifestEntryInput(address = ADDR, sha256 = "zz")))
        }
        assertEquals(400, ex.statusCode)
        assertTrue(ex.message!!.contains("entries[0]: invalid hex sha256"), ex.message)
    }
}
