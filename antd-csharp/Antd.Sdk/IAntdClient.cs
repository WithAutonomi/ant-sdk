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

    // Files
    Task<FileUploadResult> FileUploadPublicAsync(string path, string? paymentMode = null);
    Task FileDownloadPublicAsync(string address, string destPath);
    Task<FileUploadResult> DirUploadPublicAsync(string path, string? paymentMode = null);
    Task DirDownloadPublicAsync(string address, string destPath);
    Task<string> FileCostAsync(string path, bool isPublic = true);

    // Wallet
    Task<WalletAddress> WalletAddressAsync();
    Task<WalletBalance> WalletBalanceAsync();
    Task<bool> WalletApproveAsync();

    // External Signer (Two-Phase Upload)
    Task<PrepareUploadResult> PrepareUploadAsync(string path);
    Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data);
    Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes);
    Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash);
}
