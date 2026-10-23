using System.Text.Json;
using Antd.Sdk;
using Google.Protobuf;
using Grpc.Core;
using Grpc.Core.Testing;
using Xunit;
using Pb = Antd.V1;

namespace Antd.Sdk.Tests;

/// <summary>Shared values for the sha256 tests.</summary>
internal static class ShaFixtures
{
    public const string Hash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
    public const string Link = "ant://manifest/wUFOVAE";
    public const string Address = "42424242424242424242424242424242424242424242424242424242424242aa";
}

/// <summary>sha256 on the upload results and manifest entries, over REST (mock daemon).</summary>
public sealed class Sha256RestTests : IDisposable
{
    private readonly MockServer _server = new();
    private readonly AntdRestClient _client;

    public Sha256RestTests() =>
        _client = new AntdRestClient(_server.BaseUrl, timeout: TimeSpan.FromSeconds(5));

    public void Dispose()
    {
        _client.Dispose();
        _server.Dispose();
    }

    private JsonElement LastBody(string path) =>
        JsonDocument.Parse(_server.LastRequestBodies[$"POST {path}"]).RootElement;

    private static bool Has(JsonElement e, string name) => e.TryGetProperty(name, out _);

    // ── Upload results ──

    [Fact]
    public async Task DataPut_ReadsSha256_WhenPresent_NullWhenAbsentOrEmpty()
    {
        _server.RouteOk("POST", "/v1/data", new { data_map = "dm", chunks_stored = 3, payment_mode_used = "auto", sha256 = ShaFixtures.Hash });
        _server.Start();
        var withHash = await _client.DataPutAsync(new byte[] { 1 });
        Assert.Equal(ShaFixtures.Hash, withHash.Sha256);
        Assert.Equal("dm", withHash.DataMap);

        _server.RouteOk("POST", "/v1/data", new { data_map = "dm", chunks_stored = 3, payment_mode_used = "auto" });
        Assert.Null((await _client.DataPutAsync(new byte[] { 1 })).Sha256);

        _server.RouteOk("POST", "/v1/data", new { data_map = "dm", sha256 = "" });
        Assert.Null((await _client.DataPutAsync(new byte[] { 1 })).Sha256);
    }

    [Fact]
    public async Task DataPutPublic_ReadsSha256_WhenPresent_NullWhenAbsentOrEmpty()
    {
        _server.RouteOk("POST", "/v1/data/public", new { address = "ad", chunks_stored = 2, payment_mode_used = "auto", sha256 = ShaFixtures.Hash });
        _server.Start();
        Assert.Equal(ShaFixtures.Hash, (await _client.DataPutPublicAsync(new byte[] { 1 })).Sha256);

        _server.RouteOk("POST", "/v1/data/public", new { address = "ad" });
        Assert.Null((await _client.DataPutPublicAsync(new byte[] { 1 })).Sha256);

        _server.RouteOk("POST", "/v1/data/public", new { address = "ad", sha256 = "" });
        Assert.Null((await _client.DataPutPublicAsync(new byte[] { 1 })).Sha256);
    }

    [Fact]
    public async Task FilePut_ReadsSha256_WhenPresent_NullWhenAbsentOrEmpty()
    {
        var full = new { data_map = "dm", storage_cost_atto = "1", gas_cost_wei = "2", chunks_stored = 3, payment_mode_used = "auto" };
        _server.RouteOk("POST", "/v1/files", new { full.data_map, full.storage_cost_atto, full.gas_cost_wei, full.chunks_stored, full.payment_mode_used, sha256 = ShaFixtures.Hash });
        _server.Start();
        var r = await _client.FilePutAsync("/tmp/f");
        Assert.Equal(ShaFixtures.Hash, r.Sha256);
        Assert.Equal(("dm", "1", "2", 3UL, "auto"), (r.DataMap, r.StorageCostAtto, r.GasCostWei, r.ChunksStored, r.PaymentModeUsed));

        _server.RouteOk("POST", "/v1/files", full);
        Assert.Null((await _client.FilePutAsync("/tmp/f")).Sha256);

        _server.RouteOk("POST", "/v1/files", new { full.data_map, full.storage_cost_atto, full.gas_cost_wei, full.chunks_stored, full.payment_mode_used, sha256 = "" });
        Assert.Null((await _client.FilePutAsync("/tmp/f")).Sha256);
    }

