package com.autonomi.sdk

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
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
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The REST pointer surface against a mock daemon: request shapes, the
 * decimal-string counters (up to u64::MAX), REST's nulls, and the error codes
 * that share an HTTP status with older errors.
 */
class PointerRestTest {

    private lateinit var server: MockWebServer
    private lateinit var client: AntdRestClient
    private lateinit var daemon: Daemon

    companion object {
        val A = "aa".repeat(32)
        val B = "bb".repeat(32)
        val T1 = "11".repeat(32)
        val T2 = "22".repeat(32)
        val SID = "cd".repeat(32)
        const val MAX = "18446744073709551615"

        fun json(body: String, code: Int = 200): MockResponse =
            MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body)

        fun error(code: Int, antdCode: String, message: String, extra: String = ""): MockResponse =
            json("""{"error":"$message","code":"$antdCode"$extra}""", code)
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

        fun count(key: String): Int = requests.count { it.first == key }
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

    private fun finalityJson(status: String, extra: String) =
        """{"address":"$A","group":7,"answered":7,"status":"$status"$extra}"""

    private fun finalState(target: String, holders: Int, transferredTo: String? = null) =
        """{"state_id":"$SID","kind":"pointer","kind_tag":1,"target":"$target","holders":$holders,""" +
            """"transferred_to":${transferredTo?.let { "\"$it\"" } ?: "null"}}"""

    // ── Methods ──

    @Test
    fun `pointerKeys lists the addresses the daemon can write`() = runTest {
        daemon.on("GET /v1/pointers/keys", json("""{"keys":[{"address":"$A"},{"address":"$B"}]}"""))
        assertEquals(listOf(A, B), client.pointerKeys())
    }

    @Test
    fun `pointerCreate posts owner, target and the default chunk kind`() = runTest {
        daemon.on("POST /v1/pointers", json("""{"address":"$A","state_id":"$SID","counter":"0"}"""))
        val w = client.pointerCreate(A, T1)
        assertEquals(PointerWriteResult(A, SID, 0uL), w)
        val body = daemon.body("POST /v1/pointers")
        assertEquals(A, body.str("owner"))
        assertEquals(T1, body.str("target"))
        assertEquals("chunk", body.str("kind"))
    }

    @Test
    fun `pointerUpdate posts to the update route with a pointer kind`() = runTest {
        daemon.on("POST /v1/pointers/update", json("""{"address":"$A","state_id":"$SID","counter":"41"}"""))
        val w = client.pointerUpdate(A, B, PointerKind.POINTER)
        assertEquals(41uL, w.counter)
        val body = daemon.body("POST /v1/pointers/update")
        assertEquals(B, body.str("target"))
        assertEquals("pointer", body.str("kind"))
    }

    @Test
    fun `pointerGet reads a final record at u64 max`() = runTest {
        val owner = "ab".repeat(1952)
        daemon.on(
            "GET /v1/pointers/$A",
            json(
                """{"address":"$A","owner":"$owner","counter":"$MAX","kind":"chunk","kind_tag":0,""" +
                    """"target":"$T1","state_id":"$SID","is_final":true,"transferred_to":"$B"}""",
            ),
        )
        val r = client.pointerGet(A)
        assertEquals(ULong.MAX_VALUE, r.counter)
        assertEquals(PointerRecord.FINAL_COUNTER, r.counter)
        assertTrue(r.isFinal)
        assertEquals(B, r.transferredTo)
        assertEquals(owner, r.owner)
        assertEquals("chunk", r.kind)
        assertEquals(0u, r.kindTag)
        assertEquals(PointerKind.CHUNK, r.targetKind)
        assertEquals(T1, r.target)
        assertEquals(SID, r.stateId)
    }

    @Test
    fun `pointerGet maps a null transferred_to and keeps an unknown kind tag`() = runTest {
        daemon.on(
            "GET /v1/pointers/$A",
            json(
                """{"address":"$A","owner":"ab","counter":"3","kind":"unknown","kind_tag":7,""" +
                    """"target":"$T1","state_id":"$SID","is_final":false,"transferred_to":null}""",
            ),
        )
        val r = client.pointerGet(A)
        assertEquals(3uL, r.counter)
        assertFalse(r.isFinal)
        assertNull(r.transferredTo)
        assertEquals("unknown", r.kind)
        assertEquals(7u, r.kindTag)
        assertNull(r.targetKind)
    }

