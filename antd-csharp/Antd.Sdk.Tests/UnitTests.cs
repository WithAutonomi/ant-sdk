using System.Net;
using System.Text;
using System.Text.Json;
using Antd.Sdk;
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
}
