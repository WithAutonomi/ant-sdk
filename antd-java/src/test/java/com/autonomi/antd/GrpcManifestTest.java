package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;

import io.grpc.CallOptions;
import io.grpc.Channel;
import io.grpc.ClientCall;
import io.grpc.ClientInterceptor;
import io.grpc.Grpc;
import io.grpc.InsecureChannelCredentials;
import io.grpc.InsecureServerCredentials;
import io.grpc.ManagedChannel;
import io.grpc.MethodDescriptor;
import io.grpc.Server;
import io.grpc.Status;
import io.grpc.StatusRuntimeException;
import io.grpc.inprocess.InProcessChannelBuilder;
import io.grpc.inprocess.InProcessServerBuilder;
import io.grpc.stub.StreamObserver;

import antd.v1.ManifestServiceGrpc;
import antd.v1.Manifests;

import com.google.protobuf.ByteString;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The manifest API over gRPC ({@link GrpcAntdClient}) against a mock
 * {@code ManifestService}: request shapes (raw bytes, proto3 optional
 * presence), unset sizes reading as {@code null} (not 0), the checks made
 * before sending, the error mapping, and the per-call message limits.
 */
class GrpcManifestTest {

    static final byte[] HEADER = ManifestRestTest.HEADER;
    static final String LINK = ManifestRestTest.LINK;
    static final String ADDR = ManifestRestTest.ADDR;

    private Server server;
    private ManagedChannel channel;
    private GrpcAntdClient client;
    private MockManifestService manifests;
    /** CallOptions of every call, by full method name. */
    private final Map<String, CallOptions> seen = new ConcurrentHashMap<>();

    @BeforeEach
    void setUp() throws Exception {
        String name = InProcessServerBuilder.generateName();
        manifests = new MockManifestService();
        server = InProcessServerBuilder.forName(name)
                .directExecutor()
                .addService(manifests)
                .build()
                .start();
        channel = InProcessChannelBuilder.forName(name)
                .directExecutor()
                .intercept(new CallOptionsRecorder(seen))
                .build();
        client = new GrpcAntdClient(channel);
    }

    @AfterEach
    void tearDown() {
        client.close();
        channel.shutdownNow();
        server.shutdownNow();
    }

    /** Records each call's CallOptions, as the stub hands them to the channel. */
    static final class CallOptionsRecorder implements ClientInterceptor {
        private final Map<String, CallOptions> seen;

        CallOptionsRecorder(Map<String, CallOptions> seen) {
            this.seen = seen;
        }

        @Override
        public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(
                MethodDescriptor<ReqT, RespT> method, CallOptions callOptions, Channel next) {
            seen.put(method.getFullMethodName(), callOptions);
            return next.newCall(method, callOptions);
        }
    }