    @Test
    fun `pointerResolve returns the target at the end of the chain`() = runTest {
        daemon.on("GET /v1/pointers/$A/resolve", json("""{"kind":"chunk","kind_tag":0,"target":"$T2"}"""))
        val t = client.pointerResolve(A)
        assertEquals(PointerTarget("chunk", 0u, T2), t)
        assertEquals(PointerKind.CHUNK, t.targetKind)
    }

    @Test
    fun `pointerFinality open carries the corroborated counter`() = runTest {
        daemon.on(
            "GET /v1/pointers/$A/finality",
            json(finalityJson("open", ""","counter":"1","state":null,"states":[],"majority":null,"transferred_to":null""")),
        )
        val f = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Open, f.status)
        assertEquals(1uL, f.counter)
        assertEquals(7u, f.group)
        assertEquals(7u, f.answered)
        assertNull(f.state)
        assertNull(f.majority)
        assertNull(f.transferredTo)
        assertTrue(f.states.isEmpty())
        assertFalse(f.isFinal)
    }

    @Test
    fun `pointerFinality open with no corroborated state has a null counter`() = runTest {
        daemon.on("GET /v1/pointers/$A/finality", json(finalityJson("open", ""","counter":null,"states":[]""")))
        val f = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Open, f.status)
        assertNull(f.counter)
    }

    @Test
    fun `pointerFinality final carries the one state and the recipient`() = runTest {
        daemon.on(
            "GET /v1/pointers/$A/finality",
            json(finalityJson("final", ""","counter":null,"state":${finalState(B, 7, B)},"states":[],"transferred_to":"$B"""")),
        )
        val f = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Final, f.status)
        assertTrue(f.isFinal)
        assertNull(f.counter)
        assertEquals(PointerFinalState(SID, "pointer", 1u, B, 7u, B), f.state)
        assertEquals(B, f.transferredTo)
    }

    @Test
    fun `pointerFinality forked lists every state and the majority`() = runTest {
        daemon.on(
            "GET /v1/pointers/$A/finality",
            json(
                finalityJson(
                    "forked",
                    ""","states":[${finalState(T1, 4)},${finalState(T2, 2)}],"majority":${finalState(T1, 4)}""",
                ),
            ),
        )
        val f = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Forked, f.status)
        assertEquals(listOf(T1, T2), f.states.map { it.target })
        assertEquals(listOf(4u, 2u), f.states.map { it.holders })
        assertEquals(T1, f.majority?.target)
        assertNull(f.states[0].transferredTo)
        assertNull(f.state)
    }

    @Test
    fun `pointerFinality keeps a status this SDK does not know`() = runTest {
        daemon.on("GET /v1/pointers/$A/finality", json(finalityJson("contested", ""","states":[]""")))
        val f = client.pointerFinality(A)
        assertEquals(PointerFinalityStatus.Unknown("contested"), f.status)
        assertEquals("contested", f.status.wire)
        assertFalse(f.isFinal)
    }

    @Test
    fun `pointerController follows the transfers`() = runTest {
        daemon.on(
            "GET /v1/pointers/$A/controller",
            json("""{"pointer":"$B","transfers":["$B"],"frozen":false}"""),
        )
        assertEquals(PointerController(B, listOf(B), false), client.pointerController(A))
    }

    @Test
    fun `pointerTransfer posts owner and recipient and carries the finality`() = runTest {
        daemon.on(
            "POST /v1/pointers/transfer",
            json(
                """{"address":"$A","state_id":"$SID","finality":""" +
                    finalityJson("final", ""","state":${finalState(B, 7, B)},"states":[],"transferred_to":"$B"""") + "}",
            ),
        )
        val t = client.pointerTransfer(A, B)
        assertEquals(A, t.address)
        assertEquals(SID, t.stateId)
        assertTrue(t.finality!!.isFinal)
        assertEquals(B, t.finality!!.transferredTo)
        assertNull(t.finalityError)
        val body = daemon.body("POST /v1/pointers/transfer")
        assertEquals(A, body.str("owner"))
        assertEquals(B, body.str("recipient"))
    }

    @Test
    fun `pointerTransfer whose finality check failed reports why`() = runTest {
        daemon.on(
            "POST /v1/pointers/transfer",
            json("""{"address":"$A","state_id":"$SID","finality":null,"finality_error":"close group did not answer"}"""),
        )
        val t = client.pointerTransfer(A, B)
        assertNull(t.finality)
        assertEquals("close group did not answer", t.finalityError)
    }

    private fun prepareJson(op: String, counter: String, extra: String = "") =
        """{"upload_id":"pp-1","op":"$op","address":"$A","state_id":"$SID","counter":"$counter",""" +
            """"payment_type":"wave_batch","payments":[{"quote_hash":"0xqh","rewards_address":"0xra","amount":"7"}],""" +
            """"total_amount":"7","payment_vault_address":"0xvault","payment_token_address":"0xtoken",""" +
            """"rpc_url":"http://localhost:8545"$extra}"""

    @Test
    fun `pointerPrepare create sends target and kind and no signed-quote flag by default`() = runTest {
        daemon.on("POST /v1/pointers/prepare", json(prepareJson("create", "0")))
        val p = client.pointerPrepare(A, PointerOp.Create(T1))
        val body = daemon.body("POST /v1/pointers/prepare")
        assertEquals("create", body.str("op"))
        assertEquals(A, body.str("owner"))
        assertEquals(T1, body.str("target"))
        assertEquals("chunk", body.str("kind"))
        assertFalse("recipient" in body)
        assertFalse("include_signed_quotes" in body)
        assertEquals("pp-1", p.uploadId)
        assertEquals("create", p.op)
        assertEquals(0uL, p.counter)
        assertEquals("wave_batch", p.paymentType)
        assertEquals(listOf(PaymentInfo("0xqh", "0xra", "7")), p.payments)
        assertEquals("7", p.totalAmount)
        assertEquals("0xvault", p.paymentVaultAddress)
        assertEquals("0xtoken", p.paymentTokenAddress)
        assertEquals("http://localhost:8545", p.rpcUrl)
        assertTrue(p.signedQuotes.isEmpty())
    }

    @Test
    fun `pointerPrepare update can ask for signed quotes`() = runTest {
        daemon.on(
            "POST /v1/pointers/prepare",
            json(
                prepareJson(
                    "update",
                    "5",
                    ""","signed_quotes":[{"quote_hash":"0xqh","quote":"cXVvdGU="},""" +
                        """{"quote_hash":"0xqh2","quote":"cTI=","commitment_sidecar":"c2lkZQ=="}]""",
                ),
            ),
        )
        val p = client.pointerPrepare(A, PointerOp.Update(T2, PointerKind.POINTER), includeSignedQuotes = true)
        val body = daemon.body("POST /v1/pointers/prepare")
        assertEquals("update", body.str("op"))
        assertEquals("pointer", body.str("kind"))
        assertEquals("true", body.str("include_signed_quotes"))
        assertEquals(5uL, p.counter)
        assertEquals(
            listOf(SignedQuoteEntry("0xqh", "cXVvdGU=", null), SignedQuoteEntry("0xqh2", "cTI=", "c2lkZQ==")),
            p.signedQuotes,
        )
    }

    @Test
    fun `pointerPrepare transfer sends only the recipient`() = runTest {
        daemon.on("POST /v1/pointers/prepare", json(prepareJson("transfer", MAX)))
        val p = client.pointerPrepare(A, PointerOp.Transfer(B))
        val body = daemon.body("POST /v1/pointers/prepare")
        assertEquals("transfer", body.str("op"))
        assertEquals(B, body.str("recipient"))
        assertFalse("target" in body)
        assertFalse("kind" in body)
        assertEquals(ULong.MAX_VALUE, p.counter)
    }

    @Test
    fun `pointerFinalize posts the upload id and tx hashes`() = runTest {
        daemon.on("POST /v1/pointers/finalize", json("""{"address":"$A","state_id":"$SID","counter":"6"}"""))
        val r = client.pointerFinalize("pp-1", mapOf("0xqh" to "0xtx"))
        assertEquals(PointerFinalizeResult(A, SID, 6uL, null), r)
        val body = daemon.body("POST /v1/pointers/finalize")
        assertEquals("pp-1", body.str("upload_id"))
        assertEquals("0xtx", body["tx_hashes"]!!.jsonObject.str("0xqh"))
    }

    @Test
    fun `pointerFinalize of a transfer carries the finality`() = runTest {
        daemon.on(
            "POST /v1/pointers/finalize",
            json(
                """{"address":"$A","state_id":"$SID","counter":"$MAX","finality":""" +
                    finalityJson("settling", ""","state":${finalState(B, 3, B)},"states":[]""") + "}",
            ),
        )
        val r = client.pointerFinalize("pp-1", emptyMap())
        assertEquals(ULong.MAX_VALUE, r.counter)
        assertEquals(PointerFinalityStatus.Settling, r.finality!!.status)
        assertEquals(3u, r.finality!!.state!!.holders)
    }

    // ── Counters ──

    @Test
    fun `a malformed counter is an error, never zero`() = runTest {
        val bad = listOf(
            "", "-1", "+1", " 1", "1 ", "0x10", "1.0", "1e3",
            "18446744073709551616", // u64::MAX + 1
            "١", // ARABIC-INDIC DIGIT ONE: a Unicode digit, not ASCII
        )
        for (counter in bad) {
            daemon.on("POST /v1/pointers", json("""{"address":"$A","state_id":"$SID","counter":"$counter"}"""))
            val ex = assertFailsWith<InternalException>("counter \"$counter\"") { client.pointerCreate(A, T1) }
            assertTrue(ex.message!!.contains("not a decimal counter"), ex.message)
        }
    }

    @Test
    fun `an empty finality counter reads as unset, a malformed one fails`() = runTest {
        daemon.on("GET /v1/pointers/$A/finality", json(finalityJson("open", ""","counter":"","states":[]""")))
        assertNull(client.pointerFinality(A).counter)
        daemon.on("GET /v1/pointers/$A/finality", json(finalityJson("open", ""","counter":"-3","states":[]""")))
        assertFailsWith<InternalException> { client.pointerFinality(A) }
    }

    @Test
    fun `counter parsing accepts the full u64 range`() {
        assertEquals(0uL, parsePointerCounter("counter", "0"))
        assertEquals(ULong.MAX_VALUE, parsePointerCounter("counter", MAX))
        assertEquals(9223372036854775808uL, parsePointerCounter("counter", "9223372036854775808"))
        assertNull(parseOptionalPointerCounter("counter", null))
        assertNull(parseOptionalPointerCounter("counter", ""))
    }

    // ── Errors ──

    @Test
    fun `POINTER_FINAL is its own 409, not AlreadyExists`() = runTest {
        daemon.on("POST /v1/pointers/update", error(409, "POINTER_FINAL", "Pointer is final: transferred"))
        val ex = assertFailsWith<PointerFinalException> { client.pointerUpdate(A, T1) }
        assertEquals(409, ex.statusCode)
        assertEquals("Pointer is final: transferred", ex.message)
    }

    @Test
    fun `POINTER_FORKED is a PointerForkedException and still a ForkException`() = runTest {
        daemon.on("GET /v1/pointers/$A", error(409, "POINTER_FORKED", "Pointer is forked: no majority"))
        val ex = assertFailsWith<PointerForkedException> { client.pointerGet(A) }
        assertIs<ForkException>(ex)
        assertEquals(409, ex.statusCode)
    }

    @Test
    fun `CONFLICT is its own 409`() = runTest {
        daemon.on("POST /v1/pointers/update", error(409, "CONFLICT", "Conflict: a prepared write awaits payment"))
        val ex = assertFailsWith<ConflictException> { client.pointerUpdate(A, T1) }
        assertEquals(409, ex.statusCode)
    }

    @Test
    fun `ALREADY_EXISTS on create keeps its mapping`() = runTest {
        daemon.on("POST /v1/pointers", error(409, "ALREADY_EXISTS", "Already exists: pointer"))
        assertFailsWith<AlreadyExistsException> { client.pointerCreate(A, T1) }
    }

    @Test
    fun `CLOSE_GROUP_SHORTFALL carries retryable only when it is the literal true`() = runTest {
        val cases = listOf(
            ""","retryable":true""" to true,
            ""","retryable":false""" to false,
            "" to false,
            ""","retryable":"true"""" to false,
            ""","retryable":1""" to false,
        )
        for ((extra, retryable) in cases) {
            daemon.on("POST /v1/pointers/finalize", error(503, "CLOSE_GROUP_SHORTFALL", "Close group shortfall: 3/7", extra))
            val ex = assertFailsWith<CloseGroupShortfallException>(extra) { client.pointerFinalize("pp-1", emptyMap()) }
            assertEquals(retryable, ex.retryable, extra)
            assertEquals(503, ex.statusCode)
        }
    }

    @Test
    fun `other 409 and 503 codes keep the status mapping`() {
        assertIs<AlreadyExistsException>(ExceptionMapping.fromHttpStatus(409, """{"error":"x","code":"SOMETHING_NEW"}"""))
        assertIs<AlreadyExistsException>(ExceptionMapping.fromHttpStatus(409, "plain text"))
        assertIs<ServiceUnavailableException>(
            ExceptionMapping.fromHttpStatus(503, """{"error":"no wallet","code":"SERVICE_UNAVAILABLE"}"""),
        )
        // A non-string code never selects a typed exception.
        assertIs<AlreadyExistsException>(ExceptionMapping.fromHttpStatus(409, """{"error":"x","code":7}"""))
        // PARTIAL_UPLOAD still wins on its own code.
        assertIs<PartialUploadException>(
            ExceptionMapping.fromHttpStatus(502, """{"error":"p","code":"PARTIAL_UPLOAD","retryable":true}"""),
        )
    }

    @Test
    fun `an unknown owner and a missing pointer keep their mappings`() = runTest {
        daemon.on("POST /v1/pointers", error(400, "BAD_REQUEST", "Bad request: no key for owner"))
        assertFailsWith<BadRequestException> { client.pointerCreate(B, T1) }
        daemon.on("GET /v1/pointers/$B", error(404, "NOT_FOUND", "Record not found: pointer"))
        assertFailsWith<NotFoundException> { client.pointerGet(B) }
    }

    @Test
    fun `paid writes are sent once, never retried`() = runTest {
        val shortfall = error(503, "CLOSE_GROUP_SHORTFALL", "Close group shortfall", ""","retryable":true""")
        for (key in listOf("POST /v1/pointers", "POST /v1/pointers/update", "POST /v1/pointers/transfer", "POST /v1/pointers/finalize")) {
            daemon.on(key, shortfall)
        }
        assertFailsWith<CloseGroupShortfallException> { client.pointerCreate(A, T1) }
        assertFailsWith<CloseGroupShortfallException> { client.pointerUpdate(A, T1) }
        assertFailsWith<CloseGroupShortfallException> { client.pointerTransfer(A, B) }
        assertFailsWith<CloseGroupShortfallException> { client.pointerFinalize("pp-1", emptyMap()) }
        assertEquals(1, daemon.count("POST /v1/pointers"))
        assertEquals(1, daemon.count("POST /v1/pointers/update"))
        assertEquals(1, daemon.count("POST /v1/pointers/transfer"))
        assertEquals(1, daemon.count("POST /v1/pointers/finalize"))
    }

    @Test
    fun `finality statuses round-trip through their wire strings`() {
        for (s in listOf(
            PointerFinalityStatus.Open, PointerFinalityStatus.Settling, PointerFinalityStatus.Unconfirmed,
            PointerFinalityStatus.Final, PointerFinalityStatus.Forked,
        )) {
            assertEquals(s, PointerFinalityStatus.fromWire(s.wire))
        }
        assertEquals(PointerKind.POINTER, PointerKind.fromTag(1u))
        assertNull(PointerKind.fromTag(2u))
    }
}
