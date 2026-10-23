package com.autonomi.antd;

import com.autonomi.antd.errors.BadRequestException;
import com.autonomi.antd.models.*;

import io.grpc.ManagedChannel;
import io.grpc.Server;
import io.grpc.Status;
import io.grpc.StatusRuntimeException;
import io.grpc.inprocess.InProcessChannelBuilder;
import io.grpc.inprocess.InProcessServerBuilder;
import io.grpc.stub.StreamObserver;

import antd.v1.Data;
import antd.v1.DataServiceGrpc;
import antd.v1.FileServiceGrpc;
import antd.v1.Files;
import antd.v1.ManifestServiceGrpc;
import antd.v1.Manifests;
import antd.v1.Upload;
import antd.v1.UploadServiceGrpc;

import com.google.protobuf.ByteString;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The {@code sha256} fields (antd 0.17.0) over gRPC against mock services:
 * each upload result reads the field and maps the empty string to
 * {@code null}; a manifest entry sets the proto3 {@code optional} field only
 * when given; entry info reads {@code ""} as none.
 */
class Sha256GrpcTest {

    static final String SHA = Sha256RestTest.SHA;
    static final String ADDR = ManifestRestTest.ADDR;

    /** What every mock upload RPC answers in its {@code sha256}. */
    private volatile String answer = SHA;
    private volatile Manifests.BuildManifestRequest lastBuild;
    private volatile Manifests.BuildManifestResponse build;
    private volatile Manifests.DecodeManifestResponse decode;
    private volatile StatusRuntimeException buildError;

    private Server server;
    private ManagedChannel channel;
    private GrpcAntdClient client;

    @BeforeEach
    void setUp() throws Exception {
        String name = InProcessServerBuilder.generateName();
        server = InProcessServerBuilder.forName(name)
                .directExecutor()
                .addService(new DataServiceGrpc.DataServiceImplBase() {
                    @Override
                    public void put(Data.PutDataRequest req, StreamObserver<Data.PutDataResponse> obs) {
                        obs.onNext(Data.PutDataResponse.newBuilder().setDataMap("dm").setChunksStored(3)
                                .setSha256(answer).build());
                        obs.onCompleted();
                    }

                    @Override
                    public void putPublic(Data.PutPublicDataRequest req,
                                          StreamObserver<Data.PutPublicDataResponse> obs) {
                        obs.onNext(Data.PutPublicDataResponse.newBuilder().setAddress("a").setChunksStored(3)
                                .setSha256(answer).build());
                        obs.onCompleted();
                    }
                })
                .addService(new FileServiceGrpc.FileServiceImplBase() {
                    @Override
                    public void put(Files.PutFileRequest req, StreamObserver<Files.PutFileResponse> obs) {
                        obs.onNext(Files.PutFileResponse.newBuilder().setDataMap("dm").setChunksStored(3)
                                .setSha256(answer).build());
                        obs.onCompleted();
                    }

                    @Override
                    public void putPublic(Files.PutFileRequest req,
                                          StreamObserver<Files.PutFilePublicResponse> obs) {
                        obs.onNext(Files.PutFilePublicResponse.newBuilder().setAddress("a").setChunksStored(3)
                                .setSha256(answer).build());
                        obs.onCompleted();
                    }
                })
                .addService(new UploadServiceGrpc.UploadServiceImplBase() {
                    @Override
                    public void finalizeUpload(Upload.FinalizeUploadRequest req,
                                               StreamObserver<Upload.FinalizeUploadResponse> obs) {
                        obs.onNext(Upload.FinalizeUploadResponse.newBuilder().setChunksStored(2)
                                .setSha256(answer).build());
                        obs.onCompleted();
                    }
                })
                .addService(new ManifestServiceGrpc.ManifestServiceImplBase() {
                    @Override
                    public void build(Manifests.BuildManifestRequest req,
                                      StreamObserver<Manifests.BuildManifestResponse> obs) {
                        lastBuild = req;
                        if (buildError != null) {
                            obs.onError(buildError);
                            return;
                        }
                        obs.onNext(build);
                        obs.onCompleted();
                    }

                    @Override
                    public void decode(Manifests.DecodeManifestRequest req,
                                       StreamObserver<Manifests.DecodeManifestResponse> obs) {
                        obs.onNext(decode);
                        obs.onCompleted();
                    }
                })
                .build()
                .start();
        channel = InProcessChannelBuilder.forName(name).directExecutor().build();
        client = new GrpcAntdClient(channel);

        Manifests.ManifestEntryInfo withHash = Manifests.ManifestEntryInfo.newBuilder()
                .setEffectiveName("a.txt").setPath("a.txt").setKind("public").setContentAddress(ADDR)
                .setSha256(SHA).build();
        // Plain string: the daemon sends "" for none.
        Manifests.ManifestEntryInfo without = Manifests.ManifestEntryInfo.newBuilder()
                .setEffectiveName("b.txt").setPath("b.txt").setKind("public").setContentAddress(ADDR)
                .setSha256("").build();
        build = Manifests.BuildManifestResponse.newBuilder()
                .setManifest(ByteString.copyFrom(ManifestRestTest.HEADER)).setLink(ManifestRestTest.LINK)
                .addEntries(withHash).addEntries(without).build();
        decode = Manifests.DecodeManifestResponse.newBuilder().setSource("manifest")
                .addEntries(withHash).addEntries(without).build();
    }

