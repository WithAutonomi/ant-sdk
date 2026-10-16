using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Antd.Sdk;
using Google.Protobuf;
using Grpc.Core;
using Grpc.Core.Testing;
using Grpc.Net.Client;
using Xunit;
using Pb = Antd.V1;

namespace Antd.Sdk.Tests;

/// <summary>Shared canned values for the manifest tests.</summary>
internal static class ManifestFixtures
{
    /// <summary>The five-byte <c>.ant</c> header; <see cref="HeaderBase64"/> is its base64.</summary>
    public static readonly byte[] Header = { 0xC1, (byte)'A', (byte)'N', (byte)'T', 0x01 };
    public const string HeaderBase64 = "wUFOVAE=";
    public const string Link = "ant://manifest/wUFOVAE";
    public const string Address = "42424242424242424242424242424242424242424242424242424242424242aa";

    /// <summary>Every byte value, so a base64 slip (URL-safe alphabet, padding) shows.</summary>
    public static byte[] AllBytes() => Enumerable.Range(0, 256).Select(i => (byte)i).ToArray();

    public static string BadEntryBody(string detail) => JsonSerializer.Serialize(new
    {
        error = $"Bad request: 1 invalid entries: entries[0]: {detail}",
        code = "BAD_REQUEST",
    });
}

/// <summary>REST manifest methods against a mock daemon.</summary>
public sealed class ManifestRestTests : IDisposable
{
    private readonly MockServer _server = new();
    private readonly AntdRestClient _client;

    public ManifestRestTests() =>
        _client = new AntdRestClient(_server.BaseUrl, timeout: TimeSpan.FromSeconds(5));

    public void Dispose()
    {
        _client.Dispose();
        _server.Dispose();
    }

    private JsonElement LastBody(string path) =>
        JsonDocument.Parse(_server.LastRequestBodies[$"POST {path}"]).RootElement;

    private static bool Has(JsonElement e, string name) => e.TryGetProperty(name, out _);

    [Fact]
    public async Task BuildManifest_SendsEntriesAndOptions_ReturnsRawBytes()
    {
        _server.Route("POST", "/v1/manifests/build", 200, $$"""
            {
              "manifest": "{{ManifestFixtures.HeaderBase64}}",
              "link": "{{ManifestFixtures.Link}}",
              "entries": [
                {"effective_name": "a.txt", "path": "a.txt", "size": 10, "kind": "embedded",
                 "content_address": "cc", "exact_size": 10},
                {"effective_name": "11", "kind": "public", "content_address": "11"}
              ]
            }
            """);
        _server.Start();

        var built = await _client.BuildManifestAsync(
            new[] { ManifestEntryInput.Embedded("abcd", "a.txt", 10), ManifestEntryInput.Public("11") },
            new BuildManifestOptions("album", new[] { "aa", "bb" }, EmbedRoots: false));

        var body = LastBody("/v1/manifests/build");
        Assert.Equal("album", body.GetProperty("name").GetString());
        Assert.False(body.GetProperty("embed_roots").GetBoolean());
        Assert.Equal(new[] { "aa", "bb" }, body.GetProperty("torrent_info_hashes").EnumerateArray().Select(h => h.GetString()));
        var entries = body.GetProperty("entries").EnumerateArray().ToList();
        Assert.Equal(2, entries.Count);
        Assert.Equal("a.txt", entries[0].GetProperty("path").GetString());
        Assert.Equal(10UL, entries[0].GetProperty("size").GetUInt64());
        Assert.Equal("abcd", entries[0].GetProperty("data_map").GetString());
        Assert.False(Has(entries[0], "address"), "an embedded entry must not send an address");
        Assert.Equal("11", entries[1].GetProperty("address").GetString());
        Assert.False(Has(entries[1], "path") || Has(entries[1], "size") || Has(entries[1], "data_map"),
            $"unset fields must be left out: {entries[1]}");

        Assert.Equal(ManifestFixtures.Header, built.Manifest);
        Assert.Equal(ManifestFixtures.Link, built.Link);
        Assert.Equal(2, built.Entries.Count);
        Assert.Equal(new ManifestEntryInfo("a.txt", "a.txt", 10UL, "embedded", "cc", null, 10UL, null), built.Entries[0]);
        Assert.Equal(new ManifestEntryInfo("11", null, null, "public", "11", null, null, null), built.Entries[1]);
    }

