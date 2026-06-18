using System.Text;
using Antd.V1;
using Google.Protobuf;
using Grpc.Core;
using Grpc.Core.Testing;
using Xunit;

namespace Antd.Sdk.Tests;

/// <summary>
/// Mock-server tests for AntdGrpcClient's V2-284 external-signer surface.
/// Mirrors the antd-rust / antd-go / antd-py / antd-java / antd-kotlin
/// suites.
///
/// Bypasses the channel by passing pre-built service-client subclasses that
/// override the generated <c>*Async</c> methods to return canned
/// <see cref="AsyncUnaryCall{TResponse}"/> values via the
/// <see cref="TestCalls"/> helpers.
/// </summary>
public sealed class GrpcClientTests
{
    private static AsyncUnaryCall<T> Reply<T>(T value) =>
        TestCalls.AsyncUnaryCall(
            Task.FromResult(value),
            Task.FromResult(new Metadata()),
            () => Status.DefaultSuccess,
            () => new Metadata(),
            () => { });

    private sealed class MockChunkServiceClient : ChunkService.ChunkServiceClient
    {
        public override AsyncUnaryCall<PrepareChunkResponse> PrepareChunkAsync(
            PrepareChunkRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            // Inputs starting with "EXISTS" → already-stored short-circuit.
            var prefix = Encoding.UTF8.GetString(
                request.Data.ToByteArray(), 0, Math.Min(6, request.Data.Length));
            if (prefix == "EXISTS")
            {
                return Reply(new PrepareChunkResponse
                {
                    Address = "0xabc",
                    AlreadyStored = true,
                });
            }
            var resp = new PrepareChunkResponse
            {
                Address = "0xnewchunk",
                AlreadyStored = false,
                UploadId = "upid_chunk_42",
                PaymentType = "wave_batch",
                TotalAmount = "100",
                PaymentVaultAddress = "0xvault",
                PaymentTokenAddress = "0xtoken",
                RpcUrl = "http://localhost:8545",
            };
            resp.Payments.Add(new PaymentEntry
            {
                QuoteHash = "0xq1",
                RewardsAddress = "0xr1",
                Amount = "100",
            });
            return Reply(resp);
        }

        public override AsyncUnaryCall<FinalizeChunkResponse> FinalizeChunkAsync(
            FinalizeChunkRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            // Echo upload_id into address so the test can verify forwarding.
            return Reply(new FinalizeChunkResponse
            {
                Address = $"addr_for_{request.UploadId}",
            });
        }
    }

    private sealed class MockUploadServiceClient : UploadService.UploadServiceClient
    {
        public override AsyncUnaryCall<PrepareUploadResponse> PrepareFileUploadAsync(
            PrepareFileUploadRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            var resp = new PrepareUploadResponse
            {
                UploadId = $"upid_file_{request.Visibility}",
                PaymentType = "wave_batch",
                TotalAmount = "1",
                PaymentVaultAddress = "0xvault",
                PaymentTokenAddress = "0xtoken",
                RpcUrl = "http://localhost:8545",
            };
            resp.Payments.Add(new PaymentEntry
            {
                QuoteHash = "0xqa",
                RewardsAddress = "0xra",
                Amount = "1",
            });
            return Reply(resp);
        }

        public override AsyncUnaryCall<PrepareUploadResponse> PrepareDataUploadAsync(
            PrepareDataUploadRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            var uid = $"upid_data_{request.Visibility}";
            var prefix = Encoding.UTF8.GetString(
                request.Data.ToByteArray(), 0, Math.Min(6, request.Data.Length));
            if (prefix == "MERKLE")
            {
                var merkle = new PrepareUploadResponse
                {
                    UploadId = uid,
                    PaymentType = "merkle",
                    Depth = 7,
                    MerklePaymentTimestamp = 1_700_000_000L,
                    TotalAmount = "0",
                    PaymentVaultAddress = "0xvault",
                    PaymentTokenAddress = "0xtoken",
                    RpcUrl = "http://localhost:8545",
                };
                var pc = new Antd.V1.PoolCommitmentEntry { PoolHash = "0xpool" };
                pc.Candidates.Add(new Antd.V1.CandidateNodeEntry
                {
                    RewardsAddress = "0xc1",
                    Amount = "5",
                });
                merkle.PoolCommitments.Add(pc);
                return Reply(merkle);
            }
            var wave = new PrepareUploadResponse
            {
                UploadId = uid,
                PaymentType = "wave_batch",
                TotalAmount = "2",
                PaymentVaultAddress = "0xvault",
                PaymentTokenAddress = "0xtoken",
                RpcUrl = "http://localhost:8545",
            };
            wave.Payments.Add(new PaymentEntry
            {
                QuoteHash = "0xqb",
                RewardsAddress = "0xrb",
                Amount = "2",
            });
            return Reply(wave);
        }