    [Fact]
    public async Task FilePutPublic_ReadsSha256_WhenPresent_NullWhenAbsentOrEmpty()
    {
        _server.RouteOk("POST", "/v1/files/public", new { address = "ad", storage_cost_atto = "1", gas_cost_wei = "2", chunks_stored = 3, payment_mode_used = "auto", sha256 = ShaFixtures.Hash });
        _server.Start();
        Assert.Equal(ShaFixtures.Hash, (await _client.FilePutPublicAsync("/tmp/f")).Sha256);

        _server.RouteOk("POST", "/v1/files/public", new { address = "ad", storage_cost_atto = "1", gas_cost_wei = "2", chunks_stored = 3, payment_mode_used = "auto" });
        Assert.Null((await _client.FilePutPublicAsync("/tmp/f")).Sha256);

        _server.RouteOk("POST", "/v1/files/public", new { address = "ad", storage_cost_atto = "1", gas_cost_wei = "2", chunks_stored = 3, payment_mode_used = "auto", sha256 = "" });
        Assert.Null((await _client.FilePutPublicAsync("/tmp/f")).Sha256);
    }

    [Fact]
    public async Task FinalizeUpload_AndFinalizeMerkle_ReadSha256_NullWhenAbsentOrEmpty()
    {
        var tx = new Dictionary<string, string> { ["q"] = "t" };
        _server.RouteOk("POST", "/v1/upload/finalize", new { address = "", chunks_stored = 4, data_map = "dm", sha256 = ShaFixtures.Hash });
        _server.Start();
        Assert.Equal(ShaFixtures.Hash, (await _client.FinalizeUploadAsync("up", tx)).Sha256);
        Assert.Equal(ShaFixtures.Hash, (await _client.FinalizeMerkleUploadAsync("up", "pool")).Sha256);

        _server.RouteOk("POST", "/v1/upload/finalize", new { address = "", chunks_stored = 4, data_map = "dm" });
        Assert.Null((await _client.FinalizeUploadAsync("up", tx)).Sha256);
        Assert.Null((await _client.FinalizeMerkleUploadAsync("up", "pool")).Sha256);

        _server.RouteOk("POST", "/v1/upload/finalize", new { address = "", chunks_stored = 4, data_map = "dm", sha256 = "" });
        Assert.Null((await _client.FinalizeUploadAsync("up", tx)).Sha256);
        Assert.Null((await _client.FinalizeMerkleUploadAsync("up", "pool")).Sha256);
    }

    // ── Manifest entries ──

    [Fact]
    public async Task BuildManifest_SendsSha256WhenSet_OmitsItOtherwise_PassesItThroughUnchanged()
    {
        _server.RouteOk("POST", "/v1/manifests/build", new { manifest = ManifestFixtures.HeaderBase64, entries = Array.Empty<object>() });
        _server.Start();

        await _client.BuildManifestAsync(new[]
        {
            ManifestEntryInput.Public(ShaFixtures.Address, "a.txt") with { Sha256 = ShaFixtures.Hash },
            ManifestEntryInput.Public(ShaFixtures.Address, "b.txt"),
            ManifestEntryInput.Public(ShaFixtures.Address, "c.txt") with { Sha256 = "" },
            // No client-side validation or lowercasing: the daemon decides.
            ManifestEntryInput.Public(ShaFixtures.Address, "d.txt") with { Sha256 = "ZZ" },
        });

        var entries = LastBody("/v1/manifests/build").GetProperty("entries").EnumerateArray().ToList();
        Assert.Equal(ShaFixtures.Hash, entries[0].GetProperty("sha256").GetString());
        Assert.False(Has(entries[1], "sha256"), $"an unset sha256 must be left out: {entries[1]}");
        Assert.False(Has(entries[2], "sha256"), $"an empty sha256 must be left out: {entries[2]}");
        Assert.Equal("ZZ", entries[3].GetProperty("sha256").GetString());
        Assert.Equal(JsonValueKind.String, entries[0].GetProperty("sha256").ValueKind);
    }

