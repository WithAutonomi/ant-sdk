namespace Antd.Sdk;

public partial interface IAntdClient
{
    // Manifests (the antd release after 0.15.0, the first with the manifest
    // API): ADR-0006 `.ant` files and `ant://` links.
    //
    // Nothing is uploaded or paid for. Build and a resolving decode read
    // DataMaps from the network, so they can time out; they are safe to
    // retry. The .ant bytes are raw bytes here on both transports (REST
    // carries them as base64). Sizes are ulong?, and an unset size is null,
    // never 0.
    //
    // These have default implementations that throw NotSupportedException, so
    // a class that implements IAntdClient outside this package keeps
    // compiling; AntdRestClient and AntdGrpcClient implement them all.

    /// <summary>
    /// Build a <c>.ant</c> manifest from DataMaps and public addresses already
    /// in hand. Nothing is uploaded or paid for.
    /// </summary>
    /// <param name="entries">The files. Each sets exactly one of <c>DataMap</c> or <c>Address</c>.</param>
    /// <param name="options"><c>null</c>: no name, no torrent hashes, and roots embedded.</param>
    /// <exception cref="ArgumentException">An entry sets both or neither of <c>DataMap</c> and <c>Address</c>; nothing was sent.</exception>
    /// <exception cref="BadRequestException">
    /// The daemon refused an entry (a bad path, DataMap or address) or a
    /// torrent hash; the message names each bad entry as <c>entries[i]</c>.
    /// </exception>
    Task<BuiltManifest> BuildManifestAsync(IReadOnlyList<ManifestEntryInput> entries, BuildManifestOptions? options = null) =>
        throw new NotSupportedException("this IAntdClient does not implement manifests");

    /// <summary>
    /// Decode <c>.ant</c> bytes. With <paramref name="resolve"/>, the daemon
    /// fetches each entry's DataMap (and wrapper records) to report
    /// <see cref="ManifestEntryInfo.ExactSize"/> and confirm the DataMap is on
    /// the network; content chunks are not fetched, and one entry's failure is
    /// reported in its <see cref="ManifestEntryInfo.Error"/>, not thrown.
    /// </summary>
    /// <exception cref="ArgumentException"><paramref name="manifest"/> is empty; nothing was sent.</exception>
    /// <exception cref="BadRequestException">The bytes are not a manifest.</exception>
    Task<DecodedManifest> DecodeManifestAsync(byte[] manifest, bool resolve = false) =>
        throw new NotSupportedException("this IAntdClient does not implement manifests");

    /// <summary>
    /// Decode an <c>ant://</c> manifest link, a file link or a bare 64-hex
    /// address; a file link or address reads as one public entry with no path
    /// (<see cref="DecodedManifest.Source"/> <c>"file_link"</c>). See
    /// <see cref="DecodeManifestAsync"/> for <paramref name="resolve"/>.
    /// </summary>
    /// <exception cref="ArgumentException"><paramref name="link"/> is empty; nothing was sent.</exception>
    /// <exception cref="BadRequestException">The link is not one of those forms.</exception>
    Task<DecodedManifest> DecodeManifestLinkAsync(string link, bool resolve = false) =>
        throw new NotSupportedException("this IAntdClient does not implement manifests");
}