    [Fact]
    public async Task BuildManifest_NullOptions_EmbedsRootsAndLeavesTheRestOut()
    {
        _server.RouteOk("POST", "/v1/manifests/build", new { manifest = "", entries = Array.Empty<object>() });
        _server.Start();

        var built = await _client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11") });

        var body = LastBody("/v1/manifests/build");
        Assert.True(body.GetProperty("embed_roots").GetBoolean());
        Assert.False(Has(body, "name"), "an unset name must be left out");
        Assert.False(Has(body, "torrent_info_hashes"), "no torrent hashes must be left out");
        Assert.Empty(built.Manifest);
        Assert.Null(built.Link);
        Assert.Empty(built.Entries);
    }

    [Fact]
    public async Task BuildManifest_EmptyStringsReadAsUnset()
    {
        _server.RouteOk("POST", "/v1/manifests/build", new { manifest = "", entries = Array.Empty<object>() });
        _server.Start();

        await _client.BuildManifestAsync(
            new[] { new ManifestEntryInput(Path: "", DataMap: "", Address: "11") },
            new BuildManifestOptions(Name: "", TorrentInfoHashes: Array.Empty<string>()));

        var body = LastBody("/v1/manifests/build");
        Assert.False(Has(body, "name") || Has(body, "torrent_info_hashes"), body.ToString());
        var entry = body.GetProperty("entries")[0];
        Assert.False(Has(entry, "path") || Has(entry, "data_map"), entry.ToString());
        Assert.Equal("11", entry.GetProperty("address").GetString());
    }

    [Fact]
    public void BuildManifestOptions_DefaultToEmbeddingRoots()
    {
        Assert.True(new BuildManifestOptions().EmbedRoots);
        Assert.True(new BuildManifestOptions(Name: "album").EmbedRoots);
        Assert.False((new BuildManifestOptions() with { EmbedRoots = false }).EmbedRoots);
    }

    [Fact]
    public async Task BuildManifest_SizeZeroIsSent_UnsetSizeIsNot()
    {
        _server.Route("POST", "/v1/manifests/build", 200, """
            {"manifest": "", "entries": [
              {"effective_name": "empty", "path": "empty", "size": 0, "kind": "public", "content_address": "11", "exact_size": 0},
              {"effective_name": "none", "path": "none", "kind": "public", "content_address": "22"}
            ]}
            """);
        _server.Start();

        var built = await _client.BuildManifestAsync(new[]
        {
            ManifestEntryInput.Public("11", "empty", size: 0),
            ManifestEntryInput.Public("22", "none"),
        });

        var entries = LastBody("/v1/manifests/build").GetProperty("entries");
        Assert.Equal(0UL, entries[0].GetProperty("size").GetUInt64());
        Assert.False(Has(entries[1], "size"));
        // 0 is a size; absent is none.
        Assert.Equal((0UL, 0UL), (built.Entries[0].Size!.Value, built.Entries[0].ExactSize!.Value));
        Assert.Null(built.Entries[1].Size);
        Assert.Null(built.Entries[1].ExactSize);
    }

    [Fact]
    public async Task BuildManifest_SizesAreReadExactly()
    {
        // 2^53 + 1 is the first integer a float64 JSON reader rounds.
        _server.Route("POST", "/v1/manifests/build", 200, """
            {"manifest": "", "entries": [
              {"effective_name": "big", "path": "big", "size": 9007199254740993, "kind": "public",
               "content_address": "11", "exact_size": 18446744073709551615}
            ]}
            """);
        _server.Start();

        var built = await _client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11", "big", 9007199254740993UL) });

        Assert.Equal(9007199254740993UL, LastBody("/v1/manifests/build").GetProperty("entries")[0].GetProperty("size").GetUInt64());
        Assert.Equal(9007199254740993UL, built.Entries[0].Size);
        Assert.Equal(ulong.MaxValue, built.Entries[0].ExactSize);
    }

