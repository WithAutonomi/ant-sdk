using System.Net;
using System.Text;
using System.Text.Json;
using Antd.Sdk;
using Grpc.Core;
using Xunit;

namespace Antd.Sdk.Tests;

/// <summary>
/// A lightweight mock HTTP server using HttpListener.
/// Routes requests by method + path and returns canned JSON responses.
/// </summary>
internal sealed class MockServer : IDisposable
{
    private readonly HttpListener _listener = new();
    private readonly CancellationTokenSource _cts = new();
    private readonly Dictionary<string, (int StatusCode, string Body)> _routes = new();
    private readonly Dictionary<string, Func<string, (int StatusCode, string Body)>> _dynamicRoutes = new();
    private Task? _loop;

    /// <summary>Most recent request body received for each "METHOD path" key.</summary>
    public Dictionary<string, string> LastRequestBodies { get; } = new();

    public string BaseUrl { get; }

    public MockServer()
    {
        // Find a free port by binding to port 0, then releasing it.
        var tmp = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        tmp.Start();
        var port = ((System.Net.IPEndPoint)tmp.LocalEndpoint).Port;
        tmp.Stop();

        BaseUrl = $"http://localhost:{port}/";
        _listener.Prefixes.Add(BaseUrl);
    }

    /// <summary>
    /// Register a canned response for a given method + path.
    /// Path should start with "/".
    /// </summary>
    public void Route(string method, string path, int statusCode, string body)
    {
        _routes[$"{method.ToUpperInvariant()} {path}"] = (statusCode, body);
    }

    /// <summary>Register a 200 JSON response.</summary>
    public void RouteOk(string method, string path, object json)
    {
        var body = JsonSerializer.Serialize(json);
        Route(method, path, 200, body);
    }

    /// <summary>
    /// Register a handler that picks the response from the request body —
    /// used for endpoints whose response shape branches on input (e.g.
    /// /v1/chunks/prepare, where already-stored and new-chunk paths differ).
    /// </summary>
    public void RouteDynamic(string method, string path, Func<string, (int StatusCode, string Body)> handler)
    {
        _dynamicRoutes[$"{method.ToUpperInvariant()} {path}"] = handler;
    }

    public void Start()
    {
        _listener.Start();
        _loop = Task.Run(async () =>
        {
            while (!_cts.IsCancellationRequested)
            {
                try
                {
                    var ctx = await _listener.GetContextAsync();
                    HandleRequest(ctx);
                }
                catch (HttpListenerException) { break; }
                catch (ObjectDisposedException) { break; }
            }
        });
    }

    private void HandleRequest(HttpListenerContext ctx)
    {
        var method = ctx.Request.HttpMethod.ToUpperInvariant();
        // Strip query string for route matching
        var path = ctx.Request.Url!.AbsolutePath;
        var key = $"{method} {path}";

        // Capture the request body (always — tests want to inspect what the
        // client actually sent, regardless of which response variant we picked).
        string requestBody = "";
        if (ctx.Request.HasEntityBody)
        {
            using var reader = new System.IO.StreamReader(ctx.Request.InputStream, ctx.Request.ContentEncoding);
            requestBody = reader.ReadToEnd();
        }
        LastRequestBodies[key] = requestBody;

        if (_dynamicRoutes.TryGetValue(key, out var handler))
        {
            var (statusCode, body) = handler(requestBody);
            ctx.Response.StatusCode = statusCode;
            ctx.Response.ContentType = "application/json";
            var bytes = Encoding.UTF8.GetBytes(body);
            ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        }
        else if (_routes.TryGetValue(key, out var route))
        {
            ctx.Response.StatusCode = route.StatusCode;
            ctx.Response.ContentType = "application/json";
            var bytes = Encoding.UTF8.GetBytes(route.Body);
            ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        }
        else
        {
            // Fallback: 404
            ctx.Response.StatusCode = 404;
            var msg = Encoding.UTF8.GetBytes($"No mock route for {key}");
            ctx.Response.OutputStream.Write(msg, 0, msg.Length);
        }

        ctx.Response.Close();
    }

    public void Dispose()
    {
        _cts.Cancel();
        _listener.Stop();
        _listener.Close();
        _cts.Dispose();
    }
}

/// <summary>
/// xUnit unit tests for AntdRestClient using a local mock HTTP server.
/// </summary>
public sealed class AntdRestClientTests : IDisposable
{
    private readonly MockServer _server;
    private readonly AntdRestClient _client;

    public AntdRestClientTests()
    {
        _server = new MockServer();
        _client = new AntdRestClient(_server.BaseUrl, timeout: TimeSpan.FromSeconds(5));
    }

    public void Dispose()
    {
        _client.Dispose();
        _server.Dispose();
    }

    // ── Health ──

    [Fact]
    public async Task HealthAsync_ReturnsOk()
    {
        _server.RouteOk("GET", "/health", new
        {
            status = "ok",
            network = "testnet",
            version = "0.4.0",
            evm_network = "local",
            uptime_seconds = 42,
            build_commit = "abcdef123456",
            payment_token_address = "0xtoken",
            payment_vault_address = "0xvault",
        });
        _server.Start();

        var result = await _client.HealthAsync();

        Assert.True(result.Ok);
        Assert.Equal("testnet", result.Network);
        Assert.Equal("0.4.0", result.Version);
        Assert.Equal("local", result.EvmNetwork);
        Assert.Equal(42UL, result.UptimeSeconds);
        Assert.Equal("abcdef123456", result.BuildCommit);
        Assert.Equal("0xtoken", result.PaymentTokenAddress);
        Assert.Equal("0xvault", result.PaymentVaultAddress);
    }

    [Fact]
    public async Task HealthAsync_PreV0_4_0Daemon_LeavesDiagnosticsEmpty()
    {
        // Older daemons reply with just status + network; the optional DTO
        // properties default to null, and HealthStatusFromDto fills "" / 0.
        _server.RouteOk("GET", "/health", new { status = "ok", network = "default" });
        _server.Start();

        var result = await _client.HealthAsync();

        Assert.True(result.Ok);
        Assert.Equal("default", result.Network);
        Assert.Equal("", result.Version);
        Assert.Equal("", result.EvmNetwork);
        Assert.Equal(0UL, result.UptimeSeconds);
        Assert.Equal("", result.BuildCommit);
    }

