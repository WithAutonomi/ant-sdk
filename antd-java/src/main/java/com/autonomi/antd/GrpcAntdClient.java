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

import antd.v1.WalletServiceGrpc;
import antd.v1.Wallet.GetWalletAddressRequest;
import antd.v1.Wallet.GetWalletAddressResponse;
import antd.v1.Wallet.GetWalletBalanceRequest;
import antd.v1.Wallet.GetWalletBalanceResponse;
import antd.v1.Wallet.WalletApproveRequest;
import antd.v1.Wallet.WalletApproveResponse;

import antd.v1.FileServiceGrpc;
import antd.v1.Files.PutFileRequest;
import antd.v1.Files.PutFileResponse;
import antd.v1.Files.PutFilePublicResponse;
import antd.v1.Files.GetFileRequest;
import antd.v1.Files.GetFileResponse;
import antd.v1.Files.GetFilePublicRequest;
import antd.v1.Files.FileCostRequest;

import antd.v1.Common.Cost;

import com.google.protobuf.ByteString;

import java.util.concurrent.TimeUnit;

/**
 * gRPC client for the antd daemon.
 */
public class GrpcAntdClient implements AutoCloseable {

    public static final String DEFAULT_TARGET = "localhost:50051";
    private static final long SHUTDOWN_TIMEOUT_SECONDS = 5;

    private final ManagedChannel channel;
    private final HealthServiceGrpc.HealthServiceBlockingStub healthStub;
    private final DataServiceGrpc.DataServiceBlockingStub dataStub;
    private final ChunkServiceGrpc.ChunkServiceBlockingStub chunkStub;
    private final FileServiceGrpc.FileServiceBlockingStub fileStub;
    private final WalletServiceGrpc.WalletServiceBlockingStub walletStub;

    public static GrpcAntdClient autoDiscover() {
        String target = DaemonDiscovery.discoverGrpcTarget();
        if (target.isEmpty()) {
            target = DEFAULT_TARGET;
        }
        return new GrpcAntdClient(target);
    }

    public GrpcAntdClient() {
        this(DEFAULT_TARGET);
    }

    public GrpcAntdClient(String target) {
        this(ManagedChannelBuilder.forTarget(target).usePlaintext().build());
    }