    @AfterEach
    void tearDown() {
        client.close();
        channel.shutdownNow();
        server.shutdownNow();
    }

    @Test
    void uploadResultsReadSha256() {
        assertEquals(SHA, client.dataPut("x".getBytes()).sha256());
        assertEquals(SHA, client.dataPutPublic("x".getBytes()).sha256());
        assertEquals(SHA, client.filePut("/tmp/x").sha256());
        assertEquals(SHA, client.filePutPublic("/tmp/x").sha256());
        assertEquals(SHA, client.finalizeUpload("up1", Map.of("q", "t")).sha256());
        assertEquals(SHA, client.finalizeMerkleUpload("up1", "0xwin").sha256());
        // The other fields still map.
        assertEquals("dm", client.dataPut("x".getBytes()).dataMap());
        assertEquals(3L, client.filePutPublic("/tmp/x").chunksStored());
    }

    @Test
    void anEmptySha256ReadsAsNone() {
        answer = "";
        assertNull(client.dataPut("x".getBytes()).sha256());
        assertNull(client.dataPutPublic("x".getBytes()).sha256());
        assertNull(client.filePut("/tmp/x").sha256());
        assertNull(client.filePutPublic("/tmp/x").sha256());
        assertNull(client.finalizeUpload("up1", Map.of("q", "t")).sha256());
        assertNull(client.finalizeMerkleUpload("up1", "0xwin").sha256());
    }

    @Test
    void buildSetsSha256OnlyWhenGiven() {
        client.buildManifest(List.of(
                ManifestEntryInput.ofAddress(ADDR).withSha256(SHA),
                ManifestEntryInput.ofAddress(ADDR),
                ManifestEntryInput.ofAddress(ADDR).withSha256("")));
        Manifests.BuildManifestRequest req = lastBuild;
        assertTrue(req.getEntries(0).hasSha256());
        assertEquals(SHA, req.getEntries(0).getSha256());
        assertFalse(req.getEntries(1).hasSha256(), "an unset sha256 must not be sent");
        assertFalse(req.getEntries(2).hasSha256(), "an empty sha256 must not be sent");
    }

    @Test
    void buildAndDecodeReadSha256OrNone() {
        List<ManifestEntryInfo> built = client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR))).entries();
        assertEquals(SHA, built.get(0).sha256());
        assertNull(built.get(1).sha256(), "an empty string on the wire reads as none");

        List<ManifestEntryInfo> decoded = client.decodeManifestLink(ManifestRestTest.LINK, false).entries();
        assertEquals(SHA, decoded.get(0).sha256());
        assertNull(decoded.get(1).sha256());
    }

    @Test
    void aBadSha256IsABadRequestWithTheDaemonsMessage() {
        buildError = Status.INVALID_ARGUMENT
                .withDescription("entries[0]: sha256 must be 32 bytes, got 1").asRuntimeException();
        BadRequestException e = assertThrows(BadRequestException.class,
                () -> client.buildManifest(List.of(ManifestEntryInput.ofAddress(ADDR).withSha256("ab"))));
        assertEquals(400, e.getStatusCode());
        assertTrue(e.getMessage().contains("entries[0]: sha256 must be 32 bytes, got 1"), e.getMessage());
    }
}