    [Fact]
    public async Task BuildAndDecode_ReadEntrySha256_NullWhenAbsentOrEmpty()
    {
        var body = $$"""
            {"manifest": "{{ManifestFixtures.HeaderBase64}}", "source": "manifest",
             "entries": [
               {"effective_name": "a.txt", "path": "a.txt", "kind": "public", "content_address": "aa", "sha256": "{{ShaFixtures.Hash}}"},
               {"effective_name": "b.txt", "path": "b.txt", "kind": "public", "content_address": "bb"},
               {"effective_name": "c.txt", "path": "c.txt", "kind": "public", "content_address": "cc", "sha256": ""}
             ]}
            """;
        _server.Route("POST", "/v1/manifests/build", 200, body);
        _server.Route("POST", "/v1/manifests/decode", 200, body);
        _server.Start();

        var built = await _client.BuildManifestAsync(new[] { ManifestEntryInput.Public("aa") });
        var decoded = await _client.DecodeManifestLinkAsync(ShaFixtures.Link);
        foreach (var entries in new[] { built.Entries, decoded.Entries })
        {
            Assert.Equal(ShaFixtures.Hash, entries[0].Sha256);
            Assert.Null(entries[1].Sha256);
            Assert.Null(entries[2].Sha256);
        }
    }

    [Fact]
    public async Task BuildManifest_BadSha256_IsBadRequest_AndKeepsTheDaemonMessage()
    {
        _server.Route("POST", "/v1/manifests/build", 400, JsonSerializer.Serialize(new
        {
            error = "Bad request: 1 invalid entries: entries[0]: invalid hex sha256: Invalid character 'z' at position 0",
            code = "BAD_REQUEST",
        }));
        _server.Start();

        var ex = await Assert.ThrowsAsync<BadRequestException>(() => _client.BuildManifestAsync(
            new[] { ManifestEntryInput.Public(ShaFixtures.Address, "a.txt") with { Sha256 = "zz" } }));
        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("entries[0]: invalid hex sha256", ex.Message);
    }
}

/// <summary>sha256 over gRPC, against mocked service stubs.</summary>
public sealed class Sha256GrpcTests
{
    private static AsyncUnaryCall<T> Reply<T>(T value) =>
        TestCalls.AsyncUnaryCall(
            Task.FromResult(value),
            Task.FromResult(new Metadata()),
            () => Status.DefaultSuccess,
            () => new Metadata(),
            () => { });

    private static AsyncUnaryCall<T> Fail<T>(StatusCode code, string detail)
    {
        var status = new Status(code, detail);
        return TestCalls.AsyncUnaryCall(
            Task.FromException<T>(new RpcException(status)),
            Task.FromResult(new Metadata()),
            () => status,
            () => new Metadata(),
            () => { });
    }

    private sealed class MockData : Pb.DataService.DataServiceClient
    {
        public string Sha = "";
        public override AsyncUnaryCall<Pb.PutDataResponse> PutAsync(
            Pb.PutDataRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default) =>
            Reply(new Pb.PutDataResponse { DataMap = "dm", ChunksStored = 3, PaymentModeUsed = "auto", Sha256 = Sha });
        public override AsyncUnaryCall<Pb.PutPublicDataResponse> PutPublicAsync(
            Pb.PutPublicDataRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default) =>
            Reply(new Pb.PutPublicDataResponse { Address = "ad", ChunksStored = 2, PaymentModeUsed = "auto", Sha256 = Sha });
    }

