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
    Task<UploadCostEstimate> DataCostAsync(byte[] data);

    // Chunks
    Task<PutResult> ChunkPutAsync(byte[] data);
    Task<byte[]> ChunkGetAsync(string address);
    Task<PrepareChunkResult> PrepareChunkUploadAsync(byte[] data);
    Task<string> FinalizeChunkUploadAsync(string uploadId, IDictionary<string, string> txHashes);

    // Files
    Task<FileUploadResult> FileUploadPublicAsync(string path, string? paymentMode = null);
    Task FileDownloadPublicAsync(string address, string destPath);
    Task<UploadCostEstimate> FileCostAsync(string path, bool isPublic = true);

    // Wallet
    Task<WalletAddress> WalletAddressAsync();
    Task<WalletBalance> WalletBalanceAsync();
    Task<bool> WalletApproveAsync();

    // External Signer (Two-Phase Upload)
    Task<PrepareUploadResult> PrepareUploadAsync(string path, string? visibility = null);
    Task<PrepareUploadResult> PrepareUploadPublicAsync(string path);
    Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data, string? visibility = null);
    Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes);
    Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash);
}