    [Theory]
    [InlineData(0, "1 invalid entries: entries[0]: needs a data_map or an address")]
    [InlineData(1, "1 invalid entries: entries[1]: give data_map or address, not both")]
    [InlineData(2, "1 invalid entries: entries[0]: needs a data_map or an address")]
    [InlineData(3, "1 invalid entries: entries[1]: needs a data_map or an address")]
    public async Task BuildManifest_BothOrNeither_IsTheDaemonsBadRequest_BeforeSending(int which, string message)
    {
        _server.Start();
        IReadOnlyList<ManifestEntryInput> bad = which switch
        {
            0 => new[] { new ManifestEntryInput(Path: "x") },
            1 => new[] { ManifestEntryInput.Public("11"), new ManifestEntryInput(DataMap: "aa", Address: "bb") },
            2 => new[] { new ManifestEntryInput(DataMap: "", Address: "") },
            _ => new[] { ManifestEntryInput.Public("11"), null! },
        };

        var ex = await Assert.ThrowsAsync<BadRequestException>(() => _client.BuildManifestAsync(bad));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(message, ex.Message);
        Assert.Empty(_server.LastRequestBodies);
    }

    [Fact]
    public async Task BuildManifest_SeveralBadEntries_AreReportedTogether()
    {
        _server.Start();
        var ex = await Assert.ThrowsAsync<BadRequestException>(() => _client.BuildManifestAsync(new[]
        {
            new ManifestEntryInput(DataMap: "aa", Address: "bb"),
            ManifestEntryInput.Public("11"),
            new ManifestEntryInput(Path: "x"),
        }));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(
            "2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address",
            ex.Message);
        Assert.Empty(_server.LastRequestBodies);
    }