    /** Canned answers; records the last request; fails every RPC with {@link #error} when set. */
    static final class MockManifestService extends ManifestServiceGrpc.ManifestServiceImplBase {
        volatile Manifests.BuildManifestRequest lastBuild;
        volatile Manifests.DecodeManifestRequest lastDecode;
        final AtomicInteger calls = new AtomicInteger();
        volatile StatusRuntimeException error;
        volatile Manifests.BuildManifestResponse build = Manifests.BuildManifestResponse.newBuilder()
                .setManifest(ByteString.copyFrom(HEADER))
                .setLink(LINK)
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName("a.txt").setPath("a.txt").setSize(10).setKind("embedded")
                        .setContentAddress("cc").setExactSize(10))
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName(ADDR).setKind("public").setContentAddress(ADDR))
                .build();
        volatile Manifests.DecodeManifestResponse decode = Manifests.DecodeManifestResponse.newBuilder()
                .setSource("manifest")
                .setName("album")
                .setTorrentInfoHashV2("bb")
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName("a.txt").setPath("a.txt").setKind("embedded")
                        .setContentAddress("cc").setDataMap("abcd").setExactSize(3))
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName("b").setPath("b").setKind("public").setContentAddress("dd")
                        .setError("Record not found: gone"))
                .build();

        @Override
        public void build(Manifests.BuildManifestRequest req, StreamObserver<Manifests.BuildManifestResponse> obs) {
            calls.incrementAndGet();
            lastBuild = req;
            if (error != null) {
                obs.onError(error);
                return;
            }
            obs.onNext(build);
            obs.onCompleted();
        }

        @Override
        public void decode(Manifests.DecodeManifestRequest req, StreamObserver<Manifests.DecodeManifestResponse> obs) {
            calls.incrementAndGet();
            lastDecode = req;
            if (error != null) {
                obs.onError(error);
                return;
            }
            obs.onNext(decode);
            obs.onCompleted();
        }
    }

    static List<ManifestEntryInput> twoEntries() {
        return ManifestRestTest.twoEntries();
    }

    // ── Build ──

    @Test
    void buildSendsEntriesWithPresence() {
        client.buildManifest(twoEntries(), BuildManifestOptions.DEFAULT.withName("album"));
        Manifests.BuildManifestRequest req = manifests.lastBuild;
        assertTrue(req.hasName());
        assertEquals("album", req.getName());
        assertTrue(req.hasEmbedRoots(), "embed_roots is sent explicitly");
        assertTrue(req.getEmbedRoots(), "embed_roots should default to true");
        assertEquals(0, req.getTorrentInfoHashesCount());
        assertEquals(2, req.getEntriesCount());

        Manifests.ManifestEntryInput first = req.getEntries(0);
        assertTrue(first.hasPath());
        assertEquals("a.txt", first.getPath());
        assertTrue(first.hasSize());
        assertEquals(10, first.getSize());
        assertEquals(Manifests.ManifestEntryInput.SourceCase.DATA_MAP, first.getSourceCase());
        assertEquals("abcd", first.getDataMap());

        Manifests.ManifestEntryInput second = req.getEntries(1);
        assertFalse(second.hasPath(), "an unset path must not be sent");
        assertFalse(second.hasSize(), "an unset size must not be sent as 0");
        assertEquals(Manifests.ManifestEntryInput.SourceCase.ADDRESS, second.getSourceCase());
        assertEquals(ADDR, second.getAddress());
    }

    @Test
    void buildOptionsMapOntoTheRequest() {
        List<String> hashes = List.of("aa".repeat(20), "bb".repeat(32));
        client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR)),
                new BuildManifestOptions("", hashes, true));
        Manifests.BuildManifestRequest req = manifests.lastBuild;
        assertFalse(req.hasName(), "an empty name must not be sent");
        assertTrue(req.hasEmbedRoots());
        assertFalse(req.getEmbedRoots());
        assertEquals(hashes, req.getTorrentInfoHashesList());

        client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR)), null);
        assertTrue(manifests.lastBuild.getEmbedRoots());
        assertFalse(manifests.lastBuild.hasName());
    }

    @Test
    void buildReturnsRawBytesAndReadsUnsetSizesAsNull() {
        BuiltManifest b = client.buildManifest(twoEntries());
        assertArrayEquals(HEADER, b.manifest());
        assertEquals(LINK, b.link());
        assertEquals(new ManifestEntryInfo("a.txt", "a.txt", 10L, "embedded", "cc", null, 10L, null),
                b.entries().get(0));
        ManifestEntryInfo p = b.entries().get(1);
        assertEquals(new ManifestEntryInfo(ADDR, null, null, "public", ADDR, null, null, null), p);
    }

    @Test
    void zeroSizesArePresentAndAnEmptyLinkIsNull() {
        manifests.build = Manifests.BuildManifestResponse.newBuilder()
                .setManifest(ByteString.copyFrom(HEADER))
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName("e").setPath("e").setSize(0).setKind("embedded")
                        .setContentAddress("cc").setExactSize(0))
                .build();
        BuiltManifest b = client.buildManifest(List.of(ManifestEntryInput.ofDataMap("ab").withSize(0L)));
        assertTrue(manifests.lastBuild.getEntries(0).hasSize(), "a zero size is still sent");
        assertNull(b.link());
        assertEquals(0L, b.entries().get(0).size());
        assertEquals(0L, b.entries().get(0).exactSize());
    }

    @Test
    void invalidInputIsRefusedLikeTheDaemonBeforeSending() {
        ManifestRestTest.assertRefused("1 invalid entries: entries[0]: needs a data_map or an address",
                assertThrows(BadRequestException.class,
                        () -> client.buildManifest(List.of(new ManifestEntryInput("p", null, null, null)))));
        ManifestRestTest.assertRefused("2 invalid entries: entries[0]: give data_map or address, not both; "
                        + "entries[1]: needs a data_map or an address",
                assertThrows(BadRequestException.class, () -> client.buildManifest(List.of(
                        new ManifestEntryInput(null, null, "aa", ADDR),
                        new ManifestEntryInput(null, null, null, null)))));
        ManifestRestTest.assertRefused("1 invalid entries: entries[0]: size must not be negative, got -5",
                assertThrows(BadRequestException.class,
                        () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withSize(-5L)))));
        String empty = "needs a manifest (base64 .ant bytes) or a link";
        ManifestRestTest.assertRefused(empty,
                assertThrows(BadRequestException.class, () -> client.decodeManifest(new byte[0], true)));
        ManifestRestTest.assertRefused(empty,
                assertThrows(BadRequestException.class, () -> client.decodeManifestLink("", true)));
        assertEquals(0, manifests.calls.get(), "nothing may be sent for invalid input");
    }

    @Test
    void invalidArgumentIsABadRequestWithTheDaemonsMessage() {
        manifests.error = Status.INVALID_ARGUMENT
                .withDescription("1 invalid entries: entries[0]: invalid path \"../x\": a component is \"..\"")
                .asRuntimeException();
        BadRequestException e = assertThrows(BadRequestException.class,
                () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withPath("../x"))));
        assertTrue(e.getMessage().contains("entries[0]: invalid path \"../x\""), e.getMessage());

        manifests.error = Status.INVALID_ARGUMENT.withDescription("not a manifest").asRuntimeException();
        assertThrows(BadRequestException.class, () -> client.decodeManifest(HEADER, false));
    }

    // ── Decode ──

    @Test
    void decodeSendsRawBytes() {
        DecodedManifest d = client.decodeManifest(HEADER, true);
        Manifests.DecodeManifestRequest req = manifests.lastDecode;
        assertEquals(Manifests.DecodeManifestRequest.InputCase.MANIFEST, req.getInputCase());
        assertArrayEquals(HEADER, req.getManifest().toByteArray(), "gRPC carries raw bytes, not base64");
        assertTrue(req.getResolve());

        assertEquals("manifest", d.source());
        assertEquals("album", d.name());
        assertNull(d.torrentInfoHashV1(), "an empty hash reads as null");
        assertEquals("bb", d.torrentInfoHashV2());
        ManifestEntryInfo a = d.entries().get(0);
        assertEquals("abcd", a.dataMap());
        assertEquals(3L, a.exactSize());
        assertNull(a.size());
        assertNull(a.error());
        ManifestEntryInfo b = d.entries().get(1);
        assertEquals("Record not found: gone", b.error());
        assertNull(b.exactSize());
        assertNull(b.dataMap());
    }

    @Test
    void decodeLinkSendsTheLink() {
        manifests.decode = Manifests.DecodeManifestResponse.newBuilder()
                .setSource("file_link")
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName(ADDR).setKind("public").setContentAddress(ADDR))
                .build();
        DecodedManifest d = client.decodeManifestLink(ADDR, false);
        Manifests.DecodeManifestRequest req = manifests.lastDecode;
        assertEquals(Manifests.DecodeManifestRequest.InputCase.LINK, req.getInputCase());
        assertEquals(ADDR, req.getLink());
        assertFalse(req.getResolve());
        assertEquals(DecodedManifest.SOURCE_FILE_LINK, d.source());
        assertNull(d.name());
        assertEquals(1, d.entries().size());
        assertNull(d.entries().get(0).path());
        assertNull(d.entries().get(0).exactSize());
    }

    // ── Message limits ──

    @Test
    void everyManifestCallRaisesItsMessageLimits() {
        client.buildManifest(twoEntries());
        client.decodeManifest(HEADER, false);
        client.decodeManifestLink(LINK, false);
        for (String method : List.of(
                ManifestServiceGrpc.getBuildMethod().getFullMethodName(),
                ManifestServiceGrpc.getDecodeMethod().getFullMethodName())) {
            CallOptions o = seen.get(method);
            assertNotNull(o, "no call to " + method);
            assertEquals(256 * 1024 * 1024, o.getMaxInboundMessageSize(), method);
            assertEquals(100 * 1024 * 1024, o.getMaxOutboundMessageSize(), method);
        }
        assertEquals(ManifestWire.MAX_GRPC_INBOUND_MESSAGE_BYTES, 256 * 1024 * 1024);
        assertEquals(ManifestWire.MAX_GRPC_OUTBOUND_MESSAGE_BYTES, 100 * 1024 * 1024);
    }

    /**
     * Over a real socket, where gRPC enforces its 4 MiB default: a 5 MiB
     * manifest comes back through the client, while a plain stub on the same
     * channel is refused it.
     */
    @Test
    void aManifestPastFourMibArrivesOverARealSocket() throws Exception {
        byte[] big = new byte[5 * 1024 * 1024];
        for (int i = 0; i < big.length; i++) big[i] = (byte) (i * 31);
        MockManifestService svc = new MockManifestService();
        svc.build = Manifests.BuildManifestResponse.newBuilder().setManifest(ByteString.copyFrom(big)).build();
        svc.decode = Manifests.DecodeManifestResponse.newBuilder()
                .setSource("manifest")
                .addEntries(Manifests.ManifestEntryInfo.newBuilder()
                        .setEffectiveName("x").setKind("embedded").setContentAddress("cc")
                        .setDataMap("ab".repeat(big.length / 2)))
                .build();
        Server real = Grpc.newServerBuilderForPort(0, InsecureServerCredentials.create())
                .addService(svc)
                .maxInboundMessageSize(ManifestWire.MAX_GRPC_OUTBOUND_MESSAGE_BYTES)
                .build()
                .start();
        ManagedChannel ch = Grpc.newChannelBuilderForAddress("127.0.0.1", real.getPort(),
                InsecureChannelCredentials.create()).build();
        try (GrpcAntdClient c = new GrpcAntdClient(ch)) {
            assertArrayEquals(big, c.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR))).manifest());

            // Decode sends the 5 MiB back, and gets a 5 MiB hex DataMap.
            DecodedManifest d = c.decodeManifest(big, false);
            assertArrayEquals(big, svc.lastDecode.getManifest().toByteArray());
            assertEquals(big.length, d.entries().get(0).dataMap().length());

            // The control: gRPC's default limit refuses the same response.
            StatusRuntimeException e = assertThrows(StatusRuntimeException.class,
                    () -> ManifestServiceGrpc.newBlockingStub(ch).build(
                            Manifests.BuildManifestRequest.getDefaultInstance()));
            assertEquals(Status.Code.RESOURCE_EXHAUSTED, e.getStatus().getCode());
        } finally {
            real.shutdownNow();
            real.awaitTermination(5, TimeUnit.SECONDS);
        }
    }

    @Test
    void entryListsAreUnmodifiable() {
        BuiltManifest b = client.buildManifest(twoEntries());
        assertThrows(UnsupportedOperationException.class, () -> b.entries().add(null));
        DecodedManifest d = client.decodeManifest(HEADER, false);
        assertThrows(UnsupportedOperationException.class, () -> d.entries().add(null));
    }
}
