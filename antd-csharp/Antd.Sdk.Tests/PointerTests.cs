using System.Net;
using System.Text.Json;
using Antd.Sdk;
using Grpc.Core;
using Grpc.Core.Testing;
using Xunit;
using Pb = Antd.V1;

namespace Antd.Sdk.Tests;

/// <summary>Shared canned values for the pointer tests.</summary>
internal static class PointerFixtures
{
    public const string Owner = "aa00000000000000000000000000000000000000000000000000000000000001";
    public const string Recipient = "bb00000000000000000000000000000000000000000000000000000000000002";
    public const string Target = "cc00000000000000000000000000000000000000000000000000000000000003";
    public const string StateId = "dd00000000000000000000000000000000000000000000000000000000000004";
    public const string MaxCounter = "18446744073709551615";

    private static readonly string[] Malformed =
    {
        "",
        "-1",
        "+1",
        " 1",
        "1 ",
        "1.0",
        "1e3",
        "0x10",
        "1,000",
        "18446744073709551616",
        "\u0661", // ARABIC-INDIC DIGIT ONE: .NET reads only ASCII digits
        "abc",
    };

    /// <summary>Counters a strict decimal-u64 parser must refuse.</summary>
    public static TheoryData<string> MalformedCounters => new(Malformed);

    /// <summary>
    /// The same, less the empty string: in a finality answer an empty counter
    /// is the unset marker, not a malformed value.
    /// </summary>
    public static TheoryData<string> MalformedSetCounters => new(Malformed.Where(c => c.Length > 0));
}

/// <summary>REST pointer methods against a mock daemon.</summary>
public sealed class PointerRestTests : IDisposable
{
    private readonly MockServer _server = new();
    private readonly AntdRestClient _client;

    public PointerRestTests() =>
        _client = new AntdRestClient(_server.BaseUrl, timeout: TimeSpan.FromSeconds(5));

    public void Dispose()
    {
        _client.Dispose();
        _server.Dispose();
    }

    private JsonElement LastBody(string method, string path) =>
        JsonDocument.Parse(_server.LastRequestBodies[$"{method} {path}"]).RootElement;

    private static object FinalityJson(string status = "final") => new
    {
        address = PointerFixtures.Owner,
        group = 7,
        answered = 7,
        status,
        counter = (string?)null,
        state = new
        {
            state_id = PointerFixtures.StateId,
            kind = "pointer",
            kind_tag = 1,
            target = PointerFixtures.Recipient,
            holders = 7,
            transferred_to = PointerFixtures.Recipient,
        },
        states = Array.Empty<object>(),
        majority = (object?)null,
        transferred_to = PointerFixtures.Recipient,
    };

    [Fact]
    public async Task PointerKeys_ReturnsAddresses()
    {
        _server.RouteOk("GET", "/v1/pointers/keys", new
        {
            keys = new[] { new { address = PointerFixtures.Owner }, new { address = PointerFixtures.Recipient } },
        });
        _server.Start();

        var keys = await _client.PointerKeysAsync();

        Assert.Equal(new[] { PointerFixtures.Owner, PointerFixtures.Recipient }, keys);
    }

    [Fact]
    public async Task PointerCreate_SendsOwnerTargetKind_ParsesCounter()
    {
        _server.RouteOk("POST", "/v1/pointers", new
        {
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            counter = "0",
        });
        _server.Start();

        var w = await _client.PointerCreateAsync(PointerFixtures.Owner, PointerFixtures.Target);

        Assert.Equal(new PointerWriteResult(PointerFixtures.Owner, PointerFixtures.StateId, 0UL), w);
        var body = LastBody("POST", "/v1/pointers");
        Assert.Equal(PointerFixtures.Owner, body.GetProperty("owner").GetString());
        Assert.Equal(PointerFixtures.Target, body.GetProperty("target").GetString());
        Assert.Equal("chunk", body.GetProperty("kind").GetString());
    }

    [Fact]
    public async Task PointerUpdate_SendsPointerKind_ParsesMaxCounter()
    {
        _server.RouteOk("POST", "/v1/pointers/update", new
        {
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            counter = PointerFixtures.MaxCounter,
        });
        _server.Start();

        var w = await _client.PointerUpdateAsync(PointerFixtures.Owner, PointerFixtures.Recipient, PointerKind.Pointer);

        Assert.Equal(ulong.MaxValue, w.Counter);
        Assert.Equal("pointer", LastBody("POST", "/v1/pointers/update").GetProperty("kind").GetString());
    }

    [Fact]
    public async Task PointerTransfer_ParsesFinality()
    {
        _server.RouteOk("POST", "/v1/pointers/transfer", new
        {
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            finality = FinalityJson(),
        });
        _server.Start();

        var t = await _client.PointerTransferAsync(PointerFixtures.Owner, PointerFixtures.Recipient);

        Assert.Equal(PointerFixtures.Owner, t.Address);
        Assert.Null(t.FinalityError);
        var f = Assert.IsType<PointerFinality>(t.Finality);
        Assert.True(f.IsFinal);
        Assert.Equal(PointerFinalityStatus.Final, f.Status);
        Assert.Equal("final", f.RawStatus);
        Assert.Null(f.Counter);
        Assert.Equal(PointerFixtures.Recipient, f.TransferredTo);
        Assert.Equal(7u, f.State!.Holders);
        Assert.Equal(PointerKind.Pointer, PointerKindExtensions.FromTag(f.State.KindTag));
        Assert.Empty(f.States);
        Assert.Null(f.Majority);
        var body = LastBody("POST", "/v1/pointers/transfer");
        Assert.Equal(PointerFixtures.Recipient, body.GetProperty("recipient").GetString());
    }

    [Fact]
    public async Task PointerTransfer_FinalityCheckFailed_KeepsTheError()
    {
        _server.RouteOk("POST", "/v1/pointers/transfer", new
        {
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            finality = (object?)null,
            finality_error = "close group did not answer",
        });
        _server.Start();

        var t = await _client.PointerTransferAsync(PointerFixtures.Owner, PointerFixtures.Recipient);

        Assert.Null(t.Finality);
        Assert.Equal("close group did not answer", t.FinalityError);
    }

