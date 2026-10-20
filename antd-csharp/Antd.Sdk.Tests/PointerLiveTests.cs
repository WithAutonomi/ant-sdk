using System.Text;
using Antd.Sdk;
using Xunit;
using Xunit.Abstractions;

namespace Antd.Sdk.Tests;

/// <summary>
/// Live pointer round trip against a running antd with a devnet behind it.
/// Passes without doing anything unless all three are set:
/// <list type="bullet">
/// <item><description><c>ANTD_TEST_URL</c>: the daemon's REST base URL, e.g. <c>http://127.0.0.1:8082</c>.</description></item>
/// <item><description><c>ANTD_TEST_GRPC</c>: its gRPC endpoint, e.g. <c>127.0.0.1:50051</c> (<c>http://</c> is added when missing).</description></item>
/// <item><description><c>ANTD_TEST_POINTER_OWNERS</c>: two comma-separated pointer addresses the daemon holds keys for
/// (<c>antd --pointer-keys</c>) and that have <b>never been written</b>. The test creates both, transfers the first to
/// the second, and leaves the second with a prepared write awaiting payment, so each pair can be used once.</description></item>
/// </list>
/// Every write is paid by the daemon's wallet, so run it against a devnet:
/// <code>
/// ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 ANTD_TEST_POINTER_OWNERS=&lt;hex&gt;,&lt;hex&gt; \
///   dotnet test Antd.Sdk.Tests --filter FullyQualifiedName~PointerLiveTests --logger "console;verbosity=detailed"
/// </code>
/// </summary>
public sealed class PointerLiveTests
{
    private readonly ITestOutputHelper _out;

    public PointerLiveTests(ITestOutputHelper output) => _out = output;

    /// <summary>The daemon accepts a 0x prefix but returns bare hex.</summary>
    private static string Norm(string address)
    {
        var a = address.Trim();
        return (a.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? a[2..] : a).ToLowerInvariant();
    }

    [Fact]
    public async Task LivePointerRoundTrip()
    {
        var url = Environment.GetEnvironmentVariable("ANTD_TEST_URL");
        var grpcTarget = Environment.GetEnvironmentVariable("ANTD_TEST_GRPC");
        var owners = Environment.GetEnvironmentVariable("ANTD_TEST_POINTER_OWNERS");
        if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(grpcTarget) || string.IsNullOrEmpty(owners))
        {
            _out.WriteLine("live pointers: set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run");
            return;
        }
        var pair = owners.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        Assert.True(pair.Length == 2, "ANTD_TEST_POINTER_OWNERS must hold two addresses");
        var (a, b) = (Norm(pair[0]), Norm(pair[1]));
        if (!grpcTarget.Contains("://")) grpcTarget = "http://" + grpcTarget;

        using var rest = new AntdRestClient(url, TimeSpan.FromMinutes(5));
        using var grpc = new AntdGrpcClient(grpcTarget);

        // Both owners must be writable through this daemon, over both transports.
        var keys = (await rest.PointerKeysAsync()).Select(Norm).ToList();
        Assert.True(keys.Contains(a) && keys.Contains(b), $"daemon holds no key for one of the owners: {string.Join(",", keys)}");
        Assert.Equal(keys.Order(), (await grpc.PointerKeysAsync()).Select(Norm).Order());
        _out.WriteLine($"keys: {keys.Count}, owners {a[..8]}.. and {b[..8]}.. present");

        // Real targets, so the chain can be followed back to bytes. Unique
        // per run, so nothing is already stored.
        var run = Guid.NewGuid().ToString("N");
        var oneBytes = Encoding.UTF8.GetBytes($"antd-csharp pointer target one {run}");
        var twoBytes = Encoding.UTF8.GetBytes($"antd-csharp pointer target two {run}");
        var one = Norm((await rest.DataPutPublicAsync(oneBytes)).Address);
        var two = Norm((await rest.DataPutPublicAsync(twoBytes)).Address);
        _out.WriteLine($"targets: {one[..8]}.. {two[..8]}..");

        // ── REST: create, read, update ──
        await Assert.ThrowsAsync<NotFoundException>(() => rest.PointerGetAsync(a));
        var w = await rest.PointerCreateAsync(a, one);
        Assert.Equal(0UL, w.Counter);
        Assert.Equal(a, Norm(w.Address));
        // Refused before paying. Over REST a 409 ALREADY_EXISTS is an
        // AlreadyExistsException, as over gRPC.
        var exists = await Assert.ThrowsAsync<AlreadyExistsException>(() => rest.PointerCreateAsync(a, two));
        Assert.Contains("ALREADY_EXISTS", exists.Message);

        var r = await rest.PointerGetAsync(a);
        Assert.Equal((0UL, one, false), (r.Counter, Norm(r.Target), r.IsFinal));
        Assert.Equal(PointerKind.Chunk, r.TargetKind);
        Assert.Equal(2 * 1952, r.Owner.Length);
        Assert.Null(r.TransferredTo);
        var res = await rest.PointerResolveAsync(a);
        Assert.Equal(one, Norm(res.Target));
        Assert.Equal(oneBytes, await rest.DataGetPublicAsync(res.Target));

