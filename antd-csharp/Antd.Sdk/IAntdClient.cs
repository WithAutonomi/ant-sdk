namespace Antd.Sdk;

/// <summary>
/// Common interface for both REST (<see cref="AntdRestClient"/>) and gRPC
/// (<see cref="AntdGrpcClient"/>) antd clients.
/// </summary>
public interface IAntdClient : IDisposable, IAsyncDisposable
{
    // Health
    Task<HealthStatus> HealthAsync();

    // Data
    Task<DataPutPublicResult> DataPutPublicAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto);
    Task<byte[]> DataGetPublicAsync(string address);
    Task<DataPutResult> DataPutAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto);
    Task<byte[]> DataGetAsync(string dataMap);
    Task<UploadCostEstimate> DataCostAsync(byte[] data, PaymentMode paymentMode = PaymentMode.Auto);

    // Chunks
    Task<PutResult> ChunkPutAsync(byte[] data);
    Task<byte[]> ChunkGetAsync(string address);
    Task<PrepareChunkResult> PrepareChunkUploadAsync(byte[] data);
    Task<string> FinalizeChunkUploadAsync(string uploadId, IDictionary<string, string> txHashes);

    // Files
    Task<FilePutResult> FilePutAsync(string path, PaymentMode paymentMode = PaymentMode.Auto);
    Task FileGetAsync(string dataMap, string destPath);
    Task<FilePutPublicResult> FilePutPublicAsync(string path, PaymentMode paymentMode = PaymentMode.Auto);
    Task FileGetPublicAsync(string address, string destPath);
    Task<UploadCostEstimate> FileCostAsync(string path, bool isPublic = true, PaymentMode paymentMode = PaymentMode.Auto);

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
