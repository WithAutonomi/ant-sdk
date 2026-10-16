package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;

import io.grpc.ManagedChannel;
import io.grpc.Metadata;
import io.grpc.Server;
import io.grpc.Status;
import io.grpc.StatusRuntimeException;
import io.grpc.inprocess.InProcessChannelBuilder;
import io.grpc.inprocess.InProcessServerBuilder;
import io.grpc.stub.StreamObserver;

import antd.v1.ChunkServiceGrpc;
import antd.v1.Chunks.GetChunkRequest;
import antd.v1.Chunks.GetChunkResponse;
import antd.v1.Common;
import antd.v1.PointerServiceGrpc;
import antd.v1.Pointers;

import com.google.protobuf.ByteString;
import com.google.protobuf.Message;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;

import java.math.BigInteger;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The pointer API over gRPC ({@link GrpcAntdClient}) against an in-process
 * mock {@code PointerService}: request shapes, proto conversion (counters up to
 * 2^64 - 1, empty strings and absent messages as {@code null}) and the
 * {@code x-antd-error-code} trailer mapping.
 */
class GrpcPointerTest {

    static final String A = PointerRestTest.A;
    static final String B = PointerRestTest.B;
    static final String T1 = PointerRestTest.T1;
    static final String T2 = PointerRestTest.T2;
    static final String MAX = PointerRestTest.MAX;

    private Server server;
    private ManagedChannel channel;
    private GrpcAntdClient client;
    private MockPointerService pointers;
    private FailingChunkService chunks;

    @BeforeEach
    void setUp() throws Exception {
        String name = InProcessServerBuilder.generateName();
        pointers = new MockPointerService();
        chunks = new FailingChunkService();
        server = InProcessServerBuilder.forName(name)
                .directExecutor()
                .addService(pointers)
                .addService(chunks)
                .build()
                .start();
        channel = InProcessChannelBuilder.forName(name).directExecutor().build();
        client = new GrpcAntdClient(channel);
    }

    @AfterEach
    void tearDown() {
        client.close();
        channel.shutdownNow();
        server.shutdownNow();
    }

    static StatusRuntimeException status(Status.Code code, String message, String tag) {
        Metadata trailers = new Metadata();
        if (tag != null) trailers.put(GrpcAntdClient.ANTD_ERROR_CODE, tag);
        return code.toStatus().withDescription(message).asRuntimeException(trailers);
    }

    static Pointers.PointerFinalState finalState(String target, int holders, String transferredTo) {
        return Pointers.PointerFinalState.newBuilder()
                .setStateId("ee".repeat(32))
                .setKind("pointer")
                .setKindTag(1)
                .setTarget(target)
                .setHolders(holders)
                .setTransferredTo(transferredTo == null ? "" : transferredTo)
                .build();
    }

    /** Canned answers; records the last request; fails every RPC with {@link #error} when set. */
    static final class MockPointerService extends PointerServiceGrpc.PointerServiceImplBase {
        volatile Message last;
        final AtomicInteger calls = new AtomicInteger();
        volatile StatusRuntimeException error;
        volatile Pointers.PointerWriteResponse write = Pointers.PointerWriteResponse.newBuilder()
                .setAddress(A).setStateId(T2).setCounter("0").build();
        volatile Pointers.PointerRecord record = Pointers.PointerRecord.newBuilder()
                .setAddress(A).setOwner("ab").setCounter("0").setKind("chunk").setKindTag(0)
                .setTarget(T1).setStateId(T2).build();
        volatile Pointers.PointerFinality finality = Pointers.PointerFinality.newBuilder()
                .setAddress(A).setGroup(7).setAnswered(7).setStatus("open").build();
        volatile Pointers.PointerTransferResponse transfer = Pointers.PointerTransferResponse.newBuilder()
                .setAddress(A).setStateId(T2).build();
        volatile Pointers.PreparePointerResponse prepare = Pointers.PreparePointerResponse.newBuilder()
                .setUploadId("up-1").setOp("update").setAddress(A).setStateId(T2).setCounter("2")
                .setPaymentType("wave_batch")
                .addPayments(Common.PaymentEntry.newBuilder()
                        .setQuoteHash("0xq1").setRewardsAddress("0xr1").setAmount("123"))
                .setTotalAmount("123").setPaymentVaultAddress("0xvault")
                .setPaymentTokenAddress("0xtoken").setRpcUrl("http://rpc").build();
        volatile Pointers.FinalizePointerResponse finalized = Pointers.FinalizePointerResponse.newBuilder()
                .setAddress(A).setStateId(T2).setCounter("3").build();

