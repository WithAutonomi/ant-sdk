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
import antd.v1.Data.GetDataRequest;
import antd.v1.Data.GetDataResponse;
import antd.v1.Data.PutDataRequest;
import antd.v1.Data.PutDataResponse;
import antd.v1.Data.DataCostRequest;

import antd.v1.ChunkServiceGrpc;
import antd.v1.Chunks.GetChunkRequest;
import antd.v1.Chunks.GetChunkResponse;
import antd.v1.Chunks.PutChunkRequest;
import antd.v1.Chunks.PutChunkResponse;

import antd.v1.FileServiceGrpc;
import antd.v1.Files.PutFileRequest;
import antd.v1.Files.PutFilePublicResponse;
import antd.v1.Files.GetFilePublicRequest;
import antd.v1.Files.GetFileResponse;
import antd.v1.Files.FileCostRequest;

import antd.v1.Common.Cost;

import com.google.protobuf.ByteString;

import org.junit.jupiter.api.*;

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
                        .addService(new MockWalletService())
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
                            .setVersion("0.4.0")
                            .setEvmNetwork("local")
                            .setUptimeSeconds(42)
                            .setBuildCommit("abcdef123456")
                            .setPaymentTokenAddress("0xtoken")
                            .setPaymentVaultAddress("0xvault")
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
        public void put(PutDataRequest request,
                               StreamObserver<PutDataResponse> responseObserver) {
            responseObserver.onNext(
                    PutDataResponse.newBuilder()
                            .setCost(Cost.newBuilder().setAttoTokens("200").build())
                            .setDataMap("dm123")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void get(GetDataRequest request,
                               StreamObserver<GetDataResponse> responseObserver) {
            responseObserver.onNext(
                    GetDataResponse.newBuilder()
                            .setData(ByteString.copyFromUtf8("secret"))
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void cost(DataCostRequest request,
                            StreamObserver<Cost> responseObserver) {
            responseObserver.onNext(
                    Cost.newBuilder()
                            .setAttoTokens("50")
                            .setFileSize(4)
                            .setChunkCount(3)
                            .setEstimatedGasCostWei("150000000000000")
                            .setPaymentMode("single")
                            .build());
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
        public void putPublic(PutFileRequest request,
                                 StreamObserver<PutFilePublicResponse> responseObserver) {
            responseObserver.onNext(
                    PutFilePublicResponse.newBuilder()
                            .setAddress("file1")
                            .setStorageCostAtto("1000")
                            .setGasCostWei("42")
                            .setChunksStored(3L)
                            .setPaymentModeUsed("auto")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void getPublic(GetFilePublicRequest request,
                                   StreamObserver<GetFileResponse> responseObserver) {
            responseObserver.onNext(GetFileResponse.getDefaultInstance());
            responseObserver.onCompleted();
        }

        @Override
        public void cost(FileCostRequest request,
                                StreamObserver<Cost> responseObserver) {
            responseObserver.onNext(
                    Cost.newBuilder()
                            .setAttoTokens("1000")
                            .setFileSize(4096)
                            .setChunkCount(3)
                            .setEstimatedGasCostWei("150000000000000")
                            .setPaymentMode("auto")
                            .build());
            responseObserver.onCompleted();
        }
    }

    // =========================================================================
    // Tests
    // =========================================================================

    // --- Health ---

    @Test
    void testHealth() {
        HealthStatus h = client.health();
        assertTrue(h.ok());
        assertEquals("local", h.network());
        assertEquals("0.4.0", h.version());
        assertEquals("local", h.evmNetwork());
        assertEquals(42L, h.uptimeSeconds());
        assertEquals("abcdef123456", h.buildCommit());
        assertEquals("0xtoken", h.paymentTokenAddress());
        assertEquals("0xvault", h.paymentVaultAddress());
    }

    // --- Data (Immutable) ---

    @Test
    void testDataPutPublic() {
        DataPutPublicResult put = client.dataPutPublic("hello".getBytes());
        assertEquals("abc123", put.address());
    }

    @Test
    void testDataGetPublic() {
        byte[] data = client.dataGetPublic("abc123");
        assertEquals("hello", new String(data));
    }

    @Test
    void testDataPutPrivate() {
        DataPutResult put = client.dataPut("secret".getBytes());
        assertEquals("dm123", put.dataMap());
    }

    @Test
    void testDataGetPrivate() {
        byte[] data = client.dataGet("dm123");
        assertEquals("secret", new String(data));
    }

    @Test
    void testDataCost() {
        UploadCostEstimate est = client.dataCost("test".getBytes());
        assertEquals("50", est.cost());
        assertEquals(4L, est.fileSize());
        assertEquals(3, est.chunkCount());
        assertEquals("150000000000000", est.estimatedGasCostWei());
        assertEquals("single", est.paymentMode());
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
        FilePutPublicResult put = client.filePutPublic("/tmp/test.txt");
        assertEquals("file1", put.address());
        assertEquals("1000", put.storageCostAtto());
        assertEquals("42", put.gasCostWei());
        assertEquals(3L, put.chunksStored());
        assertEquals("auto", put.paymentModeUsed());
    }

    @Test
    void testFileDownloadPublic() {
        assertDoesNotThrow(() -> client.fileGetPublic("file1", "/tmp/out.txt"));
    }

    @Test
    void testFileCost() {
        UploadCostEstimate est = client.fileCost("/tmp/test.txt", true);
        assertEquals("1000", est.cost());
        assertEquals(4096L, est.fileSize());
        assertEquals(3, est.chunkCount());
        assertEquals("150000000000000", est.estimatedGasCostWei());
        assertEquals("auto", est.paymentMode());
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

    // =========================================================================
    // V2-286 MockWalletService + tests
    // =========================================================================

    static class MockWalletService extends antd.v1.WalletServiceGrpc.WalletServiceImplBase {
        @Override
        public void getAddress(antd.v1.Wallet.GetWalletAddressRequest req,
                io.grpc.stub.StreamObserver<antd.v1.Wallet.GetWalletAddressResponse> resp) {
            resp.onNext(antd.v1.Wallet.GetWalletAddressResponse.newBuilder()
                    .setAddress("0xabc1234567890abcdef1234567890abcdef123456")
                    .build());
            resp.onCompleted();
        }

        @Override
        public void getBalance(antd.v1.Wallet.GetWalletBalanceRequest req,
                io.grpc.stub.StreamObserver<antd.v1.Wallet.GetWalletBalanceResponse> resp) {
            resp.onNext(antd.v1.Wallet.GetWalletBalanceResponse.newBuilder()
                    .setBalance("1000000000000000000")
                    .setGasBalance("500000000000000000")
                    .build());
            resp.onCompleted();
        }

        @Override
        public void approve(antd.v1.Wallet.WalletApproveRequest req,
                io.grpc.stub.StreamObserver<antd.v1.Wallet.WalletApproveResponse> resp) {
            resp.onNext(antd.v1.Wallet.WalletApproveResponse.newBuilder()
                    .setApproved(true)
                    .build());
            resp.onCompleted();
        }
    }

    @Test
    void walletAddressReturnsAddress() {
        com.autonomi.antd.models.WalletAddress r = client.walletAddress();
        assertEquals("0xabc1234567890abcdef1234567890abcdef123456", r.address());
    }

    @Test
    void walletBalanceReturnsBalances() {
        com.autonomi.antd.models.WalletBalance r = client.walletBalance();
        assertEquals("1000000000000000000", r.balance());
        assertEquals("500000000000000000", r.gasBalance());
    }

    @Test
    void walletApproveReturnsTrue() {
        assertTrue(client.walletApprove());
    }

    /**
     * Daemon emits gRPC FailedPrecondition for "wallet not configured"; the
     * established mapping in GrpcAntdClient.mapException surfaces this as
     * PaymentException. (Semantic is a bit off vs REST's 503 but matches every
     * SDK.)
     */
    @Test
    void walletAddressUnconfiguredReturnsPaymentException() throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        Server errServer = InProcessServerBuilder.forName(serverName)
                .directExecutor()
                .addService(new antd.v1.WalletServiceGrpc.WalletServiceImplBase() {
                    @Override
                    public void getAddress(antd.v1.Wallet.GetWalletAddressRequest req,
                            io.grpc.stub.StreamObserver<antd.v1.Wallet.GetWalletAddressResponse> resp) {
                        resp.onError(io.grpc.Status.FAILED_PRECONDITION
                                .withDescription("wallet not configured — set AUTONOMI_WALLET_KEY")
                                .asRuntimeException());
                    }
                })
                .build()
                .start();
        ManagedChannel ch = InProcessChannelBuilder.forName(serverName).directExecutor().build();
        try (GrpcAntdClient c = new GrpcAntdClient(ch)) {
            com.autonomi.antd.errors.PaymentException ex = assertThrows(
                    com.autonomi.antd.errors.PaymentException.class,
                    c::walletAddress);
            assertTrue(ex.getMessage().contains("wallet not configured"));
        } finally {
            ch.shutdownNow();
            errServer.shutdownNow();
        }
    }
}