    private sealed class MockFiles : Pb.FileService.FileServiceClient
    {
        public string Sha = "";
        public override AsyncUnaryCall<Pb.PutFileResponse> PutAsync(
            Pb.PutFileRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default) =>
            Reply(new Pb.PutFileResponse { DataMap = "dm", StorageCostAtto = "1", GasCostWei = "2", ChunksStored = 3, PaymentModeUsed = "auto", Sha256 = Sha });
        public override AsyncUnaryCall<Pb.PutFilePublicResponse> PutPublicAsync(
            Pb.PutFileRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default) =>
            Reply(new Pb.PutFilePublicResponse { Address = "ad", StorageCostAtto = "1", GasCostWei = "2", ChunksStored = 3, PaymentModeUsed = "auto", Sha256 = Sha });
    }

    private sealed class MockUpload : Pb.UploadService.UploadServiceClient
    {
        public string Sha = "";
        public override AsyncUnaryCall<Pb.FinalizeUploadResponse> FinalizeUploadAsync(
            Pb.FinalizeUploadRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default) =>
            Reply(new Pb.FinalizeUploadResponse { Address = "ad", DataMap = "dm", ChunksStored = 4, Sha256 = Sha });
    }

    private sealed class MockManifest : Pb.ManifestService.ManifestServiceClient
    {
        public Pb.BuildManifestRequest? LastBuild;
        public Pb.BuildManifestResponse BuildReply = new() { Manifest = ByteString.CopyFrom(ManifestFixtures.Header) };
        public Pb.DecodeManifestResponse DecodeReply = new() { Source = "manifest" };
        public Status? Failure;

        public override AsyncUnaryCall<Pb.BuildManifestResponse> BuildAsync(
            Pb.BuildManifestRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            LastBuild = request;
            return Failure is { } f ? Fail<Pb.BuildManifestResponse>(f.StatusCode, f.Detail) : Reply(BuildReply);
        }

        public override AsyncUnaryCall<Pb.DecodeManifestResponse> DecodeAsync(
            Pb.DecodeManifestRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default) =>
            Reply(DecodeReply);
    }

    private static AntdGrpcClient Client(
        Pb.DataService.DataServiceClient? data = null,
        Pb.FileService.FileServiceClient? files = null,
        Pb.UploadService.UploadServiceClient? upload = null) =>
        new(health: null!, data: data!, chunks: null!, files: files!, upload: upload!, wallet: null!);

    [Theory]
    [InlineData(ShaFixtures.Hash, ShaFixtures.Hash)]
    [InlineData("", null)]
    public async Task DataPut_AndPublic_MapSha256_EmptyIsNull(string wire, string? expected)
    {
        var client = Client(data: new MockData { Sha = wire });
        Assert.Equal(expected, (await client.DataPutAsync(new byte[] { 1 })).Sha256);
        Assert.Equal(expected, (await client.DataPutPublicAsync(new byte[] { 1 })).Sha256);
    }

    [Theory]
    [InlineData(ShaFixtures.Hash, ShaFixtures.Hash)]
    [InlineData("", null)]
    public async Task FilePut_AndPublic_MapSha256_EmptyIsNull(string wire, string? expected)
    {
        var client = Client(files: new MockFiles { Sha = wire });
        Assert.Equal(expected, (await client.FilePutAsync("/tmp/f")).Sha256);
        Assert.Equal(expected, (await client.FilePutPublicAsync("/tmp/f")).Sha256);
    }

    [Theory]
    [InlineData(ShaFixtures.Hash, ShaFixtures.Hash)]
    [InlineData("", null)]
    public async Task Finalize_AndFinalizeMerkle_MapSha256_EmptyIsNull(string wire, string? expected)
    {
        var client = Client(upload: new MockUpload { Sha = wire });
        Assert.Equal(expected, (await client.FinalizeUploadAsync("up", new() { ["q"] = "t" })).Sha256);
        Assert.Equal(expected, (await client.FinalizeMerkleUploadAsync("up", "pool")).Sha256);
    }

