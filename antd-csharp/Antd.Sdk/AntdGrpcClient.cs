using Grpc.Core;
using Grpc.Net.Client;
using Google.Protobuf;
using Antd.V1;

namespace Antd.Sdk;

public sealed class AntdGrpcClient : IAntdClient
{
    private readonly GrpcChannel? _channel;
    private readonly HealthService.HealthServiceClient _health;
    private readonly DataService.DataServiceClient _data;
    private readonly ChunkService.ChunkServiceClient _chunks;
    private readonly FileService.FileServiceClient _files;
    private readonly UploadService.UploadServiceClient _upload;

    public AntdGrpcClient(string target = "http://localhost:50051")
    {
        _channel = GrpcChannel.ForAddress(target);
        _health = new HealthService.HealthServiceClient(_channel);
        _data = new DataService.DataServiceClient(_channel);
        _chunks = new ChunkService.ChunkServiceClient(_channel);
        _files = new FileService.FileServiceClient(_channel);
        _upload = new UploadService.UploadServiceClient(_channel);
    }

    /// <summary>
    /// Test-only constructor accepting pre-built service clients (which can be
    /// subclassed mocks). Bypasses channel construction so tests can run
    /// without a real network endpoint.
    /// </summary>
    internal AntdGrpcClient(
        HealthService.HealthServiceClient health,
        DataService.DataServiceClient data,
        ChunkService.ChunkServiceClient chunks,
        FileService.FileServiceClient files,
        UploadService.UploadServiceClient upload)
    {
        _channel = null;
        _health = health;
        _data = data;
        _chunks = chunks;
        _files = files;
        _upload = upload;
    }

    public static AntdGrpcClient AutoDiscover()
    {
        var target = DaemonDiscovery.DiscoverGrpcTarget();
        return string.IsNullOrEmpty(target) ? new AntdGrpcClient() : new AntdGrpcClient(target);
    }

    public void Dispose() => _channel?.Dispose();

    public ValueTask DisposeAsync()
    {
        _channel?.Dispose();
        return ValueTask.CompletedTask;
    }

    private static AntdException Wrap(RpcException ex) => ExceptionMapping.FromGrpcStatus(ex);

