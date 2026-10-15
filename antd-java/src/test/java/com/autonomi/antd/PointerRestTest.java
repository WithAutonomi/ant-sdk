package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;

import java.io.IOException;
import java.math.BigInteger;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletionException;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The pointer API over REST ({@link AntdClient} and {@link AsyncAntdClient})
 * against a mock daemon: request shapes, response parsing (counters up to
 * 2^64 - 1, unset values, unknown statuses) and the error-code mapping.
 */
class PointerRestTest {

    static final String A = "a1".repeat(32);
    static final String B = "b2".repeat(32);
    static final String T1 = "c3".repeat(32);
    static final String T2 = "d4".repeat(32);
    static final String MAX = "18446744073709551615";

    private MockWebServer server;
    private AntdClient client;
    private AsyncAntdClient async;

    @BeforeEach
    void setUp() throws IOException {
        server = new MockWebServer();
        server.start();
        client = new AntdClient(server.url("/").toString(), Duration.ofSeconds(10));
        async = new AsyncAntdClient(server.url("/").toString(), Duration.ofSeconds(10));
    }

    @AfterEach
    void tearDown() throws IOException {
        client.close();
        async.close();
        server.shutdown();
    }

    private void reply(String body) {
        reply(200, body);
    }

    private void reply(int status, String body) {
        server.enqueue(new MockResponse()
                .setResponseCode(status)
                .setHeader("Content-Type", "application/json")
                .setBody(body));
    }

    private RecordedRequest taken() throws InterruptedException {
        RecordedRequest r = server.takeRequest(5, TimeUnit.SECONDS);
        assertNotNull(r, "no request reached the mock daemon");
        return r;
    }

    private static Map<String, Object> bodyOf(RecordedRequest r) {
        return Json.parseObject(r.getBody().readUtf8());
    }

    static String finalState(String target, int holders, String transferredTo) {
        return "{\"state_id\":\"" + "ee".repeat(32) + "\",\"kind\":\"pointer\",\"kind_tag\":1,"
                + "\"target\":\"" + target + "\",\"holders\":" + holders + ",\"transferred_to\":"
                + (transferredTo == null ? "null" : "\"" + transferredTo + "\"") + "}";
    }

    // ── Reads ──

    @Test
    void keysListsAddresses() throws Exception {
        reply("{\"keys\":[{\"address\":\"" + A + "\"},{\"address\":\"" + B + "\"}]}");
        assertEquals(List.of(A, B), client.pointerKeys());
        RecordedRequest r = taken();
        assertEquals("GET", r.getMethod());
        assertEquals("/v1/pointers/keys", r.getPath());
    }

    @Test
    void getParsesAFinalTransferredRecord() throws Exception {
        reply("{\"address\":\"" + A + "\",\"owner\":\"" + "ab".repeat(1952) + "\",\"counter\":\"" + MAX
                + "\",\"kind\":\"pointer\",\"kind_tag\":1,\"target\":\"" + B + "\",\"state_id\":\"" + T2
                + "\",\"is_final\":true,\"transferred_to\":\"" + B + "\"}");
        PointerRecord r = client.pointerGet(A);
        assertEquals("/v1/pointers/" + A, taken().getPath());
        assertEquals(A, r.address());
        assertEquals(2 * 1952, r.owner().length());
        assertEquals(new BigInteger(MAX), r.counter());
        assertEquals(PointerRecord.FINAL_COUNTER, r.counter());
        assertEquals("pointer", r.kind());
        assertEquals(1, r.kindTag());
        assertEquals(PointerTargetKind.POINTER, r.targetKind().orElseThrow());
        assertEquals(B, r.target());
        assertEquals(T2, r.stateId());
        assertTrue(r.isFinal());
        assertEquals(B, r.transferredTo());
    }

