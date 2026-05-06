using Grpc.Core;
using Grpc.Net.Client;
using Google.Protobuf;
using Antd.V1;

namespace Antd.Sdk;

public sealed class AntdGrpcClient : IAntdClient
{
    private readonly GrpcChannel _channel;
    private readonly HealthService.HealthServiceClient _health;
    private readonly DataService.DataServiceClient _data;
    private readonly ChunkService.ChunkServiceClient _chunks;
    private readonly FileService.FileServiceClient _files;

    public AntdGrpcClient(string target = "http://localhost:50051")
    {
        _channel = GrpcChannel.ForAddress(target);
        _health = new HealthService.HealthServiceClient(_channel);
        _data = new DataService.DataServiceClient(_channel);
        _chunks = new ChunkService.ChunkServiceClient(_channel);
        _files = new FileService.FileServiceClient(_channel);
    }

    /// <summary>
    /// Creates an AntdGrpcClient by reading the daemon.port file written by antd.
    /// Falls back to the default target if the port file is not found.
    /// </summary>
    public static AntdGrpcClient AutoDiscover()
    {
        var target = DaemonDiscovery.DiscoverGrpcTarget();
        return string.IsNullOrEmpty(target) ? new AntdGrpcClient() : new AntdGrpcClient(target);
    }

    public void Dispose() => _channel.Dispose();

    private static AntdException Wrap(RpcException ex) => ExceptionMapping.FromGrpcStatus(ex);

    // ── Health ──

    public async Task<HealthStatus> HealthAsync()
    {
        try
        {
            var resp = await _health.CheckAsync(new HealthCheckRequest());
            return HealthStatusFromResp(resp);
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.Unavailable)
        {
            return new HealthStatus(false, "unknown");
        }
        catch (RpcException)
        {
            return new HealthStatus(true, "unknown"); // server responded — it's reachable
        }
        catch
        {
            return new HealthStatus(false, "unknown");
        }
    }

    /// <summary>
    /// Convert a gRPC <see cref="HealthCheckResponse"/> into a typed
    /// <see cref="HealthStatus"/>.
    /// </summary>
    internal static HealthStatus HealthStatusFromResp(HealthCheckResponse resp) =>
        new(
            resp.Status == "ok",
            resp.Network ?? "unknown",
            resp.Version ?? "",
            resp.EvmNetwork ?? "",
            resp.UptimeSeconds,
            resp.BuildCommit ?? "",
            resp.PaymentTokenAddress ?? "",
            resp.PaymentVaultAddress ?? "");

    // ── Data ──

    public async Task<PutResult> DataPutPublicAsync(byte[] data, string? paymentMode = null)
    {
        try
        {
            var resp = await _data.PutPublicAsync(new PutPublicDataRequest { Data = ByteString.CopyFrom(data) });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> DataGetPublicAsync(string address)
    {
        try
        {
            var resp = await _data.GetPublicAsync(new GetPublicDataRequest { Address = address });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<PutResult> DataPutPrivateAsync(byte[] data, string? paymentMode = null)
    {
        try
        {
            var resp = await _data.PutPrivateAsync(new PutPrivateDataRequest { Data = ByteString.CopyFrom(data) });
            return new PutResult(resp.Cost.AttoTokens, resp.DataMap);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> DataGetPrivateAsync(string dataMap)
    {
        try
        {
            var resp = await _data.GetPrivateAsync(new GetPrivateDataRequest { DataMap = dataMap });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<UploadCostEstimate> DataCostAsync(byte[] data)
    {
        try
        {
            var resp = await _data.GetCostAsync(new DataCostRequest { Data = ByteString.CopyFrom(data) });
            return new UploadCostEstimate(
                resp.AttoTokens, resp.FileSize, resp.ChunkCount,
                resp.EstimatedGasCostWei, resp.PaymentMode);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Chunks ──

    public async Task<PutResult> ChunkPutAsync(byte[] data)
    {
        try
        {
            var resp = await _chunks.PutAsync(new PutChunkRequest { Data = ByteString.CopyFrom(data) });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> ChunkGetAsync(string address)
    {
        try
        {
            var resp = await _chunks.GetAsync(new GetChunkRequest { Address = address });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Files ──

    public async Task<FileUploadResult> FileUploadPublicAsync(string path, string? paymentMode = null)
    {
        try
        {
            var resp = await _files.UploadPublicAsync(new UploadFileRequest { Path = path });
            return new FileUploadResult(resp.Address, resp.StorageCostAtto, resp.GasCostWei, resp.ChunksStored, resp.PaymentModeUsed);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task FileDownloadPublicAsync(string address, string destPath)
    {
        try
        {
            await _files.DownloadPublicAsync(new DownloadPublicRequest { Address = address, DestPath = destPath });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<FileUploadResult> DirUploadPublicAsync(string path, string? paymentMode = null)
    {
        try
        {
            var resp = await _files.DirUploadPublicAsync(new UploadFileRequest { Path = path });
            return new FileUploadResult(resp.Address, resp.StorageCostAtto, resp.GasCostWei, resp.ChunksStored, resp.PaymentModeUsed);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task DirDownloadPublicAsync(string address, string destPath)
    {
        try
        {
            await _files.DirDownloadPublicAsync(new DownloadPublicRequest { Address = address, DestPath = destPath });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<UploadCostEstimate> FileCostAsync(string path, bool isPublic = true)
    {
        try
        {
            var resp = await _files.GetFileCostAsync(new Antd.V1.FileCostRequest
            {
                Path = path,
                IsPublic = isPublic,
            });
            return new UploadCostEstimate(
                resp.AttoTokens, resp.FileSize, resp.ChunkCount,
                resp.EstimatedGasCostWei, resp.PaymentMode);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Wallet (not yet available via gRPC) ──

    public Task<WalletAddress> WalletAddressAsync()
        => throw new NotSupportedException("WalletAddress is not yet supported via gRPC");

    public Task<WalletBalance> WalletBalanceAsync()
        => throw new NotSupportedException("WalletBalance is not yet supported via gRPC");

    public Task<bool> WalletApproveAsync()
        => throw new NotSupportedException("WalletApprove is not yet supported via gRPC");

    // ── External Signer (not yet available via gRPC) ──

    public Task<PrepareUploadResult> PrepareUploadAsync(string path)
        => throw new NotSupportedException("PrepareUpload is not yet supported via gRPC");

    public Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data)
        => throw new NotSupportedException("PrepareDataUpload is not yet supported via gRPC");

    public Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes)
        => throw new NotSupportedException("FinalizeUpload is not yet supported via gRPC");

    public Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash)
        => throw new NotSupportedException("FinalizeMerkleUpload is not yet supported via gRPC");
}
