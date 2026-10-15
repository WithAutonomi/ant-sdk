package com.autonomi.sdk

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
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
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The REST manifest surface against a mock daemon: the base64 wire form of
 * the `.ant` bytes, unset sizes reading as null (never 0), the both-or-neither
 * entry check, the `embed_roots` default and a 400 mapping to
 * [BadRequestException].
 */
class ManifestRestTest {

    private lateinit var server: MockWebServer
    private lateinit var client: AntdRestClient
    private lateinit var daemon: Daemon

    companion object {
        /** The five-byte `.ant` header; "wUFOVAE=" is its base64. */
        val HEADER = byteArrayOf(0xC1.toByte(), 'A'.code.toByte(), 'N'.code.toByte(), 'T'.code.toByte(), 0x01)
        const val HEADER_B64 = "wUFOVAE="
        const val LINK = "ant://manifest/wUFOVAE"
        val ADDR = "11".repeat(32)
        val CA = "cc".repeat(32)
        const val MAX = "18446744073709551615"

        fun json(body: String, code: Int = 200): MockResponse =
            MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body)
    }

    /** Answers each `METHOD path` with the response a test set, and records every request. */
    class Daemon : Dispatcher() {
        val responses = mutableMapOf<String, MockResponse>()
        val requests = mutableListOf<Pair<String, String>>()

        override fun dispatch(request: RecordedRequest): MockResponse {
            val key = "${request.method} ${request.path}"
            requests += key to request.body.readUtf8()
            return responses[key] ?: json("""{"error":"no route $key","code":"NOT_FOUND"}""", 404)
        }

        fun on(key: String, response: MockResponse) {
            responses[key] = response
        }

        fun body(key: String): JsonObject =
            Json.parseToJsonElement(requests.last { it.first == key }.second).jsonObject
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

    private fun JsonObject.str(key: String): String? = this[key]?.jsonPrimitive?.content
    private fun JsonObject.entries(): List<JsonObject> = this["entries"]!!.jsonArray.map { it.jsonObject }

    // ── buildManifest ──

    @Test
    fun `buildManifest sends both entry kinds and options, and decodes the base64 manifest`() = runTest {
        daemon.on(
            "POST /v1/manifests/build",
            json(
                """{"manifest":"$HEADER_B64","link":"$LINK","entries":[
                  {"effective_name":"a.txt","path":"a.txt","size":10,"kind":"embedded","content_address":"$CA","exact_size":10},
                  {"effective_name":"$ADDR","kind":"public","content_address":"$ADDR"}
                ]}""",
            ),
        )
        val built = client.buildManifest(
            listOf(
                ManifestEntryInput(path = "a.txt", size = 10u, dataMap = "abcd"),
                ManifestEntryInput(address = ADDR),
            ),
            BuildManifestOptions(name = "album", torrentInfoHashes = listOf("aa".repeat(20)), embedRoots = false),
        )

        val body = daemon.body("POST /v1/manifests/build")
        assertEquals("album", body.str("name"))
        assertEquals(JsonPrimitive(false), body["embed_roots"])
        assertEquals(JsonArray(listOf(JsonPrimitive("aa".repeat(20)))), body["torrent_info_hashes"])
        val (first, second) = body.entries()
        assertEquals("a.txt", first.str("path"))
        assertEquals("abcd", first.str("data_map"))
        assertEquals(JsonPrimitive(10), first["size"])
        assertFalse("address" in first, "an embedded entry must not send an address: $first")
        assertEquals(ADDR, second.str("address"))
        assertFalse("path" in second || "size" in second || "data_map" in second, "unset fields must be omitted: $second")

        // Raw bytes out, never base64.
        assertContentEquals(HEADER, built.manifest)
        assertEquals(LINK, built.link)
        assertEquals(2, built.entries.size)
        val (a, p) = built.entries
        assertEquals(ManifestEntryInfo("a.txt", "embedded", CA, path = "a.txt", size = 10uL, exactSize = 10uL), a)
        // REST omits unset fields: they read as null, never 0 or "".
        assertEquals(ManifestEntryInfo(ADDR, "public", ADDR), p)
        assertNull(p.size)
        assertNull(p.exactSize)
        assertNull(p.path)
        assertNull(p.dataMap)
        assertNull(p.error)
    }

    @Test
    fun `buildManifest defaults to embedding roots and omits an empty name and no torrent hashes`() = runTest {
        daemon.on("POST /v1/manifests/build", json("""{"manifest":"","entries":[]}"""))
        val built = client.buildManifest(listOf(ManifestEntryInput(address = ADDR)))
        val body = daemon.body("POST /v1/manifests/build")
        assertEquals(JsonPrimitive(true), body["embed_roots"])
        assertFalse("name" in body, "$body")
        assertFalse("torrent_info_hashes" in body, "$body")

        client.buildManifest(listOf(ManifestEntryInput(address = ADDR, path = "")), BuildManifestOptions(name = ""))
        val second = daemon.body("POST /v1/manifests/build")
        assertFalse("name" in second, "an empty name must be omitted: $second")
        assertFalse("path" in second.entries().single(), "an empty path must be omitted: $second")

        // No link in the response (it did not fit): null, not "".
        assertNull(built.link)
        assertEquals(0, built.manifest.size)
    }

    @Test
    fun `buildManifest carries sizes as exact u64 numbers both ways`() = runTest {
        daemon.on(
            "POST /v1/manifests/build",
            json(
                """{"manifest":"$HEADER_B64","entries":[
                  {"effective_name":"big","path":"big","size":$MAX,"kind":"public","content_address":"$ADDR","exact_size":0}
                ]}""",
            ),
        )
        val built = client.buildManifest(listOf(ManifestEntryInput(path = "big", size = ULong.MAX_VALUE, address = ADDR)))
        // An unquoted JSON number, digit for digit.
        val raw = daemon.requests.last().second
        assertTrue(raw.contains("\"size\":$MAX"), raw)
        val size = daemon.body("POST /v1/manifests/build").entries().single()["size"]!!.jsonPrimitive
        assertFalse(size.isString, "size must be a JSON number: $raw")
        assertEquals(ULong.MAX_VALUE, built.entries.single().size)
        // An exact size of 0 is a real 0, distinct from unset.
        assertEquals(0uL, built.entries.single().exactSize)
    }

    @Test
    fun `buildManifest rejects entries with both or neither source before sending, in the daemon's words`() = runTest {
        val cases = mapOf(
            ManifestEntryInput(path = "x") to "1 invalid entries: entries[1]: needs a data_map or an address",
            ManifestEntryInput(dataMap = "", address = "") to "1 invalid entries: entries[1]: needs a data_map or an address",
            ManifestEntryInput(dataMap = "aa", address = ADDR) to "1 invalid entries: entries[1]: give data_map or address, not both",
        )
        for ((bad, message) in cases) {
            val ex = assertFailsWith<BadRequestException>("$bad") {
                client.buildManifest(listOf(ManifestEntryInput(address = ADDR), bad))
            }
            assertEquals(400, ex.statusCode)
            assertEquals(message, ex.message)
        }
        assertTrue(daemon.requests.isEmpty(), "nothing may be sent: ${daemon.requests}")
    }

    @Test
    fun `every bad entry is reported together, at most 20, then a count`() = runTest {
        val two = assertFailsWith<BadRequestException> {
            client.buildManifest(listOf(ManifestEntryInput(dataMap = "aa", address = ADDR), ManifestEntryInput(address = ADDR), ManifestEntryInput()))
        }
        assertEquals(400, two.statusCode)
        assertEquals(
            "2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address",
            two.message,
        )
        val many = assertFailsWith<BadRequestException> { client.buildManifest(List(23) { ManifestEntryInput() }) }
        val shown = (0 until 20).joinToString("; ") { "entries[$it]: needs a data_map or an address" }
        assertEquals("23 invalid entries: $shown; and 3 more", many.message)
        assertTrue(daemon.requests.isEmpty())
    }

    @Test
    fun `an empty string counts as unset, so the other source is sent`() = runTest {
        daemon.on("POST /v1/manifests/build", json("""{"manifest":"","entries":[]}"""))
        client.buildManifest(listOf(ManifestEntryInput(dataMap = "", address = ADDR)))
        val entry = daemon.body("POST /v1/manifests/build").entries().single()
        assertEquals(ADDR, entry.str("address"))
        assertFalse("data_map" in entry, "$entry")
    }

    @Test
    fun `a 400 naming the entry is a BadRequestException carrying the daemon's message`() = runTest {
        daemon.on(
            "POST /v1/manifests/build",
            json("""{"error":"Bad request: entries[1]: invalid path \"../x\": parent components are not allowed","code":"BAD_REQUEST"}""", 400),
        )
        val ex = assertFailsWith<BadRequestException> {
            client.buildManifest(listOf(ManifestEntryInput(address = ADDR), ManifestEntryInput(address = ADDR, path = "../x")))
        }
        assertEquals(400, ex.statusCode)
        assertTrue(ex.message!!.contains("entries[1]: invalid path"), ex.message)
    }

    @Test
    fun `a manifest that is not base64 is an InternalException`() = runTest {
        daemon.on("POST /v1/manifests/build", json("""{"manifest":"not base64!","entries":[]}"""))
        assertFailsWith<InternalException> { client.buildManifest(listOf(ManifestEntryInput(address = ADDR))) }
    }

    // ── decodeManifest / decodeManifestLink ──

    @Test
    fun `decodeManifest sends the bytes as base64 and maps every field`() = runTest {
        daemon.on(
            "POST /v1/manifests/decode",
            json(
                """{"source":"manifest","name":"album","torrent_info_hash_v2":"${"bb".repeat(32)}","entries":[
                  {"effective_name":"a.txt","path":"a.txt","kind":"embedded","content_address":"$CA","data_map":"abcd","exact_size":3},
                  {"effective_name":"b","path":"b","kind":"public","content_address":"$ADDR","error":"Record not found: gone"}
                ]}""",
            ),
        )
        val decoded = client.decodeManifest(HEADER, resolve = true)

        val body = daemon.body("POST /v1/manifests/decode")
        assertEquals(HEADER_B64, body.str("manifest"))
        assertEquals(JsonPrimitive(true), body["resolve"])
        assertFalse("link" in body, "$body")

        assertEquals("manifest", decoded.source)
        assertEquals("album", decoded.name)
        assertNull(decoded.torrentInfoHashV1)
        assertEquals("bb".repeat(32), decoded.torrentInfoHashV2)
        val (a, b) = decoded.entries
        assertEquals("abcd", a.dataMap)
        assertEquals(3uL, a.exactSize)
        assertNull(a.size, "no recorded size reads as null")
        assertNull(a.error)
        assertEquals("Record not found: gone", b.error)
        assertNull(b.exactSize, "a failed resolve has no exact size")
        assertNull(b.dataMap, "a public entry has no DataMap")
    }

    @Test
    fun `decodeManifestLink sends the link and no bytes, resolve defaulting to false`() = runTest {
        daemon.on(
            "POST /v1/manifests/decode",
            json("""{"source":"file_link","entries":[{"effective_name":"$ADDR","kind":"public","content_address":"$ADDR"}]}"""),
        )
        val decoded = client.decodeManifestLink(ADDR)
        val body = daemon.body("POST /v1/manifests/decode")
        assertEquals(ADDR, body.str("link"))
        assertEquals(JsonPrimitive(false), body["resolve"])
        assertFalse("manifest" in body, "a link request must not send manifest bytes: $body")
        assertEquals(DecodedManifest("file_link", null, null, null, listOf(ManifestEntryInfo(ADDR, "public", ADDR))), decoded)
    }

    @Test
    fun `decode rejects empty input before sending`() = runTest {
        for (call in listOf<suspend () -> Any>({ client.decodeManifest(ByteArray(0)) }, { client.decodeManifestLink("") })) {
            val ex = assertFailsWith<BadRequestException> { call() }
            assertEquals(400, ex.statusCode)
            assertEquals("needs a manifest (base64 .ant bytes) or a link", ex.message)
        }
        assertTrue(daemon.requests.isEmpty(), "nothing may be sent: ${daemon.requests}")
    }

    @Test
    fun `a 400 on decode is a BadRequestException`() = runTest {
        daemon.on(
            "POST /v1/manifests/decode",
            json("""{"error":"Bad request: not a manifest: missing or invalid header","code":"BAD_REQUEST"}""", 400),
        )
        val ex = assertFailsWith<BadRequestException> { client.decodeManifest("nope".toByteArray()) }
        assertTrue(ex.message!!.contains("not a manifest"), ex.message)
    }

    @Test
    fun `BuiltManifest compares its bytes by content`() {
        val entries = listOf(ManifestEntryInfo(ADDR, "public", ADDR))
        assertEquals(BuiltManifest(HEADER.copyOf(), LINK, entries), BuiltManifest(HEADER.copyOf(), LINK, entries))
        assertEquals(BuiltManifest(HEADER.copyOf(), LINK, entries).hashCode(), BuiltManifest(HEADER.copyOf(), LINK, entries).hashCode())
        assertFalse(BuiltManifest(HEADER, LINK, entries) == BuiltManifest(byteArrayOf(1), LINK, entries))
    }
}