        private <T> void reply(Message request, StreamObserver<T> observer, T response) {
            last = request;
            calls.incrementAndGet();
            if (error != null) {
                observer.onError(error);
                return;
            }
            observer.onNext(response);
            observer.onCompleted();
        }

        @Override
        public void listKeys(Pointers.ListPointerKeysRequest req,
                             StreamObserver<Pointers.ListPointerKeysResponse> obs) {
            reply(req, obs, Pointers.ListPointerKeysResponse.newBuilder()
                    .addKeys(Pointers.PointerKey.newBuilder().setAddress(A))
                    .addKeys(Pointers.PointerKey.newBuilder().setAddress(B))
                    .build());
        }

        @Override
        public void create(Pointers.PointerWriteRequest req, StreamObserver<Pointers.PointerWriteResponse> obs) {
            reply(req, obs, write);
        }

        @Override
        public void update(Pointers.PointerWriteRequest req, StreamObserver<Pointers.PointerWriteResponse> obs) {
            reply(req, obs, write);
        }

        @Override
        public void transfer(Pointers.PointerTransferRequest req,
                             StreamObserver<Pointers.PointerTransferResponse> obs) {
            reply(req, obs, transfer);
        }

        @Override
        public void get(Pointers.GetPointerRequest req, StreamObserver<Pointers.PointerRecord> obs) {
            reply(req, obs, record);
        }

        @Override
        public void resolve(Pointers.ResolvePointerRequest req, StreamObserver<Pointers.PointerResolved> obs) {
            reply(req, obs, Pointers.PointerResolved.newBuilder()
                    .setKind("chunk").setKindTag(0).setTarget(T1).build());
        }

        @Override
        public void finality(Pointers.PointerFinalityRequest req, StreamObserver<Pointers.PointerFinality> obs) {
            reply(req, obs, finality);
        }

        @Override
        public void controller(Pointers.PointerControllerRequest req,
                               StreamObserver<Pointers.PointerController> obs) {
            reply(req, obs, Pointers.PointerController.newBuilder()
                    .setPointer(B).addTransfers(B).setFrozen(false).build());
        }

        @Override
        public void prepare(Pointers.PreparePointerRequest req,
                            StreamObserver<Pointers.PreparePointerResponse> obs) {
            reply(req, obs, prepare);
        }

        @Override
        public void finalize(Pointers.FinalizePointerRequest req,
                             StreamObserver<Pointers.FinalizePointerResponse> obs) {
            reply(req, obs, finalized);
        }
    }

    /** A chunk read that fails with a tagged status, to show the mapping is not pointer-only. */
    static final class FailingChunkService extends ChunkServiceGrpc.ChunkServiceImplBase {
        volatile StatusRuntimeException error;

        @Override
        public void get(GetChunkRequest req, StreamObserver<GetChunkResponse> obs) {
            obs.onError(error);
        }
    }

    // ── Reads ──

    @Test
    void keysListsAddresses() {
        assertEquals(List.of(A, B), client.pointerKeys());
        assertInstanceOf(Pointers.ListPointerKeysRequest.class, pointers.last);
    }

    @Test
    void getConvertsAFinalTransferredRecord() {
        pointers.record = pointers.record.toBuilder()
                .setCounter(MAX).setKind("pointer").setKindTag(1).setTarget(B)
                .setIsFinal(true).setTransferredTo(B).build();
        PointerRecord r = client.pointerGet(A);
        assertEquals(A, ((Pointers.GetPointerRequest) pointers.last).getAddress());
        assertEquals(PointerRecord.FINAL_COUNTER, r.counter());
        assertTrue(r.isFinal());
        assertEquals(B, r.transferredTo());
        assertEquals(PointerTargetKind.POINTER, r.targetKind().orElseThrow());
        assertEquals("ab", r.owner());
    }

