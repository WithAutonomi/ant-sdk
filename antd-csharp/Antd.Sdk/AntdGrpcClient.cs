using Grpc.Core;
using Grpc.Net.Client;
using Google.Protobuf;
using Antd.V1;

namespace Antd.Sdk;

public sealed class AntdGrpcClient : IAntdClient
{
    private readonly GrpcChannel _channel;
    private readonly HealthService.HealthServiceClient _health;
    private readonly DataService.DataServiceClient _data;
    private readonly ChunkService.ChunkServiceClient _chunks;
    private readonly FileService.FileServiceClient _files;

    public AntdGrpcClient(string target = "http://localhost:50051")
    {
        _channel = GrpcChannel.ForAddress(target);
        _health = new HealthService.HealthServiceClient(_channel);
        _data = new DataService.DataServiceClient(_channel);
        _chunks = new ChunkService.ChunkServiceClient(_channel);
        _files = new FileService.FileServiceClient(_channel);
    }

    /// <summary>
    /// Creates an AntdGrpcClient by reading the daemon.port file written by antd.
    /// Falls back to the default target if the port file is not found.
    /// </summary>
    public static AntdGrpcClient AutoDiscover()
    {
        var target = DaemonDiscovery.DiscoverGrpcTarget();
        return string.IsNullOrEmpty(target) ? new AntdGrpcClient() : new AntdGrpcClient(target);
    }

    public void Dispose() => _channel.Dispose();

    private static AntdException Wrap(RpcException ex) => ExceptionMapping.FromGrpcStatus(ex);

    // ── Health ──

    public async Task<HealthStatus> HealthAsync()
    {
        try
        {
            var resp = await _health.CheckAsync(new HealthCheckRequest());
            return new HealthStatus(resp.Status == "ok", resp.Network ?? "unknown");
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.Unavailable)
        {
            return new HealthStatus(false, "unknown");
        }
        catch (RpcException)
        {
            return new HealthStatus(true, "unknown"); // server responded — it's reachable
        }
        catch
        {
            return new HealthStatus(false, "unknown");
        }
    }

    // ── Data ──

    public async Task<PutResult> DataPutPublicAsync(byte[] data, string? paymentMode = null)
    {
        try
        {
            var resp = await _data.PutPublicAsync(new PutPublicDataRequest { Data = ByteString.CopyFrom(data) });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> DataGetPublicAsync(string address)
    {
        try
        {
            var resp = await _data.GetPublicAsync(new GetPublicDataRequest { Address = address });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<PutResult> DataPutPrivateAsync(byte[] data, string? paymentMode = null)
    {
        try
        {
            var resp = await _data.PutPrivateAsync(new PutPrivateDataRequest { Data = ByteString.CopyFrom(data) });
            return new PutResult(resp.Cost.AttoTokens, resp.DataMap);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> DataGetPrivateAsync(string dataMap)
    {
        try
        {
            var resp = await _data.GetPrivateAsync(new GetPrivateDataRequest { DataMap = dataMap });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> DataCostAsync(byte[] data)
    {
        try
        {
            var resp = await _data.GetCostAsync(new DataCostRequest { Data = ByteString.CopyFrom(data) });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Chunks ──

    public async Task<PutResult> ChunkPutAsync(byte[] data)
    {
        try
        {
            var resp = await _chunks.PutAsync(new PutChunkRequest { Data = ByteString.CopyFrom(data) });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<byte[]> ChunkGetAsync(string address)
    {
        try
        {
            var resp = await _chunks.GetAsync(new GetChunkRequest { Address = address });
            return resp.Data.ToByteArray();
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Files ──

    public async Task<PutResult> FileUploadPublicAsync(string path, string? paymentMode = null)
    {
        try
        {
            var resp = await _files.UploadPublicAsync(new UploadFileRequest { Path = path });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task FileDownloadPublicAsync(string address, string destPath)
    {
        try
        {
            await _files.DownloadPublicAsync(new DownloadPublicRequest { Address = address, DestPath = destPath });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<PutResult> DirUploadPublicAsync(string path, string? paymentMode = null)
    {
        try
        {
            var resp = await _files.DirUploadPublicAsync(new UploadFileRequest { Path = path });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task DirDownloadPublicAsync(string address, string destPath)
    {
        try
        {
            await _files.DirDownloadPublicAsync(new DownloadPublicRequest { Address = address, DestPath = destPath });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<Archive> ArchiveGetPublicAsync(string address)
    {
        try
        {
            var resp = await _files.ArchiveGetPublicAsync(new ArchiveGetRequest { Address = address });
            var entries = resp.Entries.Select(e => new ArchiveEntry(e.Path, e.Address, e.Created, e.Modified, e.Size)).ToList();
            return new Archive(entries);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<PutResult> ArchivePutPublicAsync(Archive archive)
    {
        try
        {
            var req = new ArchivePutRequest();
            req.Entries.AddRange(archive.Entries.Select(e => new Antd.V1.ArchiveEntry
            {
                Path = e.Path,
                Address = e.Address,
                Created = e.Created,
                Modified = e.Modified,
                Size = e.Size,
            }));
            var resp = await _files.ArchivePutPublicAsync(req);
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> FileCostAsync(string path, bool isPublic = true, bool includeArchive = false)
    {
        try
        {
            var resp = await _files.GetFileCostAsync(new Antd.V1.FileCostRequest
            {
                Path = path,
                IsPublic = isPublic,
                IncludeArchive = includeArchive,
            });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }
}