    [Fact]
    public async Task HealthAsync_ServerDown_ReturnsFalse()
    {
        // Don't start the server - connection will fail
        var deadClient = new AntdRestClient("http://localhost:1", timeout: TimeSpan.FromSeconds(1));
        try
        {
            var result = await deadClient.HealthAsync();
            Assert.False(result.Ok);
            Assert.Equal("unknown", result.Network);
        }
        finally
        {
            deadClient.Dispose();
        }
    }

    // ── Data Public ──

    [Fact]
    public async Task DataPutPublicAsync_ReturnsCostAndAddress()
    {
        _server.RouteOk("POST", "/v1/data/public", new
        {
            cost = "42",
            address = "abc123def456"
        });
        _server.Start();

        var result = await _client.DataPutPublicAsync(Encoding.UTF8.GetBytes("hello"));

        Assert.Equal("abc123def456", result.Address);
    }

    [Fact]
    public async Task DataGetPublicAsync_ReturnsDecodedBytes()
    {
        var original = Encoding.UTF8.GetBytes("test data content");
        _server.RouteOk("GET", "/v1/data/public/abc123", new
        {
            data = Convert.ToBase64String(original)
        });
        _server.Start();

        var result = await _client.DataGetPublicAsync("abc123");

        Assert.Equal(original, result);
    }

    // ── Data Private ──

    [Fact]
    public async Task DataPutPrivateAsync_ReturnsCostAndDataMap()
    {
        _server.RouteOk("POST", "/v1/data", new
        {
            cost = "99",
            data_map = "map_abc123"
        });
        _server.Start();

        var result = await _client.DataPutAsync(Encoding.UTF8.GetBytes("secret"));

        Assert.Equal("map_abc123", result.DataMap);
    }

    [Fact]
    public async Task DataGetPrivateAsync_ReturnsDecodedBytes()
    {
        var original = Encoding.UTF8.GetBytes("private data content");
        _server.RouteOk("POST", "/v1/data/get", new
        {
            data = Convert.ToBase64String(original)
        });
        _server.Start();

        var result = await _client.DataGetAsync("some_data_map");

        Assert.Equal(original, result);
    }

    // ── Data Streaming ──

    [Fact]
    public async Task DataStreamAsync_ReturnsRawByteStream()
    {
        var original = Encoding.UTF8.GetBytes("private streamed content");
        // The daemon streams raw decrypted bytes (not base64/JSON).
        _server.Route("POST", "/v1/data/stream", 200, Encoding.UTF8.GetString(original));
        _server.Start();

        await using var stream = await _client.DataStreamAsync("some_data_map");
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms);

