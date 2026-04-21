package com.autonomi.antd;

import com.autonomi.antd.errors.*;
import com.autonomi.antd.models.*;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;

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
import antd.v1.Files.FileCostRequest;

import antd.v1.Common.Cost;

import com.google.protobuf.ByteString;

import java.util.concurrent.TimeUnit;

/**
 * gRPC client for the antd daemon — the gateway to the Autonomi decentralized network.
 *
 * <p>Uses {@code io.grpc} blocking stubs for synchronous calls. Implements the same
 * methods as {@link AntdClient} but communicates over gRPC instead of REST.
 *
 * <p>Implements {@link AutoCloseable} so it can be used in try-with-resources blocks.
 *
 * <pre>{@code
 * try (var client = new GrpcAntdClient()) {
 *     HealthStatus health = client.health();
 *     System.out.println(health.network());
 * }
 * }</pre>
 */
public class GrpcAntdClient implements AutoCloseable {

    /** Default gRPC target address. */
    public static final String DEFAULT_TARGET = "localhost:50051";

    /** Default shutdown timeout. */
    private static final long SHUTDOWN_TIMEOUT_SECONDS = 5;

    private final ManagedChannel channel;
    private final HealthServiceGrpc.HealthServiceBlockingStub healthStub;
    private final DataServiceGrpc.DataServiceBlockingStub dataStub;
    private final ChunkServiceGrpc.ChunkServiceBlockingStub chunkStub;
    private final FileServiceGrpc.FileServiceBlockingStub fileStub;

    /**
     * Creates a client that auto-discovers the daemon via the {@code daemon.port} file.
     * Falls back to {@link #DEFAULT_TARGET} if discovery fails.
     *
     * @return a new GrpcAntdClient connected to the discovered or default target
     */
    public static GrpcAntdClient autoDiscover() {
        String target = DaemonDiscovery.discoverGrpcTarget();
        if (target.isEmpty()) {
            target = DEFAULT_TARGET;
        }
        return new GrpcAntdClient(target);
    }

    /**
     * Creates a client connected to {@code localhost:50051} with plaintext (no TLS).
     */
    public GrpcAntdClient() {
        this(DEFAULT_TARGET);
    }

    /**
     * Creates a client connected to the given target (e.g. {@code "myhost:50051"}).
     *
     * @param target the gRPC target string (host:port)
     */
    public GrpcAntdClient(String target) {
        this(ManagedChannelBuilder.forTarget(target).usePlaintext().build());
    }

    /**
     * Creates a client using a pre-built {@link ManagedChannel}. The client takes
     * ownership and will shut down the channel on {@link #close()}.
     *
     * @param channel the managed channel to use
     */
    public GrpcAntdClient(ManagedChannel channel) {
        this.channel = channel;
        this.healthStub = HealthServiceGrpc.newBlockingStub(channel);
        this.dataStub = DataServiceGrpc.newBlockingStub(channel);
        this.chunkStub = ChunkServiceGrpc.newBlockingStub(channel);
        this.fileStub = FileServiceGrpc.newBlockingStub(channel);
    }

