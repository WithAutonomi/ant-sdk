namespace Antd.Sdk;

// Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
// of files, each with an optional path and size and either an embedded
// DataMap or a public DataMap address. The daemon builds and decodes them
// through ant-core, so callers never re-implement the format.
//
// Nothing is uploaded or paid for. The network is read only to resolve
// DataMaps (the embedding policy on build, and `resolve` on decode), so a
// call can time out; retrying is safe.

/// <summary>
/// One file for <c>BuildManifestAsync</c>. Set exactly one of
/// <paramref name="DataMap"/> or <paramref name="Address"/>; the SDK refuses
/// both or neither before sending. <see cref="Embedded"/> and
/// <see cref="Public"/> build one.
/// </summary>
/// <param name="Path">
/// The relative path the entry extracts under, subject to the portable path
/// rules (the daemon names a bad one in a <see cref="BadRequestException"/>).
/// <c>null</c> or empty: it extracts under its content address.
/// </param>
/// <param name="Size">
/// The plaintext size to record, as given (the creator's claim). <c>null</c>:
/// none is recorded; readers take the exact size from an embedded root
/// DataMap.
/// </param>
/// <param name="DataMap">
/// A hex DataMap, as the private upload methods return it. The entry embeds
/// it: the manifest is the key to the file.
/// </param>
/// <param name="Address">A public file's DataMap address (hex, 32 bytes).</param>
/// <param name="Sha256">
/// The plaintext's SHA-256 to record (hex), passed through as given; the
/// daemon validates it (requires antd 0.17.0 or later). <c>null</c> or empty:
/// none is recorded and none is sent. Set it with
/// <c>entry with { Sha256 = "..." }</c>.
/// </param>
public sealed record ManifestEntryInput(
    string? Path = null,
    ulong? Size = null,
    string? DataMap = null,
    string? Address = null,
    string? Sha256 = null)
{
    /// <summary>
    /// Deconstructs the members this record had before <c>Sha256</c> was added, so
    /// <c>var (a, b, ...) = result;</c> and positional patterns written against
    /// the earlier shape keep compiling. The compiler-generated overload that
    /// also yields <c>Sha256</c> stays.
    /// </summary>
    public void Deconstruct(out string? Path, out ulong? Size, out string? DataMap, out string? Address)
    {
        Path = this.Path;
        Size = this.Size;
        DataMap = this.DataMap;
        Address = this.Address;
    }

    /// <summary>An entry that embeds <paramref name="dataMap"/> (hex).</summary>
    public static ManifestEntryInput Embedded(string dataMap, string? path = null, ulong? size = null) =>
        new(path, size, DataMap: dataMap);

    /// <summary>An entry that names a public file by its DataMap <paramref name="address"/> (hex).</summary>
    public static ManifestEntryInput Public(string address, string? path = null, ulong? size = null) =>
        new(path, size, Address: address);
}

/// <summary>The optional parts of a <c>BuildManifestAsync</c> call.</summary>
/// <param name="Name">A suggested root directory name (one portable path component).</param>
/// <param name="TorrentInfoHashes">
/// BitTorrent info hashes of the same files: hex, 40 characters for v1 and/or
/// 64 for v2.
/// </param>
/// <param name="EmbedRoots">
/// <c>true</c> (the default): the daemon resolves each shrunk DataMap's root,
/// fetching its wrapper records, and embeds the root when it is at most
/// 64 KiB, so recipients skip that fetch (ADR-0006's policy). <c>false</c>
/// embeds shrunk DataMaps exactly as given.
/// </param>
public sealed record BuildManifestOptions(
    string? Name = null,
    IReadOnlyList<string>? TorrentInfoHashes = null,
    bool EmbedRoots = true);

/// <summary>What a manifest says about one entry.</summary>
/// <param name="EffectiveName"><paramref name="Path"/>, or the content address in hex when there is none.</param>
/// <param name="Path">The entry's path; <c>null</c> when it has none.</param>
/// <param name="Size">The size recorded in the manifest (the creator's claim); <c>null</c> when none is.</param>
/// <param name="Kind"><c>"embedded"</c> or <c>"public"</c>.</param>
/// <param name="ContentAddress">
/// Hex. The file's public DataMap address, whether or not it was ever made
/// public; the same for private and public uploads of one file.
/// </param>
/// <param name="DataMap">
/// The embedded DataMap in the hex form the download methods accept. Decode
/// only; <c>null</c> for public entries and in a build result.
/// </param>
/// <param name="ExactSize">
/// The exact plaintext size: from an embedded root DataMap, or after a
/// resolving decode. <c>null</c> when neither gave one.
/// </param>
/// <param name="Error">Why a resolving decode failed for this entry; <c>null</c> when it did not.</param>
/// <param name="Sha256">
/// The plaintext's SHA-256 (lowercase hex) recorded in the manifest;
/// <c>null</c> when none is (requires antd 0.17.0 or later).
/// </param>
public sealed record ManifestEntryInfo(
    string EffectiveName,
    string? Path,
    ulong? Size,
    string Kind,
    string ContentAddress,
    string? DataMap,
    ulong? ExactSize,
    string? Error,
    string? Sha256 = null)
{
    /// <summary>
    /// Deconstructs the members this record had before <c>Sha256</c> was added, so
    /// <c>var (a, b, ...) = result;</c> and positional patterns written against
    /// the earlier shape keep compiling. The compiler-generated overload that
    /// also yields <c>Sha256</c> stays.
    /// </summary>
    public void Deconstruct(out string EffectiveName, out string? Path, out ulong? Size, out string Kind, out string ContentAddress, out string? DataMap, out ulong? ExactSize, out string? Error)
    {
        EffectiveName = this.EffectiveName;
        Path = this.Path;
        Size = this.Size;
        Kind = this.Kind;
        ContentAddress = this.ContentAddress;
        DataMap = this.DataMap;
        ExactSize = this.ExactSize;
        Error = this.Error;
    }
}