    public GrpcAntdClient(ManagedChannel channel) {
        this.channel = channel;
        this.healthStub = HealthServiceGrpc.newBlockingStub(channel);
        this.dataStub = DataServiceGrpc.newBlockingStub(channel);
        this.chunkStub = ChunkServiceGrpc.newBlockingStub(channel);
        this.fileStub = FileServiceGrpc.newBlockingStub(channel);
        this.walletStub = WalletServiceGrpc.newBlockingStub(channel);
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

    // Error mapping

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

    // Health

    public HealthStatus health() {
        try {
            HealthCheckResponse resp = healthStub.check(HealthCheckRequest.getDefaultInstance());
            return healthStatusFromGrpc(resp);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    static HealthStatus healthStatusFromGrpc(HealthCheckResponse resp) {
        return new HealthStatus(
                "ok".equals(resp.getStatus()),
                resp.getNetwork(),
                resp.getVersion(),
                resp.getEvmNetwork(),
                resp.getUptimeSeconds(),
                resp.getBuildCommit(),
                resp.getPaymentTokenAddress(),
                resp.getPaymentVaultAddress());
    }

    // Data

    public DataPutResult dataPut(byte[] data, PaymentMode paymentMode) {
        try {
            PutDataRequest req = PutDataRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .setPaymentMode(paymentMode.wireValue())
                    .build();
            PutDataResponse resp = dataStub.put(req);
            return new DataPutResult(resp.getDataMap());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public DataPutResult dataPut(byte[] data) {
        return dataPut(data, PaymentMode.AUTO);
    }

    public byte[] dataGet(String dataMap) {
        try {
            GetDataRequest req = GetDataRequest.newBuilder().setDataMap(dataMap).build();
            GetDataResponse resp = dataStub.get(req);
            return resp.getData().toByteArray();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public DataPutPublicResult dataPutPublic(byte[] data, PaymentMode paymentMode) {
        try {
            PutPublicDataRequest req = PutPublicDataRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .setPaymentMode(paymentMode.wireValue())
                    .build();
            PutPublicDataResponse resp = dataStub.putPublic(req);
            return new DataPutPublicResult(resp.getAddress());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public DataPutPublicResult dataPutPublic(byte[] data) {
        return dataPutPublic(data, PaymentMode.AUTO);
    }

    public byte[] dataGetPublic(String address) {
        try {
            GetPublicDataRequest req = GetPublicDataRequest.newBuilder().setAddress(address).build();
            GetPublicDataResponse resp = dataStub.getPublic(req);
            return resp.getData().toByteArray();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public UploadCostEstimate dataCost(byte[] data, PaymentMode paymentMode) {
        try {
            DataCostRequest req = DataCostRequest.newBuilder()
                    .setData(ByteString.copyFrom(data))
                    .setPaymentMode(paymentMode.wireValue())
                    .build();
            Cost resp = dataStub.cost(req);
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

    public UploadCostEstimate dataCost(byte[] data) {
        return dataCost(data, PaymentMode.AUTO);
    }

    // Chunks

    public PutResult chunkPut(byte[] data) {
        try {
            PutChunkRequest req = PutChunkRequest.newBuilder().setData(ByteString.copyFrom(data)).build();
            PutChunkResponse resp = chunkStub.put(req);
            return new PutResult(resp.getCost().getAttoTokens(), resp.getAddress());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public byte[] chunkGet(String address) {
        try {
            GetChunkRequest req = GetChunkRequest.newBuilder().setAddress(address).build();
            GetChunkResponse resp = chunkStub.get(req);
            return resp.getData().toByteArray();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    // Files

    public FilePutResult filePut(String path, PaymentMode paymentMode) {
        try {
            PutFileRequest req = PutFileRequest.newBuilder()
                    .setPath(path)
                    .setPaymentMode(paymentMode.wireValue())
                    .build();
            PutFileResponse resp = fileStub.put(req);
            return new FilePutResult(
                    resp.getDataMap(),
                    resp.getStorageCostAtto(),
                    resp.getGasCostWei(),
                    resp.getChunksStored(),
                    resp.getPaymentModeUsed());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public FilePutResult filePut(String path) {
        return filePut(path, PaymentMode.AUTO);
    }

    public void fileGet(String dataMap, String destPath) {
        try {
            GetFileRequest req = GetFileRequest.newBuilder()
                    .setDataMap(dataMap)
                    .setDestPath(destPath)
                    .build();
            fileStub.get(req);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public FilePutPublicResult filePutPublic(String path, PaymentMode paymentMode) {
        try {
            PutFileRequest req = PutFileRequest.newBuilder()
                    .setPath(path)
                    .setPaymentMode(paymentMode.wireValue())
                    .build();
            PutFilePublicResponse resp = fileStub.putPublic(req);
            return new FilePutPublicResult(
                    resp.getAddress(),
                    resp.getStorageCostAtto(),
                    resp.getGasCostWei(),
                    resp.getChunksStored(),
                    resp.getPaymentModeUsed());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public FilePutPublicResult filePutPublic(String path) {
        return filePutPublic(path, PaymentMode.AUTO);
    }

    public void fileGetPublic(String address, String destPath) {
        try {
            GetFilePublicRequest req = GetFilePublicRequest.newBuilder()
                    .setAddress(address)
                    .setDestPath(destPath)
                    .build();
            fileStub.getPublic(req);
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public UploadCostEstimate fileCost(String path, boolean isPublic, PaymentMode paymentMode) {
        try {
            FileCostRequest req = FileCostRequest.newBuilder()
                    .setPath(path)
                    .setIsPublic(isPublic)
                    .setPaymentMode(paymentMode.wireValue())
                    .build();
            Cost resp = fileStub.cost(req);
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

    public UploadCostEstimate fileCost(String path, boolean isPublic) {
        return fileCost(path, isPublic, PaymentMode.AUTO);
    }

    // Wallet — V2-286 parity with REST AntdClient.walletAddress/Balance/Approve.
    // A missing daemon wallet emits gRPC FailedPrecondition which mapException
    // surfaces as PaymentException (the established FailedPrecondition→Payment
    // convention across all SDKs; semantic is a bit off vs REST's 503 but
    // matches every other SDK).

    public WalletAddress walletAddress() {
        try {
            GetWalletAddressResponse resp = walletStub.getAddress(
                    GetWalletAddressRequest.getDefaultInstance());
            return new WalletAddress(resp.getAddress());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public WalletBalance walletBalance() {
        try {
            GetWalletBalanceResponse resp = walletStub.getBalance(
                    GetWalletBalanceRequest.getDefaultInstance());
            return new WalletBalance(resp.getBalance(), resp.getGasBalance());
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }

    public boolean walletApprove() {
        try {
            WalletApproveResponse resp = walletStub.approve(
                    WalletApproveRequest.getDefaultInstance());
            return resp.getApproved();
        } catch (StatusRuntimeException e) {
            throw mapException(e);
        }
    }
}