        public override AsyncUnaryCall<FinalizeUploadResponse> FinalizeUploadAsync(
            FinalizeUploadRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            // Merkle: winner_pool_hash populated.
            if (!string.IsNullOrEmpty(request.WinnerPoolHash))
            {
                return Reply(new FinalizeUploadResponse
                {
                    DataMap = "dm_merkle",
                    Address = request.StoreDataMap ? "stored_on_network" : "",
                    ChunksStored = 64UL,
                });
            }
            // Wave-batch: include data_map_address when visibility was public.
            var dmAddress = request.UploadId.EndsWith("public") ? "addr_public_dm" : "";
            return Reply(new FinalizeUploadResponse
            {
                DataMap = "dm_wave",
                DataMapAddress = dmAddress,
                ChunksStored = 3UL,
            });
        }
    }

    /// <summary>In-memory <see cref="IAsyncStreamReader{T}"/> over a fixed list,
    /// so the mock server-stream needs no live channel.</summary>
    private sealed class ListStreamReader<T> : IAsyncStreamReader<T>
    {
        private readonly IEnumerator<T> _e;
        public ListStreamReader(IEnumerable<T> items) => _e = items.GetEnumerator();
        public T Current => _e.Current;
        public Task<bool> MoveNext(CancellationToken cancellationToken) => Task.FromResult(_e.MoveNext());
    }

    private sealed class MockDataServiceClient : DataService.DataServiceClient
    {
        private static AsyncServerStreamingCall<DataChunk> Stream(Metadata responseHeaders, params DataChunk[] frames) =>
            TestCalls.AsyncServerStreamingCall(
                new ListStreamReader<DataChunk>(frames),
                Task.FromResult(responseHeaders),
                () => Status.DefaultSuccess,
                () => new Metadata(),
                () => { });

        // Server-streams the payload in two chunks so the client's
        // chunk-by-chunk consumption is exercised, not just a single message.
        // When include_progress is set, interleaves a progress frame between the
        // data frames — mirroring the daemon's oneof DataChunk behaviour — and
        // sends the byte-total denominator as x-content-length initial metadata.
        private static AsyncServerStreamingCall<DataChunk> StreamOf(bool includeProgress, params byte[][] parts)
        {
            var frames = new List<DataChunk>();
            if (includeProgress)
                frames.Add(new DataChunk { Progress = new Antd.V1.DownloadProgress { Phase = "fetching", Fetched = 1, Total = 2 } });
            frames.AddRange(parts.Select(p => new DataChunk { Data = ByteString.CopyFrom(p) }));
            var total = parts.Sum(p => p.Length);
            var headers = includeProgress
                ? new Metadata { { "x-content-length", total.ToString() } }
                : new Metadata();
            return Stream(headers, frames.ToArray());
        }

        public override AsyncServerStreamingCall<DataChunk> Stream(StreamDataRequest request, CallOptions options)
            => StreamOf(request.IncludeProgress, Encoding.UTF8.GetBytes("sec"), Encoding.UTF8.GetBytes("ret"));

        public override AsyncServerStreamingCall<DataChunk> StreamPublic(StreamPublicDataRequest request, CallOptions options)
            => StreamOf(request.IncludeProgress, Encoding.UTF8.GetBytes("hel"), Encoding.UTF8.GetBytes("lo"));
    }

    private static AntdGrpcClient MakeClient() =>
        new AntdGrpcClient(
            health: new HealthService.HealthServiceClient(new TestServiceInvoker()),
            data: new MockDataServiceClient(),
            chunks: new MockChunkServiceClient(),
            files: new FileService.FileServiceClient(new TestServiceInvoker()),
            upload: new MockUploadServiceClient(),
            wallet: new WalletService.WalletServiceClient(new TestServiceInvoker()));