    @Override
    public void close() {
        channel.shutdown();
        try {
            if (!channel.awaitTermination(SHUTDOWN_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                channel.shutdownNow();
            }
        } catch (InterruptedException e) {
            channel.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }

    // ── Error mapping ──

    /**
     * Maps gRPC status codes to the {@link AntdException} hierarchy.
     */
    private static AntdException mapException(StatusRuntimeException e) {
        String msg = e.getStatus().getDescription();
        if (msg == null) msg = e.getMessage();

        return switch (e.getStatus().getCode()) {
            case INVALID_ARGUMENT -> new BadRequestException(msg);
            case NOT_FOUND -> new NotFoundException(msg);
            case ALREADY_EXISTS -> new AlreadyExistsException(msg);
            case FAILED_PRECONDITION -> new PaymentException(msg);
            case RESOURCE_EXHAUSTED -> new TooLargeException(msg);
            case INTERNAL -> new InternalException(msg);
            case UNAVAILABLE -> new NetworkException(msg);
            default -> new AntdException(e.getStatus().getCode().value(), msg);
        };
    }

    // ── Health ──

    /**
     * Check daemon health status.
     */
    public HealthStatus health() {
        try {
            HealthCheckResponse resp = healthStub.check(HealthCheckRequest.getDefaultInstance());
            return new HealthStatus("ok".equals(resp.getStatus()), resp.getNetwork());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    // ── Data (Immutable) ──

    /**
     * Store public data on the network.
     */
    public PutResult dataPutPublic(byte[] data) {
        try {
            PutPublicDataRequest req = PutPublicDataRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .build();
            PutPublicDataResponse resp = dataStub.putPublic(req);
            return new PutResult(resp.getCost().getAttoTokens(), resp.getAddress());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Retrieve public data by address.
     */
    public byte[] dataGetPublic(String address) {
        try {
            GetPublicDataRequest req = GetPublicDataRequest.newBuilder()
                    .setAddress(address)
                    .build();
            GetPublicDataResponse resp = dataStub.getPublic(req);
            return resp.getData().toByteArray();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Store encrypted private data on the network.
     */
    public PutResult dataPutPrivate(byte[] data) {
        try {
            PutPrivateDataRequest req = PutPrivateDataRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .build();
            PutPrivateDataResponse resp = dataStub.putPrivate(req);
            return new PutResult(resp.getCost().getAttoTokens(), resp.getDataMap());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Retrieve private data by data map.
     */
    public byte[] dataGetPrivate(String dataMap) {
        try {
            GetPrivateDataRequest req = GetPrivateDataRequest.newBuilder()
                    .setDataMap(dataMap)
                    .build();
            GetPrivateDataResponse resp = dataStub.getPrivate(req);
            return resp.getData().toByteArray();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Pre-upload cost breakdown for the given bytes.
     */
    public UploadCostEstimate dataCost(byte[] data) {
        try {
            DataCostRequest req = DataCostRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .build();
            Cost resp = dataStub.getCost(req);
            return new UploadCostEstimate(
                    resp.getAttoTokens(),
                    resp.getFileSize(),
                    resp.getChunkCount(),
                    resp.getEstimatedGasCostWei(),
                    resp.getPaymentMode());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    // ── Chunks ──

    /**
     * Store a raw chunk on the network.
     */
    public PutResult chunkPut(byte[] data) {
        try {
            PutChunkRequest req = PutChunkRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .build();
            PutChunkResponse resp = chunkStub.put(req);
            return new PutResult(resp.getCost().getAttoTokens(), resp.getAddress());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Retrieve a raw chunk by address.
     */
    public byte[] chunkGet(String address) {
        try {
            GetChunkRequest req = GetChunkRequest.newBuilder()
                    .setAddress(address)
                    .build();
            GetChunkResponse resp = chunkStub.get(req);
            return resp.getData().toByteArray();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    // ── Files & Directories ──

    /**
     * Upload a file to the network (public).
     */
    public FileUploadResult fileUploadPublic(String path) {
        try {
            UploadFileRequest req = UploadFileRequest.newBuilder()
                    .setPath(path)
                    .build();
            UploadPublicResponse resp = fileStub.uploadPublic(req);
            return toFileUploadResult(resp);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Download a public file to a local path.
     */
    public void fileDownloadPublic(String address, String destPath) {
        try {
            DownloadPublicRequest req = DownloadPublicRequest.newBuilder()
                    .setAddress(address)
                    .setDestPath(destPath)
                    .build();
            fileStub.downloadPublic(req);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Upload a directory to the network (public).
     */
    public FileUploadResult dirUploadPublic(String path) {
        try {
            UploadFileRequest req = UploadFileRequest.newBuilder()
                    .setPath(path)
                    .build();
            UploadPublicResponse resp = fileStub.dirUploadPublic(req);
            return toFileUploadResult(resp);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    private static FileUploadResult toFileUploadResult(UploadPublicResponse resp) {
        return new FileUploadResult(
                resp.getAddress(),
                resp.getStorageCostAtto(),
                resp.getGasCostWei(),
                resp.getChunksStored(),
                resp.getPaymentModeUsed());
    }

    /**
     * Download a public directory to a local path.
     */
    public void dirDownloadPublic(String address, String destPath) {
        try {
            DownloadPublicRequest req = DownloadPublicRequest.newBuilder()
                    .setAddress(address)
                    .setDestPath(destPath)
                    .build();
            fileStub.dirDownloadPublic(req);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    /**
     * Pre-upload cost breakdown for the file at {@code path}.
     */
    public UploadCostEstimate fileCost(String path, boolean isPublic) {
        try {
            FileCostRequest req = FileCostRequest.newBuilder()
                    .setPath(path)
                    .setIsPublic(isPublic)
                    .build();
            Cost resp = fileStub.getFileCost(req);
            return new UploadCostEstimate(
                    resp.getAttoTokens(),
                    resp.getFileSize(),
                    resp.getChunkCount(),
                    resp.getEstimatedGasCostWei(),
                    resp.getPaymentMode());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }
}