        Assert.Equal(original, ms.ToArray());
        // Verify the request body matches the buffered get (data_map field).
        var sent = _server.LastRequestBodies["POST /v1/data/stream"];
        Assert.Contains("some_data_map", sent);
    }

    [Fact]
    public async Task DataStreamPublicAsync_ReturnsRawByteStream()
    {
        var original = Encoding.UTF8.GetBytes("public streamed content");
        _server.Route("GET", "/v1/data/public/abc123/stream", 200, Encoding.UTF8.GetString(original));
        _server.Start();

        await using var stream = await _client.DataStreamPublicAsync("abc123");
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms);

        Assert.Equal(original, ms.ToArray());
    }

    [Fact]
    public async Task DataStreamAsync_Non2xx_ThrowsMappedException()
    {
        _server.Route("POST", "/v1/data/stream", 404, "{\"error\":\"not found\",\"code\":\"NOT_FOUND\"}");
        _server.Start();

        var ex = await Assert.ThrowsAsync<NotFoundException>(
            () => _client.DataStreamAsync("missing"));

        Assert.Equal(404, ex.StatusCode);
        Assert.Contains("not found", ex.Message);
    }

    [Fact]
    public async Task DataStreamPublicAsync_Non2xx_ThrowsMappedException()
    {
        _server.Route("GET", "/v1/data/public/missing/stream", 502, "{\"error\":\"bad gateway\",\"code\":\"NETWORK\"}");
        _server.Start();

        var ex = await Assert.ThrowsAsync<NetworkException>(
            () => _client.DataStreamPublicAsync("missing"));

        Assert.Equal(502, ex.StatusCode);
    }

    // ── Data Streaming With Progress (NDJSON) ──

    [Fact]
    public async Task DataStreamWithProgressAsync_ParsesNdjsonFrames()
    {
        // meta (skipped) → progress → data → data, mirroring the daemon's NDJSON.
        var ndjson =
            "{\"type\":\"meta\",\"total_size\":6}\n" +
            "{\"type\":\"progress\",\"phase\":\"fetching\",\"fetched\":1,\"total\":2}\n" +
            "{\"type\":\"data\",\"chunk\":\"" + Convert.ToBase64String(Encoding.UTF8.GetBytes("sec")) + "\"}\n" +
            "{\"type\":\"data\",\"chunk\":\"" + Convert.ToBase64String(Encoding.UTF8.GetBytes("ret")) + "\"}\n";
        _server.Route("POST", "/v1/data/stream", 200, ndjson);
        _server.Start();

        var buf = new List<byte>();
        DownloadProgress? progress = null;
        ulong? totalSize = null;
        var sawData = false;
        await foreach (var frame in _client.DataStreamWithProgressAsync("some_data_map"))
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
        // The leading NDJSON meta line surfaces the byte-total denominator.
        Assert.Equal(6UL, totalSize);
        Assert.NotNull(progress);
        Assert.Equal("fetching", progress!.Phase);
        Assert.Equal(1UL, progress.Fetched);
        Assert.Equal(2UL, progress.Total);

        // The request opts into NDJSON via Accept and carries the data_map.
        var sent = _server.LastRequestBodies["POST /v1/data/stream"];
        Assert.Contains("some_data_map", sent);
    }

    [Fact]
    public async Task DataStreamPublicWithProgressAsync_ParsesNdjsonFrames()
    {
        var ndjson =
            "{\"type\":\"meta\",\"total_size\":5}\n" +
            "{\"type\":\"data\",\"chunk\":\"" + Convert.ToBase64String(Encoding.UTF8.GetBytes("hello")) + "\"}\n";
        _server.Route("GET", "/v1/data/public/abc123/stream", 200, ndjson);
        _server.Start();

        var buf = new List<byte>();
        ulong? totalSize = null;
        await foreach (var frame in _client.DataStreamPublicWithProgressAsync("abc123"))
        {
            if (frame.IsMeta) totalSize = frame.TotalSize;
            else if (!frame.IsProgress) buf.AddRange(frame.Data!);
        }

        Assert.Equal("hello", Encoding.UTF8.GetString(buf.ToArray()));
        // The leading NDJSON meta line surfaces the byte-total denominator.
        Assert.Equal(5UL, totalSize);
    }

    [Fact]
    public async Task DataStreamWithProgressAsync_ErrorFrame_Throws()
    {
        // A terminal error frame surfaces as the SDK's mapped exception —
        // raw octet-stream downloads cannot signal a mid-stream failure.
        var ndjson =
            "{\"type\":\"meta\",\"total_size\":0}\n" +
            "{\"type\":\"error\",\"message\":\"chunk fetch failed\"}\n";
        _server.Route("POST", "/v1/data/stream", 200, ndjson);
        _server.Start();

        var ex = await Assert.ThrowsAsync<InternalException>(async () =>
        {
            await foreach (var _ in _client.DataStreamWithProgressAsync("some_data_map")) { }
        });

        Assert.Contains("chunk fetch failed", ex.Message);
    }

    // ── Data Cost ──

    [Fact]
    public async Task DataCostAsync_ReturnsCost()
    {
        _server.RouteOk("POST", "/v1/data/cost", new
        {
            cost = "7",
            file_size = 4,
            chunk_count = 3,
            estimated_gas_cost_wei = "150000000000000",
            payment_mode = "single",
        });
        _server.Start();

        var est = await _client.DataCostAsync(Encoding.UTF8.GetBytes("estimate me"));

        Assert.Equal("7", est.Cost);
        Assert.Equal(4UL, est.FileSize);
        Assert.Equal(3U, est.ChunkCount);
        Assert.Equal("150000000000000", est.EstimatedGasCostWei);
        Assert.Equal("single", est.PaymentMode);
    }

    // ── Chunks ──

    [Fact]
    public async Task ChunkPutAsync_ReturnsCostAndAddress()
    {
        _server.RouteOk("POST", "/v1/chunks", new
        {
            cost = "5",
            address = "chunk_addr_123"
        });
        _server.Start();

        var result = await _client.ChunkPutAsync(Encoding.UTF8.GetBytes("chunk payload"));

        Assert.Equal("5", result.Cost);
        Assert.Equal("chunk_addr_123", result.Address);
    }

    [Fact]
    public async Task ChunkGetAsync_ReturnsDecodedBytes()
    {
        var original = Encoding.UTF8.GetBytes("chunk content");
        _server.RouteOk("GET", "/v1/chunks/chunk_addr_123", new
        {
            data = Convert.ToBase64String(original)
        });
        _server.Start();

        var result = await _client.ChunkGetAsync("chunk_addr_123");

        Assert.Equal(original, result);
    }

    // ── Wallet ──

    [Fact]
    public async Task WalletAddressAsync_ReturnsAddress()
    {
        _server.RouteOk("GET", "/v1/wallet/address", new
        {
            address = "0xDeAdBeEf1234567890"
        });
        _server.Start();

        var result = await _client.WalletAddressAsync();

        Assert.Equal("0xDeAdBeEf1234567890", result.Address);
    }

    [Fact]
    public async Task WalletBalanceAsync_ReturnsBalances()
    {
        _server.RouteOk("GET", "/v1/wallet/balance", new
        {
            balance = "1000000",
            gas_balance = "500"
        });
        _server.Start();

        var result = await _client.WalletBalanceAsync();

        Assert.Equal("1000000", result.Balance);
        Assert.Equal("500", result.GasBalance);
    }

    [Fact]
    public async Task WalletApproveAsync_ReturnsTrue()
    {
        _server.RouteOk("POST", "/v1/wallet/approve", new { approved = true });
        _server.Start();

        var result = await _client.WalletApproveAsync();

        Assert.True(result);
    }

    // ── Error Mapping ──

    [Fact]
    public async Task ErrorMapping_404_ThrowsNotFoundException()
    {
        _server.Route("GET", "/v1/data/public/missing", 404, "not found");
        _server.Start();

        var ex = await Assert.ThrowsAsync<NotFoundException>(
            () => _client.DataGetPublicAsync("missing"));

        Assert.Equal(404, ex.StatusCode);
        Assert.Contains("not found", ex.Message);
    }

    [Fact]
    public async Task ErrorMapping_400_ThrowsBadRequestException()
    {
        _server.Route("POST", "/v1/data/public", 400, "invalid payload");
        _server.Start();

        var ex = await Assert.ThrowsAsync<BadRequestException>(
            () => _client.DataPutPublicAsync(Encoding.UTF8.GetBytes("bad")));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("invalid payload", ex.Message);
    }

    [Fact]
    public async Task ErrorMapping_502_ThrowsNetworkException()
    {
        _server.Route("POST", "/v1/data/public", 502, "bad gateway");
        _server.Start();

        var ex = await Assert.ThrowsAsync<NetworkException>(
            () => _client.DataPutPublicAsync(Encoding.UTF8.GetBytes("data")));

        Assert.Equal(502, ex.StatusCode);
    }

    [Fact]
    public async Task ErrorMapping_402_ThrowsPaymentException()
    {
        _server.Route("POST", "/v1/data/public", 402, "payment required");
        _server.Start();

        var ex = await Assert.ThrowsAsync<PaymentException>(
            () => _client.DataPutPublicAsync(Encoding.UTF8.GetBytes("data")));

        Assert.Equal(402, ex.StatusCode);
    }

    [Fact]
    public async Task ErrorMapping_500_ThrowsInternalException()
    {
        _server.Route("POST", "/v1/data/cost", 500, "server error");
        _server.Start();

        var ex = await Assert.ThrowsAsync<InternalException>(
            () => _client.DataCostAsync(Encoding.UTF8.GetBytes("data")));

        Assert.Equal(500, ex.StatusCode);
    }

    [Fact]
    public async Task ErrorMapping_503_ThrowsServiceUnavailableException()
    {
        _server.Route("GET", "/v1/wallet/balance", 503, "service unavailable");
        _server.Start();

        var ex = await Assert.ThrowsAsync<ServiceUnavailableException>(
            () => _client.WalletBalanceAsync());

        Assert.Equal(503, ex.StatusCode);
    }

    // ── Files ──

    [Fact]
    public async Task FileUploadPublicAsync_ReturnsFilePutPublicResult()
    {
        _server.RouteOk("POST", "/v1/files/public", new
        {
            address = "file_addr_001",
            storage_cost_atto = "1000",
            gas_cost_wei = "42",
            chunks_stored = 3,
            payment_mode_used = "auto"
        });
        _server.Start();

        var result = await _client.FilePutPublicAsync("/tmp/test.txt");

        Assert.Equal("file_addr_001", result.Address);
        Assert.Equal("1000", result.StorageCostAtto);
        Assert.Equal("42", result.GasCostWei);
        Assert.Equal(3UL, result.ChunksStored);
        Assert.Equal("auto", result.PaymentModeUsed);
    }

    // ── External Signer ──

    [Fact]
    public async Task PrepareUploadAsync_ReturnsPrepareResult()
    {
        _server.RouteOk("POST", "/v1/upload/prepare", new
        {
            upload_id = "up_123",
            payments = new[]
            {
                new { quote_hash = "qh1", rewards_address = "ra1", amount = "100" }
            },
            total_amount = "100",
            payment_vault_address = "pva1",
            payment_token_address = "pta1",
            rpc_url = "https://rpc.example.com",
            total_chunks = 3,
            already_stored_count = 1
        });
        _server.Start();

        var result = await _client.PrepareUploadAsync("/tmp/upload.dat");

        Assert.Equal("up_123", result.UploadId);
        Assert.Single(result.Payments);
        Assert.Equal("qh1", result.Payments[0].QuoteHash);
        Assert.Equal("100", result.TotalAmount);
        Assert.Equal("https://rpc.example.com", result.RpcUrl);
        // already-stored preflight (added in antd 0.10.0)
        Assert.Equal(3L, result.TotalChunks);
        Assert.Equal(1L, result.AlreadyStoredCount);
    }

    [Fact]
    public async Task FinalizeUploadAsync_ReturnsResult()
    {
        _server.RouteOk("POST", "/v1/upload/finalize", new
        {
            address = "final_addr_001",
            chunks_stored = 42
        });
        _server.Start();

        var txHashes = new Dictionary<string, string> { ["qh1"] = "0xabc" };
        var result = await _client.FinalizeUploadAsync("up_123", txHashes);

        Assert.Equal("final_addr_001", result.Address);
        Assert.Equal(42, result.ChunksStored);
    }

    [Fact]
    public async Task PrepareUploadAsync_Merkle_ReturnsPoolCommitments()
    {
        _server.RouteOk("POST", "/v1/upload/prepare", new
        {
            upload_id = "up_merkle_1",
            payments = Array.Empty<object>(),
            total_amount = "500",
            payment_vault_address = "pva_m",
            payment_token_address = "pta_m",
            rpc_url = "https://rpc.example.com",
            payment_type = "merkle_batch",
            depth = 3,
            pool_commitments = new[]
            {
                new
                {
                    pool_hash = "pool_abc",
                    candidates = new[]
                    {
                        new { rewards_address = "ra_1", amount = "200" },
                        new { rewards_address = "ra_2", amount = "300" }
                    }
                }
            },
            merkle_payment_timestamp = 1700000000L
        });
        _server.Start();

        var result = await _client.PrepareUploadAsync("/tmp/merkle.dat");

        Assert.Equal("up_merkle_1", result.UploadId);
        Assert.Equal("merkle_batch", result.PaymentType);
        Assert.Equal(3, result.Depth);
        Assert.NotNull(result.PoolCommitments);
        Assert.Single(result.PoolCommitments);
        Assert.Equal("pool_abc", result.PoolCommitments[0].PoolHash);
        Assert.Equal(2, result.PoolCommitments[0].Candidates.Count);
        Assert.Equal("ra_1", result.PoolCommitments[0].Candidates[0].RewardsAddress);
        Assert.Equal("200", result.PoolCommitments[0].Candidates[0].Amount);
        Assert.Equal("ra_2", result.PoolCommitments[0].Candidates[1].RewardsAddress);
        Assert.Equal("300", result.PoolCommitments[0].Candidates[1].Amount);
        Assert.Equal(1700000000L, result.MerklePaymentTimestamp);
        Assert.Equal("500", result.TotalAmount);
        Assert.Empty(result.Payments);
        // preflight fields absent in this response default to 0
        Assert.Equal(0L, result.TotalChunks);
        Assert.Equal(0L, result.AlreadyStoredCount);
    }

    [Fact]
    public async Task FinalizeMerkleUploadAsync_ReturnsResult()
    {
        _server.RouteOk("POST", "/v1/upload/finalize", new
        {
            address = "merkle_addr_001",
            chunks_stored = 99
        });
        _server.Start();

        var result = await _client.FinalizeMerkleUploadAsync("up_merkle_1", "pool_abc");

        Assert.Equal("merkle_addr_001", result.Address);
        Assert.Equal(99, result.ChunksStored);
    }

    // ── V2-249 / V2-274: public prepare + single-chunk external signer ──

    [Fact]
    public async Task PrepareUploadPublicAsync_SendsVisibilityPublic()
    {
        _server.RouteOk("POST", "/v1/upload/prepare", new
        {
            upload_id = "up_pub_1",
            payments = new[]
            {
                new { quote_hash = "qh1", rewards_address = "ra1", amount = "100" }
            },
            total_amount = "100",
            payment_vault_address = "0xVault",
            payment_token_address = "0xToken",
            rpc_url = "http://rpc.local"
        });
        _server.Start();

        var result = await _client.PrepareUploadPublicAsync("/tmp/file.dat");

        Assert.Equal("up_pub_1", result.UploadId);
        // Body should have carried visibility=public.
        var body = _server.LastRequestBodies["POST /v1/upload/prepare"];
        using var doc = JsonDocument.Parse(body);
        Assert.Equal("public", doc.RootElement.GetProperty("visibility").GetString());
        Assert.Equal("/tmp/file.dat", doc.RootElement.GetProperty("path").GetString());
    }

    [Fact]
    public async Task PrepareUploadAsync_NullVisibility_OmitsField()
    {
        _server.RouteOk("POST", "/v1/upload/prepare", new
        {
            upload_id = "up_priv_1",
            payments = Array.Empty<object>(),
            total_amount = "0",
            payment_vault_address = "0xV",
            payment_token_address = "0xT",
            rpc_url = "http://rpc.local"
        });
        _server.Start();

        await _client.PrepareUploadAsync("/tmp/private.dat");

        // No visibility key — preserves the pre-public daemon wire shape.
        var body = _server.LastRequestBodies["POST /v1/upload/prepare"];
        using var doc = JsonDocument.Parse(body);
        Assert.False(doc.RootElement.TryGetProperty("visibility", out _));
        Assert.Equal("/tmp/private.dat", doc.RootElement.GetProperty("path").GetString());
    }

    [Fact]
    public async Task FinalizeUploadAsync_SurfacesDataMapAddressOnPublicFinalize()
    {
        _server.RouteOk("POST", "/v1/upload/finalize", new
        {
            address = "",
            chunks_stored = 4,
            data_map = "deadbeef",
            data_map_address = "cafebabe"
        });
        _server.Start();

        var result = await _client.FinalizeUploadAsync(
            "up_pub_1",
            new Dictionary<string, string> { ["qh1"] = "tx1" });

        Assert.Equal("deadbeef", result.DataMap);
        Assert.Equal("cafebabe", result.DataMapAddress);
        Assert.Equal(4L, result.ChunksStored);
    }

    [Fact]
    public async Task FinalizeUploadAsync_PrivateUpload_OmitsDataMapAddress()
    {
        // Pre-0.6.1 daemons don't emit data_map_address — field defaults to "".
        _server.RouteOk("POST", "/v1/upload/finalize", new
        {
            address = "0xFinal",
            chunks_stored = 2,
            data_map = "deadbeef"
        });
        _server.Start();

        var result = await _client.FinalizeUploadAsync(
            "up_priv_1",
            new Dictionary<string, string> { ["qh1"] = "tx1" });

        Assert.Equal("", result.DataMapAddress);
        Assert.Equal("deadbeef", result.DataMap);
        Assert.Equal("0xFinal", result.Address);
    }

    [Fact]
    public async Task PrepareChunkUploadAsync_AlreadyStored_OmitsPaymentFields()
    {
        // already_stored=true → only address + already_stored matter, the
        // payment fields are absent from the wire response.
        _server.RouteOk("POST", "/v1/chunks/prepare", new
        {
            address = "aa" + new string('1', 62),
            already_stored = true,
        });
        _server.Start();

        var result = await _client.PrepareChunkUploadAsync(Encoding.UTF8.GetBytes("already-stored"));

        Assert.True(result.AlreadyStored);
        Assert.StartsWith("aa", result.Address);
        Assert.Equal("", result.UploadId);
        Assert.NotNull(result.Payments);
        Assert.Empty(result.Payments!);
        Assert.Equal("", result.TotalAmount);
        Assert.Equal("", result.PaymentType);

        // And the request body must be base64-encoded under `data`.
        var body = _server.LastRequestBodies["POST /v1/chunks/prepare"];
        using var doc = JsonDocument.Parse(body);
        Assert.Equal(Convert.ToBase64String(Encoding.UTF8.GetBytes("already-stored")),
            doc.RootElement.GetProperty("data").GetString());
    }

    [Fact]
    public async Task PrepareChunkUploadAsync_NewChunk_ReturnsWaveBatchIntent()
    {
        _server.RouteOk("POST", "/v1/chunks/prepare", new
        {
            address = "bb" + new string('2', 62),
            already_stored = false,
            upload_id = "chunk_up_1",
            payment_type = "wave_batch",
            payments = new[]
            {
                new { quote_hash = "qh1", rewards_address = "ra1", amount = "100" },
                new { quote_hash = "qh2", rewards_address = "ra2", amount = "100" },
            },
            total_amount = "200",
            payment_vault_address = "0xVault",
            payment_token_address = "0xToken",
            rpc_url = "http://rpc.local",
        });
        _server.Start();

        var result = await _client.PrepareChunkUploadAsync(Encoding.UTF8.GetBytes("new"));

        Assert.False(result.AlreadyStored);
        Assert.Equal("chunk_up_1", result.UploadId);
        Assert.Equal("wave_batch", result.PaymentType);
        Assert.NotNull(result.Payments);
        Assert.Equal(2, result.Payments!.Count);
        Assert.Equal("qh1", result.Payments[0].QuoteHash);
        Assert.Equal("100", result.Payments[1].Amount);
        Assert.Equal("200", result.TotalAmount);
        Assert.Equal("0xVault", result.PaymentVaultAddress);
        Assert.Equal("http://rpc.local", result.RpcUrl);
    }

    [Fact]
    public async Task FinalizeChunkUploadAsync_ReturnsAddressAndForwardsTxHashes()
    {
        _server.RouteOk("POST", "/v1/chunks/finalize", new
        {
            address = "cc" + new string('3', 62),
        });
        _server.Start();

        var txHashes = new Dictionary<string, string>
        {
            ["qh1"] = "tx1",
            ["qh2"] = "tx2",
        };
        var addr = await _client.FinalizeChunkUploadAsync("chunk_up_1", txHashes);

        Assert.StartsWith("cc", addr);
        Assert.Equal(64, addr.Length);

        var body = _server.LastRequestBodies["POST /v1/chunks/finalize"];
        using var doc = JsonDocument.Parse(body);
        Assert.Equal("chunk_up_1", doc.RootElement.GetProperty("upload_id").GetString());
        var tx = doc.RootElement.GetProperty("tx_hashes");
        Assert.Equal("tx1", tx.GetProperty("qh1").GetString());
        Assert.Equal("tx2", tx.GetProperty("qh2").GetString());
    }

    [Fact]
    public async Task PrepareUploadAsync_BackwardCompat_DefaultsPaymentType()
    {
        // Simulate an older daemon response without merkle fields
        _server.RouteOk("POST", "/v1/upload/prepare", new
        {
            upload_id = "up_legacy",
            payments = new[]
            {
                new { quote_hash = "qh1", rewards_address = "ra1", amount = "100" }
            },
            total_amount = "100",
            payment_vault_address = "pva1",
            payment_token_address = "pta1",
            rpc_url = "https://rpc.example.com"
        });
        _server.Start();

        var result = await _client.PrepareUploadAsync("/tmp/legacy.dat");

        Assert.Equal("up_legacy", result.UploadId);
        Assert.Equal("wave_batch", result.PaymentType);
        Assert.Null(result.Depth);
        Assert.Null(result.PoolCommitments);
        Assert.Null(result.MerklePaymentTimestamp);
        Assert.Single(result.Payments);
        Assert.Equal("qh1", result.Payments[0].QuoteHash);
    }

    // ── Partial upload (PARTIAL_UPLOAD) ──

    [Fact]
    public async Task FinalizeUploadAsync_PartialUpload_CarriesCountsAndRetryable()
    {
        _server.Route("POST", "/v1/upload/finalize", 502, JsonSerializer.Serialize(new
        {
            error = "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)",
            code = "PARTIAL_UPLOAD",
            chunks_stored = 300,
            chunks_failed = 12,
            total_chunks = 312,
            retryable = true,
        }));
        _server.Start();

        var ex = await Assert.ThrowsAsync<PartialUploadException>(
            () => _client.FinalizeUploadAsync("up_partial", new Dictionary<string, string> { ["qh1"] = "tx1" }));

        Assert.Equal(300UL, ex.ChunksStored);
        Assert.Equal(12UL, ex.ChunksFailed);
        Assert.Equal(312UL, ex.TotalChunks);
        Assert.True(ex.Retryable);
        Assert.True(ex.RetentionKnown);
        Assert.Equal(502, ex.StatusCode);
        Assert.StartsWith("Partial upload: 300/312", ex.Message);
        // A partial upload has always arrived as a 502, so existing
        // catch (NetworkException) blocks must keep matching.
        Assert.IsAssignableFrom<NetworkException>(ex);
    }

    [Fact]
    public async Task FinalizeMerkleUploadAsync_PartialUpload_RetryableDefaultsFalse()
    {
        // An older daemon (< 0.14.0) never sends `retryable`: the flag reads
        // false so callers do not loop on an upload_id the daemon may have
        // dropped, and retention reads as unknown so they do not re-prepare
        // (and pay again) on that signal alone either.
        _server.Route("POST", "/v1/upload/finalize", 502, JsonSerializer.Serialize(new
        {
            error = "Partial upload: 300/312 chunks stored, 12 failed after retries",
            code = "PARTIAL_UPLOAD",
            chunks_stored = 300,
            chunks_failed = 12,
            total_chunks = 312,
        }));
        _server.Start();

        var ex = await Assert.ThrowsAsync<PartialUploadException>(
            () => _client.FinalizeMerkleUploadAsync("up_merkle_partial", "pool_abc"));

        Assert.False(ex.Retryable);
        Assert.False(ex.RetentionKnown);
        Assert.Equal(300UL, ex.ChunksStored);
        Assert.Equal(12UL, ex.ChunksFailed);
        Assert.Equal(312UL, ex.TotalChunks);
    }

    [Theory]
    [InlineData("true", true, true)]
    [InlineData("false", false, true)]
    [InlineData(null, false, false)] // absent: a daemon before 0.14.0
    [InlineData("null", false, false)]
    [InlineData("\"true\"", false, false)]
    [InlineData("\"false\"", false, false)]
    [InlineData("1", false, false)]
    [InlineData("0", false, false)]
    [InlineData("{}", false, false)]
    public async Task FinalizeUploadAsync_PartialUpload_RetentionKnownOnlyForABooleanRetryable(
        string? retryableJson, bool retryable, bool retentionKnown)
    {
        // `retryable` must be a JSON boolean to count as the daemon's
        // verdict. true: retained, finalize again. false: confirmed nothing
        // retained, re-prepare. Anything else: unknown, reconcile first.
        var flag = retryableJson is null ? "" : $",\"retryable\":{retryableJson}";
        _server.Route("POST", "/v1/upload/finalize", 502,
            "{\"error\":\"Partial upload: 3/5 chunks stored, 2 failed after retries: quorum\"," +
            "\"code\":\"PARTIAL_UPLOAD\",\"chunks_stored\":3,\"chunks_failed\":2,\"total_chunks\":5" + flag + "}");
        _server.Start();

        var ex = await Assert.ThrowsAsync<PartialUploadException>(
            () => _client.FinalizeUploadAsync("up_retention", new Dictionary<string, string> { ["qh1"] = "tx1" }));

        Assert.Equal(retryable, ex.Retryable);
        Assert.Equal(retentionKnown, ex.RetentionKnown);
        Assert.Equal(3UL, ex.ChunksStored);
        Assert.Equal(2UL, ex.ChunksFailed);
        Assert.Equal(5UL, ex.TotalChunks);
    }

    [Fact]
    public async Task ErrorMapping_502_WithOtherCode_StaysNetworkException()
    {
        // Only code == "PARTIAL_UPLOAD" is special-cased; any other JSON
        // error body keeps the status-based mapping.
        _server.Route("POST", "/v1/upload/finalize", 502,
            JsonSerializer.Serialize(new { error = "peer unreachable", code = "NETWORK" }));
        _server.Start();

        var ex = await Assert.ThrowsAsync<NetworkException>(
            () => _client.FinalizeUploadAsync("up_net", new Dictionary<string, string>()));

        Assert.IsNotType<PartialUploadException>(ex);
        Assert.Equal(502, ex.StatusCode);
    }

    [Theory]
    [InlineData("{\"error\":\"x\",\"code\":{}}")]
    [InlineData("{\"error\":\"x\",\"code\":[\"PARTIAL_UPLOAD\"]}")]
    [InlineData("{\"error\":\"x\",\"code\":null}")]
    [InlineData("{\"error\":\"x\",\"code\":502}")]
    [InlineData("[{\"error\":\"x\",\"code\":\"PARTIAL_UPLOAD\",\"chunks_stored\":1}]")]
    [InlineData("{\"error\":\"x\",\"code\":\"PARTIAL_UPLOAD\",\"chunks_stored\":")]
    [InlineData("{\"error\":\"x\",\"code\":\"\\uDC00\"}")]
    [InlineData("{\"error\":\"x\",\"code\":\"PARTIAL_UPLOAD\",\"c\\uD800\":0}")]
    public async Task ErrorMapping_502_BodyWithoutReadablePartialUploadCode_StaysNetworkException(string body)
    {
        // `code` must be the string "PARTIAL_UPLOAD" in a body that reads as
        // a JSON object. Any other shape (object, array, null or number code,
        // a top-level array body, truncated JSON, a code or property name
        // whose escape is not valid UTF-16) is not a partial upload: it falls
        // back to the status-based mapping instead of escaping the typed
        // exception contract as a parse error.
        _server.Route("POST", "/v1/upload/finalize", 502, body);
        _server.Start();

        var ex = await Assert.ThrowsAsync<NetworkException>(
            () => _client.FinalizeUploadAsync("up_bad_code", new Dictionary<string, string>()));

        Assert.IsNotType<PartialUploadException>(ex);
        Assert.Equal(502, ex.StatusCode);
        Assert.Equal(body, ex.Message);
    }

    [Theory]
    [InlineData("{\"error\":\"Partial upload: bad counts\",\"code\":\"PARTIAL_UPLOAD\",\"chunks_failed\":[]}", "Partial upload: bad counts")]
    [InlineData("{\"error\":{\"msg\":\"x\"},\"code\":\"PARTIAL_UPLOAD\",\"chunks_stored\":\"300\",\"chunks_failed\":{},\"total_chunks\":-1,\"retryable\":\"true\"}", null)]
    [InlineData("{\"error\":42,\"code\":\"PARTIAL_UPLOAD\",\"chunks_stored\":1.5,\"chunks_failed\":null,\"total_chunks\":1e3,\"retryable\":1}", null)]
    [InlineData("{\"error\":null,\"code\":\"PARTIAL_UPLOAD\",\"chunks_stored\":18446744073709551616,\"chunks_failed\":true,\"total_chunks\":[312],\"retryable\":null}", null)]
    [InlineData("{\"error\":\"\\uD800\",\"code\":\"PARTIAL_UPLOAD\"}", null)]
    public async Task ErrorMapping_502_PartialUploadWithWrongTypedFields_ReadsDefaults(string body, string? expectedMessage)
    {
        // A count or flag that is not the expected JSON kind (array, object,
        // string, negative, fractional, out of range, null) reads as absent,
        // i.e. zero / false, and an `error` that is not a decodable string
        // falls back to the raw body: still the typed exception, never a
        // parse error.
        _server.Route("POST", "/v1/upload/finalize", 502, body);
        _server.Start();

        var ex = await Assert.ThrowsAsync<PartialUploadException>(
            () => _client.FinalizeUploadAsync("up_bad_fields", new Dictionary<string, string>()));

        Assert.Equal(0UL, ex.ChunksStored);
        Assert.Equal(0UL, ex.ChunksFailed);
        Assert.Equal(0UL, ex.TotalChunks);
        Assert.False(ex.Retryable);
        Assert.False(ex.RetentionKnown);
        Assert.Equal(502, ex.StatusCode);
        Assert.Equal(expectedMessage ?? body, ex.Message);
    }

    [Fact]
    public void ErrorMapping_BodyThatIsNotValidUtf16_FallsBackWithoutThrowing()
    {
        // Unreachable over HTTP (the response decoder replaces bad bytes),
        // but the shared mapper must still not throw on a string holding a
        // lone surrogate.
        var body = "{\"error\":\"\uD800\",\"code\":\"PARTIAL_UPLOAD\"}";

        var ex = ExceptionMapping.FromHttpStatus(HttpStatusCode.BadGateway, body);

        Assert.IsType<NetworkException>(ex);
        Assert.Equal(body, ex.Message);
    }
}