    // Health

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
            return new HealthStatus(true, "unknown");
        }
        catch
        {
            return new HealthStatus(false, "unknown");
        }
    }

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

    // Data

    public async Task<DataPutResult> DataPutAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto)
    {
        try
        {
            var resp = await _data.PutAsync(new PutDataRequest
            {
                Data = ByteString.CopyFrom(data),
                PaymentMode = paymentMode.ToWire(),
            });
            return new DataPutResult(resp.DataMap);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> DataGetAsync(string dataMap)
    {
        try
        {
            var resp = await _data.GetAsync(new GetDataRequest { DataMap = dataMap });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<DataPutPublicResult> DataPutPublicAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto)
    {
        try
        {
            var resp = await _data.PutPublicAsync(new PutPublicDataRequest
            {
                Data = ByteString.CopyFrom(data),
                PaymentMode = paymentMode.ToWire(),
            });
            return new DataPutPublicResult(resp.Address);
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

    public async Task<UploadCostEstimate> DataCostAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto)
    {
        try
        {
            var resp = await _data.CostAsync(new DataCostRequest
            {
                Data = ByteString.CopyFrom(data),
                PaymentMode = paymentMode.ToWire(),
            });
            return new UploadCostEstimate(
                resp.AttoTokens, resp.FileSize, resp.ChunkCount,
                resp.EstimatedGasCostWei, resp.PaymentMode);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // Chunks

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

    public async Task<PrepareChunkResult> PrepareChunkUploadAsync(byte[] data)
    {
        try
        {
            var resp = await _chunks.PrepareChunkAsync(new PrepareChunkRequest
            {
                Data = ByteString.CopyFrom(data),
            });
            var payments = resp.Payments
                .Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount))
                .ToList();
            return new PrepareChunkResult(
                resp.Address,
                resp.AlreadyStored,
                resp.UploadId,
                resp.PaymentType,
                payments,
                resp.TotalAmount,
                resp.PaymentVaultAddress,
                resp.PaymentTokenAddress,
                resp.RpcUrl);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> FinalizeChunkUploadAsync(string uploadId, IDictionary<string, string> txHashes)
    {
        try
        {
            var req = new FinalizeChunkRequest { UploadId = uploadId };
            foreach (var kv in txHashes) req.TxHashes[kv.Key] = kv.Value;
            var resp = await _chunks.FinalizeChunkAsync(req);
            return resp.Address;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // Files

    public async Task<FilePutResult> FilePutAsync(string path, PaymentMode paymentMode = PaymentMode.Auto)
    {
        try
        {
            var resp = await _files.PutAsync(new PutFileRequest
            {
                Path = path,
                PaymentMode = paymentMode.ToWire(),
            });
            return new FilePutResult(
                resp.DataMap, resp.StorageCostAtto, resp.GasCostWei,
                resp.ChunksStored, resp.PaymentModeUsed);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task FileGetAsync(string dataMap, string destPath)
    {
        try
        {
            await _files.GetAsync(new GetFileRequest { DataMap = dataMap, DestPath = destPath });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<FilePutPublicResult> FilePutPublicAsync(string path, PaymentMode paymentMode = PaymentMode.Auto)
    {
        try
        {
            var resp = await _files.PutPublicAsync(new PutFileRequest
            {
                Path = path,
                PaymentMode = paymentMode.ToWire(),
            });
            return new FilePutPublicResult(
                resp.Address, resp.StorageCostAtto, resp.GasCostWei,
                resp.ChunksStored, resp.PaymentModeUsed);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task FileGetPublicAsync(string address, string destPath)
    {
        try
        {
            await _files.GetPublicAsync(new GetFilePublicRequest { Address = address, DestPath = destPath });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<UploadCostEstimate> FileCostAsync(string path, bool isPublic = true, PaymentMode paymentMode = PaymentMode.Auto)
    {
        try
        {
            var resp = await _files.CostAsync(new Antd.V1.FileCostRequest
            {
                Path = path,
                IsPublic = isPublic,
                PaymentMode = paymentMode.ToWire(),
            });
            return new UploadCostEstimate(
                resp.AttoTokens, resp.FileSize, resp.ChunkCount,
                resp.EstimatedGasCostWei, resp.PaymentMode);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // Wallet (not yet available via gRPC)

    public Task<WalletAddress> WalletAddressAsync()
        => throw new NotSupportedException("WalletAddress is not yet supported via gRPC");

    public Task<WalletBalance> WalletBalanceAsync()
        => throw new NotSupportedException("WalletBalance is not yet supported via gRPC");

    public Task<bool> WalletApproveAsync()
        => throw new NotSupportedException("WalletApprove is not yet supported via gRPC");


    // External Signer (Two-Phase Upload)

    private static PrepareUploadResult MapPrepareResponse(PrepareUploadResponse resp)
    {
        var payments = resp.Payments
            .Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount))
            .ToList();

        var isMerkle = resp.PaymentType == "merkle";
        int? depth = isMerkle ? (int?)resp.Depth : null;
        long? merkleTs = isMerkle ? (long?)resp.MerklePaymentTimestamp : null;
        List<PoolCommitmentEntry>? poolCommitments = isMerkle
            ? resp.PoolCommitments.Select(pc => new PoolCommitmentEntry(
                pc.PoolHash,
                pc.Candidates.Select(c => new CandidateNodeEntry(c.RewardsAddress, c.Amount)).ToList()))
                .ToList()
            : null;

        return new PrepareUploadResult(
            UploadId: resp.UploadId,
            Payments: payments,
            TotalAmount: resp.TotalAmount,
            PaymentVaultAddress: resp.PaymentVaultAddress,
            PaymentTokenAddress: resp.PaymentTokenAddress,
            RpcUrl: resp.RpcUrl,
            PaymentType: resp.PaymentType,
            Depth: depth,
            PoolCommitments: poolCommitments,
            MerklePaymentTimestamp: merkleTs);
    }

    private static FinalizeUploadResult MapFinalizeResponse(FinalizeUploadResponse resp) =>
        new(resp.Address, (long)resp.ChunksStored, resp.DataMap, resp.DataMapAddress);

    public async Task<PrepareUploadResult> PrepareUploadAsync(string path, string? visibility = null)
    {
        try
        {
            var resp = await _upload.PrepareFileUploadAsync(new PrepareFileUploadRequest
            {
                Path = path,
                Visibility = visibility ?? "",
            });
            return MapPrepareResponse(resp);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public Task<PrepareUploadResult> PrepareUploadPublicAsync(string path) =>
        PrepareUploadAsync(path, "public");

    public async Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data, string? visibility = null)
    {
        try
        {
            var resp = await _upload.PrepareDataUploadAsync(new PrepareDataUploadRequest
            {
                Data = ByteString.CopyFrom(data),
                Visibility = visibility ?? "",
            });
            return MapPrepareResponse(resp);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes)
    {
        try
        {
            var req = new FinalizeUploadRequest { UploadId = uploadId };
            foreach (var kv in txHashes) req.TxHashes[kv.Key] = kv.Value;
            var resp = await _upload.FinalizeUploadAsync(req);
            return MapFinalizeResponse(resp);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash)
    {
        try
        {
            var resp = await _upload.FinalizeUploadAsync(new FinalizeUploadRequest
            {
                UploadId = uploadId,
                WinnerPoolHash = winnerPoolHash,
            });
            return new FinalizeMerkleUploadResult(
                resp.Address, (long)resp.ChunksStored, resp.DataMap, resp.DataMapAddress);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }
}
