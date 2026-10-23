using System.Security.Cryptography;
using System.Text;
using Antd.Sdk;
using Xunit;
using Xunit.Abstractions;

namespace Antd.Sdk.Tests;

/// <summary>
/// Live sha256 check against a running antd 0.17.0 or later. Passes without
/// doing anything unless <c>ANTD_TEST_URL</c> and <c>ANTD_TEST_SHA_LINK</c> are set:
/// <list type="bullet">
/// <item><description><c>ANTD_TEST_URL</c>: the daemon's REST base URL.</description></item>
/// <item><description><c>ANTD_TEST_SHA_LINK</c>: a manifest link with entries <c>public.txt</c> and
/// <c>private.txt</c> (each with a sha256) and <c>nohash.txt</c> (none).</description></item>
/// <item><description><c>ANTD_TEST_SHA_PUBLIC_ADDRESS</c>, <c>ANTD_TEST_SHA_PUBLIC_SHA256</c>,
/// <c>ANTD_TEST_SHA_DATA_MAP_SHA256</c>: the fixtures' address and hashes.</description></item>
/// <item><description><c>ANTD_TEST_GRPC</c> (optional): the gRPC endpoint; repeats the checks over gRPC.</description></item>
/// </list>
/// One paid call per transport: a small public data upload, whose returned
/// sha256 must equal the SHA-256 computed here over the same bytes.
/// </summary>
public sealed class Sha256LiveTests
{
    private readonly ITestOutputHelper _out;

    public Sha256LiveTests(ITestOutputHelper output) => _out = output;

    private static string Env(string name) => Environment.GetEnvironmentVariable(name)?.Trim() ?? "";

    [Fact]
    public async Task LiveSha256()
    {
        var url = Env("ANTD_TEST_URL");
        var link = Env("ANTD_TEST_SHA_LINK");
        if (url.Length == 0 || link.Length == 0)
        {
            _out.WriteLine("live sha256: set ANTD_TEST_URL and ANTD_TEST_SHA_LINK (see the class doc) to run");
            return;
        }

        using var rest = new AntdRestClient(url, TimeSpan.FromMinutes(5));
        await Check("REST", rest, link);

        var grpcTarget = Env("ANTD_TEST_GRPC");
        if (grpcTarget.Length == 0)
        {
            _out.WriteLine("gRPC: set ANTD_TEST_GRPC to repeat over gRPC");
            return;
        }
        if (!grpcTarget.Contains("://")) grpcTarget = "http://" + grpcTarget;
        using var grpc = new AntdGrpcClient(grpcTarget);
        await Check("gRPC", grpc, link);
    }

    private async Task Check(string transport, IAntdClient client, string link)
    {
        var publicSha = Env("ANTD_TEST_SHA_PUBLIC_SHA256");
        var dataMapSha = Env("ANTD_TEST_SHA_DATA_MAP_SHA256");
        var publicAddress = Env("ANTD_TEST_SHA_PUBLIC_ADDRESS");

        // 1. Decode the fixture link without resolving.
        var decoded = await client.DecodeManifestLinkAsync(link, resolve: false);
        var byPath = decoded.Entries.ToDictionary(e => e.Path ?? e.EffectiveName);
        Assert.Equal(publicSha, byPath["public.txt"].Sha256);
        Assert.Equal(dataMapSha, byPath["private.txt"].Sha256);
        Assert.Null(byPath["nohash.txt"].Sha256);
        _out.WriteLine($"{transport} decode OK: public.txt {byPath["public.txt"].Sha256}, private.txt {byPath["private.txt"].Sha256}, nohash.txt none");

        // 2. Build with a sha256: the returned entry carries it.
        var built = await client.BuildManifestAsync(new[]
        {
            ManifestEntryInput.Public(publicAddress, "a.txt") with { Sha256 = publicSha },
        });
        Assert.Equal(publicSha, Assert.Single(built.Entries).Sha256);
        _out.WriteLine($"{transport} build OK: a.txt {built.Entries[0].Sha256}");

        // 3. A bad sha256 is the bad-request error.
        var bad = await Assert.ThrowsAsync<BadRequestException>(() => client.BuildManifestAsync(new[]
        {
            ManifestEntryInput.Public(publicAddress, "a.txt") with { Sha256 = "zz" },
        }));
        Assert.Contains("entries[0]", bad.Message);
        _out.WriteLine($"{transport} bad sha256 OK: {bad.Message}");

        // 4. One paid call: a small public upload, hashed locally.
        var payload = Encoding.UTF8.GetBytes(
            $"sha-fanout csharp {transport} {DateTimeOffset.UtcNow.ToUnixTimeSeconds()}");
        var local = Convert.ToHexString(SHA256.HashData(payload)).ToLowerInvariant();
        var put = await client.DataPutPublicAsync(payload);
        Assert.Equal(local, put.Sha256);
        _out.WriteLine($"{transport} data put public OK: local sha256 {local}, returned {put.Sha256}, address {put.Address}");
    }
}