/// <summary>
/// The constructors: the original signature stays source-compatible, and
/// Retryable always implies RetentionKnown.
/// </summary>
public sealed class PartialUploadExceptionTests
{
    [Theory]
    [InlineData(true, true)]
    [InlineData(false, false)]
    public void LegacyConstructor_RetentionKnownFollowsRetryable(bool retryable, bool retentionKnown)
    {
        var ex = new PartialUploadException("Partial upload: 1/2 chunks stored, 1 failed", 1, 1, 2, retryable);

        Assert.Equal(retryable, ex.Retryable);
        Assert.Equal(retentionKnown, ex.RetentionKnown);
        Assert.Equal(502, ex.StatusCode);
    }

    [Theory]
    [InlineData(true, true, true)]
    [InlineData(false, true, true)]
    [InlineData(false, false, false)]
    [InlineData(true, false, true)] // Retryable implies RetentionKnown
    public void Constructor_RetryableImpliesRetentionKnown(bool retryable, bool retentionKnownArg, bool retentionKnown)
    {
        var ex = new PartialUploadException("Partial upload: 1/2 chunks stored, 1 failed", 1, 1, 2, retryable, retentionKnownArg, 503);

        Assert.Equal(retryable, ex.Retryable);
        Assert.Equal(retentionKnown, ex.RetentionKnown);
        Assert.Equal(503, ex.StatusCode);
    }
}

