using System.Text.Json.Serialization;

namespace Antd.Sdk;

// Manifests over REST (/v1/manifests). See IAntdClient for each method's
// contract. The .ant bytes travel as base64 in the JSON (`manifest` in the
// build response and the decode request); callers only see raw bytes. Unset
// fields are left out of requests, and absent ones read as null.
public sealed partial class AntdRestClient
{
    public async Task<BuiltManifest> BuildManifestAsync(
        IReadOnlyList<ManifestEntryInput> entries, BuildManifestOptions? options = null)
    {
        ManifestWire.CheckEntries(entries);
        options ??= new BuildManifestOptions();
        var body = new
        {
            name = ManifestWire.NullIfEmpty(options.Name),
            torrent_info_hashes = options.TorrentInfoHashes is { Count: > 0 } hashes ? hashes : null,
            // Sent either way, as antd-go does; the daemon's default is true.
            embed_roots = options.EmbedRoots,
            entries = entries.Select(e => new
            {
                path = ManifestWire.NullIfEmpty(e.Path),
                size = e.Size,
                data_map = ManifestWire.NullIfEmpty(e.DataMap),
                address = ManifestWire.NullIfEmpty(e.Address),
            }).ToList(),
        };
        var resp = await PostJsonAsync<ManifestBuildDto>("/v1/manifests/build", body);
        return new BuiltManifest(
            ManifestWire.FromBase64(resp.Manifest),
            ManifestWire.NullIfEmpty(resp.Link),
            MapManifestEntries(resp.Entries));
    }

    public async Task<DecodedManifest> DecodeManifestAsync(byte[] manifest, bool resolve = false)
    {
        ManifestWire.CheckManifest(manifest);
        return await DecodeManifestBodyAsync(new { manifest = Convert.ToBase64String(manifest), resolve });
    }

    public async Task<DecodedManifest> DecodeManifestLinkAsync(string link, bool resolve = false)
    {
        ArgumentException.ThrowIfNullOrEmpty(link);
        return await DecodeManifestBodyAsync(new { link, resolve });
    }

    private async Task<DecodedManifest> DecodeManifestBodyAsync(object body)
    {
        var resp = await PostJsonAsync<ManifestDecodeDto>("/v1/manifests/decode", body);
        return new DecodedManifest(
            resp.Source ?? "",
            ManifestWire.NullIfEmpty(resp.Name),
            ManifestWire.NullIfEmpty(resp.TorrentInfoHashV1),
            ManifestWire.NullIfEmpty(resp.TorrentInfoHashV2),
            MapManifestEntries(resp.Entries));
    }

    private static List<ManifestEntryInfo> MapManifestEntries(List<ManifestEntryInfoDto>? entries) =>
        entries?.Select(e => new ManifestEntryInfo(
            e.EffectiveName ?? "",
            ManifestWire.NullIfEmpty(e.Path),
            e.Size,
            e.Kind ?? "",
            e.ContentAddress ?? "",
            ManifestWire.NullIfEmpty(e.DataMap),
            e.ExactSize,
            ManifestWire.NullIfEmpty(e.Error))).ToList() ?? [];

    // Sizes are JSON numbers, read straight into ulong?: an absent size is
    // null, never 0.

    private sealed record ManifestEntryInfoDto(
        [property: JsonPropertyName("effective_name")] string? EffectiveName = null,
        [property: JsonPropertyName("path")] string? Path = null,
        [property: JsonPropertyName("size")] ulong? Size = null,
        [property: JsonPropertyName("kind")] string? Kind = null,
        [property: JsonPropertyName("content_address")] string? ContentAddress = null,
        [property: JsonPropertyName("data_map")] string? DataMap = null,
        [property: JsonPropertyName("exact_size")] ulong? ExactSize = null,
        [property: JsonPropertyName("error")] string? Error = null);

    private sealed record ManifestBuildDto(
        [property: JsonPropertyName("manifest")] string? Manifest = null,
        [property: JsonPropertyName("link")] string? Link = null,
        [property: JsonPropertyName("entries")] List<ManifestEntryInfoDto>? Entries = null);

    private sealed record ManifestDecodeDto(
        [property: JsonPropertyName("source")] string? Source = null,
        [property: JsonPropertyName("name")] string? Name = null,
        [property: JsonPropertyName("torrent_info_hash_v1")] string? TorrentInfoHashV1 = null,
        [property: JsonPropertyName("torrent_info_hash_v2")] string? TorrentInfoHashV2 = null,
        [property: JsonPropertyName("entries")] List<ManifestEntryInfoDto>? Entries = null);
}
