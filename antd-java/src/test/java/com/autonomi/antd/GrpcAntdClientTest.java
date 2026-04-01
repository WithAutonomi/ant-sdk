package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;

import io.grpc.*;
import io.grpc.inprocess.InProcessChannelBuilder;
import io.grpc.inprocess.InProcessServerBuilder;
import io.grpc.stub.StreamObserver;
// GrpcCleanupRule is JUnit4 only — we manage cleanup manually with @AfterEach

import antd.v1.HealthServiceGrpc;
import antd.v1.Health.HealthCheckRequest;
import antd.v1.Health.HealthCheckResponse;

import antd.v1.DataServiceGrpc;
import antd.v1.Data.GetPublicDataRequest;
import antd.v1.Data.GetPublicDataResponse;
import antd.v1.Data.PutPublicDataRequest;
import antd.v1.Data.PutPublicDataResponse;
import antd.v1.Data.GetPrivateDataRequest;
import antd.v1.Data.GetPrivateDataResponse;
import antd.v1.Data.PutPrivateDataRequest;
import antd.v1.Data.PutPrivateDataResponse;
import antd.v1.Data.DataCostRequest;

import antd.v1.ChunkServiceGrpc;
import antd.v1.Chunks.GetChunkRequest;
import antd.v1.Chunks.GetChunkResponse;
import antd.v1.Chunks.PutChunkRequest;
import antd.v1.Chunks.PutChunkResponse;

import antd.v1.FileServiceGrpc;
import antd.v1.Files.UploadFileRequest;
import antd.v1.Files.UploadPublicResponse;
import antd.v1.Files.DownloadPublicRequest;
import antd.v1.Files.DownloadResponse;
import antd.v1.Files.ArchiveGetRequest;
import antd.v1.Files.ArchiveGetResponse;
import antd.v1.Files.ArchivePutRequest;
import antd.v1.Files.ArchivePutResponse;
import antd.v1.Files.FileCostRequest;

import antd.v1.Common.Cost;

import com.google.protobuf.ByteString;

import org.junit.jupiter.api.*;

import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * In-process gRPC tests for {@link GrpcAntdClient}.
 *
 * <p>Uses {@code io.grpc.testing} with {@link InProcessServerBuilder} and
 * {@link InProcessChannelBuilder} so no real network sockets are opened.
 * Each service is implemented as a mock {@link BindableService} that returns
 * canned responses matching the data in the REST-based {@link AntdClientTest}.
 */
class GrpcAntdClientTest {

    private Server server;
    private ManagedChannel channel;
    private GrpcAntdClient client;

    @BeforeEach
    void setUp() throws Exception {
        String serverName = InProcessServerBuilder.generateName();

        server = InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new MockHealthService())
                        .addService(new MockDataService())
                        .addService(new MockChunkService())
                        .addService(new MockFileService())
                        .build()
                        .start();

        channel = InProcessChannelBuilder.forName(serverName)
                        .directExecutor()
                        .build();

