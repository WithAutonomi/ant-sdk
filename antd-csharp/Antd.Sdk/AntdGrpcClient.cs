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
    private readonly PointerService.PointerServiceClient _pointers;
    private readonly ScratchpadService.ScratchpadServiceClient _scratchpads;
    private readonly GraphService.GraphServiceClient _graph;
    private readonly RegisterService.RegisterServiceClient _registers;
    private readonly VaultService.VaultServiceClient _vaults;
    private readonly FileService.FileServiceClient _files;

    public AntdGrpcClient(string target = "http://localhost:50051")
    {
        _channel = GrpcChannel.ForAddress(target);
        _health = new HealthService.HealthServiceClient(_channel);
        _data = new DataService.DataServiceClient(_channel);
        _chunks = new ChunkService.ChunkServiceClient(_channel);
        _pointers = new PointerService.PointerServiceClient(_channel);
        _scratchpads = new ScratchpadService.ScratchpadServiceClient(_channel);
        _graph = new GraphService.GraphServiceClient(_channel);
        _registers = new RegisterService.RegisterServiceClient(_channel);
        _vaults = new VaultService.VaultServiceClient(_channel);
        _files = new FileService.FileServiceClient(_channel);
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

    public async Task<PutResult> DataPutPublicAsync(byte[] data)
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

    public async Task<PutResult> DataPutPrivateAsync(byte[] data)
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

    // ── Pointers ──

    public async Task<PutResult> PointerCreateAsync(string ownerSecretKey, PointerTarget target)
    {
        try
        {
            var resp = await _pointers.CreateAsync(new CreatePointerRequest
            {
                OwnerSecretKey = ownerSecretKey,
                Target = new Antd.V1.PointerTarget { Kind = target.Kind, Address = target.Address },
            });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<Pointer> PointerGetAsync(string address)
    {
        try
        {
            var resp = await _pointers.GetAsync(new GetPointerRequest { Address = address });
            return new Pointer(resp.Address, resp.Owner, resp.Counter,
                new PointerTarget(resp.Target.Kind, resp.Target.Address));
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<bool> PointerExistsAsync(string address)
    {
        try
        {
            var resp = await _pointers.CheckExistenceAsync(new CheckPointerRequest { Address = address });
            return resp.Exists;
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.NotFound)
        {
            return false;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task PointerUpdateAsync(string ownerSecretKey, PointerTarget target)
    {
        try
        {
            await _pointers.UpdateAsync(new UpdatePointerRequest
            {
                OwnerSecretKey = ownerSecretKey,
                Target = new Antd.V1.PointerTarget { Kind = target.Kind, Address = target.Address },
            });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> PointerCostAsync(string publicKey)
    {
        try
        {
            var resp = await _pointers.GetCostAsync(new PointerCostRequest { PublicKey = publicKey });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Scratchpads ──

    public async Task<PutResult> ScratchpadCreateAsync(string ownerSecretKey, ulong contentType, byte[] data)
    {
        try
        {
            var resp = await _scratchpads.CreateAsync(new CreateScratchpadRequest
            {
                OwnerSecretKey = ownerSecretKey,
                ContentType = contentType,
                Data = ByteString.CopyFrom(data),
            });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<ScratchpadRecord> ScratchpadGetAsync(string address)
    {
        try
        {
            var resp = await _scratchpads.GetAsync(new GetScratchpadRequest { Address = address });
            return new ScratchpadRecord(resp.Address, resp.DataEncoding, resp.Data.ToByteArray(), resp.Counter);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<bool> ScratchpadExistsAsync(string address)
    {
        try
        {
            var resp = await _scratchpads.CheckExistenceAsync(new CheckScratchpadRequest { Address = address });
            return resp.Exists;
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.NotFound)
        {
            return false;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task ScratchpadUpdateAsync(string ownerSecretKey, ulong contentType, byte[] data)
    {
        try
        {
            await _scratchpads.UpdateAsync(new UpdateScratchpadRequest
            {
                OwnerSecretKey = ownerSecretKey,
                ContentType = contentType,
                Data = ByteString.CopyFrom(data),
            });
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> ScratchpadCostAsync(string publicKey)
    {
        try
        {
            var resp = await _scratchpads.GetCostAsync(new ScratchpadCostRequest { PublicKey = publicKey });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Graph ──

    public async Task<PutResult> GraphEntryPutAsync(string ownerSecretKey, List<string> parents, string content, List<GraphDescendant> descendants)
    {
        try
        {
            var req = new PutGraphEntryRequest
            {
                OwnerSecretKey = ownerSecretKey,
                Content = content,
            };
            req.Parents.AddRange(parents);
            req.Descendants.AddRange(descendants.Select(d => new Antd.V1.GraphDescendant
            {
                PublicKey = d.PublicKey,
                Content = d.Content,
            }));
            var resp = await _graph.PutAsync(req);
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<GraphEntry> GraphEntryGetAsync(string address)
    {
        try
        {
            var resp = await _graph.GetAsync(new GetGraphEntryRequest { Address = address });
            var descendants = resp.Descendants.Select(d => new GraphDescendant(d.PublicKey, d.Content)).ToList();
            return new GraphEntry(resp.Owner, resp.Parents.ToList(), resp.Content, descendants);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<bool> GraphEntryExistsAsync(string address)
    {
        try
        {
            var resp = await _graph.CheckExistenceAsync(new CheckGraphEntryRequest { Address = address });
            return resp.Exists;
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.NotFound)
        {
            return false;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> GraphEntryCostAsync(string publicKey)
    {
        try
        {
            var resp = await _graph.GetCostAsync(new GraphEntryCostRequest { PublicKey = publicKey });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Registers ──

    public async Task<PutResult> RegisterCreateAsync(string ownerSecretKey, string initialValue)
    {
        try
        {
            var resp = await _registers.CreateAsync(new CreateRegisterRequest
            {
                OwnerSecretKey = ownerSecretKey,
                InitialValue = initialValue,
            });
            return new PutResult(resp.Cost.AttoTokens, resp.Address);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<Register> RegisterGetAsync(string address)
    {
        try
        {
            var resp = await _registers.GetAsync(new GetRegisterRequest { Address = address });
            return new Register(resp.Value);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<PutResult> RegisterUpdateAsync(string ownerSecretKey, string newValue)
    {
        try
        {
            var resp = await _registers.UpdateAsync(new UpdateRegisterRequest
            {
                OwnerSecretKey = ownerSecretKey,
                NewValue = newValue,
            });
            return new PutResult(resp.Cost.AttoTokens, "");
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> RegisterCostAsync(string publicKey)
    {
        try
        {
            var resp = await _registers.GetCostAsync(new RegisterCostRequest { PublicKey = publicKey });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Vaults ──

    public async Task<Vault> VaultGetAsync(string secretKey)
    {
        try
        {
            var resp = await _vaults.GetAsync(new GetVaultRequest { SecretKey = secretKey });
            return new Vault(resp.Data.ToByteArray(), resp.ContentType);
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> VaultPutAsync(string secretKey, byte[] data, ulong contentType)
    {
        try
        {
            var resp = await _vaults.PutAsync(new PutVaultRequest
            {
                SecretKey = secretKey,
                Data = ByteString.CopyFrom(data),
                ContentType = contentType,
            });
            return resp.Cost.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<string> VaultCostAsync(string secretKey, ulong maxSize)
    {
        try
        {
            var resp = await _vaults.GetCostAsync(new VaultCostRequest
            {
                SecretKey = secretKey,
                MaxSize = maxSize,
            });
            return resp.AttoTokens;
        }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    // ── Files ──

    public async Task<PutResult> FileUploadPublicAsync(string path)
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

    public async Task<PutResult> DirUploadPublicAsync(string path)
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
