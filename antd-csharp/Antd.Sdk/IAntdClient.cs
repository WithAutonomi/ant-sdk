namespace Antd.Sdk;

public interface IAntdClient : IDisposable
{
    // Health
    Task<HealthStatus> HealthAsync();

    // Data
    Task<PutResult> DataPutPublicAsync(byte[] data);
    Task<byte[]> DataGetPublicAsync(string address);
    Task<PutResult> DataPutPrivateAsync(byte[] data);
    Task<byte[]> DataGetPrivateAsync(string dataMap);
    Task<string> DataCostAsync(byte[] data);

    // Chunks
    Task<PutResult> ChunkPutAsync(byte[] data);
    Task<byte[]> ChunkGetAsync(string address);

    // Pointers
    Task<PutResult> PointerCreateAsync(string ownerSecretKey, PointerTarget target);
    Task<Pointer> PointerGetAsync(string address);
    Task<bool> PointerExistsAsync(string address);
    Task PointerUpdateAsync(string ownerSecretKey, PointerTarget target);
    Task<string> PointerCostAsync(string publicKey);

    // Scratchpads
    Task<PutResult> ScratchpadCreateAsync(string ownerSecretKey, ulong contentType, byte[] data);
    Task<ScratchpadRecord> ScratchpadGetAsync(string address);
    Task<bool> ScratchpadExistsAsync(string address);
    Task ScratchpadUpdateAsync(string ownerSecretKey, ulong contentType, byte[] data);
    Task<string> ScratchpadCostAsync(string publicKey);

    // Graph
    Task<PutResult> GraphEntryPutAsync(string ownerSecretKey, List<string> parents, string content, List<GraphDescendant> descendants);
    Task<GraphEntry> GraphEntryGetAsync(string address);
    Task<bool> GraphEntryExistsAsync(string address);
    Task<string> GraphEntryCostAsync(string publicKey);

    // Registers
    Task<PutResult> RegisterCreateAsync(string ownerSecretKey, string initialValue);
    Task<Register> RegisterGetAsync(string address);
    Task<PutResult> RegisterUpdateAsync(string ownerSecretKey, string newValue);
    Task<string> RegisterCostAsync(string publicKey);

    // Vaults
    Task<Vault> VaultGetAsync(string secretKey);
    Task<string> VaultPutAsync(string secretKey, byte[] data, ulong contentType);
    Task<string> VaultCostAsync(string secretKey, ulong maxSize);

    // Files
    Task<PutResult> FileUploadPublicAsync(string path);
    Task FileDownloadPublicAsync(string address, string destPath);
    Task<PutResult> DirUploadPublicAsync(string path);
    Task DirDownloadPublicAsync(string address, string destPath);
    Task<Archive> ArchiveGetPublicAsync(string address);
    Task<PutResult> ArchivePutPublicAsync(Archive archive);
    Task<string> FileCostAsync(string path, bool isPublic = true, bool includeArchive = false);
}