        w = await rest.PointerUpdateAsync(a, two);
        Assert.Equal(1UL, w.Counter);
        Assert.Equal(two, Norm((await rest.PointerResolveAsync(a)).Target));
        var f = await rest.PointerFinalityAsync(a);
        Assert.Equal(PointerFinalityStatus.Open, f.Status);
        Assert.Equal(1UL, f.Counter);
        Assert.Equal(f.Group, f.Answered);
        _out.WriteLine($"REST create/update/get/resolve OK; finality {f.RawStatus} counter {f.Counter} ({f.Answered}/{f.Group})");

        // ── gRPC: a write, then reads ──
        w = await grpc.PointerCreateAsync(b, one);
        Assert.Equal(0UL, w.Counter);
        await Assert.ThrowsAsync<AlreadyExistsException>(() => grpc.PointerCreateAsync(b, two));
        r = await grpc.PointerGetAsync(b);
        Assert.Equal((0UL, one, false), (r.Counter, Norm(r.Target), r.IsFinal));
        Assert.Null(r.TransferredTo);
        var gf = await grpc.PointerFinalityAsync(b);
        Assert.Equal(PointerFinalityStatus.Open, gf.Status);
        // Unset ("" over gRPC) when no state is corroborated yet; 0 otherwise.
        Assert.True(gf.Counter is null or 0UL, $"counter {gf.Counter}");
        Assert.Null(gf.TransferredTo);
        _out.WriteLine("gRPC create/get/finality OK");

        // ── transfer a -> b ──
        var t = await rest.PointerTransferAsync(a, b);
        var tf = Assert.IsType<PointerFinality>(t.Finality);
        Assert.Equal(PointerFinalityStatus.Final, tf.Status);
        Assert.Equal(b, Norm(tf.TransferredTo!));
        r = await rest.PointerGetAsync(a);
        Assert.True(r.IsFinal);
        Assert.Equal(ulong.MaxValue, r.Counter);
        Assert.Equal(b, Norm(r.TransferredTo!));
        var c = await rest.PointerControllerAsync(a);
        Assert.Equal(b, Norm(c.Pointer));
        Assert.Equal(new[] { b }, c.Transfers.Select(Norm));
        Assert.False(c.Frozen);
        var gc = await grpc.PointerControllerAsync(a);
        Assert.Equal(c.Pointer, gc.Pointer);
        // a now resolves through b, over both transports.
        Assert.Equal(one, Norm((await grpc.PointerResolveAsync(a)).Target));
        Assert.Equal(one, Norm((await rest.PointerResolveAsync(a)).Target));
        var gtf = await grpc.PointerFinalityAsync(a);
        Assert.True(gtf.IsFinal);
        Assert.Equal(b, Norm(gtf.TransferredTo!));
        r = await grpc.PointerGetAsync(a);
        Assert.Equal((ulong.MaxValue, true), (r.Counter, r.IsFinal));
        _out.WriteLine($"transfer OK: finality {tf.RawStatus}, counter {r.Counter}");

        // A final pointer refuses every write, before anything is paid.
        await Assert.ThrowsAsync<PointerFinalException>(() => rest.PointerUpdateAsync(a, one));
        await Assert.ThrowsAsync<PointerFinalException>(() => grpc.PointerUpdateAsync(a, one));
        await Assert.ThrowsAsync<PointerFinalException>(() => rest.PointerTransferAsync(a, b));
        _out.WriteLine("POINTER_FINAL over REST and gRPC OK");

        // ── external signer, up to the quote ──
        // Last: the prepared write blocks b's other writes until it expires.
        var p = await rest.PointerPrepareAsync(PointerPrepareRequest.Update(b, two));
        Assert.Equal(("update", 1UL), (p.Op, p.Counter));
        Assert.Equal("wave_batch", p.PaymentType);
        Assert.NotEmpty(p.Payments);
        Assert.NotEmpty(p.UploadId);
        Assert.Equal(b, Norm(p.Address));
        await Assert.ThrowsAsync<ConflictException>(() => rest.PointerUpdateAsync(b, two));
        await Assert.ThrowsAsync<ConflictException>(() => grpc.PointerPrepareAsync(PointerPrepareRequest.Update(b, two)));
        await Assert.ThrowsAsync<ConflictException>(() => grpc.PointerUpdateAsync(b, two));
        // A finalize without the payment is refused and keeps the session.
        await Assert.ThrowsAsync<BadRequestException>(
            () => rest.PointerFinalizeAsync(p.UploadId, new Dictionary<string, string>()));
        await Assert.ThrowsAsync<ConflictException>(() => rest.PointerUpdateAsync(b, two));
        _out.WriteLine($"prepare OK (total {p.TotalAmount}, {p.Payments.Count} payment(s)); CONFLICT over REST and gRPC OK");
    }
}
