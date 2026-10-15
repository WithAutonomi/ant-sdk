using Antd.Sdk;
using Xunit;
using Xunit.Abstractions;

namespace Antd.Sdk.Tests;

/// <summary>
/// Live manifest round trip against a running antd with a devnet behind it.
/// It builds and decodes manifests of data that is already uploaded, so it
/// pays for nothing and needs no wallet. Passes without doing anything unless
/// <c>ANTD_TEST_URL</c> and <c>ANTD_TEST_MANIFEST_ADDRESSES</c> are set:
/// <list type="bullet">
/// <item><description><c>ANTD_TEST_URL</c>: the daemon's REST base URL, e.g. <c>http://127.0.0.1:8082</c>.</description></item>
/// <item><description><c>ANTD_TEST_MANIFEST_ADDRESSES</c>, <c>ANTD_TEST_MANIFEST_SIZES</c>: two comma-separated
/// public data addresses and their exact plaintext sizes.</description></item>
/// <item><description><c>ANTD_TEST_MANIFEST_DATA_MAP</c>, <c>ANTD_TEST_MANIFEST_DATA_MAP_SIZE</c>: a private
/// upload's hex DataMap and its size.</description></item>
/// <item><description><c>ANTD_TEST_MANIFEST_LINK</c> (optional): an <c>ant://manifest/</c> link built from
/// those three entries.</description></item>
/// <item><description><c>ANTD_TEST_GRPC</c> (optional): the gRPC endpoint, e.g. <c>127.0.0.1:50051</c>
/// (<c>http://</c> is added when missing); repeats the checks over gRPC.</description></item>
/// </list>
/// <code>
/// ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=&lt;hex&gt;,&lt;hex&gt; ... \
///   dotnet test Antd.Sdk.Tests --filter FullyQualifiedName~ManifestLiveTests --logger "console;verbosity=detailed"
/// </code>
/// </summary>
public sealed class ManifestLiveTests
{
    private readonly ITestOutputHelper _out;

    public ManifestLiveTests(ITestOutputHelper output) => _out = output;

    private static string Env(string name) => Environment.GetEnvironmentVariable(name)?.Trim() ?? "";

    private static string[] List(string name) =>
        Env(name).Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    private sealed record Fixtures(string[] Addresses, ulong[] Sizes, string DataMap, ulong DataMapSize, string Link)
    {
        public List<ManifestEntryInput> Entries() => new()
        {
            // No size claim on the public entries, so their Size stays unset;
            // the embedded one records its size.
            ManifestEntryInput.Public(Addresses[0], "public/one.txt"),
            ManifestEntryInput.Public(Addresses[1], "public/two.txt"),
            ManifestEntryInput.Embedded(DataMap, "private/three.txt", DataMapSize),
        };

        public static BuildManifestOptions Options => new(Name: "antd-csharp-live");
    }

    [Fact]
    public async Task LiveManifestRoundTrip()
    {
        var url = Env("ANTD_TEST_URL");
        var addresses = List("ANTD_TEST_MANIFEST_ADDRESSES");
        if (url.Length == 0 || addresses.Length == 0)
        {
            _out.WriteLine("live manifests: set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES (see the class doc) to run");
            return;
        }
        var sizes = List("ANTD_TEST_MANIFEST_SIZES").Select(ulong.Parse).ToArray();
        Assert.True(addresses.Length == 2 && sizes.Length == 2,
            "ANTD_TEST_MANIFEST_ADDRESSES and ANTD_TEST_MANIFEST_SIZES must hold two values each");
        var dataMap = Env("ANTD_TEST_MANIFEST_DATA_MAP");
        Assert.False(dataMap.Length == 0, "ANTD_TEST_MANIFEST_DATA_MAP must be set");
        var fx = new Fixtures(addresses, sizes, dataMap, ulong.Parse(Env("ANTD_TEST_MANIFEST_DATA_MAP_SIZE")),
            Env("ANTD_TEST_MANIFEST_LINK"));

        using var rest = new AntdRestClient(url, TimeSpan.FromMinutes(5));
        var restBytes = await RoundTrip("REST", rest, fx);

        var grpcTarget = Env("ANTD_TEST_GRPC");
        if (grpcTarget.Length == 0)
        {
            _out.WriteLine("gRPC: set ANTD_TEST_GRPC to repeat over gRPC");
            return;
        }
        if (!grpcTarget.Contains("://")) grpcTarget = "http://" + grpcTarget;
        using var grpc = new AntdGrpcClient(grpcTarget);
        var grpcBytes = await RoundTrip("gRPC", grpc, fx);
        // The encoding is ant-core's, so both transports build the same bytes.
        Assert.Equal(restBytes, grpcBytes);
        _out.WriteLine($"REST and gRPC built identical manifests ({restBytes.Length} bytes)");
    }