    [Fact]
    public void CheckEntries_ShowsAtMostTwenty_ThenCountsTheRest()
    {
        var entries = Enumerable.Range(0, 23).Select(_ => new ManifestEntryInput()).ToList();

        var ex = Assert.Throws<BadRequestException>(() => ManifestWire.CheckEntries(entries));

        var shown = string.Join("; ", Enumerable.Range(0, 20).Select(i => $"entries[{i}]: needs a data_map or an address"));
        Assert.Equal($"23 invalid entries: {shown}; and 3 more", ex.Message);
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task BuildManifest_NullEntries_IsABadRequest()
    {
        var ex = await Assert.ThrowsAsync<BadRequestException>(() => _client.BuildManifestAsync(null!));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task BuildManifest_BadRequest_IsTyped_AndKeepsTheMessage()
    {
        _server.Route("POST", "/v1/manifests/build", 400,
            ManifestFixtures.BadEntryBody("invalid path \"../x\": path component \"..\" is not allowed"));
        _server.Start();

        var ex = await Assert.ThrowsAsync<BadRequestException>(
            () => _client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11", "../x") }));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("entries[0]: invalid path", ex.Message);
    }

    [Fact]
    public async Task BuildManifest_ResponseNotBase64_Throws()
    {
        _server.RouteOk("POST", "/v1/manifests/build", new { manifest = "not base64!", entries = Array.Empty<object>() });
        _server.Start();

        var ex = await Assert.ThrowsAsync<AntdException>(
            () => _client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11") }));
        Assert.Contains("base64", ex.Message);
    }

    [Fact]
    public async Task DecodeManifest_SendsBase64_ReadsEntries()
    {
        _server.Route("POST", "/v1/manifests/decode", 200, """
            {
              "source": "manifest", "name": "album", "torrent_info_hash_v2": "bb",
              "entries": [
                {"effective_name": "a.txt", "path": "a.txt", "kind": "embedded",
                 "content_address": "cc", "data_map": "abcd", "exact_size": 3},
                {"effective_name": "b", "path": "b", "kind": "public", "content_address": "dd",
                 "error": "Record not found: gone"}
              ]
            }
            """);
        _server.Start();

        var decoded = await _client.DecodeManifestAsync(ManifestFixtures.Header, resolve: true);

        var body = LastBody("/v1/manifests/decode");
        Assert.Equal(ManifestFixtures.HeaderBase64, body.GetProperty("manifest").GetString());
        Assert.True(body.GetProperty("resolve").GetBoolean());
        Assert.False(Has(body, "link"));

        Assert.Equal(("manifest", "album", (string?)null, "bb"),
            (decoded.Source, decoded.Name, decoded.TorrentInfoHashV1, decoded.TorrentInfoHashV2));
        Assert.Equal(new ManifestEntryInfo("a.txt", "a.txt", null, "embedded", "cc", "abcd", 3UL, null), decoded.Entries[0]);
        // A failed resolve is the entry's error, not a failed call.
        Assert.Equal("Record not found: gone", decoded.Entries[1].Error);
        Assert.Null(decoded.Entries[1].ExactSize);
        Assert.Null(decoded.Entries[1].DataMap);
    }

    [Fact]
    public async Task Manifest_Base64RoundTrip_EveryByteValue()
    {
        var bytes = ManifestFixtures.AllBytes();
        _server.RouteOk("POST", "/v1/manifests/build", new { manifest = Convert.ToBase64String(bytes), entries = Array.Empty<object>() });
        _server.RouteOk("POST", "/v1/manifests/decode", new { source = "manifest", entries = Array.Empty<object>() });
        _server.Start();

        var built = await _client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11") });
        Assert.Equal(bytes, built.Manifest);

        await _client.DecodeManifestAsync(built.Manifest);
        var sent = LastBody("/v1/manifests/decode").GetProperty("manifest").GetString()!;
        // Standard alphabet with padding, as the daemon decodes it.
        Assert.Equal(Convert.ToBase64String(bytes), sent);
        Assert.Equal(bytes, Convert.FromBase64String(sent));
        Assert.False(LastBody("/v1/manifests/decode").GetProperty("resolve").GetBoolean());
    }

    [Fact]
    public async Task DecodeManifestLink_SendsTheLink()
    {
        _server.Route("POST", "/v1/manifests/decode", 200, $$"""
            {"source": "file_link", "entries": [
              {"effective_name": "{{ManifestFixtures.Address}}", "kind": "public", "content_address": "{{ManifestFixtures.Address}}", "exact_size": 46}
            ]}
            """);
        _server.Start();

        var decoded = await _client.DecodeManifestLinkAsync(ManifestFixtures.Address);

        var body = LastBody("/v1/manifests/decode");
        Assert.Equal(ManifestFixtures.Address, body.GetProperty("link").GetString());
        Assert.False(body.GetProperty("resolve").GetBoolean());
        Assert.False(Has(body, "manifest"), "a link request must not send manifest bytes");
        Assert.Equal("file_link", decoded.Source);
        Assert.Null(decoded.Name);
        var entry = Assert.Single(decoded.Entries);
        Assert.Equal((ManifestFixtures.Address, (string?)null, (ulong?)null, 46UL), (entry.ContentAddress, entry.Path, entry.Size, entry.ExactSize!.Value));
    }

    [Fact]
    public async Task DecodeManifest_BadRequest_IsTyped()
    {
        _server.Route("POST", "/v1/manifests/decode", 400,
            """{"error": "Bad request: not a manifest: missing or invalid header", "code": "BAD_REQUEST"}""");
        _server.Start();

        var ex = await Assert.ThrowsAsync<BadRequestException>(() => _client.DecodeManifestAsync(new byte[] { 1, 2, 3 }));
        Assert.Contains("not a manifest", ex.Message);
    }

    [Fact]
    public async Task Decode_EmptyInput_IsRefusedBeforeSending()
    {
        _server.Start();

        var calls = new Func<Task>[]
        {
            () => _client.DecodeManifestAsync(Array.Empty<byte>()),
            () => _client.DecodeManifestAsync(null!),
            () => _client.DecodeManifestLinkAsync(""),
            () => _client.DecodeManifestLinkAsync(null!),
        };
        foreach (var call in calls)
        {
            var ex = await Assert.ThrowsAsync<BadRequestException>(call);
            Assert.Equal(400, ex.StatusCode);
            Assert.Equal("needs a manifest (base64 .ant bytes) or a link", ex.Message);
        }
        Assert.Empty(_server.LastRequestBodies);
    }
}

/// <summary>gRPC manifest methods against a mocked ManifestService stub.</summary>
public sealed class ManifestGrpcTests
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

    private sealed class MockManifestService : Pb.ManifestService.ManifestServiceClient
    {
        public Pb.BuildManifestRequest? LastBuild;
        public Pb.DecodeManifestRequest? LastDecode;
        public int Calls;
        public Pb.BuildManifestResponse BuildReply = new() { Manifest = ByteString.CopyFrom(ManifestFixtures.Header) };
        public Pb.DecodeManifestResponse DecodeReply = new() { Source = "manifest" };
        public Status? Failure;

        public override AsyncUnaryCall<Pb.BuildManifestResponse> BuildAsync(
            Pb.BuildManifestRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            Calls++;
            LastBuild = request;
            return Failure is { } f ? Fail<Pb.BuildManifestResponse>(f.StatusCode, f.Detail) : Reply(BuildReply);
        }

        public override AsyncUnaryCall<Pb.DecodeManifestResponse> DecodeAsync(
            Pb.DecodeManifestRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
        {
            Calls++;
            LastDecode = request;
            return Failure is { } f ? Fail<Pb.DecodeManifestResponse>(f.StatusCode, f.Detail) : Reply(DecodeReply);
        }
    }

    [Fact]
    public async Task Build_SetsPresenceAndTheSource_ReturnsRawBytes()
    {
        var mock = new MockManifestService();
        mock.BuildReply.Link = ManifestFixtures.Link;
        mock.BuildReply.Entries.Add(new Pb.ManifestEntryInfo
        {
            EffectiveName = "a.txt",
            Path = "a.txt",
            Size = 10,
            Kind = "embedded",
            ContentAddress = "cc",
            ExactSize = 10,
        });
        mock.BuildReply.Entries.Add(new Pb.ManifestEntryInfo { EffectiveName = "11", Kind = "public", ContentAddress = "11" });

        var built = await new AntdGrpcClient(mock).BuildManifestAsync(
            new[] { ManifestEntryInput.Embedded("abcd", "a.txt", 10), ManifestEntryInput.Public("11") },
            new BuildManifestOptions("album", new[] { "aa" }));

        var req = mock.LastBuild!;
        Assert.True(req.HasName);
        Assert.Equal("album", req.Name);
        Assert.Equal(new[] { "aa" }, req.TorrentInfoHashes);
        Assert.True(req.HasEmbedRoots && req.EmbedRoots, "embed_roots must be sent, and true by default");
        var (first, second) = (req.Entries[0], req.Entries[1]);
        Assert.Equal(Pb.ManifestEntryInput.SourceOneofCase.DataMap, first.SourceCase);
        Assert.Equal(("a.txt", true, 10UL, "abcd"), (first.Path, first.HasSize, first.Size, first.DataMap));
        Assert.Equal(Pb.ManifestEntryInput.SourceOneofCase.Address, second.SourceCase);
        Assert.Equal("11", second.Address);
        Assert.False(second.HasPath || second.HasSize, "unset path and size must stay unset");

        Assert.Equal(ManifestFixtures.Header, built.Manifest);
        Assert.Equal(ManifestFixtures.Link, built.Link);
        Assert.Equal(new ManifestEntryInfo("a.txt", "a.txt", 10UL, "embedded", "cc", null, 10UL, null), built.Entries[0]);
        Assert.Equal(new ManifestEntryInfo("11", null, null, "public", "11", null, null, null), built.Entries[1]);
    }

    [Fact]
    public async Task Build_NullOptions_SendsEmbedRootsTrue_AndNoName()
    {
        var mock = new MockManifestService();
        var built = await new AntdGrpcClient(mock).BuildManifestAsync(new[] { ManifestEntryInput.Public("11") });

        Assert.True(mock.LastBuild!.HasEmbedRoots);
        Assert.True(mock.LastBuild.EmbedRoots);
        Assert.False(mock.LastBuild.HasName);
        Assert.Empty(mock.LastBuild.TorrentInfoHashes);
        Assert.Null(built.Link);
    }

    [Fact]
    public async Task Build_KeepShrunkDataMaps_SendsEmbedRootsFalse()
    {
        var mock = new MockManifestService();
        await new AntdGrpcClient(mock).BuildManifestAsync(
            new[] { ManifestEntryInput.Public("11") }, new BuildManifestOptions(EmbedRoots: false));

        Assert.True(mock.LastBuild!.HasEmbedRoots);
        Assert.False(mock.LastBuild.EmbedRoots);
    }

    [Fact]
    public async Task Build_SizeZeroIsPresent_UnsetIsAbsent()
    {
        var mock = new MockManifestService();
        mock.BuildReply.Entries.Add(new Pb.ManifestEntryInfo { EffectiveName = "z", Kind = "public", ContentAddress = "11", Size = 0, ExactSize = 0 });
        mock.BuildReply.Entries.Add(new Pb.ManifestEntryInfo { EffectiveName = "n", Kind = "public", ContentAddress = "22" });

        var built = await new AntdGrpcClient(mock).BuildManifestAsync(new[]
        {
            ManifestEntryInput.Public("11", "z", size: 0),
            ManifestEntryInput.Public("22", "n"),
        });

        Assert.True(mock.LastBuild!.Entries[0].HasSize);
        Assert.Equal(0UL, mock.LastBuild.Entries[0].Size);
        Assert.False(mock.LastBuild.Entries[1].HasSize);
        Assert.Equal((0UL, 0UL), (built.Entries[0].Size!.Value, built.Entries[0].ExactSize!.Value));
        Assert.Null(built.Entries[1].Size);
        Assert.Null(built.Entries[1].ExactSize);
    }

    [Fact]
    public async Task Build_BothOrNeither_IsRefusedBeforeSending()
    {
        var mock = new MockManifestService();
        var client = new AntdGrpcClient(mock);

        var neither = await Assert.ThrowsAsync<BadRequestException>(
            () => client.BuildManifestAsync(new[] { new ManifestEntryInput(Path: "x") }));
        Assert.Equal((400, "1 invalid entries: entries[0]: needs a data_map or an address"), (neither.StatusCode, neither.Message));
        var both = await Assert.ThrowsAsync<BadRequestException>(
            () => client.BuildManifestAsync(new[] { new ManifestEntryInput(DataMap: "aa", Address: "bb") }));
        Assert.Equal((400, "1 invalid entries: entries[0]: give data_map or address, not both"), (both.StatusCode, both.Message));
        Assert.Equal(0, mock.Calls);
    }

    [Fact]
    public async Task Build_InvalidArgument_IsBadRequest_AndKeepsTheDetail()
    {
        var mock = new MockManifestService
        {
            Failure = new Status(StatusCode.InvalidArgument, "Bad request: 1 invalid entries: entries[0]: invalid path \"../x\""),
        };

        var ex = await Assert.ThrowsAsync<BadRequestException>(
            () => new AntdGrpcClient(mock).BuildManifestAsync(new[] { ManifestEntryInput.Public("11", "../x") }));
        Assert.Equal("Bad request: 1 invalid entries: entries[0]: invalid path \"../x\"", ex.Message);
    }

    [Fact]
    public async Task Decode_SendsRawBytes_ReadsPresence()
    {
        var bytes = ManifestFixtures.AllBytes();
        var mock = new MockManifestService
        {
            DecodeReply = new Pb.DecodeManifestResponse { Source = "manifest", Name = "album", TorrentInfoHashV2 = "bb" },
        };
        mock.DecodeReply.Entries.Add(new Pb.ManifestEntryInfo
        {
            EffectiveName = "a.txt",
            Path = "a.txt",
            Kind = "embedded",
            ContentAddress = "cc",
            DataMap = "abcd",
            ExactSize = 3,
        });
        mock.DecodeReply.Entries.Add(new Pb.ManifestEntryInfo
        {
            EffectiveName = "b",
            Path = "b",
            Kind = "public",
            ContentAddress = "dd",
            Error = "Record not found: gone",
        });

        var decoded = await new AntdGrpcClient(mock).DecodeManifestAsync(bytes, resolve: true);

        Assert.Equal(Pb.DecodeManifestRequest.InputOneofCase.Manifest, mock.LastDecode!.InputCase);
        Assert.Equal(bytes, mock.LastDecode.Manifest.ToByteArray());
        Assert.True(mock.LastDecode.Resolve);
        Assert.Equal(("manifest", "album", (string?)null, "bb"),
            (decoded.Source, decoded.Name, decoded.TorrentInfoHashV1, decoded.TorrentInfoHashV2));
        Assert.Equal(new ManifestEntryInfo("a.txt", "a.txt", null, "embedded", "cc", "abcd", 3UL, null), decoded.Entries[0]);
        Assert.Equal(new ManifestEntryInfo("b", "b", null, "public", "dd", null, null, "Record not found: gone"), decoded.Entries[1]);
    }

    [Fact]
    public async Task DecodeLink_SendsTheLink_UnsetNameIsNull()
    {
        var mock = new MockManifestService { DecodeReply = new Pb.DecodeManifestResponse { Source = "file_link" } };
        mock.DecodeReply.Entries.Add(new Pb.ManifestEntryInfo
        {
            EffectiveName = ManifestFixtures.Address,
            Kind = "public",
            ContentAddress = ManifestFixtures.Address,
        });

        var decoded = await new AntdGrpcClient(mock).DecodeManifestLinkAsync(ManifestFixtures.Address);

        Assert.Equal(Pb.DecodeManifestRequest.InputOneofCase.Link, mock.LastDecode!.InputCase);
        Assert.Equal(ManifestFixtures.Address, mock.LastDecode.Link);
        Assert.False(mock.LastDecode.Resolve);
        Assert.Equal("file_link", decoded.Source);
        Assert.Null(decoded.Name);
        var entry = Assert.Single(decoded.Entries);
        Assert.Null(entry.Path);
        Assert.Null(entry.ExactSize);
    }

    [Fact]
    public async Task Decode_InvalidArgument_IsBadRequest()
    {
        var mock = new MockManifestService
        {
            Failure = new Status(StatusCode.InvalidArgument, "Bad request: not a manifest: missing or invalid header"),
        };

        var ex = await Assert.ThrowsAsync<BadRequestException>(
            () => new AntdGrpcClient(mock).DecodeManifestAsync(new byte[] { 1, 2, 3 }));
        Assert.Contains("not a manifest", ex.Message);
    }

    [Fact]
    public async Task Decode_EmptyInput_IsRefusedBeforeSending()
    {
        var mock = new MockManifestService();
        var client = new AntdGrpcClient(mock);

        var bytes = await Assert.ThrowsAsync<BadRequestException>(() => client.DecodeManifestAsync(Array.Empty<byte>()));
        var link = await Assert.ThrowsAsync<BadRequestException>(() => client.DecodeManifestLinkAsync(""));
        foreach (var ex in new[] { bytes, link })
            Assert.Equal((400, "needs a manifest (base64 .ant bytes) or a link"), (ex.StatusCode, ex.Message));
        Assert.Equal(0, mock.Calls);
    }
}

/// <summary>
/// The manifest channel's message limits, exercised through Grpc.Net.Client
/// itself: a stub on a channel whose HTTP handler answers in-process with a
/// framed gRPC response, so the client's real size checks run.
/// </summary>
public sealed class ManifestGrpcLimitTests
{
    /// <summary>Past Grpc.Net.Client's default 4 MiB receive limit.</summary>
    private const int Big = 5 * 1024 * 1024;

    /// <summary>Answers every call with <c>reply</c>, and keeps the request message it was sent.</summary>
    private sealed class GrpcReplyHandler : HttpMessageHandler
    {
        private readonly IMessage _reply;

        public GrpcReplyHandler(IMessage reply) => _reply = reply;

        public byte[]? LastRequest { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            // gRPC framing: one compressed-flag byte, a big-endian length, the message.
            var sent = await request.Content!.ReadAsByteArrayAsync(cancellationToken);
            LastRequest = sent[5..];

            var payload = _reply.ToByteArray();
            var framed = new byte[5 + payload.Length];
            BinaryPrimitives.WriteUInt32BigEndian(framed.AsSpan(1), (uint)payload.Length);
            payload.CopyTo(framed, 5);
            var resp = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Version = HttpVersion.Version20,
                Content = new ByteArrayContent(framed),
            };
            resp.Content.Headers.ContentType = new MediaTypeHeaderValue("application/grpc");
            resp.TrailingHeaders.Add("grpc-status", "0");
            return resp;
        }
    }

    private static Pb.BuildManifestResponse BigBuildReply() =>
        new() { Manifest = ByteString.CopyFrom(new byte[Big]), Link = "" };

    [Fact]
    public void ManifestChannel_RaisesBothLimitsPastTheLargestManifest()
    {
        var options = AntdGrpcClient.ManifestChannelOptions();
        Assert.Equal(AntdGrpcClient.MaxManifestGrpcMessage, options.MaxReceiveMessageSize);
        Assert.Equal(AntdGrpcClient.MaxManifestGrpcMessage, options.MaxSendMessageSize);
        Assert.True(AntdGrpcClient.MaxManifestGrpcMessage > 64 * 1024 * 1024, "a manifest can be 64 MiB");
    }

    [Fact]
    public async Task ManifestChannel_ReceivesAResponsePastFourMiB()
    {
        var handler = new GrpcReplyHandler(BigBuildReply());
        using var channel = GrpcChannel.ForAddress("http://localhost", AntdGrpcClient.ManifestChannelOptions(handler));
        var client = new AntdGrpcClient(new Pb.ManifestService.ManifestServiceClient(channel));

        var built = await client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11") });

        Assert.Equal(Big, built.Manifest.Length);
        Assert.Null(built.Link);
    }

    [Fact]
    public async Task DefaultChannel_RefusesTheSameResponse()
    {
        // The control: without the raised limit the same reply fails, so the
        // test above is measuring the limit.
        var handler = new GrpcReplyHandler(BigBuildReply());
        using var channel = GrpcChannel.ForAddress("http://localhost", new GrpcChannelOptions { HttpHandler = handler });
        var stub = new Pb.ManifestService.ManifestServiceClient(channel);

        var ex = await Assert.ThrowsAsync<RpcException>(async () => await stub.BuildAsync(new Pb.BuildManifestRequest()));
        Assert.Equal(StatusCode.ResourceExhausted, ex.StatusCode);
    }

    [Fact]
    public async Task ManifestChannel_SendsADecodePastFourMiB_AsRawBytes()
    {
        var bytes = new byte[Big];
        new Random(7).NextBytes(bytes);
        var handler = new GrpcReplyHandler(new Pb.DecodeManifestResponse { Source = "manifest" });
        using var channel = GrpcChannel.ForAddress("http://localhost", AntdGrpcClient.ManifestChannelOptions(handler));

        var decoded = await new AntdGrpcClient(new Pb.ManifestService.ManifestServiceClient(channel)).DecodeManifestAsync(bytes);

        Assert.Equal("manifest", decoded.Source);
        var sent = Pb.DecodeManifestRequest.Parser.ParseFrom(handler.LastRequest);
        Assert.Equal(bytes, sent.Manifest.ToByteArray());
    }
}

/// <summary>
/// IAntdClient's manifest members have default implementations, so a class
/// written against the interface before manifests existed still compiles.
/// </summary>
public sealed class ManifestInterfaceCompatTests
{
    private sealed class PreManifestClient : IAntdClient
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

    private static readonly string[] ManifestMembers =
        { nameof(IAntdClient.BuildManifestAsync), nameof(IAntdClient.DecodeManifestAsync), nameof(IAntdClient.DecodeManifestLinkAsync) };

    [Fact]
    public async Task ManifestMembers_DefaultToNotSupported()
    {
        IAntdClient client = new PreManifestClient();
        await Assert.ThrowsAsync<NotSupportedException>(() => client.BuildManifestAsync(new[] { ManifestEntryInput.Public("11") }));
        await Assert.ThrowsAsync<NotSupportedException>(() => client.DecodeManifestAsync(ManifestFixtures.Header));
        await Assert.ThrowsAsync<NotSupportedException>(() => client.DecodeManifestLinkAsync(ManifestFixtures.Link));
    }

    [Fact]
    public void BothClients_ImplementTheManifestMembers()
    {
        // A public method with the interface member's signature replaces the
        // default implementation.
        foreach (var type in new[] { typeof(AntdRestClient), typeof(AntdGrpcClient) })
        {
            var map = type.GetInterfaceMap(typeof(IAntdClient));
            var manifest = map.InterfaceMethods.Zip(map.TargetMethods).Where(m => ManifestMembers.Contains(m.First.Name)).ToList();
            Assert.Equal(ManifestMembers.Length, manifest.Count);
            foreach (var (iface, impl) in manifest)
                Assert.True(impl.DeclaringType == type, $"{type.Name} does not implement {iface.Name}");
        }
    }
}