    [Fact]
    public async Task PointerGet_ParsesRecord()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}", new
        {
            address = PointerFixtures.Owner,
            owner = "ab",
            counter = "3",
            kind = "chunk",
            kind_tag = 0,
            target = PointerFixtures.Target,
            state_id = PointerFixtures.StateId,
            is_final = false,
            transferred_to = (string?)null,
        });
        _server.Start();

        var r = await _client.PointerGetAsync(PointerFixtures.Owner);

        Assert.Equal(
            new PointerRecord(PointerFixtures.Owner, "ab", 3UL, "chunk", 0, PointerFixtures.Target,
                PointerFixtures.StateId, false, null),
            r);
        Assert.Equal(PointerKind.Chunk, r.TargetKind);
    }

    [Fact]
    public async Task PointerGet_FinalTransferredRecord()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}", new
        {
            address = PointerFixtures.Owner,
            owner = "ab",
            counter = PointerFixtures.MaxCounter,
            kind = "unknown",
            kind_tag = 9,
            target = PointerFixtures.Recipient,
            state_id = PointerFixtures.StateId,
            is_final = true,
            transferred_to = PointerFixtures.Recipient,
        });
        _server.Start();

        var r = await _client.PointerGetAsync(PointerFixtures.Owner);

        Assert.True(r.IsFinal);
        Assert.Equal(ulong.MaxValue, r.Counter);
        Assert.Equal(PointerFixtures.Recipient, r.TransferredTo);
        Assert.Equal("unknown", r.Kind);
        Assert.Equal((byte)9, r.KindTag);
        Assert.Null(r.TargetKind);
    }

    [Theory]
    [MemberData(nameof(PointerFixtures.MalformedCounters), MemberType = typeof(PointerFixtures))]
    public async Task PointerGet_MalformedCounter_Throws(string counter)
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}", new
        {
            address = PointerFixtures.Owner,
            owner = "ab",
            counter,
            kind = "chunk",
            kind_tag = 0,
            target = PointerFixtures.Target,
            state_id = PointerFixtures.StateId,
            is_final = false,
        });
        _server.Start();

        var ex = await Assert.ThrowsAsync<AntdException>(() => _client.PointerGetAsync(PointerFixtures.Owner));
        Assert.Contains("not a decimal counter", ex.Message);
    }

    [Fact]
    public async Task PointerGet_MissingCounter_Throws()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}", new
        {
            address = PointerFixtures.Owner,
            kind = "chunk",
            target = PointerFixtures.Target,
        });
        _server.Start();

        await Assert.ThrowsAsync<AntdException>(() => _client.PointerGetAsync(PointerFixtures.Owner));
    }

    [Fact]
    public async Task PointerResolve_ParsesTarget()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}/resolve", new
        {
            kind = "chunk",
            kind_tag = 0,
            target = PointerFixtures.Target,
        });
        _server.Start();

        var t = await _client.PointerResolveAsync(PointerFixtures.Owner);

        Assert.Equal(new PointerTarget("chunk", 0, PointerFixtures.Target), t);
        Assert.Equal(PointerKind.Chunk, t.TargetKind);
    }

    [Fact]
    public async Task PointerFinality_Open_ParsesCounter()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}/finality", new
        {
            address = PointerFixtures.Owner,
            group = 7,
            answered = 6,
            status = "open",
            counter = "12",
            state = (object?)null,
            states = Array.Empty<object>(),
            majority = (object?)null,
            transferred_to = (string?)null,
        });
        _server.Start();

        var f = await _client.PointerFinalityAsync(PointerFixtures.Owner);

        Assert.Equal(PointerFinalityStatus.Open, f.Status);
        Assert.False(f.IsFinal);
        Assert.Equal(12UL, f.Counter);
        Assert.Equal(7u, f.Group);
        Assert.Equal(6u, f.Answered);
        Assert.Null(f.State);
        Assert.Null(f.TransferredTo);
    }

    [Fact]
    public async Task PointerFinality_Forked_ParsesStatesAndMajority()
    {
        var a = new { state_id = "s1", kind = "pointer", kind_tag = 1, target = "t1", holders = 4, transferred_to = "t1" };
        var b = new { state_id = "s2", kind = "pointer", kind_tag = 1, target = "t2", holders = 2, transferred_to = "t2" };
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}/finality", new
        {
            address = PointerFixtures.Owner,
            group = 7,
            answered = 7,
            status = "forked",
            counter = (string?)null,
            state = (object?)null,
            states = new[] { a, b },
            majority = a,
            transferred_to = (string?)null,
        });
        _server.Start();

        var f = await _client.PointerFinalityAsync(PointerFixtures.Owner);

        Assert.Equal(PointerFinalityStatus.Forked, f.Status);
        Assert.Equal(new[] { "s1", "s2" }, f.States.Select(s => s.StateId));
        Assert.Equal(new PointerFinalState("s1", "pointer", 1, "t1", 4, "t1"), f.Majority);
        Assert.Null(f.Counter);
    }

    [Fact]
    public async Task PointerFinality_UnknownStatus_KeepsRawValue()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}/finality", new
        {
            address = PointerFixtures.Owner,
            group = 7,
            answered = 7,
            status = "contested",
            states = Array.Empty<object>(),
        });
        _server.Start();

        var f = await _client.PointerFinalityAsync(PointerFixtures.Owner);

        Assert.Equal(PointerFinalityStatus.Unknown, f.Status);
        Assert.Equal("contested", f.RawStatus);
        Assert.False(f.IsFinal);
    }

    [Theory]
    [MemberData(nameof(PointerFixtures.MalformedSetCounters), MemberType = typeof(PointerFixtures))]
    public async Task PointerFinality_MalformedCounter_Throws(string counter)
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}/finality", new
        {
            address = PointerFixtures.Owner,
            group = 7,
            answered = 7,
            status = "open",
            counter,
            states = Array.Empty<object>(),
        });
        _server.Start();

        await Assert.ThrowsAsync<AntdException>(() => _client.PointerFinalityAsync(PointerFixtures.Owner));
    }

    [Fact]
    public async Task PointerController_ParsesTransfers()
    {
        _server.RouteOk("GET", $"/v1/pointers/{PointerFixtures.Owner}/controller", new
        {
            pointer = PointerFixtures.Recipient,
            transfers = new[] { PointerFixtures.Recipient },
            frozen = false,
        });
        _server.Start();

        var c = await _client.PointerControllerAsync(PointerFixtures.Owner);

        Assert.Equal(PointerFixtures.Recipient, c.Pointer);
        Assert.Equal(new[] { PointerFixtures.Recipient }, c.Transfers);
        Assert.False(c.Frozen);
    }

    private void RoutePrepare(string op, string counter, object? signedQuotes = null) =>
        _server.RouteOk("POST", "/v1/pointers/prepare", new
        {
            signed_quotes = signedQuotes,
            upload_id = "up1",
            op,
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            counter,
            payment_type = "wave_batch",
            payments = new[] { new { quote_hash = "0xq", rewards_address = "0xr", amount = "5" } },
            total_amount = "5",
            payment_vault_address = "0xvault",
            payment_token_address = "0xtoken",
            rpc_url = "http://localhost:8545",
        });

    [Fact]
    public async Task PointerPrepare_Update_SendsTargetAndKind()
    {
        RoutePrepare("update", "4");
        _server.Start();

        var p = await _client.PointerPrepareAsync(
            PointerPrepareRequest.Update(PointerFixtures.Owner, PointerFixtures.Target));

        Assert.Equal("up1", p.UploadId);
        Assert.Equal("update", p.Op);
        Assert.Equal(4UL, p.Counter);
        Assert.Equal("wave_batch", p.PaymentType);
        Assert.Equal(new PaymentInfo("0xq", "0xr", "5"), Assert.Single(p.Payments));
        Assert.Equal("5", p.TotalAmount);
        Assert.Equal("0xvault", p.PaymentVaultAddress);
        Assert.Equal("0xtoken", p.PaymentTokenAddress);
        Assert.Equal("http://localhost:8545", p.RpcUrl);
        var body = LastBody("POST", "/v1/pointers/prepare");
        Assert.Equal("update", body.GetProperty("op").GetString());
        Assert.Equal(PointerFixtures.Target, body.GetProperty("target").GetString());
        Assert.Equal("chunk", body.GetProperty("kind").GetString());
        Assert.False(body.TryGetProperty("recipient", out _));
    }

    [Fact]
    public async Task PointerPrepare_SignedQuotes_FlagOmittedByDefault_ResultEmpty()
    {
        RoutePrepare("update", "4");
        _server.Start();

        var p = await _client.PointerPrepareAsync(
            PointerPrepareRequest.Update(PointerFixtures.Owner, PointerFixtures.Target));

        Assert.False(LastBody("POST", "/v1/pointers/prepare").TryGetProperty("include_signed_quotes", out _));
        Assert.Empty(p.SignedQuotes);
    }

    [Fact]
    public async Task PointerPrepare_SignedQuotes_FlagSentWhenTrue_ParsesEntries()
    {
        RoutePrepare("update", "4", new object[]
        {
            new { quote_hash = "0xq", quote = "cXVvdGU=", commitment_sidecar = "c2lkZQ==" },
            new { quote_hash = "0xq2", quote = "cTI=" },
        });
        _server.Start();

        var p = await _client.PointerPrepareAsync(
            PointerPrepareRequest.Update(PointerFixtures.Owner, PointerFixtures.Target, includeSignedQuotes: true));

        Assert.True(LastBody("POST", "/v1/pointers/prepare").GetProperty("include_signed_quotes").GetBoolean());
        Assert.Equal(
            new[] { new SignedQuoteEntry("0xq", "cXVvdGU=", "c2lkZQ=="), new SignedQuoteEntry("0xq2", "cTI=", null) },
            p.SignedQuotes);
    }

    [Fact]
    public async Task PointerPrepare_Transfer_SendsRecipientOnly()
    {
        RoutePrepare("transfer", PointerFixtures.MaxCounter);
        _server.Start();

        var p = await _client.PointerPrepareAsync(
            PointerPrepareRequest.Transfer(PointerFixtures.Owner, PointerFixtures.Recipient));

        Assert.Equal(ulong.MaxValue, p.Counter);
        var body = LastBody("POST", "/v1/pointers/prepare");
        Assert.Equal("transfer", body.GetProperty("op").GetString());
        Assert.Equal(PointerFixtures.Recipient, body.GetProperty("recipient").GetString());
        Assert.False(body.TryGetProperty("target", out _));
        Assert.False(body.TryGetProperty("kind", out _));
    }

    [Fact]
    public async Task PointerFinalize_SendsTxHashes_ParsesFinality()
    {
        _server.RouteOk("POST", "/v1/pointers/finalize", new
        {
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            counter = PointerFixtures.MaxCounter,
            finality = FinalityJson(),
        });
        _server.Start();

        var r = await _client.PointerFinalizeAsync("up1", new Dictionary<string, string> { ["0xq"] = "0xtx" });

        Assert.Equal(ulong.MaxValue, r.Counter);
        Assert.True(r.Finality!.IsFinal);
        var body = LastBody("POST", "/v1/pointers/finalize");
        Assert.Equal("up1", body.GetProperty("upload_id").GetString());
        Assert.Equal("0xtx", body.GetProperty("tx_hashes").GetProperty("0xq").GetString());
    }

    [Fact]
    public async Task PointerFinalize_WithoutFinality_IsNull()
    {
        _server.RouteOk("POST", "/v1/pointers/finalize", new
        {
            address = PointerFixtures.Owner,
            state_id = PointerFixtures.StateId,
            counter = "1",
        });
        _server.Start();

        var r = await _client.PointerFinalizeAsync("up1", new Dictionary<string, string>());

        Assert.Equal(1UL, r.Counter);
        Assert.Null(r.Finality);
    }

    // ── Error mapping ──

    private static string ErrorBody(string code, string error = "boom", bool? retryable = null) =>
        retryable is null
            ? JsonSerializer.Serialize(new { error, code })
            : JsonSerializer.Serialize(new { error, code, retryable });

    [Fact]
    public async Task Update_PointerFinal_ThrowsPointerFinalException()
    {
        _server.Route("POST", "/v1/pointers/update", 409, ErrorBody("POINTER_FINAL", "Pointer is final: transferred"));
        _server.Start();

        var ex = await Assert.ThrowsAsync<PointerFinalException>(
            () => _client.PointerUpdateAsync(PointerFixtures.Owner, PointerFixtures.Target));

        Assert.Equal(409, ex.StatusCode);
        Assert.Equal("Pointer is final: transferred", ex.Message);
        Assert.IsAssignableFrom<ForkException>(ex);
    }

    [Fact]
    public async Task Get_PointerForked_ThrowsPointerForkedException()
    {
        _server.Route("GET", $"/v1/pointers/{PointerFixtures.Owner}", 409, ErrorBody("POINTER_FORKED"));
        _server.Start();

        var ex = await Assert.ThrowsAsync<PointerForkedException>(() => _client.PointerGetAsync(PointerFixtures.Owner));
        Assert.Equal(409, ex.StatusCode);
    }

    [Fact]
    public async Task Update_Conflict_ThrowsConflictException()
    {
        _server.Route("POST", "/v1/pointers/update", 409, ErrorBody("CONFLICT", "Conflict: a prepared write awaits payment"));
        _server.Start();

        var ex = await Assert.ThrowsAsync<ConflictException>(
            () => _client.PointerUpdateAsync(PointerFixtures.Owner, PointerFixtures.Target));
        Assert.Equal("Conflict: a prepared write awaits payment", ex.Message);
    }

    [Fact]
    public async Task Create_AlreadyExists_KeepsTheExisting409Mapping()
    {
        // A REST 409 without a pointer code has always been a ForkException;
        // ALREADY_EXISTS keeps that mapping.
        _server.Route("POST", "/v1/pointers", 409, ErrorBody("ALREADY_EXISTS", "Already exists: pointer"));
        _server.Start();

        var ex = await Assert.ThrowsAsync<ForkException>(
            () => _client.PointerCreateAsync(PointerFixtures.Owner, PointerFixtures.Target));
        Assert.IsType<ForkException>(ex);
    }

    [Theory]
    [InlineData(true, true)]
    [InlineData(false, false)]
    [InlineData(null, false)]
    public async Task Finalize_CloseGroupShortfall_CarriesRetryable(bool? retryable, bool expected)
    {
        _server.Route("POST", "/v1/pointers/finalize", 503, ErrorBody("CLOSE_GROUP_SHORTFALL", "Close group shortfall: 3/7", retryable));
        _server.Start();

        var ex = await Assert.ThrowsAsync<CloseGroupShortfallException>(
            () => _client.PointerFinalizeAsync("up1", new Dictionary<string, string>()));

        Assert.Equal(expected, ex.Retryable);
        Assert.Equal(503, ex.StatusCode);
        Assert.Equal("Close group shortfall: 3/7", ex.Message);
    }

    [Fact]
    public async Task CloseGroupShortfall_RetryableMustBeAJsonTrue()
    {
        _server.Route("POST", "/v1/pointers/finalize", 503,
            JsonSerializer.Serialize(new { error = "x", code = "CLOSE_GROUP_SHORTFALL", retryable = "true" }));
        _server.Start();

        var ex = await Assert.ThrowsAsync<CloseGroupShortfallException>(
            () => _client.PointerFinalizeAsync("up1", new Dictionary<string, string>()));
        Assert.False(ex.Retryable);
    }

    [Fact]
    public async Task CloseGroupShortfall_OnANonPointerCall_IsTypedToo()
    {
        _server.Route("POST", "/v1/chunks", 503, ErrorBody("CLOSE_GROUP_SHORTFALL"));
        _server.Start();

        await Assert.ThrowsAsync<CloseGroupShortfallException>(() => _client.ChunkPutAsync(new byte[] { 1 }));
    }

    [Theory]
    [InlineData(409, "not json", typeof(ForkException))]
    [InlineData(409, "{\"error\":\"x\",\"code\":\"SOMETHING_NEW\"}", typeof(ForkException))]
    [InlineData(503, "{\"error\":\"wallet not configured\",\"code\":\"SERVICE_UNAVAILABLE\"}", typeof(ServiceUnavailableException))]
    [InlineData(409, "{\"error\":\"x\",\"code\":7}", typeof(ForkException))]
    [InlineData(409, "[\"POINTER_FINAL\"]", typeof(ForkException))]
    public void FromHttpStatus_UntypedBodies_KeepTheStatusMapping(int status, string body, Type expected)
    {
        var ex = ExceptionMapping.FromHttpStatus((HttpStatusCode)status, body);
        Assert.IsType(expected, ex);
        Assert.Equal(body, ex.Message);
    }
}