/// <summary>
/// Cases for the gRPC-side message parser shared by both transports' mapping
/// of the daemon's PARTIAL_UPLOAD text.
/// </summary>
public sealed class PartialUploadMessageParserTests
{
    [Theory]
    [InlineData(
        "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)",
        300UL, 12UL, 312UL, true, true)]
    [InlineData(
        "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)",
        300UL, 12UL, 312UL, false, true)]
    [InlineData("Partial upload: 300/312 chunks stored, 12 failed after retries", 300UL, 12UL, 312UL, false, true)]
    [InlineData("Partial upload: counts missing", 0UL, 0UL, 0UL, false, false)]
    // RetentionKnown needs the layout to match AND all three counts to
    // convert; Retryable additionally needs the retained hint. A layout miss
    // or an unconvertible count reads as zeros, unknown retention and not
    // retryable, whatever the hint says.
    [InlineData("Partial upload: counts missing (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    [InlineData("Partial upload: 18446744073709551616/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    [InlineData("Partial upload: 300/18446744073709551616 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    [InlineData("Partial upload: 300/312 chunks stored, 18446744073709551616 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    [InlineData("Partial upload: 18446744073709551615/18446744073709551615 chunks stored, 0 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)",
        18446744073709551615UL, 0UL, 18446744073709551615UL, true, true)]
    // Arabic-Indic digits: .NET's \d would match them; the parser is ASCII-only.
    [InlineData("Partial upload: \u0663\u0660\u0660/\u0663\u0661\u0662 chunks stored, \u0661\u0662 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    [InlineData("Partial upload: 300/312 chunks stored, \u0661\u0662 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    // The layout is anchored at the prefix: counts quoted later do not count.
    [InlineData("Partial upload: n/a chunks stored; earlier: Partial upload: 1/2 chunks stored, 1 failed (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", 0UL, 0UL, 0UL, false, false)]
    [InlineData("something else entirely", 0UL, 0UL, 0UL, false, false)]
    [InlineData("", 0UL, 0UL, 0UL, false, false)]
    public void ParsePartialUploadMessage_RecoversCountsAndRetainedHint(
        string message, ulong stored, ulong failed, ulong total, bool retryable, bool retentionKnown)
    {
        var parsed = ExceptionMapping.ParsePartialUploadMessage(message);

        Assert.Equal(stored, parsed.Stored);
        Assert.Equal(failed, parsed.Failed);
        Assert.Equal(total, parsed.Total);
        Assert.Equal(retryable, parsed.Retryable);
        Assert.Equal(retentionKnown, parsed.RetentionKnown);
    }
}

/// <summary>
/// The gRPC <c>ABORTED</c> arm: the daemon's PARTIAL_UPLOAD only when the
/// status detail starts with the fixed "Partial upload:" prefix; every other
/// ABORTED, including one that quotes the prefix after other text, keeps the
/// pre-existing version-conflict mapping.
/// </summary>
public sealed class GrpcAbortedMappingTests
{
    private static AntdException Map(string detail) =>
        ExceptionMapping.FromGrpcStatus(new RpcException(new Status(Grpc.Core.StatusCode.Aborted, detail)));

    [Fact]
    public void Aborted_WithPartialUploadPrefix_MapsToPartialUploadException()
    {
        var ex = Assert.IsType<PartialUploadException>(Map(
            "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"));

        Assert.Equal(300UL, ex.ChunksStored);
        Assert.Equal(12UL, ex.ChunksFailed);
        Assert.Equal(312UL, ex.TotalChunks);
        Assert.True(ex.Retryable);
        Assert.True(ex.RetentionKnown);
    }

    [Fact]
    public void Aborted_GateReadsRawStatusDetail_NotTheFormattedRpcExceptionMessage()
    {
        // Grpc.Net formats RpcException.Message as
        // Status(StatusCode="Aborted", Detail="..."), so the prefix is never
        // at offset zero there; the anchored gate must read Status.Detail.
        const string detail =
            "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)";
        var rpc = new RpcException(new Status(Grpc.Core.StatusCode.Aborted, detail));
        Assert.False(rpc.Message.StartsWith("Partial upload:", StringComparison.Ordinal));

        var ex = Assert.IsType<PartialUploadException>(ExceptionMapping.FromGrpcStatus(rpc));

        Assert.Equal(detail, ex.Message);
        Assert.Equal(1UL, ex.ChunksStored);
        Assert.Equal(2UL, ex.ChunksFailed);
        Assert.Equal(3UL, ex.TotalChunks);
        Assert.True(ex.Retryable);
        Assert.True(ex.RetentionKnown);
    }

    [Theory]
    [InlineData("Partial upload: n/a chunks stored")]
    [InlineData("Partial upload: n/a chunks stored (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)")]
    [InlineData("Partial upload: 18446744073709551616/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)")]
    [InlineData("Partial upload: 300/18446744073709551616 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)")]
    [InlineData("Partial upload: 300/312 chunks stored, 18446744073709551616 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)")]
    [InlineData("Partial upload: \u0663\u0660\u0660/\u0663\u0661\u0662 chunks stored, \u0661\u0662 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)")]
    public void Aborted_WithPrefixButUnparseableCounts_IsPartialUploadWithZerosAndNotRetryable(string detail)
    {
        // The anchored prefix alone routes to the typed exception. Counts that
        // do not match or do not convert degrade to zero and Retryable false,
        // even when the retained hint is present: without counts a retry loop
        // cannot tell progress from a stuck upload.
        var ex = Assert.IsType<PartialUploadException>(Map(detail));

        Assert.Equal(0UL, ex.ChunksStored);
        Assert.Equal(0UL, ex.ChunksFailed);
        Assert.Equal(0UL, ex.TotalChunks);
        Assert.False(ex.Retryable);
        Assert.False(ex.RetentionKnown);
        Assert.Equal(detail, ex.Message);
    }

    [Theory]
    [InlineData("version conflict: expected v3, found v4")]
    [InlineData("something else entirely")]
    [InlineData("")]
    public void Aborted_WithoutPartialUploadPrefix_MapsToForkException(string detail)
    {
        var ex = Map(detail);

        Assert.IsType<ForkException>(ex);
        Assert.IsNotType<PartialUploadException>(ex);
        Assert.Equal(409, ex.StatusCode);
        Assert.Equal(detail, ex.Message);
    }

    [Theory]
    [InlineData("Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", true, true)]
    [InlineData("Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)", false, true)]
    [InlineData("Partial upload: 300/18446744073709551616 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", false, false)]
    [InlineData("Partial upload: 300/312 chunks, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)", false, false)]
    public void Aborted_RetentionKnownOnlyWhenAllThreeCountsParse(string detail, bool retryable, bool retentionKnown)
    {
        // Well-formed counts: retention is known and the retained hint decides
        // Retryable. An overflow or a layout miss: unknown, even with the hint.
        var ex = Assert.IsType<PartialUploadException>(Map(detail));

        Assert.Equal(retryable, ex.Retryable);
        Assert.Equal(retentionKnown, ex.RetentionKnown);
    }

    [Theory]
    [InlineData("upstream error: Partial upload: 1/3 chunks stored, 2 failed")]
    [InlineData("wrapped (Partial upload: 0/1 chunks stored, 1 failed; paid attempt retained)")]
    [InlineData("wrapped: Partial upload: n/a chunks stored")]
    [InlineData(" Partial upload: 1/3 chunks stored, 2 failed")]
    public void Aborted_WithPartialUploadMarkerAfterOtherText_MapsToForkException(string detail)
    {
        // The gate is anchored at the start of the detail: a status that
        // merely quotes "Partial upload:" further in (even with parseable
        // counts or the retained hint) is not a partial upload and must not
        // select paid-attempt recovery.
        var ex = Map(detail);

        Assert.IsType<ForkException>(ex);
        Assert.IsNotType<PartialUploadException>(ex);
        Assert.Equal(409, ex.StatusCode);
        Assert.Equal(detail, ex.Message);
    }
}
