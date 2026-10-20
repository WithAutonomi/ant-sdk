using System.Text;
using Antd.Sdk;

namespace Antd.Examples;

partial class Program
{
    /// <summary>
    /// Example 09: Manifests. A manifest (an ADR-0006 <c>.ant</c> file, or an
    /// <c>ant://manifest/</c> link when it is small enough) describes a set of
    /// files: each has a path and either an embedded DataMap or a public
    /// DataMap address. This uploads two pieces of public data, builds a
    /// manifest of them, and decodes its link, resolving each entry's exact
    /// size.
    ///
    /// Building and decoding upload and pay for nothing; only the two uploads
    /// pay. Needs antd 0.16.0 or later and a wallet;
    /// <c>ANTD_BASE_URL</c> overrides the daemon URL (default
    /// http://localhost:8082). Run explicitly (<c>dotnet run -- 9</c>); "all"
    /// leaves it out, so it still runs against older daemons.
    /// </summary>
    static async Task Example09_Manifests()
    {
        Console.WriteLine("=== Example 09: Manifests ===");
        var baseUrl = Environment.GetEnvironmentVariable("ANTD_BASE_URL");
        using var client = string.IsNullOrEmpty(baseUrl) ? AntdClient.CreateRest() : AntdClient.CreateRest(baseUrl);

        // 1. Two small pieces of public data (these two uploads pay).
        var stamp = DateTime.UtcNow.ToString("O");
        var one = Encoding.UTF8.GetBytes($"manifest example, note one ({stamp})");
        var two = Encoding.UTF8.GetBytes($"manifest example, note two, a little longer ({stamp})");
        var first = await client.DataPutPublicAsync(one);
        var second = await client.DataPutPublicAsync(two);
        Console.WriteLine($"Uploaded: {first.Address} ({one.Length} bytes)");
        Console.WriteLine($"          {second.Address} ({two.Length} bytes)");

        // 2. Build a manifest of them. Free: nothing is uploaded or paid for.
        var built = await client.BuildManifestAsync(
            new[]
            {
                ManifestEntryInput.Public(first.Address, "notes/one.txt"),
                ManifestEntryInput.Public(second.Address, "notes/two.txt"),
            },
            new BuildManifestOptions(Name: "example"));
        Console.WriteLine($"Manifest: {built.Manifest.Length} bytes");
        Console.WriteLine($"Link: {built.Link ?? "(too long for a link; share the .ant bytes instead)"}");
        foreach (var e in built.Entries)
            Console.WriteLine($"  {e.EffectiveName} -> {e.ContentAddress} ({e.Kind})");

        // 3. Decode the link, resolving: the daemon fetches each entry's
        // DataMap (not its content) to report its exact size.
        var decoded = built.Link is { } link
            ? await client.DecodeManifestLinkAsync(link, resolve: true)
            : await client.DecodeManifestAsync(built.Manifest, resolve: true);
        Console.WriteLine($"Decoded: source={decoded.Source}, name={decoded.Name}");
        foreach (var e in decoded.Entries)
        {
            Console.WriteLine($"  {e.EffectiveName}: exact_size={e.ExactSize?.ToString() ?? "-"}" +
                              (e.Error is null ? "" : $", error: {e.Error}"));
        }

        var sizes = decoded.Entries.ToDictionary(e => e.EffectiveName, e => e.ExactSize);
        if (sizes.GetValueOrDefault("notes/one.txt") != (ulong)one.Length
            || sizes.GetValueOrDefault("notes/two.txt") != (ulong)two.Length)
            throw new Exception("the resolved sizes do not match the uploads");

        Console.WriteLine("\n09_manifests OK!\n");
    }
}
