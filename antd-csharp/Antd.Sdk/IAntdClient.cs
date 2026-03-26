namespace Antd.Sdk;

public interface IAntdClient : IDisposable
{
    // Health
    Task<HealthStatus> HealthAsync();

    // Data
    Task<PutResult> DataPutPublicAsync(byte[] data, string? paymentMode = null);
    Task<byte[]> DataGetPublicAsync(string address);
    Task<PutResult> DataPutPrivateAsync(byte[] data, string? paymentMode = null);
    Task<byte[]> DataGetPrivateAsync(string dataMap);
    Task<string> DataCostAsync(byte[] data);

    // Chunks
    Task<PutResult> ChunkPutAsync(byte[] data);
    Task<byte[]> ChunkGetAsync(string address);

    // Graph
    Task<PutResult> GraphEntryPutAsync(string ownerSecretKey, List<string> parents, string content, List<GraphDescendant> descendants);
    Task<GraphEntry> GraphEntryGetAsync(string address);
    Task<bool> GraphEntryExistsAsync(string address);
    Task<string> GraphEntryCostAsync(string publicKey);

    // Files
    Task<PutResult> FileUploadPublicAsync(string path, string? paymentMode = null);
    Task FileDownloadPublicAsync(string address, string destPath);
    Task<PutResult> DirUploadPublicAsync(string path, string? paymentMode = null);
    Task DirDownloadPublicAsync(string address, string destPath);
    Task<Archive> ArchiveGetPublicAsync(string address);
    Task<PutResult> ArchivePutPublicAsync(Archive archive);
    Task<string> FileCostAsync(string path, bool isPublic = true, bool includeArchive = false);

    // Wallet
    Task<WalletAddress> WalletAddressAsync();
    Task<WalletBalance> WalletBalanceAsync();
}