/// <summary>gRPC pointer methods against a mocked PointerService stub.</summary>
public sealed class PointerGrpcTests
{
    private static AsyncUnaryCall<T> Reply<T>(T value) =>
        TestCalls.AsyncUnaryCall(
            Task.FromResult(value),
            Task.FromResult(new Metadata()),
            () => Status.DefaultSuccess,
            () => new Metadata(),
            () => { });

    /// <summary>A failed call whose trailers carry the daemon's error code, as tonic sends it.</summary>
    internal static AsyncUnaryCall<T> Fail<T>(StatusCode code, string detail, string? antdCode = null)
    {
        var status = new Status(code, detail);
        var trailers = new Metadata();
        if (antdCode != null) trailers.Add(ExceptionMapping.ErrorCodeTrailer, antdCode);
        return TestCalls.AsyncUnaryCall(
            Task.FromException<T>(new RpcException(status, trailers)),
            Task.FromResult(new Metadata()),
            () => status,
            () => trailers,
            () => { });
    }

    private static Pb.PointerFinality ProtoFinality(string status, string counter = "") => new()
    {
        Address = PointerFixtures.Owner,
        Group = 7,
        Answered = 7,
        Status = status,
        Counter = counter,
        TransferredTo = status == "final" ? PointerFixtures.Recipient : "",
    };