    @Test
    void anEmptyTransferIsNull() {
        PointerRecord r = client.pointerGet(A);
        assertEquals(BigInteger.ZERO, r.counter());
        assertFalse(r.isFinal());
        assertNull(r.transferredTo());
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "-1", "+1", "1.0", " 1", "0x10", "18446744073709551616", "٣", "abc"})
    void aMalformedCounterIsAnErrorNotZero(String counter) {
        pointers.record = pointers.record.toBuilder().setCounter(counter).build();
        assertThrows(AntdException.class, () -> client.pointerGet(A));
        pointers.write = pointers.write.toBuilder().setCounter(counter).build();
        assertThrows(AntdException.class, () -> client.pointerUpdate(A, T1));
    }

    @Test
    void resolveReturnsTheEndOfTheChain() {
        assertEquals(new PointerTarget("chunk", 0, T1), client.pointerResolve(A));
        assertEquals(A, ((Pointers.ResolvePointerRequest) pointers.last).getAddress());
    }

    @Test
    void finalityOpenWithoutACounterHasNullsForEveryUnsetValue() {
        PointerFinality f = client.pointerFinality(A);
        assertEquals(A, ((Pointers.PointerFinalityRequest) pointers.last).getAddress());
        assertEquals(PointerFinalityStatus.OPEN, f.status());
        assertEquals("open", f.rawStatus());
        assertNull(f.counter());
        assertNull(f.state());
        assertTrue(f.states().isEmpty());
        assertNull(f.majority());
        assertNull(f.transferredTo());
    }

    @Test
    void finalityOpenWithACounter() {
        pointers.finality = pointers.finality.toBuilder().setCounter("4").build();
        assertEquals(BigInteger.valueOf(4), client.pointerFinality(A).counter());
    }

    @Test
    void finalityFinalAndForked() {
        pointers.finality = pointers.finality.toBuilder()
                .setStatus("final").setState(finalState(B, 7, B)).setTransferredTo(B).build();
        PointerFinality f = client.pointerFinality(A);
        assertTrue(f.isFinal());
        assertEquals(7, f.state().holders());
        assertEquals(B, f.state().transferredTo());
        assertEquals(B, f.transferredTo());

        pointers.finality = Pointers.PointerFinality.newBuilder()
                .setAddress(A).setGroup(7).setAnswered(7).setStatus("forked")
                .addStates(finalState(T1, 4, null)).addStates(finalState(T2, 3, null))
                .setMajority(finalState(T1, 4, null)).build();
        f = client.pointerFinality(A);
        assertEquals(PointerFinalityStatus.FORKED, f.status());
        assertEquals(2, f.states().size());
        assertNull(f.states().get(0).transferredTo());
        assertEquals(T1, f.majority().target());
        assertNull(f.state());
    }

    @Test
    void aStatusFromANewerDaemonIsUnknownAndKept() {
        pointers.finality = pointers.finality.toBuilder().setStatus("wobbly").build();
        PointerFinality f = client.pointerFinality(A);
        assertEquals(PointerFinalityStatus.UNKNOWN, f.status());
        assertEquals("wobbly", f.rawStatus());
    }

    @Test
    void controllerFollowsTransfers() {
        assertEquals(new PointerController(B, List.of(B), false), client.pointerController(A));
    }

    // ── Writes ──

    @Test
    void createAndUpdateSendOwnerTargetAndKind() {
        assertEquals(new PointerWriteResult(A, T2, BigInteger.ZERO), client.pointerCreate(A, T1));
        Pointers.PointerWriteRequest req = (Pointers.PointerWriteRequest) pointers.last;
        assertEquals(A, req.getOwner());
        assertEquals(T1, req.getTarget());
        assertEquals("chunk", req.getKind());

        pointers.write = pointers.write.toBuilder().setCounter("1").build();
        assertEquals(BigInteger.ONE, client.pointerUpdate(A, B, PointerTargetKind.POINTER).counter());
        assertEquals("pointer", ((Pointers.PointerWriteRequest) pointers.last).getKind());

        client.pointerUpdate(A, T1, null);
        assertEquals("chunk", ((Pointers.PointerWriteRequest) pointers.last).getKind());
    }

    @Test
    void transferWithAndWithoutFinality() {
        pointers.transfer = pointers.transfer.toBuilder()
                .setFinality(Pointers.PointerFinality.newBuilder()
                        .setAddress(A).setGroup(7).setAnswered(7).setStatus("final")
                        .setState(finalState(B, 7, B)).setTransferredTo(B))
                .build();
        PointerTransferResult t = client.pointerTransfer(A, B);
        Pointers.PointerTransferRequest req = (Pointers.PointerTransferRequest) pointers.last;
        assertEquals(A, req.getOwner());
        assertEquals(B, req.getRecipient());
        assertTrue(t.finality().isFinal());
        assertNull(t.finalityError());

        pointers.transfer = Pointers.PointerTransferResponse.newBuilder()
                .setAddress(A).setStateId(T2).setFinalityError("only 3 of 7 answered").build();
        t = client.pointerTransfer(A, B);
        assertNull(t.finality());
        assertEquals("only 3 of 7 answered", t.finalityError());
    }

    // ── External signer ──

    @Test
    void prepareUpdateSendsTheOpAndConvertsThePayment() {
        PointerPrepareResult p = client.pointerPrepare(A, PointerOp.update(T1, PointerTargetKind.CHUNK));
        Pointers.PreparePointerRequest req = (Pointers.PreparePointerRequest) pointers.last;
        assertEquals(A, req.getOwner());
        assertEquals("update", req.getOp());
        assertEquals(T1, req.getTarget());
        assertEquals("chunk", req.getKind());
        assertEquals("", req.getRecipient());
        assertFalse(req.getIncludeSignedQuotes());
        assertEquals("up-1", p.uploadId());
        assertEquals(BigInteger.TWO, p.counter());
        assertEquals(List.of(new PaymentInfo("0xq1", "0xr1", "123")), p.payments());
        assertEquals("wave_batch", p.paymentType());
        assertEquals("http://rpc", p.rpcUrl());
        assertTrue(p.signedQuotes().isEmpty());
    }

    @Test
    void prepareTransferSendsOnlyTheRecipientAndBase64sSignedQuotes() {
        pointers.prepare = pointers.prepare.toBuilder()
                .setOp("transfer").setCounter(MAX)
                .addSignedQuotes(Common.SignedQuoteEntry.newBuilder()
                        .setQuoteHash("0xq1").setQuote(ByteString.copyFromUtf8("quote")))
                .addSignedQuotes(Common.SignedQuoteEntry.newBuilder()
                        .setQuoteHash("0xq2").setQuote(ByteString.copyFromUtf8("q2"))
                        .setCommitmentSidecar(ByteString.copyFromUtf8("side")))
                .build();
        PointerPrepareResult p = client.pointerPrepare(A, PointerOp.transfer(B), new PointerPrepareOptions(true));
        Pointers.PreparePointerRequest req = (Pointers.PreparePointerRequest) pointers.last;
        assertEquals("transfer", req.getOp());
        assertEquals(B, req.getRecipient());
        assertEquals("", req.getTarget());
        assertEquals("", req.getKind());
        assertTrue(req.getIncludeSignedQuotes());
        assertEquals(PointerRecord.FINAL_COUNTER, p.counter());
        // The same base64 strings the REST transport returns.
        assertEquals(List.of(
                new SignedQuoteEntry("0xq1", "cXVvdGU=", null),
                new SignedQuoteEntry("0xq2", "cTI=", "c2lkZQ==")), p.signedQuotes());
    }

    @Test
    void finalizeSendsTheUploadIdAndTxHashes() {
        PointerFinalizeResult f = client.pointerFinalize("up-1", Map.of("0xq1", "0xt1"));
        Pointers.FinalizePointerRequest req = (Pointers.FinalizePointerRequest) pointers.last;
        assertEquals("up-1", req.getUploadId());
        assertEquals(Map.of("0xq1", "0xt1"), req.getTxHashesMap());
        assertEquals(new PointerFinalizeResult(A, T2, BigInteger.valueOf(3), null), f);

        pointers.finalized = pointers.finalized.toBuilder().setCounter(MAX)
                .setFinality(Pointers.PointerFinality.newBuilder().setAddress(A).setStatus("settling")
                        .setState(finalState(B, 2, B)))
                .build();
        f = client.pointerFinalize("up-1", null);
        assertEquals(PointerFinalityStatus.SETTLING, f.finality().status());
        assertTrue(((Pointers.FinalizePointerRequest) pointers.last).getTxHashesMap().isEmpty());
    }

    // ── Errors ──

    static final String RETAINED =
            "Close group shortfall: stored on 4 of 5 (paid attempt retained: call finalize again with the "
                    + "same upload_id to store it against the same payment)";

    static Stream<Arguments> statuses() {
        return Stream.of(
                // The tag decides, when it agrees with the code.
                Arguments.of(Status.Code.FAILED_PRECONDITION, "final", "POINTER_FINAL", PointerFinalException.class),
                Arguments.of(Status.Code.FAILED_PRECONDITION, "forked", "POINTER_FORKED", ForkException.class),
                Arguments.of(Status.Code.ABORTED, "pending", "CONFLICT", ConflictException.class),
                Arguments.of(Status.Code.UNAVAILABLE, "short", "CLOSE_GROUP_SHORTFALL",
                        CloseGroupShortfallException.class),
                // Untagged, or tagged in disagreement with the code: the code decides.
                Arguments.of(Status.Code.FAILED_PRECONDITION, "no wallet", null, PaymentException.class),
                Arguments.of(Status.Code.FAILED_PRECONDITION, "x", "CONFLICT", PaymentException.class),
                Arguments.of(Status.Code.FAILED_PRECONDITION, "x", "CLOSE_GROUP_SHORTFALL", PaymentException.class),
                Arguments.of(Status.Code.UNAVAILABLE, "x", "POINTER_FINAL", NetworkException.class),
                Arguments.of(Status.Code.UNAVAILABLE, "x", "SOMETHING_NEW", NetworkException.class),
                Arguments.of(Status.Code.UNAVAILABLE, "x", null, NetworkException.class),
                Arguments.of(Status.Code.ABORTED, "x", "POINTER_FINAL", AntdException.class),
                Arguments.of(Status.Code.ALREADY_EXISTS, "exists", null, AlreadyExistsException.class),
                Arguments.of(Status.Code.ALREADY_EXISTS, "exists", "CONFLICT", AlreadyExistsException.class),
                Arguments.of(Status.Code.NOT_FOUND, "none", null, NotFoundException.class),
                Arguments.of(Status.Code.INVALID_ARGUMENT, "no key", null, BadRequestException.class));
    }

    @ParameterizedTest
    @MethodSource("statuses")
    void errorsMapByTheTrailerWhenItAgreesWithTheCode(
            Status.Code code, String message, String tag, Class<? extends AntdException> expected) {
        pointers.error = status(code, message, tag);
        AntdException e = assertThrows(AntdException.class, () -> client.pointerUpdate(A, T1));
        assertEquals(expected, e.getClass());
        assertTrue(e.getMessage().contains(message), e.getMessage());
    }

    @Test
    void aShortfallIsRetryableOnlyWithTheClosingRetainedHint() {
        pointers.error = status(Status.Code.UNAVAILABLE, RETAINED, "CLOSE_GROUP_SHORTFALL");
        CloseGroupShortfallException e = assertThrows(CloseGroupShortfallException.class,
                () -> client.pointerFinalize("up-1", Map.of()));
        assertTrue(e.isRetryable());
        assertEquals(503, e.getStatusCode());

        for (String msg : List.of(
                "Close group shortfall: only 3 of 7 answered",
                RETAINED + " and then some",
                RETAINED + "\n",
                "Close group shortfall: (paid attempt retained (nested))")) {
            pointers.error = status(Status.Code.UNAVAILABLE, msg, "CLOSE_GROUP_SHORTFALL");
            e = assertThrows(CloseGroupShortfallException.class, () -> client.pointerFinalize("up-1", Map.of()));
            assertFalse(e.isRetryable(), msg);
        }
    }

    @Test
    void anUntaggedPartialUploadIsStillAPartialUpload() {
        pointers.error = status(Status.Code.ABORTED,
                "Partial upload: 3/5 chunks stored, 2 failed after retries: x (paid attempt retained: again)", null);
        PartialUploadException e = assertThrows(PartialUploadException.class,
                () -> client.pointerFinalize("up-1", Map.of()));
        assertTrue(e.isRetryable());
    }

    @Test
    void theTrailerMappingAppliesToEveryRpc() {
        chunks.error = status(Status.Code.UNAVAILABLE, "only 3 answered", "CLOSE_GROUP_SHORTFALL");
        CloseGroupShortfallException e = assertThrows(CloseGroupShortfallException.class,
                () -> client.chunkGet(T1));
        assertFalse(e.isRetryable());
    }

    @Test
    void aFailedPaidWriteIsSentExactlyOnce() {
        pointers.error = status(Status.Code.UNAVAILABLE, "short", "CLOSE_GROUP_SHORTFALL");
        assertThrows(CloseGroupShortfallException.class, () -> client.pointerCreate(A, T1));
        assertThrows(CloseGroupShortfallException.class, () -> client.pointerUpdate(A, T1));
        assertThrows(CloseGroupShortfallException.class, () -> client.pointerTransfer(A, B));
        assertThrows(CloseGroupShortfallException.class, () -> client.pointerFinalize("up-1", Map.of()));
        assertEquals(4, pointers.calls.get());
    }
}
