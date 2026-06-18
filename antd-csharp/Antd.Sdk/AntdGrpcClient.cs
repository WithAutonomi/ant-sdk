using System.Runtime.CompilerServices;
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
    private readonly WalletService.WalletServiceClient _wallet;

    public AntdGrpcClient(string target = "http://localhost:50051")
    {
        _channel = GrpcChannel.ForAddress(target);
        _health = new HealthService.HealthServiceClient(_channel);
        _data = new DataService.DataServiceClient(_channel);
        _chunks = new ChunkService.ChunkServiceClient(_channel);
        _files = new FileService.FileServiceClient(_channel);
        _upload = new UploadService.UploadServiceClient(_channel);
        _wallet = new WalletService.WalletServiceClient(_channel);
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
        UploadService.UploadServiceClient upload,
        WalletService.WalletServiceClient wallet)
    {
        _channel = null!;
        _health = health;
        _data = data;
        _chunks = chunks;
        _files = files;
        _upload = upload;
        _wallet = wallet;
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
            return new DataPutResult(resp.DataMap, resp.ChunksStored, resp.PaymentModeUsed);
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
            return new DataPutPublicResult(resp.Address, resp.ChunksStored, resp.PaymentModeUsed);
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

    /// <summary>
    /// Streams private data from a caller-held DataMap (hex), one decrypt batch
    /// at a time, instead of buffering the whole object. The gRPC counterpart to
    /// <see cref="DataGetAsync"/> and mirror of the REST client's DataStream;
    /// yields raw byte chunks the caller consumes incrementally.
    /// </summary>
    public IAsyncEnumerable<byte[]> DataStreamAsync(string dataMap, CancellationToken cancellationToken = default)
        => StreamChunksAsync(_data.Stream(new StreamDataRequest { DataMap = dataMap }), cancellationToken);

    /// <summary>
    /// Streams public data by address — the gRPC counterpart to
    /// <see cref="DataGetPublicAsync"/>. Yields raw byte chunks.
    /// </summary>
    public IAsyncEnumerable<byte[]> DataStreamPublicAsync(string address, CancellationToken cancellationToken = default)
        => StreamChunksAsync(_data.StreamPublic(new StreamPublicDataRequest { Address = address }), cancellationToken);

    private static async IAsyncEnumerable<byte[]> StreamChunksAsync(
        AsyncServerStreamingCall<DataChunk> call,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        using (call)
        {
            while (true)
            {
                bool moved;
                // gRPC surfaces transport/server errors on MoveNext, so the
                // mapping to AntdException lives here rather than at the call.
                try { moved = await call.ResponseStream.MoveNext(cancellationToken); }
                catch (RpcException ex) { throw Wrap(ex); }
                if (!moved) yield break;
                var chunk = call.ResponseStream.Current;
                // include_progress was not set, so no progress frames arrive;
                // the oneof's .Data accessor still yields the plaintext bytes
                // (empty ByteString for a stray non-data frame).
                if (chunk.KindCase != DataChunk.KindOneofCase.Progress)
                    yield return chunk.Data.ToByteArray();
            }
        }
    }

    /// <summary>
    /// Streams private data like <see cref="DataStreamAsync"/> but requests
    /// interleaved fetch-progress frames (<c>include_progress=true</c>) so the
    /// caller can drive a <em>determinate</em> download progress bar. Each item
    /// is a <see cref="DownloadFrame"/> — either a plaintext byte chunk or a
    /// <see cref="DownloadProgress"/> update. The byte denominator is surfaced as
    /// a leading meta frame (<see cref="DownloadFrame.IsMeta"/>), read from the
    /// response's <c>x-content-length</c> metadata.
    /// </summary>
    public IAsyncEnumerable<DownloadFrame> DataStreamWithProgressAsync(string dataMap, CancellationToken cancellationToken = default)
        => StreamFramesAsync(_data.Stream(new StreamDataRequest { DataMap = dataMap, IncludeProgress = true }), cancellationToken);

    /// <summary>
    /// Public counterpart to <see cref="DataStreamWithProgressAsync"/>.
    /// </summary>
    public IAsyncEnumerable<DownloadFrame> DataStreamPublicWithProgressAsync(string address, CancellationToken cancellationToken = default)
        => StreamFramesAsync(_data.StreamPublic(new StreamPublicDataRequest { Address = address, IncludeProgress = true }), cancellationToken);

    private static async IAsyncEnumerable<DownloadFrame> StreamFramesAsync(
        AsyncServerStreamingCall<DataChunk> call,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        using (call)
        {
            var meta = await MetaFrameAsync(call);
            if (meta != null) yield return meta;

            while (true)
            {
                bool moved;
                try { moved = await call.ResponseStream.MoveNext(cancellationToken); }
                catch (RpcException ex) { throw Wrap(ex); }
                if (!moved) yield break;
                yield return FrameOf(call.ResponseStream.Current);
            }
        }
    }

    /// <summary>
    /// Reads the total download size from the stream's <c>x-content-length</c>
    /// response metadata (sent before the first chunk) and wraps it as a leading
    /// <see cref="DownloadFrame"/> meta frame. <see cref="AsyncServerStreamingCall{T}.ResponseHeadersAsync"/>
    /// completes once the server sends its initial metadata. Returns <c>null</c>
    /// when the header is absent or unparseable (older daemons), so no meta frame
    /// is emitted.
    /// </summary>
    private static async Task<DownloadFrame?> MetaFrameAsync(AsyncServerStreamingCall<DataChunk> call)
    {
        Metadata headers;
        try { headers = await call.ResponseHeadersAsync; }
        catch (RpcException ex) { throw Wrap(ex); }
        var value = headers.GetValue("x-content-length");
        return value != null && ulong.TryParse(value, out var total)
            ? DownloadFrame.OfMeta(total)
            : null;
    }

    /// <summary>
    /// Maps a wire <see cref="DataChunk"/> onto a <see cref="DownloadFrame"/>. A
    /// progress frame carries a <see cref="DownloadProgress"/>; any other case
    /// (data, or an unset oneof — which shouldn't occur) is treated as data
    /// bytes (empty for an unset oneof).
    /// </summary>
    private static DownloadFrame FrameOf(DataChunk chunk) =>
        chunk.KindCase == DataChunk.KindOneofCase.Progress
            ? DownloadFrame.OfProgress(new DownloadProgress(
                chunk.Progress.Phase, chunk.Progress.Fetched, chunk.Progress.Total))
            : DownloadFrame.OfData(chunk.Data.ToByteArray());

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

    // Wallet — V2-286 parity with REST AntdRestClient.WalletAddress/Balance/Approve.
    // A missing daemon wallet emits gRPC FailedPrecondition; the existing
    // ExceptionMapping.FromGrpcStatus maps that to PaymentError (established
    // FailedPrecondition->Payment convention across all SDKs).

    public async Task<WalletAddress> WalletAddressAsync()
    {
        try
        {
            var resp = await _wallet.GetAddressAsync(new GetWalletAddressRequest());
            return new WalletAddress(resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<WalletBalance> WalletBalanceAsync()
    {
        try
        {
            var resp = await _wallet.GetBalanceAsync(new GetWalletBalanceRequest());
            return new WalletBalance(resp.Balance, resp.GasBalance);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<bool> WalletApproveAsync()
    {
        try
        {
            var resp = await _wallet.ApproveAsync(new WalletApproveRequest());
            return resp.Approved;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }


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