/// <summary>The result of <c>BuildManifestAsync</c>.</summary>
/// <param name="Manifest">The raw <c>.ant</c> bytes.</param>
/// <param name="Link">
/// The <c>ant://manifest/</c> link, set only when it fits the recommended
/// 1,500 bytes; <c>null</c> otherwise (share <paramref name="Manifest"/> instead).
/// </param>
/// <param name="Entries">In encoded order (sorted by effective name).</param>
public sealed record BuiltManifest(
    byte[] Manifest,
    string? Link,
    List<ManifestEntryInfo> Entries);

/// <summary>The result of <c>DecodeManifestAsync</c> and <c>DecodeManifestLinkAsync</c>.</summary>
/// <param name="Source">
/// <c>"manifest"</c>, or <c>"file_link"</c> for a file link or bare address
/// (reported as one public entry with no path).
/// </param>
/// <param name="Name">The suggested root directory name; <c>null</c> when there is none.</param>
/// <param name="TorrentInfoHashV1">BitTorrent v1 info hash (hex); <c>null</c> when absent.</param>
/// <param name="TorrentInfoHashV2">BitTorrent v2 info hash (hex); <c>null</c> when absent.</param>
/// <param name="Entries">The entries, in encoded order.</param>
public sealed record DecodedManifest(
    string Source,
    string? Name,
    string? TorrentInfoHashV1,
    string? TorrentInfoHashV2,
    List<ManifestEntryInfo> Entries);

internal static class ManifestWire
{
    /// <summary>The daemon's cap on entry errors it spells out (<c>MAX_REPORTED_ENTRY_ERRORS</c>).</summary>
    private const int MaxReportedEntryErrors = 20;

    /// <summary>The daemon's message for an empty decode request.</summary>
    internal const string EmptyDecodeInput = "needs a manifest (base64 .ant bytes) or a link";

    /// <summary>
    /// Refuse, before anything is sent, an entry that sets both or neither of
    /// <see cref="ManifestEntryInput.DataMap"/> and
    /// <see cref="ManifestEntryInput.Address"/> (an empty string counts as
    /// unset). The refusal is indistinguishable from the daemon's: a
    /// <see cref="BadRequestException"/> with status 400 and the daemon's own
    /// aggregated wording (<c>parse_entries</c> and <c>entry_errors_message</c>
    /// in antd/src/manifests.rs), which reports every bad entry, at most 20.
    /// </summary>
    internal static void CheckEntries(IReadOnlyList<ManifestEntryInput> entries)
    {
        if (entries is null)
            throw new BadRequestException("needs entries", 400);
        var errors = new List<string>();
        for (var i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            string? problem = null;
            if (e is null) problem = "needs a data_map or an address";
            else if (!string.IsNullOrEmpty(e.DataMap) && !string.IsNullOrEmpty(e.Address))
                problem = "give data_map or address, not both";
            else if (string.IsNullOrEmpty(e.DataMap) && string.IsNullOrEmpty(e.Address))
                problem = "needs a data_map or an address";
            if (problem != null) errors.Add($"entries[{i}]: {problem}");
        }
        if (errors.Count == 0) return;
        var shown = string.Join("; ", errors.Take(MaxReportedEntryErrors));
        var more = errors.Count > MaxReportedEntryErrors ? $"; and {errors.Count - MaxReportedEntryErrors} more" : "";
        throw new BadRequestException($"{errors.Count} invalid entries: {shown}{more}", 400);
    }

    /// <summary>The <c>.ant</c> bytes to decode must be present.</summary>
    internal static void CheckManifest(byte[] manifest)
    {
        if (manifest is null || manifest.Length == 0)
            throw new BadRequestException(EmptyDecodeInput, 400);
    }

    /// <summary>A link to decode must be present.</summary>
    internal static void CheckLink(string link)
    {
        if (string.IsNullOrEmpty(link))
            throw new BadRequestException(EmptyDecodeInput, 400);
    }

    /// <summary>
    /// The REST transport carries the <c>.ant</c> bytes as base64; callers
    /// get raw bytes. A response that is not base64 is a protocol violation.
    /// </summary>
    internal static byte[] FromBase64(string? value)
    {
        try
        {
            return Convert.FromBase64String(value ?? "");
        }
        catch (FormatException)
        {
            throw new AntdException("antd: the manifest in the build response is not valid base64");
        }
    }

    /// <summary>
    /// An unset value: REST leaves it out, gRPC sends the empty string. Both
    /// read as <c>null</c>.
    /// </summary>
    internal static string? NullIfEmpty(string? value) => string.IsNullOrEmpty(value) ? null : value;
}