    private async Task<byte[]> RoundTrip(string transport, IAntdClient client, Fixtures fx)
    {
        // 1-2. Build: the entries come back sorted by effective name.
        var built = await client.BuildManifestAsync(fx.Entries(), Fixtures.Options);
        Assert.NotEmpty(built.Manifest);
        Assert.False(string.IsNullOrEmpty(built.Link), "three entries fit in a link");
        var link = built.Link!;
        Assert.StartsWith("ant://manifest/", link);
        Assert.Equal(new[] { "private/three.txt", "public/one.txt", "public/two.txt" },
            built.Entries.Select(e => e.EffectiveName));
        Assert.Equal(new[] { "embedded", "public", "public" }, built.Entries.Select(e => e.Kind));
        Assert.Equal(fx.Addresses, built.Entries.Skip(1).Select(e => e.ContentAddress));
        Assert.Equal(fx.DataMapSize, built.Entries[0].Size);
        Assert.Equal(fx.DataMapSize, built.Entries[0].ExactSize);
        Assert.All(built.Entries.Skip(1), e => Assert.Null(e.Size));
        Assert.All(built.Entries, e => Assert.Null(e.DataMap));
        _out.WriteLine($"{transport} build OK: {built.Manifest.Length} bytes, link {link.Length} chars");

        // 3. Decode the bytes and the link, resolving.
        foreach (var (what, decoded) in new[]
                 {
                     ("bytes", await client.DecodeManifestAsync(built.Manifest, resolve: true)),
                     ("link", await client.DecodeManifestLinkAsync(link, resolve: true)),
                 })
        {
            Assert.Equal(("manifest", "antd-csharp-live"), (decoded.Source, decoded.Name));
            Assert.Null(decoded.TorrentInfoHashV1);
            Assert.Null(decoded.TorrentInfoHashV2);
            CheckDecodedEntries(fx, decoded, publicSizesUnset: true);
            _out.WriteLine($"{transport} decode ({what}, resolve) OK: exact sizes {string.Join(",", decoded.Entries.Select(e => e.ExactSize))}");
        }

        // An unresolved decode of a public entry has no exact size to report.
        var plain = await client.DecodeManifestAsync(built.Manifest);
        Assert.All(plain.Entries.Skip(1), e => Assert.Null(e.ExactSize));
        Assert.Equal(fx.DataMapSize, plain.Entries[0].ExactSize);

        // 4. The fixture link, built elsewhere from the same three entries.
        if (fx.Link.Length > 0)
        {
            var fixture = await client.DecodeManifestLinkAsync(fx.Link, resolve: true);
            Assert.Equal("manifest", fixture.Source);
            CheckDecodedEntries(fx, fixture, publicSizesUnset: false);
            _out.WriteLine($"{transport} fixture link OK: name {fixture.Name}, {fixture.Entries.Count} entries");
        }

        // A bare address decodes as a file link: one public entry, no path.
        var file = await client.DecodeManifestLinkAsync(fx.Addresses[0], resolve: true);
        Assert.Equal("file_link", file.Source);
        var only = Assert.Single(file.Entries);
        Assert.Equal(("public", fx.Addresses[0], (string?)null, fx.Sizes[0]), (only.Kind, only.ContentAddress, only.Path, only.ExactSize!.Value));

        // 5. Bad entries: both sources is refused before sending, a bad path by the daemon.
        await Assert.ThrowsAsync<ArgumentException>(() => client.BuildManifestAsync(
            new[] { new ManifestEntryInput(DataMap: fx.DataMap, Address: fx.Addresses[0]) }));
        var bad = await Assert.ThrowsAsync<BadRequestException>(() => client.BuildManifestAsync(
            new[] { ManifestEntryInput.Public(fx.Addresses[0], "../x") }));
        Assert.Contains("entries[0]", bad.Message);
        var notManifest = await Assert.ThrowsAsync<BadRequestException>(
            () => client.DecodeManifestAsync(new byte[] { 1, 2, 3 }));
        _out.WriteLine($"{transport} bad entry OK: {bad.Message}");
        _out.WriteLine($"{transport} not a manifest OK: {notManifest.Message}");

        return built.Manifest;
    }

    /// <summary>
    /// The three fixture entries, resolved: exact sizes match the fixtures,
    /// and the DataMap entry decodes as embedded with its DataMap.
    /// </summary>
    private static void CheckDecodedEntries(Fixtures fx, DecodedManifest decoded, bool publicSizesUnset)
    {
        var byName = decoded.Entries.ToDictionary(e => e.EffectiveName);
        Assert.Equal(3, byName.Count);
        var embedded = byName["private/three.txt"];
        Assert.Equal("embedded", embedded.Kind);
        Assert.False(string.IsNullOrEmpty(embedded.DataMap), "an embedded entry decodes with its DataMap");
        Assert.Equal(fx.DataMapSize, embedded.ExactSize);
        Assert.Null(embedded.Error);
        for (var i = 0; i < 2; i++)
        {
            var e = byName[i == 0 ? "public/one.txt" : "public/two.txt"];
            Assert.Equal(("public", fx.Addresses[i]), (e.Kind, e.ContentAddress));
            Assert.Null(e.DataMap);
            Assert.Null(e.Error);
            Assert.Equal(fx.Sizes[i], e.ExactSize);
            // Built here without a size claim, a public entry records none:
            // null, not 0. (The fixture link's entries carry claims.)
            if (publicSizesUnset) Assert.Null(e.Size);
        }
    }
}