    /// <summary>
    /// Stub CallInvoker for the service clients we don't override — never
    /// invoked by the V2-284 tests.
    /// </summary>
    private sealed class TestServiceInvoker : CallInvoker
    {
        public override TResponse BlockingUnaryCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options, TRequest request) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncUnaryCall<TResponse> AsyncUnaryCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options, TRequest request) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncServerStreamingCall<TResponse> AsyncServerStreamingCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options, TRequest request) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncClientStreamingCall<TRequest, TResponse> AsyncClientStreamingCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncDuplexStreamingCall<TRequest, TResponse> AsyncDuplexStreamingCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options) =>
            throw new NotSupportedException("test invoker — not exercised");
    }

    // --- Tests ---

    [Fact]
    public async Task PrepareUpload_OmitsVisibilityWhenNull()
    {
        var client = MakeClient();
        var r = await client.PrepareUploadAsync("/tmp/x.bin");
        Assert.Equal("upid_file_", r.UploadId);
        Assert.Equal("wave_batch", r.PaymentType);
        Assert.Single(r.Payments);
        Assert.Equal("0xqa", r.Payments[0].QuoteHash);
        Assert.Null(r.Depth);
        Assert.Null(r.PoolCommitments);
        Assert.Null(r.MerklePaymentTimestamp);
    }

    [Fact]
    public async Task PrepareUpload_ForwardsVisibilityPublic()
    {
        var client = MakeClient();
        var r = await client.PrepareUploadAsync("/tmp/x.bin", "public");
        Assert.Equal("upid_file_public", r.UploadId);
    }

    [Fact]
    public async Task PrepareUploadPublic_ConvenienceWrapper()
    {
        var client = MakeClient();
        var r = await client.PrepareUploadPublicAsync("/tmp/x.bin");
        Assert.Equal("upid_file_public", r.UploadId);
    }

    [Fact]
    public async Task PrepareDataUpload_WaveBatch()
    {
        var client = MakeClient();
        var r = await client.PrepareDataUploadAsync(Encoding.UTF8.GetBytes("small"));
        Assert.Equal("upid_data_", r.UploadId);
        Assert.Equal("wave_batch", r.PaymentType);
        Assert.Null(r.Depth);
    }

    [Fact]
    public async Task PrepareDataUpload_Merkle()
    {
        var client = MakeClient();
        var r = await client.PrepareDataUploadAsync(Encoding.UTF8.GetBytes("MERKLE-large-payload"));
        Assert.Equal("merkle", r.PaymentType);
        Assert.Equal(7, r.Depth);
        Assert.Equal(1_700_000_000L, r.MerklePaymentTimestamp);
        Assert.NotNull(r.PoolCommitments);
        Assert.Single(r.PoolCommitments!);
        Assert.Equal("0xpool", r.PoolCommitments![0].PoolHash);
        Assert.Equal("0xc1", r.PoolCommitments![0].Candidates[0].RewardsAddress);
    }

    [Fact]
    public async Task FinalizeUpload_WaveBatchPrivateOmitsDataMapAddress()
    {
        var client = MakeClient();
        var r = await client.FinalizeUploadAsync("upid_file_", new() { ["0xq1"] = "0xtx1" });
        Assert.Equal("dm_wave", r.DataMap);
        Assert.Equal("", r.DataMapAddress);
        Assert.Equal(3L, r.ChunksStored);
    }

    [Fact]
    public async Task FinalizeUpload_WaveBatchPublicReturnsDataMapAddress()
    {
        var client = MakeClient();
        var r = await client.FinalizeUploadAsync("upid_file_public", new() { ["0xq1"] = "0xtx1" });
        Assert.Equal("addr_public_dm", r.DataMapAddress);
    }

    [Fact]
    public async Task FinalizeMerkleUpload_ReturnsMerkleResult()
    {
        var client = MakeClient();
        var r = await client.FinalizeMerkleUploadAsync("upid_data_", "0xwinpool");
        Assert.Equal("dm_merkle", r.DataMap);
        // store_data_map defaults to false → address empty.
        Assert.Equal("", r.Address);
        Assert.Equal(64L, r.ChunksStored);
    }

    [Fact]
    public async Task PrepareChunkUpload_NewChunk()
    {
        var client = MakeClient();
        var r = await client.PrepareChunkUploadAsync(Encoding.UTF8.GetBytes("newchunk"));
        Assert.False(r.AlreadyStored);
        Assert.Equal("0xnewchunk", r.Address);
        Assert.Equal("upid_chunk_42", r.UploadId);
        Assert.Equal("wave_batch", r.PaymentType);
        Assert.NotNull(r.Payments);
        Assert.Single(r.Payments!);
        Assert.Equal("0xq1", r.Payments![0].QuoteHash);
        Assert.Equal("100", r.TotalAmount);
        Assert.Equal("http://localhost:8545", r.RpcUrl);
    }

    [Fact]
    public async Task PrepareChunkUpload_AlreadyStoredShortCircuit()
    {
        var client = MakeClient();
        var r = await client.PrepareChunkUploadAsync(Encoding.UTF8.GetBytes("EXISTS-data"));
        Assert.True(r.AlreadyStored);
        Assert.Equal("0xabc", r.Address);
        Assert.Equal("", r.UploadId);
        Assert.True(r.Payments == null || r.Payments.Count == 0);
    }

    [Fact]
    public async Task FinalizeChunkUpload_ReturnsAddressAndForwardsBody()
    {
        var client = MakeClient();
        var addr = await client.FinalizeChunkUploadAsync(
            "upid_chunk_42", new Dictionary<string, string> { ["0xq1"] = "0xtxabc" });
        Assert.Equal("addr_for_upid_chunk_42", addr);
    }

    [Fact]
    public async Task DataStream_Private_YieldsChunks()
    {
        var client = MakeClient();
        var buf = new List<byte>();
        await foreach (var chunk in client.DataStreamAsync("dm123"))
            buf.AddRange(chunk);
        Assert.Equal("secret", Encoding.UTF8.GetString(buf.ToArray()));
    }

    [Fact]
    public async Task DataStream_Public_YieldsChunks()
    {
        var client = MakeClient();
        var buf = new List<byte>();
        await foreach (var chunk in client.DataStreamPublicAsync("abc123"))
            buf.AddRange(chunk);
        Assert.Equal("hello", Encoding.UTF8.GetString(buf.ToArray()));
    }

    [Fact]
    public async Task DataStreamWithProgress_Private_ReassemblesDataAndObservesProgress()
    {
        var client = MakeClient();
        var buf = new List<byte>();
        DownloadProgress? progress = null;
        ulong? totalSize = null;
        var sawData = false;
        await foreach (var frame in client.DataStreamWithProgressAsync("dm123"))
        {
            if (frame.IsMeta)
            {
                Assert.False(sawData, "meta frame must arrive before any data");
                totalSize = frame.TotalSize;
            }
            else if (frame.IsProgress) progress = frame.Progress;
            else { sawData = true; buf.AddRange(frame.Data!); }
        }
        Assert.Equal("secret", Encoding.UTF8.GetString(buf.ToArray()));
        // The byte-total denominator is surfaced from x-content-length (sec+ret = 6).
        Assert.Equal(6UL, totalSize);
        Assert.NotNull(progress);
        Assert.Equal("fetching", progress!.Phase);
        Assert.Equal(1UL, progress.Fetched);
        Assert.Equal(2UL, progress.Total);
    }

    [Fact]
    public async Task DataStreamWithProgress_Public_ReassemblesDataAndObservesProgress()
    {
        var client = MakeClient();
        var buf = new List<byte>();
        var sawProgress = false;
        ulong? totalSize = null;
        await foreach (var frame in client.DataStreamPublicWithProgressAsync("abc123"))
        {
            if (frame.IsMeta) totalSize = frame.TotalSize;
            else if (frame.IsProgress) sawProgress = true;
            else buf.AddRange(frame.Data!);
        }
        Assert.Equal("hello", Encoding.UTF8.GetString(buf.ToArray()));
        Assert.True(sawProgress);
        // hel+lo = 5 bytes surfaced from x-content-length.
        Assert.Equal(5UL, totalSize);
    }
}
