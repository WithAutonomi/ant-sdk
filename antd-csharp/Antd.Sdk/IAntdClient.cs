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

    /// <summary>
    /// Finalize a single-chunk external-signer upload prepared by
    /// <see cref="PrepareChunkUploadAsync"/>: hand the daemon the quote-hash
    /// to tx-hash map and let it store the chunk against that payment.
    /// </summary>
    /// <exception cref="PartialUploadException">
    /// The chunk stayed unstored after the payment settled. When
    /// <see cref="PartialUploadException.Retryable"/> is <c>true</c> (antd
    /// 0.14.0 and later) the paid attempt is retained under the same
    /// <paramref name="uploadId"/>: call this method again with the same
    /// arguments to store it against the same payment, bounding the loop.
    /// When <c>false</c>, re-prepare the same content; already-stored chunks
    /// are skipped. See docs/external-signer-flow.md, section 6.
    /// </exception>
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

    /// <summary>
    /// Finalize a wave-batch external-signer upload prepared by
    /// <see cref="PrepareUploadAsync"/> / <see cref="PrepareDataUploadAsync"/>:
    /// hand the daemon the quote-hash to tx-hash map and let it store every
    /// chunk against that payment.
    /// </summary>
    /// <exception cref="PartialUploadException">
    /// Some chunks stored but others stayed unstored after the payment
    /// settled (HTTP 502 <c>PARTIAL_UPLOAD</c> / gRPC <c>ABORTED</c>). The
    /// on-chain payment persists and the stored chunks stay on the network.
    /// When <see cref="PartialUploadException.Retryable"/> is <c>true</c>
    /// (antd 0.14.0 and later) the daemon kept the paid attempt under the
    /// same <paramref name="uploadId"/>: call this method again with the same
    /// arguments to store the remainder against the same payment, with no
    /// re-prepare, no second signature and no double payment. Bound that
    /// loop: cap the attempts and treat a
    /// <see cref="PartialUploadException.ChunksFailed"/> that stops
    /// shrinking as stuck. When <c>false</c> (older daemon) nothing was
    /// retained: re-prepare the same content, which skips already-stored
    /// chunks so the retry pays only for the remainder. See
    /// docs/external-signer-flow.md, section 6.
    /// </exception>
    Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes);

    /// <summary>
    /// Finalize a merkle external-signer upload prepared with
    /// <c>payment_type == "merkle"</c>, naming the pool the signer paid.
    /// </summary>
    /// <exception cref="PartialUploadException">
    /// Some chunks stored but others stayed unstored after the payment
    /// settled. When <see cref="PartialUploadException.Retryable"/> is
    /// <c>true</c> the daemon kept the paid attempt under the same
    /// <paramref name="uploadId"/>: call this method again with the same
    /// arguments, bounding the loop. When <c>false</c> (a finalize that
    /// deliberately left sub-batches unpaid, or an older daemon) nothing was
    /// retained: re-prepare the same content to retry only the remainder.
    /// See docs/external-signer-flow.md, section 6.
    /// </exception>
    Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash);
}
