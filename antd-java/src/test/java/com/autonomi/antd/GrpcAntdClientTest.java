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

import antd.v1.UploadServiceGrpc;
import antd.v1.Upload.PrepareFileUploadRequest;
import antd.v1.Upload.PrepareDataUploadRequest;
import antd.v1.Upload.PrepareUploadResponse;
import antd.v1.Upload.FinalizeUploadRequest;
import antd.v1.Upload.FinalizeUploadResponse;
import antd.v1.Upload.PoolCommitmentEntry;
import antd.v1.Upload.CandidateNodeEntry;

import antd.v1.Chunks.PrepareChunkRequest;
import antd.v1.Chunks.PrepareChunkResponse;
import antd.v1.Chunks.FinalizeChunkRequest;
import antd.v1.Chunks.FinalizeChunkResponse;

import antd.v1.Common.Cost;
import antd.v1.Common.PaymentEntry;

import java.util.HashMap;
import java.util.Map;

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
                        .addService(new MockUploadService())
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

        @Override
        public void prepareChunk(PrepareChunkRequest request,
                                 StreamObserver<PrepareChunkResponse> responseObserver) {
            // Inputs starting with "EXISTS" → already-stored short-circuit.
            ByteString data = request.getData();
            if (data.size() >= 6 && data.substring(0, 6).toStringUtf8().equals("EXISTS")) {
                responseObserver.onNext(
                        PrepareChunkResponse.newBuilder()
                                .setAddress("0xabc")
                                .setAlreadyStored(true)
                                .build());
            } else {
                responseObserver.onNext(
                        PrepareChunkResponse.newBuilder()
                                .setAddress("0xnewchunk")
                                .setAlreadyStored(false)
                                .setUploadId("upid_chunk_42")
                                .setPaymentType("wave_batch")
                                .addPayments(PaymentEntry.newBuilder()
                                        .setQuoteHash("0xq1")
                                        .setRewardsAddress("0xr1")
                                        .setAmount("100")
                                        .build())
                                .setTotalAmount("100")
                                .setPaymentVaultAddress("0xvault")
                                .setPaymentTokenAddress("0xtoken")
                                .setRpcUrl("http://localhost:8545")
                                .build());
            }
            responseObserver.onCompleted();
        }

        @Override
        public void finalizeChunk(FinalizeChunkRequest request,
                                  StreamObserver<FinalizeChunkResponse> responseObserver) {
            // Echo upload_id into address so the test can verify forwarding.
            responseObserver.onNext(
                    FinalizeChunkResponse.newBuilder()
                            .setAddress("addr_for_" + request.getUploadId())
                            .build());
            responseObserver.onCompleted();
        }
    }

    static class MockUploadService extends UploadServiceGrpc.UploadServiceImplBase {
        @Override
        public void prepareFileUpload(PrepareFileUploadRequest request,
                                      StreamObserver<PrepareUploadResponse> responseObserver) {
            // Encode visibility into upload_id so the test can verify forwarding.
            responseObserver.onNext(
                    PrepareUploadResponse.newBuilder()
                            .setUploadId("upid_file_" + request.getVisibility())
                            .setPaymentType("wave_batch")
                            .addPayments(PaymentEntry.newBuilder()
                                    .setQuoteHash("0xqa")
                                    .setRewardsAddress("0xra")
                                    .setAmount("1")
                                    .build())
                            .setTotalAmount("1")
                            .setPaymentVaultAddress("0xvault")
                            .setPaymentTokenAddress("0xtoken")
                            .setRpcUrl("http://localhost:8545")
                            .build());
            responseObserver.onCompleted();
        }

        @Override
        public void prepareDataUpload(PrepareDataUploadRequest request,
                                      StreamObserver<PrepareUploadResponse> responseObserver) {
            String uploadId = "upid_data_" + request.getVisibility();
            ByteString data = request.getData();
            if (data.size() >= 6 && data.substring(0, 6).toStringUtf8().equals("MERKLE")) {
                responseObserver.onNext(
                        PrepareUploadResponse.newBuilder()
                                .setUploadId(uploadId)
                                .setPaymentType("merkle")
                                .setDepth(7)
                                .addPoolCommitments(PoolCommitmentEntry.newBuilder()
                                        .setPoolHash("0xpool")
                                        .addCandidates(CandidateNodeEntry.newBuilder()
                                                .setRewardsAddress("0xc1")
                                                .setAmount("5")
                                                .build())
                                        .build())
                                .setMerklePaymentTimestamp(1_700_000_000L)
                                .setTotalAmount("0")
                                .setPaymentVaultAddress("0xvault")
                                .setPaymentTokenAddress("0xtoken")
                                .setRpcUrl("http://localhost:8545")
                                .build());
            } else {
                responseObserver.onNext(
                        PrepareUploadResponse.newBuilder()
                                .setUploadId(uploadId)
                                .setPaymentType("wave_batch")
                                .addPayments(PaymentEntry.newBuilder()
                                        .setQuoteHash("0xqb")
                                        .setRewardsAddress("0xrb")
                                        .setAmount("2")
                                        .build())
                                .setTotalAmount("2")
                                .setPaymentVaultAddress("0xvault")
                                .setPaymentTokenAddress("0xtoken")
                                .setRpcUrl("http://localhost:8545")
                                .build());
            }
            responseObserver.onCompleted();
        }

        @Override
        public void finalizeUpload(FinalizeUploadRequest request,
                                   StreamObserver<FinalizeUploadResponse> responseObserver) {
            // Merkle: winner_pool_hash populated.
            if (!request.getWinnerPoolHash().isEmpty()) {
                responseObserver.onNext(
                        FinalizeUploadResponse.newBuilder()
                                .setDataMap("dm_merkle")
                                .setAddress(request.getStoreDataMap() ? "stored_on_network" : "")
                                .setChunksStored(64L)
                                .build());
            } else {
                String uid = request.getUploadId();
                String dataMapAddress = uid.endsWith("public") ? "addr_public_dm" : "";
                responseObserver.onNext(
                        FinalizeUploadResponse.newBuilder()
                                .setDataMap("dm_wave")
                                .setDataMapAddress(dataMapAddress)
                                .setChunksStored(3L)
                                .build());
            }
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

    // --- External-signer prepare/finalize tests ---

    @Test
    void testPrepareUploadOmitsVisibilityWhenNull() {
        PrepareUploadResult r = client.prepareUpload("/tmp/x.bin");
        assertEquals("upid_file_", r.uploadId());
        assertEquals("wave_batch", r.paymentType());
        assertEquals(1, r.payments().size());
        assertEquals("0xqa", r.payments().get(0).quoteHash());
        assertNull(r.depth());
        assertNull(r.poolCommitments());
        assertNull(r.merklePaymentTimestamp());
    }

    @Test
    void testPrepareUploadForwardsVisibilityPublic() {
        PrepareUploadResult r = client.prepareUpload("/tmp/x.bin", "public");
        assertEquals("upid_file_public", r.uploadId());
    }

    @Test
    void testPrepareUploadPublicConvenience() {
        PrepareUploadResult r = client.prepareUploadPublic("/tmp/x.bin");
        assertEquals("upid_file_public", r.uploadId());
    }

    @Test
    void testPrepareDataUploadWaveBatch() {
        PrepareUploadResult r = client.prepareDataUpload("small".getBytes());
        assertEquals("upid_data_", r.uploadId());
        assertEquals("wave_batch", r.paymentType());
        assertNull(r.depth());
    }

    @Test
    void testPrepareDataUploadMerkle() {
        PrepareUploadResult r = client.prepareDataUpload("MERKLE-large-payload".getBytes());
        assertEquals("merkle", r.paymentType());
        assertEquals(Integer.valueOf(7), r.depth());
        assertEquals(Long.valueOf(1_700_000_000L), r.merklePaymentTimestamp());
        assertEquals(1, r.poolCommitments().size());
        assertEquals("0xpool", r.poolCommitments().get(0).poolHash());
        assertEquals("0xc1", r.poolCommitments().get(0).candidates().get(0).rewardsAddress());
    }

    @Test
    void testFinalizeUploadWaveBatchPrivateOmitsDataMapAddress() {
        Map<String, String> tx = new HashMap<>();
        tx.put("0xq1", "0xtx1");
        FinalizeUploadResult r = client.finalizeUpload("upid_file_", tx);
        assertEquals("dm_wave", r.dataMap());
        assertEquals("", r.dataMapAddress());
        assertEquals(3L, r.chunksStored());
    }

    @Test
    void testFinalizeUploadWaveBatchPublicReturnsDataMapAddress() {
        Map<String, String> tx = new HashMap<>();
        tx.put("0xq1", "0xtx1");
        FinalizeUploadResult r = client.finalizeUpload("upid_file_public", tx);
        assertEquals("addr_public_dm", r.dataMapAddress());
    }

    @Test
    void testFinalizeMerkleUploadStoreDataMapTrue() {
        FinalizeUploadResult r = client.finalizeMerkleUpload("upid_data_", "0xwinpool", true);
        assertEquals("dm_merkle", r.dataMap());
        assertEquals("stored_on_network", r.address());
        assertEquals(64L, r.chunksStored());
    }

    @Test
    void testFinalizeMerkleUploadStoreDataMapFalse() {
        FinalizeUploadResult r = client.finalizeMerkleUpload("upid_data_", "0xwinpool");
        assertEquals("dm_merkle", r.dataMap());
        assertEquals("", r.address());
    }

    @Test
    void testPrepareChunkUploadNewChunk() {
        PrepareChunkResult r = client.prepareChunkUpload("newchunk".getBytes());
        assertFalse(r.alreadyStored());
        assertEquals("0xnewchunk", r.address());
        assertEquals("upid_chunk_42", r.uploadId());
        assertEquals("wave_batch", r.paymentType());
        assertEquals(1, r.payments().size());
        assertEquals("0xq1", r.payments().get(0).quoteHash());
        assertEquals("100", r.totalAmount());
        assertEquals("http://localhost:8545", r.rpcUrl());
    }

    @Test
    void testPrepareChunkUploadAlreadyStoredShortCircuit() {
        PrepareChunkResult r = client.prepareChunkUpload("EXISTS-data".getBytes());
        assertTrue(r.alreadyStored());
        assertEquals("0xabc", r.address());
        assertEquals("", r.uploadId());
        assertTrue(r.payments().isEmpty());
    }

    @Test
    void testFinalizeChunkUploadReturnsAddressAndForwardsBody() {
        Map<String, String> tx = new HashMap<>();
        tx.put("0xq1", "0xtxabc");
        String addr = client.finalizeChunkUpload("upid_chunk_42", tx);
        assertEquals("addr_for_upid_chunk_42", addr);
    }
}