    [Fact]
    public async Task Build_SetsSha256PresenceOnlyWhenGiven_AndPassesItThroughUnchanged()
    {
        var mock = new MockManifest();
        await new AntdGrpcClient(mock).BuildManifestAsync(new[]
        {
            ManifestEntryInput.Public(ShaFixtures.Address, "a.txt") with { Sha256 = ShaFixtures.Hash },
            ManifestEntryInput.Public(ShaFixtures.Address, "b.txt"),
            ManifestEntryInput.Public(ShaFixtures.Address, "c.txt") with { Sha256 = "" },
            ManifestEntryInput.Public(ShaFixtures.Address, "d.txt") with { Sha256 = "ZZ" },
        });

        var e = mock.LastBuild!.Entries;
        Assert.True(e[0].HasSha256);
        Assert.Equal(ShaFixtures.Hash, e[0].Sha256);
        Assert.False(e[1].HasSha256, "an unset sha256 must stay unset");
        Assert.False(e[2].HasSha256, "an empty sha256 must stay unset");
        Assert.True(e[3].HasSha256);
        Assert.Equal("ZZ", e[3].Sha256);
    }

    [Fact]
    public async Task BuildAndDecode_ReadEntrySha256_EmptyIsNull()
    {
        var mock = new MockManifest();
        foreach (var entries in new[] { mock.BuildReply.Entries, mock.DecodeReply.Entries })
        {
            entries.Add(new Pb.ManifestEntryInfo { EffectiveName = "a", Kind = "public", ContentAddress = "aa", Sha256 = ShaFixtures.Hash });
            entries.Add(new Pb.ManifestEntryInfo { EffectiveName = "b", Kind = "public", ContentAddress = "bb" });
            entries.Add(new Pb.ManifestEntryInfo { EffectiveName = "c", Kind = "public", ContentAddress = "cc", Sha256 = "" });
        }
        var client = new AntdGrpcClient(mock);

        var built = await client.BuildManifestAsync(new[] { ManifestEntryInput.Public("aa") });
        var decoded = await client.DecodeManifestLinkAsync(ShaFixtures.Link);
        foreach (var entries in new[] { built.Entries, decoded.Entries })
        {
            Assert.Equal(ShaFixtures.Hash, entries[0].Sha256);
            Assert.Null(entries[1].Sha256);
            Assert.Null(entries[2].Sha256);
        }
    }

    [Fact]
    public async Task Build_InvalidArgumentForBadSha256_IsBadRequest()
    {
        var mock = new MockManifest
        {
            Failure = new Status(StatusCode.InvalidArgument, "Bad request: 1 invalid entries: entries[0]: sha256 must be 32 bytes, got 1"),
        };

        var ex = await Assert.ThrowsAsync<BadRequestException>(() => new AntdGrpcClient(mock).BuildManifestAsync(
            new[] { ManifestEntryInput.Public(ShaFixtures.Address, "a.txt") with { Sha256 = "aa" } }));
        Assert.Contains("entries[0]: sha256 must be 32 bytes, got 1", ex.Message);
    }
}

/// <summary>Existing construction and pattern use keep compiling with the new trailing field.</summary>
public sealed class Sha256CompatTests
{
    [Fact]
    public void ExistingPositionalConstructionStillWorks_AndSha256DefaultsToNull()
    {
        Assert.Null(new DataPutResult("dm").Sha256);
        Assert.Null(new DataPutResult("dm", 1, "auto").Sha256);
        Assert.Null(new DataPutPublicResult("ad", 1, "auto").Sha256);
        Assert.Null(new FilePutResult("dm", "1", "2", 3, "auto").Sha256);
        Assert.Null(new FilePutPublicResult("ad", "1", "2", 3, "auto").Sha256);
        Assert.Null(new FinalizeUploadResult("ad", 1, "dm", "dma").Sha256);
        Assert.Null(new FinalizeMerkleUploadResult("ad", 1, "dm", "dma").Sha256);
        Assert.Null(new ManifestEntryInput("p", 1UL, "dm", null).Sha256);
        Assert.Null(new ManifestEntryInput(Path: "p", Address: "aa").Sha256);
        var info = new ManifestEntryInfo("a", "a", 1UL, "public", "aa", null, null, null);
        Assert.Null(info.Sha256);
        Assert.Equal(info, info with { Sha256 = null });
        Assert.NotEqual(info, info with { Sha256 = ShaFixtures.Hash });
    }
}
