using Google.Protobuf;
using Grpc.Core;
using Grpc.Net.Client;
using Pb = Antd.V1;

namespace Antd.Sdk;

// Manifests over gRPC (ManifestService): the same methods, models and
// exceptions as the REST client. The .ant bytes are raw protobuf bytes here,
// and the optional sizes are proto3 `optional`, read by presence (HasSize,
// HasExactSize), so an unset size is null, never 0.
//
// A manifest can be 64 MiB and a Build or Decode response carries it, past
// Grpc.Net.Client's default 4 MiB receive limit. Grpc.Net.Client sets message
// limits per channel only (GrpcChannelOptions; CallOptions has none), so
// ManifestService gets a channel of its own to the same target, with both
// limits raised. The other services keep the defaults on the shared channel.
public sealed partial class AntdGrpcClient
{
    /// <summary>
    /// The send and receive ceiling for manifest calls: a manifest can be
    /// 64 MiB, and a decode response carries its DataMaps in hex. Matches
    /// antd-go's per-call <c>maxManifestGrpcMessage</c>.
    /// </summary>
    internal const int MaxManifestGrpcMessage = 256 * 1024 * 1024;

    // Assigned by the public constructor; the test-only constructors leave the
    // stub unset unless they are given one.
    private readonly Pb.ManifestService.ManifestServiceClient _manifest = null!;
    private readonly GrpcChannel? _manifestChannel;

    /// <summary>
    /// The options of the manifest channel: both message limits raised to
    /// <see cref="MaxManifestGrpcMessage"/>. <paramref name="handler"/> is for
    /// tests.
    /// </summary>
    internal static GrpcChannelOptions ManifestChannelOptions(HttpMessageHandler? handler = null) => new()
    {
        MaxReceiveMessageSize = MaxManifestGrpcMessage,
        MaxSendMessageSize = MaxManifestGrpcMessage,
        HttpHandler = handler,
    };

    /// <summary>
    /// Test-only constructor: a client whose manifest calls go to
    /// <paramref name="manifest"/> (a subclassed mock, or a stub on a channel
    /// the test built). The other services are unset.
    /// </summary>
    internal AntdGrpcClient(Pb.ManifestService.ManifestServiceClient manifest)
        : this(health: null!, data: null!, chunks: null!, files: null!, upload: null!, wallet: null!)
    {
        _manifest = manifest;
    }

    public async Task<BuiltManifest> BuildManifestAsync(
        IReadOnlyList<ManifestEntryInput> entries, BuildManifestOptions? options = null)
    {
        ManifestWire.CheckEntries(entries);
        options ??= new BuildManifestOptions();
        // Set either way, as antd-go does; unset means true on the daemon.
        var req = new Pb.BuildManifestRequest { EmbedRoots = options.EmbedRoots };
        if (!string.IsNullOrEmpty(options.Name)) req.Name = options.Name;
        if (options.TorrentInfoHashes != null) req.TorrentInfoHashes.Add(options.TorrentInfoHashes);
        foreach (var e in entries)
        {
            var input = new Pb.ManifestEntryInput();
            if (!string.IsNullOrEmpty(e.Path)) input.Path = e.Path;
            if (e.Size is { } size) input.Size = size;
            if (!string.IsNullOrEmpty(e.DataMap)) input.DataMap = e.DataMap;
            else input.Address = e.Address!;
            req.Entries.Add(input);
        }

        Pb.BuildManifestResponse resp;
        try { resp = await _manifest.BuildAsync(req); }
        catch (RpcException ex) { throw Wrap(ex); }
        return new BuiltManifest(
            resp.Manifest.ToByteArray(),
            ManifestWire.NullIfEmpty(resp.Link),
            resp.Entries.Select(FromPbManifestEntry).ToList());
    }

    public async Task<DecodedManifest> DecodeManifestAsync(byte[] manifest, bool resolve = false)
    {
        ManifestWire.CheckManifest(manifest);
        return await DecodeManifestRequestAsync(new Pb.DecodeManifestRequest
        {
            Manifest = ByteString.CopyFrom(manifest),
            Resolve = resolve,
        });
    }

    public async Task<DecodedManifest> DecodeManifestLinkAsync(string link, bool resolve = false)
    {
        ArgumentException.ThrowIfNullOrEmpty(link);
        return await DecodeManifestRequestAsync(new Pb.DecodeManifestRequest { Link = link, Resolve = resolve });
    }

    private async Task<DecodedManifest> DecodeManifestRequestAsync(Pb.DecodeManifestRequest req)
    {
        Pb.DecodeManifestResponse resp;
        try { resp = await _manifest.DecodeAsync(req); }
        catch (RpcException ex) { throw Wrap(ex); }
        return new DecodedManifest(
            resp.Source,
            resp.HasName ? ManifestWire.NullIfEmpty(resp.Name) : null,
            ManifestWire.NullIfEmpty(resp.TorrentInfoHashV1),
            ManifestWire.NullIfEmpty(resp.TorrentInfoHashV2),
            resp.Entries.Select(FromPbManifestEntry).ToList());
    }

    private static ManifestEntryInfo FromPbManifestEntry(Pb.ManifestEntryInfo e) =>
        new(
            e.EffectiveName,
            e.HasPath ? ManifestWire.NullIfEmpty(e.Path) : null,
            e.HasSize ? e.Size : null,
            e.Kind,
            e.ContentAddress,
            ManifestWire.NullIfEmpty(e.DataMap),
            e.HasExactSize ? e.ExactSize : null,
            ManifestWire.NullIfEmpty(e.Error));
}