        client = new GrpcAntdClient(channel);
    }

    @AfterEach
    void tearDown() {
        client.close();
        channel.shutdownNow();
        server.shutdownNow();
    }

    // =========================================================================
    // Mock service implementations
    // =========================================================================

    static class MockHealthService extends HealthServiceGrpc.HealthServiceImplBase {
        @Override
        public void check(HealthCheckRequest request,
                          StreamObserver<HealthCheckResponse> responseObserver) {
            responseObserver.onNext(
                    HealthCheckResponse.newBuilder()
                            .setStatus("ok")
                            .setNetwork("local")
                            .build());
            responseObserver.onCompleted();
        }
    }

    static class MockDataService extends DataServiceGrpc.DataServiceImplBase {
        @Override
        public void putPublic(PutPublicDataRequest request,
                              StreamObserver<PutPublicDataResponse> responseObserver) {
            responseObserver.onNext(
                    PutPublicDataResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("100").build())
                            .setAddress("abc123")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void getPublic(GetPublicDataRequest request,
                              StreamObserver<GetPublicDataResponse> responseObserver) {
            if ("abc123".equals(request.getAddress())) {
                responseObserver.onNext(
                        GetPublicDataResponse.newBuilder()
                                .setData(ByteString.copyFromUtf8("hello"))
                                .build());
                responseObserver.onCompleted();
            } else {
                responseObserver.onError(
                        Status.NOT_FOUND.withDescription("not found").asRuntimeException());
            }
        }

        @Override
        public void putPrivate(PutPrivateDataRequest request,
                               StreamObserver<PutPrivateDataResponse> responseObserver) {
            responseObserver.onNext(
                    PutPrivateDataResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("200").build())
                            .setDataMap("dm123")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void getPrivate(GetPrivateDataRequest request,
                               StreamObserver<GetPrivateDataResponse> responseObserver) {
            responseObserver.onNext(
                    GetPrivateDataResponse.newBuilder()
                            .setData(ByteString.copyFromUtf8("secret"))
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void getCost(DataCostRequest request,
                            StreamObserver<Cost> responseObserver) {
            responseObserver.onNext(
                    Cost.newBuilder().setAttoTokens("50").build());
            responseObserver.onCompleted();
        }
    }

    static class MockChunkService extends ChunkServiceGrpc.ChunkServiceImplBase {
        @Override
        public void put(PutChunkRequest request,
                        StreamObserver<PutChunkResponse> responseObserver) {
            responseObserver.onNext(
                    PutChunkResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("10").build())
                            .setAddress("chunk1")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void get(GetChunkRequest request,
                        StreamObserver<GetChunkResponse> responseObserver) {
            responseObserver.onNext(
                    GetChunkResponse.newBuilder()
                            .setData(ByteString.copyFromUtf8("chunkdata"))
                            .build());
            responseObserver.onCompleted();
        }
    }

    static class MockFileService extends FileServiceGrpc.FileServiceImplBase {
        @Override
        public void uploadPublic(UploadFileRequest request,
                                 StreamObserver<UploadPublicResponse> responseObserver) {
            responseObserver.onNext(
                    UploadPublicResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("1000").build())
                            .setAddress("file1")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void downloadPublic(DownloadPublicRequest request,
                                   StreamObserver<DownloadResponse> responseObserver) {
            responseObserver.onNext(DownloadResponse.getDefaultInstance());
            responseObserver.onCompleted();
        }

        @Override
        public void dirUploadPublic(UploadFileRequest request,
                                    StreamObserver<UploadPublicResponse> responseObserver) {
            responseObserver.onNext(
                    UploadPublicResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("2000").build())
                            .setAddress("dir1")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void dirDownloadPublic(DownloadPublicRequest request,
                                      StreamObserver<DownloadResponse> responseObserver) {
            responseObserver.onNext(DownloadResponse.getDefaultInstance());
            responseObserver.onCompleted();
        }

        @Override
        public void archiveGetPublic(ArchiveGetRequest request,
                                     StreamObserver<ArchiveGetResponse> responseObserver) {
            responseObserver.onNext(
                    ArchiveGetResponse.newBuilder()
                            .addEntries(antd.v1.Files.ArchiveEntry.newBuilder()
                                    .setPath("test.txt")
                                    .setAddress("abc")
                                    .setCreated(1000)
                                    .setModified(2000)
                                    .setSize(42)
                                    .build())
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void archivePutPublic(ArchivePutRequest request,
                                     StreamObserver<ArchivePutResponse> responseObserver) {
            responseObserver.onNext(
                    ArchivePutResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("50").build())
                            .setAddress("arc2")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void getFileCost(FileCostRequest request,
                                StreamObserver<Cost> responseObserver) {
            responseObserver.onNext(
                    Cost.newBuilder().setAttoTokens("1000").build());
            responseObserver.onCompleted();
        }
    }

    // =========================================================================
    // Tests — 15 methods
    // =========================================================================

    // --- Health ---

    @Test
    void testHealth() {
        HealthStatus h = client.health();
        assertTrue(h.ok());
        assertEquals("local", h.network());
    }

    // --- Data (Immutable) ---

    @Test
    void testDataPutPublic() {
        PutResult put = client.dataPutPublic("hello".getBytes());
        assertEquals("abc123", put.address());
        assertEquals("100", put.cost());
    }

    @Test
    void testDataGetPublic() {
        byte[] data = client.dataGetPublic("abc123");
        assertEquals("hello", new String(data));
    }

    @Test
    void testDataPutPrivate() {
        PutResult put = client.dataPutPrivate("secret".getBytes());
        assertEquals("dm123", put.address());
        assertEquals("200", put.cost());
    }

    @Test
    void testDataGetPrivate() {
        byte[] data = client.dataGetPrivate("dm123");
        assertEquals("secret", new String(data));
    }

    @Test
    void testDataCost() {
        String cost = client.dataCost("test".getBytes());
        assertEquals("50", cost);
    }

    // --- Chunks ---

    @Test
    void testChunkPut() {
        PutResult put = client.chunkPut("chunkdata".getBytes());
        assertEquals("chunk1", put.address());
        assertEquals("10", put.cost());
    }

    @Test
    void testChunkGet() {
        byte[] data = client.chunkGet("chunk1");
        assertEquals("chunkdata", new String(data));
    }

    // --- Files & Directories ---

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
    void testArchiveGetPublic() {
        Archive arc = client.archiveGetPublic("arc1");
        assertEquals(1, arc.entries().size());
        ArchiveEntry entry = arc.entries().get(0);
        assertEquals("test.txt", entry.path());
        assertEquals("abc", entry.address());
        assertEquals(1000L, entry.created());
        assertEquals(2000L, entry.modified());
        assertEquals(42L, entry.size());
    }

    @Test
    void testArchivePutPublic() {
        Archive arc = new Archive(List.of(
                new ArchiveEntry("test.txt", "abc", 1000, 2000, 42)));
        PutResult put = client.archivePutPublic(arc);
        assertEquals("arc2", put.address());
        assertEquals("50", put.cost());
    }

    @Test
    void testFileCost() {
        String cost = client.fileCost("/tmp/test.txt", true, false);
        assertEquals("1000", cost);
    }

    // =========================================================================
    // gRPC status code -> AntdException mapping
    // =========================================================================

    @Test
    void testNotFoundThrowsNotFoundException() {
        AntdException ex = assertThrows(AntdException.class,
                () -> client.dataGetPublic("nonexistent"));
        assertInstanceOf(NotFoundException.class, ex);
    }

    @Test
    void testInvalidArgumentThrowsBadRequestException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.INVALID_ARGUMENT
                                        .withDescription("bad request").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("bad".getBytes()));
            assertInstanceOf(BadRequestException.class, ex);
        }
    }

    @Test
    void testAlreadyExistsThrowsAlreadyExistsException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.ALREADY_EXISTS
                                        .withDescription("exists").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("dup".getBytes()));
            assertInstanceOf(AlreadyExistsException.class, ex);
        }
    }

    @Test
    void testFailedPreconditionThrowsPaymentException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.FAILED_PRECONDITION
                                        .withDescription("insufficient funds").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("pay".getBytes()));
            assertInstanceOf(PaymentException.class, ex);
        }
    }

    @Test
    void testResourceExhaustedThrowsTooLargeException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.RESOURCE_EXHAUSTED
                                        .withDescription("too large").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("big".getBytes()));
            assertInstanceOf(TooLargeException.class, ex);
        }
    }

    @Test
    void testInternalThrowsInternalException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.INTERNAL
                                        .withDescription("internal error").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("err".getBytes()));
            assertInstanceOf(InternalException.class, ex);
        }
    }

    @Test
    void testUnavailableThrowsNetworkException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.UNAVAILABLE
                                        .withDescription("unavailable").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("net".getBytes()));
            assertInstanceOf(NetworkException.class, ex);
        }
    }

    @Test
    void testUnknownCodeThrowsBaseAntdException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        InProcessServerBuilder.forName(serverName)
                        .directExecutor()
                        .addService(new DataServiceGrpc.DataServiceImplBase() {
                            @Override
                            public void putPublic(PutPublicDataRequest request,
                                                  StreamObserver<PutPublicDataResponse> obs) {
                                obs.onError(Status.UNIMPLEMENTED
                                        .withDescription("unimplemented").asRuntimeException());
                            }
                        })
                        .build()
                        .start();

        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();

        try (GrpcAntdClient errClient = new GrpcAntdClient(ch)) {
            AntdException ex = assertThrows(AntdException.class,
                    () -> errClient.dataPutPublic("unknown".getBytes()));
            // Should be the base class, not a specific subtype (except AntdException itself)
            assertEquals(AntdException.class, ex.getClass());
        }
    }
}