    private sealed class MockPointerService : Pb.PointerService.PointerServiceClient
    {
        public Pb.PointerWriteRequest? LastWrite;
        public string? LastWriteRpc;
        public Pb.PreparePointerRequest? LastPrepare;
        public Pb.FinalizePointerRequest? LastFinalize;
        public string Counter = "0";
        public Func<AsyncUnaryCall<Pb.PointerWriteResponse>>? WriteFailure;

        public override AsyncUnaryCall<Pb.ListPointerKeysResponse> ListKeysAsync(
            Pb.ListPointerKeysRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            var resp = new Pb.ListPointerKeysResponse();
            resp.Keys.Add(new Pb.PointerKey { Address = PointerFixtures.Owner });
            resp.Keys.Add(new Pb.PointerKey { Address = PointerFixtures.Recipient });
            return Reply(resp);
        }

        private AsyncUnaryCall<Pb.PointerWriteResponse> Write(string rpc, Pb.PointerWriteRequest request)
        {
            LastWrite = request;
            LastWriteRpc = rpc;
            if (WriteFailure != null) return WriteFailure();
            return Reply(new Pb.PointerWriteResponse
            {
                Address = request.Owner,
                StateId = PointerFixtures.StateId,
                Counter = Counter,
            });
        }

        public override AsyncUnaryCall<Pb.PointerWriteResponse> CreateAsync(
            Pb.PointerWriteRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Write("create", request);

        public override AsyncUnaryCall<Pb.PointerWriteResponse> UpdateAsync(
            Pb.PointerWriteRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Write("update", request);

        public override AsyncUnaryCall<Pb.PointerTransferResponse> TransferAsync(
            Pb.PointerTransferRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            var resp = new Pb.PointerTransferResponse { Address = request.Owner, StateId = PointerFixtures.StateId };
            // "unchecked" recipient: the finality check failed after the write.
            if (request.Recipient == "unchecked")
                resp.FinalityError = "close group did not answer";
            else
            {
                resp.Finality = ProtoFinality("final");
                resp.Finality.State = new Pb.PointerFinalState
                {
                    StateId = PointerFixtures.StateId,
                    Kind = "pointer",
                    KindTag = 1,
                    Target = request.Recipient,
                    Holders = 7,
                    TransferredTo = request.Recipient,
                };
            }
            return Reply(resp);
        }

        public override AsyncUnaryCall<Pb.PointerRecord> GetAsync(
            Pb.GetPointerRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Reply(new Pb.PointerRecord
            {
                Address = request.Address,
                Owner = "ab",
                Counter = Counter,
                Kind = "chunk",
                KindTag = 0,
                Target = PointerFixtures.Target,
                StateId = PointerFixtures.StateId,
                IsFinal = false,
                TransferredTo = "",
            });

        public override AsyncUnaryCall<Pb.PointerResolved> ResolveAsync(
            Pb.ResolvePointerRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Reply(new Pb.PointerResolved { Kind = "chunk", KindTag = 0, Target = PointerFixtures.Target });

        public override AsyncUnaryCall<Pb.PointerFinality> FinalityAsync(
            Pb.PointerFinalityRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            if (request.Address == "forked")
            {
                var f = ProtoFinality("forked");
                var a = new Pb.PointerFinalState { StateId = "s1", Kind = "pointer", KindTag = 1, Target = "t1", Holders = 4, TransferredTo = "t1" };
                f.States.Add(a);
                f.States.Add(new Pb.PointerFinalState { StateId = "s2", Kind = "pointer", KindTag = 1, Target = "t2", Holders = 2 });
                f.Majority = a;
                return Reply(f);
            }
            // "unset": an open pointer whose counter no peer corroborates.
            return Reply(ProtoFinality("open", request.Address == "unset" ? "" : Counter));
        }

        public override AsyncUnaryCall<Pb.PointerController> ControllerAsync(
            Pb.PointerControllerRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            var c = new Pb.PointerController { Pointer = PointerFixtures.Recipient, Frozen = false };
            c.Transfers.Add(PointerFixtures.Recipient);
            return Reply(c);
        }

        public override AsyncUnaryCall<Pb.PreparePointerResponse> PrepareAsync(
            Pb.PreparePointerRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            LastPrepare = request;
            var resp = new Pb.PreparePointerResponse
            {
                UploadId = "up1",
                Op = request.Op,
                Address = request.Owner,
                StateId = PointerFixtures.StateId,
                Counter = request.Op == "transfer" ? PointerFixtures.MaxCounter : "1",
                PaymentType = "wave_batch",
                TotalAmount = "5",
                PaymentVaultAddress = "0xvault",
                PaymentTokenAddress = "0xtoken",
                RpcUrl = "http://localhost:8545",
            };
            resp.Payments.Add(new Pb.PaymentEntry { QuoteHash = "0xq", RewardsAddress = "0xr", Amount = "5" });
            if (request.IncludeSignedQuotes)
            {
                resp.SignedQuotes.Add(new Pb.SignedQuoteEntry
                {
                    QuoteHash = "0xq",
                    Quote = Google.Protobuf.ByteString.CopyFromUtf8("quote"),
                    CommitmentSidecar = Google.Protobuf.ByteString.CopyFromUtf8("side"),
                });
                resp.SignedQuotes.Add(new Pb.SignedQuoteEntry
                {
                    QuoteHash = "0xq2",
                    Quote = Google.Protobuf.ByteString.CopyFromUtf8("q2"),
                });
            }
            return Reply(resp);
        }

        public override AsyncUnaryCall<Pb.FinalizePointerResponse> FinalizeAsync(
            Pb.FinalizePointerRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            LastFinalize = request;
            if (request.UploadId == "short")
                return Fail<Pb.FinalizePointerResponse>(StatusCode.Unavailable,
                    "Close group shortfall: 3/7 stored (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)",
                    "CLOSE_GROUP_SHORTFALL");
            return Reply(new Pb.FinalizePointerResponse
            {
                Address = PointerFixtures.Owner,
                StateId = PointerFixtures.StateId,
                Counter = "2",
            });
        }
    }

    private static AntdGrpcClient MakeClient(MockPointerService pointer) =>
        new(health: null!, data: null!, chunks: null!, files: null!, upload: null!, wallet: null!, pointer: pointer);

    [Fact]
    public async Task PointerKeys_ReturnsAddresses()
    {
        var keys = await MakeClient(new MockPointerService()).PointerKeysAsync();
        Assert.Equal(new[] { PointerFixtures.Owner, PointerFixtures.Recipient }, keys);
    }

    [Fact]
    public async Task PointerCreate_SendsRequest_ParsesCounter()
    {
        var mock = new MockPointerService();
        var w = await MakeClient(mock).PointerCreateAsync(PointerFixtures.Owner, PointerFixtures.Target);

        Assert.Equal(new PointerWriteResult(PointerFixtures.Owner, PointerFixtures.StateId, 0UL), w);
        Assert.Equal("create", mock.LastWriteRpc);
        Assert.Equal(PointerFixtures.Target, mock.LastWrite!.Target);
        Assert.Equal("chunk", mock.LastWrite.Kind);
    }

    [Fact]
    public async Task PointerUpdate_UsesUpdateRpc_ParsesMaxCounter()
    {
        var mock = new MockPointerService { Counter = PointerFixtures.MaxCounter };
        var w = await MakeClient(mock).PointerUpdateAsync(PointerFixtures.Owner, PointerFixtures.Recipient, PointerKind.Pointer);

        Assert.Equal(ulong.MaxValue, w.Counter);
        Assert.Equal("update", mock.LastWriteRpc);
        Assert.Equal("pointer", mock.LastWrite!.Kind);
    }

    [Theory]
    [MemberData(nameof(PointerFixtures.MalformedCounters), MemberType = typeof(PointerFixtures))]
    public async Task PointerGet_MalformedCounter_Throws(string counter)
    {
        var mock = new MockPointerService { Counter = counter };
        var ex = await Assert.ThrowsAsync<AntdException>(() => MakeClient(mock).PointerGetAsync(PointerFixtures.Owner));
        Assert.Contains("not a decimal counter", ex.Message);
    }

    [Fact]
    public async Task PointerGet_EmptyTransferredTo_IsNull()
    {
        var r = await MakeClient(new MockPointerService { Counter = "5" }).PointerGetAsync(PointerFixtures.Owner);

        Assert.Equal(5UL, r.Counter);
        Assert.Null(r.TransferredTo);
        Assert.Equal(PointerKind.Chunk, r.TargetKind);
    }

    [Fact]
    public async Task PointerTransfer_ParsesFinality()
    {
        var t = await MakeClient(new MockPointerService()).PointerTransferAsync(PointerFixtures.Owner, PointerFixtures.Recipient);

        Assert.Null(t.FinalityError);
        Assert.True(t.Finality!.IsFinal);
        Assert.Equal(PointerFixtures.Recipient, t.Finality.TransferredTo);
        Assert.Null(t.Finality.Counter);
        Assert.Null(t.Finality.Majority);
        Assert.Equal(PointerFixtures.Recipient, t.Finality.State!.TransferredTo);
    }

    [Fact]
    public async Task PointerTransfer_UnsetFinality_IsNullWithError()
    {
        var t = await MakeClient(new MockPointerService()).PointerTransferAsync(PointerFixtures.Owner, "unchecked");

        Assert.Null(t.Finality);
        Assert.Equal("close group did not answer", t.FinalityError);
    }

    [Fact]
    public async Task PointerResolve_ParsesTarget()
    {
        var t = await MakeClient(new MockPointerService()).PointerResolveAsync(PointerFixtures.Owner);
        Assert.Equal(new PointerTarget("chunk", 0, PointerFixtures.Target), t);
    }

    [Fact]
    public async Task PointerFinality_EmptyCounter_IsNull()
    {
        var f = await MakeClient(new MockPointerService()).PointerFinalityAsync("unset");

        Assert.Equal(PointerFinalityStatus.Open, f.Status);
        Assert.Null(f.Counter);
        Assert.Null(f.State);
        Assert.Null(f.TransferredTo);
    }

    [Fact]
    public async Task PointerFinality_Open_ParsesCounter()
    {
        var f = await MakeClient(new MockPointerService { Counter = "9" }).PointerFinalityAsync(PointerFixtures.Owner);
        Assert.Equal(9UL, f.Counter);
    }

    [Fact]
    public async Task PointerFinality_Forked_ParsesStatesAndMajority()
    {
        var f = await MakeClient(new MockPointerService()).PointerFinalityAsync("forked");

        Assert.Equal(PointerFinalityStatus.Forked, f.Status);
        Assert.Equal(2, f.States.Count);
        Assert.Null(f.States[1].TransferredTo);
        Assert.Equal(new PointerFinalState("s1", "pointer", 1, "t1", 4, "t1"), f.Majority);
    }

    [Fact]
    public async Task PointerController_ParsesTransfers()
    {
        var c = await MakeClient(new MockPointerService()).PointerControllerAsync(PointerFixtures.Owner);
        Assert.Equal(new PointerController(PointerFixtures.Recipient, c.Transfers, false), c);
        Assert.Equal(new[] { PointerFixtures.Recipient }, c.Transfers);
    }

    [Fact]
    public async Task PointerPrepare_Transfer_SendsRecipientAndNoKind()
    {
        var mock = new MockPointerService();
        var p = await MakeClient(mock).PointerPrepareAsync(
            PointerPrepareRequest.Transfer(PointerFixtures.Owner, PointerFixtures.Recipient));

        Assert.Equal(ulong.MaxValue, p.Counter);
        Assert.Equal("transfer", mock.LastPrepare!.Op);
        Assert.Equal(PointerFixtures.Recipient, mock.LastPrepare.Recipient);
        Assert.Equal("", mock.LastPrepare.Kind);
        Assert.Equal("", mock.LastPrepare.Target);
        Assert.Equal(new PaymentInfo("0xq", "0xr", "5"), Assert.Single(p.Payments));
    }

    [Fact]
    public async Task PointerPrepare_SignedQuotes_FlagUnsetByDefault_ResultEmpty()
    {
        var mock = new MockPointerService();
        var p = await MakeClient(mock).PointerPrepareAsync(
            PointerPrepareRequest.Update(PointerFixtures.Owner, PointerFixtures.Target));

        Assert.False(mock.LastPrepare!.IncludeSignedQuotes);
        Assert.Empty(p.SignedQuotes);
    }

    [Fact]
    public async Task PointerPrepare_SignedQuotes_FlagSet_MapsBytesToBase64()
    {
        var mock = new MockPointerService();
        var p = await MakeClient(mock).PointerPrepareAsync(
            PointerPrepareRequest.Update(PointerFixtures.Owner, PointerFixtures.Target, includeSignedQuotes: true));

        Assert.True(mock.LastPrepare!.IncludeSignedQuotes);
        Assert.Equal(
            new[] { new SignedQuoteEntry("0xq", "cXVvdGU=", "c2lkZQ=="), new SignedQuoteEntry("0xq2", "cTI=", null) },
            p.SignedQuotes);
    }

    [Fact]
    public async Task PointerPrepare_Create_SendsTargetAndKind()
    {
        var mock = new MockPointerService();
        var p = await MakeClient(mock).PointerPrepareAsync(
            PointerPrepareRequest.Create(PointerFixtures.Owner, PointerFixtures.Recipient, PointerKind.Pointer));

        Assert.Equal(1UL, p.Counter);
        Assert.Equal("create", mock.LastPrepare!.Op);
        Assert.Equal("pointer", mock.LastPrepare.Kind);
        Assert.Equal(PointerFixtures.Recipient, mock.LastPrepare.Target);
    }

    [Fact]
    public async Task PointerFinalize_ForwardsTxHashes()
    {
        var mock = new MockPointerService();
        var r = await MakeClient(mock).PointerFinalizeAsync("up1", new Dictionary<string, string> { ["0xq"] = "0xtx" });

        Assert.Equal(2UL, r.Counter);
        Assert.Null(r.Finality);
        Assert.Equal("0xtx", mock.LastFinalize!.TxHashes["0xq"]);
    }

    [Fact]
    public async Task PointerFinalize_RetainedShortfall_IsRetryable()
    {
        var ex = await Assert.ThrowsAsync<CloseGroupShortfallException>(
            () => MakeClient(new MockPointerService()).PointerFinalizeAsync("short", new Dictionary<string, string>()));
        Assert.True(ex.Retryable);
    }

    [Fact]
    public async Task PointerUpdate_TaggedFailedPrecondition_IsPointerFinal()
    {
        // The client must hand RpcException.Trailers to the mapping.
        var mock = new MockPointerService
        {
            WriteFailure = () => Fail<Pb.PointerWriteResponse>(StatusCode.FailedPrecondition, "Pointer is final", "POINTER_FINAL"),
        };
        await Assert.ThrowsAsync<PointerFinalException>(
            () => MakeClient(mock).PointerUpdateAsync(PointerFixtures.Owner, PointerFixtures.Target));
    }

    [Fact]
    public async Task PointerCreate_AlreadyExists_IsAlreadyExistsException()
    {
        var mock = new MockPointerService
        {
            WriteFailure = () => Fail<Pb.PointerWriteResponse>(StatusCode.AlreadyExists, "Already exists: pointer"),
        };
        await Assert.ThrowsAsync<AlreadyExistsException>(
            () => MakeClient(mock).PointerCreateAsync(PointerFixtures.Owner, PointerFixtures.Target));
    }
}

/// <summary>The x-antd-error-code trailer mapping, status by status.</summary>
public sealed class GrpcErrorCodeTrailerTests
{
    private static AntdException Map(StatusCode code, string detail, string? antdCode)
    {
        var trailers = new Metadata();
        if (antdCode != null) trailers.Add(ExceptionMapping.ErrorCodeTrailer, antdCode);
        return ExceptionMapping.FromGrpcStatus(new RpcException(new Status(code, detail), trailers));
    }

    [Theory]
    // The tag counts only when it agrees with the status code.
    [InlineData(StatusCode.FailedPrecondition, "POINTER_FINAL", typeof(PointerFinalException))]
    [InlineData(StatusCode.FailedPrecondition, "POINTER_FORKED", typeof(PointerForkedException))]
    [InlineData(StatusCode.Aborted, "CONFLICT", typeof(ConflictException))]
    [InlineData(StatusCode.Unavailable, "CLOSE_GROUP_SHORTFALL", typeof(CloseGroupShortfallException))]
    // No tag: the code-based mapping, so FAILED_PRECONDITION is still a payment error.
    [InlineData(StatusCode.FailedPrecondition, null, typeof(PaymentException))]
    [InlineData(StatusCode.Aborted, null, typeof(ForkException))]
    [InlineData(StatusCode.Unavailable, null, typeof(NetworkException))]
    // A tag on the wrong code, or one this SDK does not know, is ignored.
    [InlineData(StatusCode.FailedPrecondition, "CONFLICT", typeof(PaymentException))]
    [InlineData(StatusCode.FailedPrecondition, "CLOSE_GROUP_SHORTFALL", typeof(PaymentException))]
    [InlineData(StatusCode.Aborted, "POINTER_FINAL", typeof(ForkException))]
    [InlineData(StatusCode.Unavailable, "POINTER_FORKED", typeof(NetworkException))]
    [InlineData(StatusCode.NotFound, "POINTER_FINAL", typeof(NotFoundException))]
    [InlineData(StatusCode.AlreadyExists, "CONFLICT", typeof(AlreadyExistsException))]
    [InlineData(StatusCode.FailedPrecondition, "pointer_final", typeof(PaymentException))]
    [InlineData(StatusCode.FailedPrecondition, "SOMETHING_NEW", typeof(PaymentException))]
    public void Tag_MapsOnlyWhenItAgreesWithTheStatus(StatusCode code, string? antdCode, Type expected)
    {
        var ex = Map(code, "detail text", antdCode);
        Assert.IsType(expected, ex);
        Assert.Equal("detail text", ex.Message);
    }

    [Fact]
    public void TaggedTypes_CarryTheRestStatusCodes()
    {
        Assert.Equal(409, Map(StatusCode.FailedPrecondition, "x", "POINTER_FINAL").StatusCode);
        Assert.Equal(409, Map(StatusCode.Aborted, "x", "CONFLICT").StatusCode);
        Assert.Equal(503, Map(StatusCode.Unavailable, "x", "CLOSE_GROUP_SHORTFALL").StatusCode);
    }

    [Fact]
    public void TaggedAborted_IsConflictEvenWithAPartialUploadPrefix()
    {
        // The tag wins: the daemon tags only its CONFLICT.
        Assert.IsType<ConflictException>(Map(StatusCode.Aborted, "Partial upload: 1/3 chunks stored, 2 failed", "CONFLICT"));
    }

    [Theory]
    [InlineData("Close group shortfall: 3/7 (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)", true)]
    [InlineData("Close group shortfall: only 3 of 7 peers answered", false)]
    [InlineData("Close group shortfall: (paid attempt retained) but then more text", false)]
    [InlineData("Close group shortfall: x (stored chunks persist; re-prepare the same content to retry only the remainder)", false)]
    [InlineData("Close group shortfall: x (paid attempt retai", false)]
    public void Shortfall_RetryableComesFromTheClosingHint(string detail, bool retryable)
    {
        var ex = Assert.IsType<CloseGroupShortfallException>(Map(StatusCode.Unavailable, detail, "CLOSE_GROUP_SHORTFALL"));
        Assert.Equal(retryable, ex.Retryable);
    }
}

/// <summary>
/// IAntdClient's pointer members have default implementations, so a class
/// written against the interface before pointers existed still compiles.
/// </summary>
public sealed class PointerInterfaceCompatTests
{
    private sealed class PrePointerClient : IAntdClient
    {
        private static Exception No() => new NotImplementedException();
        public void Dispose() { }
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        public Task<HealthStatus> HealthAsync() => throw No();
        public Task<DataPutPublicResult> DataPutPublicAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto) => throw No();
        public Task<byte[]> DataGetPublicAsync(string address) => throw No();
        public Task<DataPutResult> DataPutAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto) => throw No();
        public Task<byte[]> DataGetAsync(string dataMap) => throw No();
        public Task<UploadCostEstimate> DataCostAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto) => throw No();
        public Task<PutResult> ChunkPutAsync(byte[] data) => throw No();
        public Task<byte[]> ChunkGetAsync(string address) => throw No();
        public Task<PrepareChunkResult> PrepareChunkUploadAsync(byte[] data) => throw No();
        public Task<string> FinalizeChunkUploadAsync(string uploadId, IDictionary<string, string> txHashes) => throw No();
        public Task<FilePutResult> FilePutAsync(string path, PaymentMode paymentMode = PaymentMode.Auto) => throw No();
        public Task FileGetAsync(string dataMap, string destPath) => throw No();
        public Task<FilePutPublicResult> FilePutPublicAsync(string path, PaymentMode paymentMode = PaymentMode.Auto) => throw No();
        public Task FileGetPublicAsync(string address, string destPath) => throw No();
        public Task<UploadCostEstimate> FileCostAsync(string path, bool isPublic = true, PaymentMode paymentMode = PaymentMode.Auto) => throw No();
        public Task<WalletAddress> WalletAddressAsync() => throw No();
        public Task<WalletBalance> WalletBalanceAsync() => throw No();
        public Task<bool> WalletApproveAsync() => throw No();
        public Task<PrepareUploadResult> PrepareUploadAsync(string path, string? visibility = null) => throw No();
        public Task<PrepareUploadResult> PrepareUploadPublicAsync(string path) => throw No();
        public Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data, string? visibility = null) => throw No();
        public Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes) => throw No();
        public Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash) => throw No();
    }

    [Fact]
    public async Task PointerMembers_DefaultToNotSupported()
    {
        IAntdClient client = new PrePointerClient();
        await Assert.ThrowsAsync<NotSupportedException>(() => client.PointerKeysAsync());
        await Assert.ThrowsAsync<NotSupportedException>(() => client.PointerGetAsync(PointerFixtures.Owner));
    }

    [Fact]
    public void BothClients_ImplementThePointerMembers()
    {
        // A public method with the interface member's signature replaces the
        // default implementation.
        foreach (var type in new[] { typeof(AntdRestClient), typeof(AntdGrpcClient) })
        {
            var map = type.GetInterfaceMap(typeof(IAntdClient));
            foreach (var (iface, impl) in map.InterfaceMethods.Zip(map.TargetMethods))
                Assert.True(impl.DeclaringType == type, $"{type.Name} does not implement {iface.Name}");
        }
    }
}