    @Test
    void getReadsAnUnsetTransferAsNull() {
        reply("{\"address\":\"" + A + "\",\"owner\":\"ab\",\"counter\":\"7\",\"kind\":\"chunk\",\"kind_tag\":0,"
                + "\"target\":\"" + T1 + "\",\"state_id\":\"" + T2 + "\",\"is_final\":false,\"transferred_to\":null}");
        PointerRecord r = client.pointerGet(A);
        assertEquals(BigInteger.valueOf(7), r.counter());
        assertFalse(r.isFinal());
        assertNull(r.transferredTo());
        assertEquals(PointerTargetKind.CHUNK, r.targetKind().orElseThrow());
    }

    @Test
    void anUnknownKindTagHasNoTargetKind() {
        reply("{\"address\":\"" + A + "\",\"owner\":\"ab\",\"counter\":\"0\",\"kind\":\"unknown\",\"kind_tag\":9,"
                + "\"target\":\"" + T1 + "\",\"state_id\":\"" + T2 + "\",\"is_final\":false,\"transferred_to\":null}");
        PointerRecord r = client.pointerGet(A);
        assertEquals("unknown", r.kind());
        assertEquals(9, r.kindTag());
        assertTrue(r.targetKind().isEmpty());
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "\"-1\"", "\"+1\"", "\"1.0\"", "\"\"", "\" 1\"", "\"1 \"", "\"0x10\"", "\"1e3\"",
            "\"18446744073709551616\"", "\"99999999999999999999999\"", "\"\\u0663\"",
            "5", "null", "true", "{}"
    })
    void aMalformedCounterIsAnErrorNotZero(String counter) {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":" + counter + "}");
        AntdException e = assertThrows(AntdException.class, () -> client.pointerCreate(A, T1));
        assertTrue(e.getMessage().contains("counter"), e.getMessage());
    }

    @Test
    void aMissingCounterIsAnError() {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\"}");
        assertThrows(AntdException.class, () -> client.pointerUpdate(A, T1));
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "1", "007", "9223372036854775807", "9223372036854775808", MAX})
    void countersAreReadAsUnsigned64Bit(String counter) {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"" + counter + "\"}");
        assertEquals(new BigInteger(counter), client.pointerCreate(A, T1).counter());
    }

    @Test
    void resolveReturnsTheEndOfTheChain() throws Exception {
        reply("{\"kind\":\"chunk\",\"kind_tag\":0,\"target\":\"" + T1 + "\"}");
        PointerTarget t = client.pointerResolve(A);
        assertEquals("/v1/pointers/" + A + "/resolve", taken().getPath());
        assertEquals(new PointerTarget("chunk", 0, T1), t);
        assertEquals(PointerTargetKind.CHUNK, t.targetKind().orElseThrow());
    }

    @Test
    void finalityOpenCarriesOnlyTheCounter() throws Exception {
        reply("{\"address\":\"" + A + "\",\"group\":7,\"answered\":7,\"status\":\"open\",\"counter\":\"1\","
                + "\"state\":null,\"states\":[],\"majority\":null,\"transferred_to\":null}");
        PointerFinality f = client.pointerFinality(A);
        assertEquals("/v1/pointers/" + A + "/finality", taken().getPath());
        assertEquals(PointerFinalityStatus.OPEN, f.status());
        assertEquals("open", f.rawStatus());
        assertEquals(7, f.group());
        assertEquals(7, f.answered());
        assertEquals(BigInteger.ONE, f.counter());
        assertNull(f.state());
        assertTrue(f.states().isEmpty());
        assertNull(f.majority());
        assertNull(f.transferredTo());
        assertFalse(f.isFinal());
    }

    @Test
    void finalityOpenWithoutACorroboratedCounterIsNull() {
        reply("{\"address\":\"" + A + "\",\"group\":7,\"answered\":4,\"status\":\"open\",\"counter\":null,"
                + "\"state\":null,\"states\":[],\"majority\":null,\"transferred_to\":null}");
        assertNull(client.pointerFinality(A).counter());
    }

    @Test
    void finalityFinalCarriesTheStateAndTheRecipient() {
        reply("{\"address\":\"" + A + "\",\"group\":7,\"answered\":7,\"status\":\"final\",\"counter\":null,"
                + "\"state\":" + finalState(B, 7, B) + ",\"states\":[],\"majority\":null,"
                + "\"transferred_to\":\"" + B + "\"}");
        PointerFinality f = client.pointerFinality(A);
        assertTrue(f.isFinal());
        assertEquals(PointerFinalityStatus.FINAL, f.status());
        assertNull(f.counter());
        assertEquals(B, f.transferredTo());
        PointerFinalState s = f.state();
        assertNotNull(s);
        assertEquals(7, s.holders());
        assertEquals(B, s.target());
        assertEquals(B, s.transferredTo());
        assertEquals(PointerTargetKind.POINTER, s.targetKind().orElseThrow());
    }

    @Test
    void finalityForkedListsEveryStateAndTheMajority() {
        reply("{\"address\":\"" + A + "\",\"group\":7,\"answered\":7,\"status\":\"forked\",\"counter\":null,"
                + "\"state\":null,\"states\":[" + finalState(T1, 4, null) + "," + finalState(T2, 3, null) + "],"
                + "\"majority\":" + finalState(T1, 4, null) + ",\"transferred_to\":null}");
        PointerFinality f = client.pointerFinality(A);
        assertEquals(PointerFinalityStatus.FORKED, f.status());
        assertEquals(2, f.states().size());
        assertEquals(T1, f.states().get(0).target());
        assertEquals(3, f.states().get(1).holders());
        assertNull(f.states().get(1).transferredTo());
        assertEquals(T1, f.majority().target());
        assertNull(f.state());
    }

    @Test
    void aStatusFromANewerDaemonIsUnknownAndKept() {
        reply("{\"address\":\"" + A + "\",\"group\":7,\"answered\":7,\"status\":\"wobbly\",\"counter\":null,"
                + "\"state\":null,\"states\":[],\"majority\":null,\"transferred_to\":null}");
        PointerFinality f = client.pointerFinality(A);
        assertEquals(PointerFinalityStatus.UNKNOWN, f.status());
        assertEquals("wobbly", f.rawStatus());
        assertFalse(f.isFinal());
    }

    @Test
    void finalityWithAMalformedCounterIsAnError() {
        reply("{\"address\":\"" + A + "\",\"group\":7,\"answered\":7,\"status\":\"open\",\"counter\":\"-3\","
                + "\"state\":null,\"states\":[],\"majority\":null,\"transferred_to\":null}");
        assertThrows(AntdException.class, () -> client.pointerFinality(A));
    }

    @Test
    void controllerFollowsTransfers() throws Exception {
        reply("{\"pointer\":\"" + B + "\",\"transfers\":[\"" + B + "\"],\"frozen\":false}");
        PointerController c = client.pointerController(A);
        assertEquals("/v1/pointers/" + A + "/controller", taken().getPath());
        assertEquals(new PointerController(B, List.of(B), false), c);
    }

    // ── Writes ──

    @Test
    void createSendsOwnerTargetAndKind() throws Exception {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"0\"}");
        PointerWriteResult w = client.pointerCreate(A, T1);
        assertEquals(new PointerWriteResult(A, T2, BigInteger.ZERO), w);
        RecordedRequest r = taken();
        assertEquals("POST", r.getMethod());
        assertEquals("/v1/pointers", r.getPath());
        assertEquals(Map.of("owner", A, "target", T1, "kind", "chunk"), bodyOf(r));
    }

    @Test
    void updateSendsThePointerKind() throws Exception {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"1\"}");
        assertEquals(BigInteger.ONE, client.pointerUpdate(A, B, PointerTargetKind.POINTER).counter());
        RecordedRequest r = taken();
        assertEquals("/v1/pointers/update", r.getPath());
        assertEquals(Map.of("owner", A, "target", B, "kind", "pointer"), bodyOf(r));
    }

    @Test
    void aNullKindMeansChunk() throws Exception {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"1\"}");
        client.pointerUpdate(A, T1, null);
        assertEquals("chunk", bodyOf(taken()).get("kind"));
    }

    @Test
    void transferReturnsTheCloseGroupsView() throws Exception {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"finality\":{\"address\":\"" + A
                + "\",\"group\":7,\"answered\":7,\"status\":\"final\",\"counter\":null,\"state\":"
                + finalState(B, 7, B) + ",\"states\":[],\"majority\":null,\"transferred_to\":\"" + B + "\"}}");
        PointerTransferResult t = client.pointerTransfer(A, B);
        RecordedRequest r = taken();
        assertEquals("/v1/pointers/transfer", r.getPath());
        assertEquals(Map.of("owner", A, "recipient", B), bodyOf(r));
        assertEquals(A, t.address());
        assertEquals(T2, t.stateId());
        assertTrue(t.finality().isFinal());
        assertEquals(B, t.finality().transferredTo());
        assertNull(t.finalityError());
    }

    @Test
    void aTransferWhoseCheckFailedCarriesTheReason() {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"finality\":null,"
                + "\"finality_error\":\"only 3 of 7 answered\"}");
        PointerTransferResult t = client.pointerTransfer(A, B);
        assertNull(t.finality());
        assertEquals("only 3 of 7 answered", t.finalityError());
    }

    // ── External signer ──

    static String prepareResponse(String op, String counter, String signedQuotes) {
        return "{\"upload_id\":\"up-1\",\"op\":\"" + op + "\",\"address\":\"" + A + "\",\"state_id\":\"" + T2
                + "\",\"counter\":\"" + counter + "\",\"payment_type\":\"wave_batch\",\"payments\":["
                + "{\"quote_hash\":\"0xq1\",\"rewards_address\":\"0xr1\",\"amount\":\"123\"}],"
                + "\"total_amount\":\"123\",\"payment_vault_address\":\"0xvault\","
                + "\"payment_token_address\":\"0xtoken\",\"rpc_url\":\"http://rpc\""
                + (signedQuotes == null ? "" : ",\"signed_quotes\":" + signedQuotes) + "}";
    }

    @Test
    void prepareUpdateSendsTheOpAndParsesThePayment() throws Exception {
        reply(prepareResponse("update", "2", null));
        PointerPrepareResult p = client.pointerPrepare(A, PointerOp.update(T1, PointerTargetKind.CHUNK));
        RecordedRequest r = taken();
        assertEquals("/v1/pointers/prepare", r.getPath());
        assertEquals(Map.of("owner", A, "op", "update", "target", T1, "kind", "chunk"), bodyOf(r));
        assertEquals("up-1", p.uploadId());
        assertEquals("update", p.op());
        assertEquals(A, p.address());
        assertEquals(T2, p.stateId());
        assertEquals(BigInteger.TWO, p.counter());
        assertEquals("wave_batch", p.paymentType());
        assertEquals(List.of(new PaymentInfo("0xq1", "0xr1", "123")), p.payments());
        assertEquals("123", p.totalAmount());
        assertEquals("0xvault", p.paymentVaultAddress());
        assertEquals("0xtoken", p.paymentTokenAddress());
        assertEquals("http://rpc", p.rpcUrl());
        assertTrue(p.signedQuotes().isEmpty());
    }

    @Test
    void prepareCreateSendsTheKind() throws Exception {
        reply(prepareResponse("create", "0", null));
        client.pointerPrepare(A, new PointerOp.Create(B, PointerTargetKind.POINTER));
        assertEquals(Map.of("owner", A, "op", "create", "target", B, "kind", "pointer"), bodyOf(taken()));
    }

    @Test
    void prepareTransferSendsOnlyTheRecipientAndCanAskForSignedQuotes() throws Exception {
        reply(prepareResponse("transfer", MAX, "[{\"quote_hash\":\"0xq1\",\"quote\":\"cXVvdGU=\"},"
                + "{\"quote_hash\":\"0xq2\",\"quote\":\"cTI=\",\"commitment_sidecar\":\"c2lkZQ==\"}]"));
        PointerPrepareResult p = client.pointerPrepare(
                A, PointerOp.transfer(B), new PointerPrepareOptions(true));
        assertEquals(Map.of("owner", A, "op", "transfer", "recipient", B, "include_signed_quotes", true),
                bodyOf(taken()));
        assertEquals(PointerRecord.FINAL_COUNTER, p.counter());
        assertEquals(List.of(
                new SignedQuoteEntry("0xq1", "cXVvdGU=", null),
                new SignedQuoteEntry("0xq2", "cTI=", "c2lkZQ==")), p.signedQuotes());
    }

    @Test
    void finalizeSendsTheUploadIdAndTxHashes() throws Exception {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"3\"}");
        Map<String, String> tx = new LinkedHashMap<>();
        tx.put("0xq1", "0xt1");
        PointerFinalizeResult f = client.pointerFinalize("up-1", tx);
        RecordedRequest r = taken();
        assertEquals("/v1/pointers/finalize", r.getPath());
        assertEquals(Map.of("upload_id", "up-1", "tx_hashes", Map.of("0xq1", "0xt1")), bodyOf(r));
        assertEquals(new PointerFinalizeResult(A, T2, BigInteger.valueOf(3), null), f);
    }

    @Test
    void finalizeOfATransferCarriesFinality() {
        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"" + MAX + "\",\"finality\":"
                + "{\"address\":\"" + A + "\",\"group\":7,\"answered\":5,\"status\":\"unconfirmed\",\"counter\":null,"
                + "\"state\":" + finalState(B, 5, B) + ",\"states\":[],\"majority\":null,\"transferred_to\":null}}");
        PointerFinalizeResult f = client.pointerFinalize("up-1", Map.of());
        assertEquals(PointerRecord.FINAL_COUNTER, f.counter());
        assertEquals(PointerFinalityStatus.UNCONFIRMED, f.finality().status());
        assertEquals(5, f.finality().state().holders());
    }

    // ── Errors ──

    static Stream<Arguments> errorCodes() {
        return Stream.of(
                Arguments.of(409, "\"code\":\"POINTER_FINAL\"", PointerFinalException.class),
                Arguments.of(409, "\"code\":\"POINTER_FORKED\"", ForkException.class),
                Arguments.of(409, "\"code\":\"CONFLICT\"", ConflictException.class),
                Arguments.of(409, "\"code\":\"ALREADY_EXISTS\"", AlreadyExistsException.class),
                Arguments.of(409, "\"code\":7", AlreadyExistsException.class),
                Arguments.of(503, "\"code\":\"CLOSE_GROUP_SHORTFALL\"", CloseGroupShortfallException.class),
                Arguments.of(503, "\"code\":\"SERVICE_UNAVAILABLE\"", ServiceUnavailableException.class),
                Arguments.of(400, "\"code\":\"BAD_REQUEST\"", BadRequestException.class),
                Arguments.of(404, "\"code\":\"NOT_FOUND\"", NotFoundException.class));
    }

    @ParameterizedTest
    @MethodSource("errorCodes")
    void errorsMapByTheBodysCode(int status, String code, Class<? extends AntdException> expected) {
        reply(status, "{\"error\":\"boom\"," + code + "}");
        AntdException e = assertThrows(AntdException.class, () -> client.pointerUpdate(A, T1));
        assertEquals(expected, e.getClass());
        assertEquals(status, e.getStatusCode());
        assertTrue(e.getMessage().contains("boom"), e.getMessage());
    }

    @Test
    void pointerRefusalsAreNotAlreadyExists() {
        reply(409, "{\"error\":\"final\",\"code\":\"POINTER_FINAL\"}");
        AntdException e = assertThrows(AntdException.class, () -> client.pointerUpdate(A, T1));
        assertFalse(e instanceof AlreadyExistsException);
        reply(409, "{\"error\":\"pending\",\"code\":\"CONFLICT\"}");
        e = assertThrows(AntdException.class, () -> client.pointerUpdate(A, T1));
        assertFalse(e instanceof AlreadyExistsException);
    }

    @Test
    void aRetainedFinalizeShortfallIsRetryable() {
        reply(503, "{\"error\":\"short (paid attempt retained: call finalize again)\","
                + "\"code\":\"CLOSE_GROUP_SHORTFALL\",\"retryable\":true}");
        CloseGroupShortfallException e = assertThrows(CloseGroupShortfallException.class,
                () -> client.pointerFinalize("up-1", Map.of()));
        assertTrue(e.isRetryable());
        assertEquals(503, e.getStatusCode());
    }

    @ParameterizedTest
    @ValueSource(strings = {"", ",\"retryable\":false", ",\"retryable\":null", ",\"retryable\":\"true\"", ",\"retryable\":1"})
    void anyOtherShortfallIsNotRetryable(String retryable) {
        reply(503, "{\"error\":\"only 3 answered\",\"code\":\"CLOSE_GROUP_SHORTFALL\"" + retryable + "}");
        CloseGroupShortfallException e = assertThrows(CloseGroupShortfallException.class,
                () -> client.pointerGet(A));
        assertFalse(e.isRetryable());
    }

    @Test
    void aNonJsonErrorKeepsTheStatusMapping() {
        reply(409, "conflict!");
        assertThrows(AlreadyExistsException.class, () -> client.pointerCreate(A, T1));
    }

    @Test
    void aWriteIsSentExactlyOnceEvenWhenItFails() {
        reply(503, "{\"error\":\"short\",\"code\":\"CLOSE_GROUP_SHORTFALL\"}");
        reply(200, "{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"1\"}");
        assertThrows(CloseGroupShortfallException.class, () -> client.pointerUpdate(A, T1));
        assertEquals(1, server.getRequestCount());
    }

    // ── Async ──

    @Test
    void asyncMirrorsTheBlockingClient() throws Exception {
        reply("{\"keys\":[{\"address\":\"" + A + "\"}]}");
        assertEquals(List.of(A), async.pointerKeysAsync().join());
        assertEquals("/v1/pointers/keys", taken().getPath());

        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"" + MAX + "\"}");
        assertEquals(PointerRecord.FINAL_COUNTER, async.pointerCreateAsync(A, T1).join().counter());
        RecordedRequest r = taken();
        assertEquals("/v1/pointers", r.getPath());
        assertEquals(Map.of("owner", A, "target", T1, "kind", "chunk"), bodyOf(r));

        reply("{\"kind\":\"chunk\",\"kind_tag\":0,\"target\":\"" + T1 + "\"}");
        assertEquals(T1, async.pointerResolveAsync(A).join().target());
        assertEquals("/v1/pointers/" + A + "/resolve", taken().getPath());

        reply(prepareResponse("transfer", MAX, null));
        assertEquals("transfer", async.pointerPrepareAsync(A, PointerOp.transfer(B)).join().op());
        assertEquals(Map.of("owner", A, "op", "transfer", "recipient", B), bodyOf(taken()));
    }

    @Test
    void asyncMapsErrorsTheSameWay() {
        reply(409, "{\"error\":\"final\",\"code\":\"POINTER_FINAL\"}");
        CompletionException e = assertThrows(CompletionException.class,
                () -> async.pointerUpdateAsync(A, T1).join());
        assertInstanceOf(PointerFinalException.class, e.getCause());

        reply("{\"address\":\"" + A + "\",\"state_id\":\"" + T2 + "\",\"counter\":\"-1\"}");
        e = assertThrows(CompletionException.class, () -> async.pointerUpdateAsync(A, T1).join());
        assertInstanceOf(AntdException.class, e.getCause());
    }
}
