namespace Antd.Sdk;

/// <summary>
/// Common interface for both REST (<see cref="AntdRestClient"/>) and gRPC
/// (<see cref="AntdGrpcClient"/>) antd clients.
/// </summary>
public partial interface IAntdClient : IDisposable, IAsyncDisposable
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
    /// When <see cref="PartialUploadException.RetentionKnown"/> is
    /// <c>true</c> but <c>Retryable</c> is <c>false</c>, the daemon kept
    /// nothing: re-prepare the same content. When <c>RetentionKnown</c> is
    /// <c>false</c> (an older daemon over REST, or an error the SDK could
    /// not fully read), the daemon may still hold the paid attempt: stop, keep
    /// <paramref name="uploadId"/> and <paramref name="txHashes"/>, and
    /// reconcile before re-preparing or paying again. See
    /// docs/external-signer-flow.md, section 6.
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
    /// shrinking as stuck. When
    /// <see cref="PartialUploadException.RetentionKnown"/> is <c>true</c> but
    /// <c>Retryable</c> is <c>false</c>, the daemon kept nothing: re-prepare
    /// the same content, which skips already-stored chunks so the retry pays
    /// only for the remainder. When <c>RetentionKnown</c> is <c>false</c> (a
    /// daemon before antd 0.14.0 over REST, or an error the SDK could not
    /// fully read),
    /// retention is unknown and the daemon may still hold the paid attempt:
    /// stop, keep <paramref name="uploadId"/> and <paramref name="txHashes"/>,
    /// and reconcile before re-preparing or paying again. See
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
    /// arguments, bounding the loop. When
    /// <see cref="PartialUploadException.RetentionKnown"/> is <c>true</c> but
    /// <c>Retryable</c> is <c>false</c> (a finalize that deliberately left
    /// sub-batches unpaid), the daemon kept nothing: re-prepare the same
    /// content to retry only the remainder. When <c>RetentionKnown</c> is
    /// <c>false</c>, retention is unknown and the daemon may still hold the
    /// paid attempt: stop, keep <paramref name="uploadId"/> and the payment
    /// artefacts, and reconcile before re-preparing or paying again. See
    /// docs/external-signer-flow.md, section 6.
    /// </exception>
    Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash);

    // Pointers (antd with the pointer API, after 0.15.0).
    //
    // Every write (create, update, transfer, finalize) pays, about the price
    // of one chunk, and every attempt pays again: the SDK never retries them,
    // and callers should not retry them automatically either. Reads are free
    // to retry. Counters are ulong; a final state sits at ulong.MaxValue.
    //
    // These have default implementations that throw NotSupportedException, so
    // a class that implements IAntdClient outside this package keeps
    // compiling; AntdRestClient and AntdGrpcClient implement them all.

    /// <summary>
    /// The addresses of the pointers this daemon holds owner keys for (loaded
    /// with <c>antd --pointer-keys</c>). Only these can be written.
    /// </summary>
    Task<List<string>> PointerKeysAsync() =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// Create the pointer at <paramref name="owner"/>, pointing at
    /// <paramref name="target"/>, paid by the daemon wallet. Pays once; do not
    /// retry automatically.
    /// </summary>
    /// <exception cref="AlreadyExistsException">
    /// gRPC: the pointer exists, refused before paying. Over REST that 409
    /// (<c>code: "ALREADY_EXISTS"</c>) is a <see cref="ForkException"/>, as
    /// every other REST 409 without a pointer code has always been.
    /// </exception>
    Task<PointerWriteResult> PointerCreateAsync(string owner, string target, PointerKind kind = PointerKind.Chunk) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// Point the pointer at <paramref name="owner"/> at
    /// <paramref name="target"/>, paid by the daemon wallet, creating it if it
    /// does not exist. Pays once; do not retry automatically.
    /// </summary>
    /// <exception cref="PointerFinalException">The pointer was handed over or frozen; refused before paying.</exception>
    /// <exception cref="ConflictException">A prepared write to the pointer awaits payment.</exception>
    Task<PointerWriteResult> PointerUpdateAsync(string owner, string target, PointerKind kind = PointerKind.Chunk) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// Hand the pointer at <paramref name="owner"/> over to the pointer at
    /// <paramref name="recipient"/> for good, paid by the daemon wallet.
    /// Readers of the owner's address are redirected to the recipient's
    /// pointer, which only its owner can move. Irreversible once stored. Pays
    /// once; do not retry automatically. Check
    /// <see cref="PointerTransferResult.Finality"/> (or
    /// <see cref="PointerFinalityAsync"/>) before relying on it.
    /// </summary>
    /// <exception cref="PointerFinalException">The pointer is already final; refused before paying.</exception>
    /// <exception cref="BadRequestException">The recipient does not exist or leads back; refused before paying.</exception>
    /// <exception cref="CloseGroupShortfallException">Not every peer of the close group answered; refused before paying, free to retry later.</exception>
    Task<PointerTransferResult> PointerTransferAsync(string owner, string recipient) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>Read the pointer at <paramref name="address"/>.</summary>
    /// <exception cref="NotFoundException">No pointer exists there.</exception>
    Task<PointerRecord> PointerGetAsync(string address) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// Follow a chain of pointers (forwardings and transfers, at most 16 hops)
    /// from <paramref name="address"/> to the target at its end.
    /// </summary>
    /// <exception cref="NotFoundException">A pointer on the chain does not exist.</exception>
    Task<PointerTarget> PointerResolveAsync(string address) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// Ask the whole close group where the pointer at
    /// <paramref name="address"/> stands. Only
    /// <see cref="PointerFinalityStatus.Final"/> means a transfer is beyond
    /// dispute.
    /// </summary>
    Task<PointerFinality> PointerFinalityAsync(string address) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// Follow the transfers from <paramref name="address"/> to the pointer
    /// whose owner now decides what it resolves to.
    /// </summary>
    Task<PointerController> PointerControllerAsync(string address) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// External signer: have the daemon sign a pointer write with its loaded
    /// owner key and quote it. Pay the result's payments with
    /// <c>payForQuotes()</c>, then call <see cref="PointerFinalizeAsync"/>. The
    /// daemon needs no wallet. While the prepared write awaits payment, other
    /// writes to the pointer throw <see cref="ConflictException"/>. Set
    /// <see cref="PointerPrepareRequest.IncludeSignedQuotes"/> to also get the
    /// full signed quotes in <see cref="PointerPrepareResult.SignedQuotes"/>.
    /// </summary>
    Task<PointerPrepareResult> PointerPrepareAsync(PointerPrepareRequest request) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");

    /// <summary>
    /// External signer: store a prepared pointer write once it is paid.
    /// <paramref name="txHashes"/> maps each quote hash from the prepare's
    /// payments to its <c>payForQuotes()</c> transaction hash. It stores the
    /// write the signer paid for: repeat it only on the retryable error below,
    /// never automatically on any other.
    /// </summary>
    /// <exception cref="CloseGroupShortfallException">
    /// The write fell short after payment. When
    /// <see cref="CloseGroupShortfallException.Retryable"/> is <c>true</c> the
    /// daemon kept the paid state: call this again with the same
    /// <paramref name="uploadId"/> (<paramref name="txHashes"/> is then
    /// ignored) to store it against the same payment, bounding the loop; the
    /// session expires with the daemon's one-hour pending TTL.
    /// </exception>
    Task<PointerFinalizeResult> PointerFinalizeAsync(string uploadId, IDictionary<string, string> txHashes) =>
        throw new NotSupportedException("this IAntdClient does not implement pointers");
}
