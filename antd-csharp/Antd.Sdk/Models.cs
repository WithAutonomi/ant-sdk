namespace Antd.Sdk;

/// <summary>
/// Health check result from the antd daemon.
///
/// The diagnostic fields (<see cref="Version"/>, <see cref="EvmNetwork"/>,
/// <see cref="UptimeSeconds"/>, <see cref="BuildCommit"/>,
/// <see cref="PaymentTokenAddress"/>, <see cref="PaymentVaultAddress"/>) were
/// added in antd 0.4.0. They default to <c>""</c> / <c>0</c> so the record
/// stays constructable from a pre-0.4.0 daemon's response.
/// </summary>
public sealed record HealthStatus(
    bool Ok,
    string Network,
    string Version = "",
    string EvmNetwork = "",
    ulong UptimeSeconds = 0,
    string BuildCommit = "",
    string PaymentTokenAddress = "",
    string PaymentVaultAddress = "");

/// <summary>Result of a put/create operation that stores data on the network.</summary>
public sealed record PutResult(string Cost, string Address);

/// <summary>Result of a public file or directory upload.</summary>
public sealed record FileUploadResult(
    string Address,
    string StorageCostAtto,
    string GasCostWei,
    ulong ChunksStored,
    string PaymentModeUsed);

/// <summary>Wallet address from the antd daemon.</summary>
public sealed record WalletAddress(string Address);

/// <summary>Wallet balance from the antd daemon.</summary>
public sealed record WalletBalance(string Balance, string GasBalance);

/// <summary>A single payment required for an upload.</summary>
public sealed record PaymentInfo(string QuoteHash, string RewardsAddress, string Amount);

/// <summary>A candidate node entry within a merkle pool commitment.</summary>
public sealed record CandidateNodeEntry(string RewardsAddress, string Amount);

/// <summary>A pool commitment entry containing candidates for merkle batch payments.</summary>
public sealed record PoolCommitmentEntry(string PoolHash, List<CandidateNodeEntry> Candidates);

/// <summary>Result of preparing an upload for external signing.</summary>
public sealed record PrepareUploadResult(
    string UploadId,
    List<PaymentInfo> Payments,
    string TotalAmount,
    string PaymentVaultAddress,
    string PaymentTokenAddress,
    string RpcUrl,
    string PaymentType = "wave_batch",
    int? Depth = null,
    List<PoolCommitmentEntry>? PoolCommitments = null,
    long? MerklePaymentTimestamp = null);

/// <summary>
/// Result of finalizing an externally-signed wave-batch upload.
///
/// <see cref="DataMap"/> is the hex-encoded serialized DataMap and is always
/// populated. <see cref="DataMapAddress"/> is set only when prepare was called
/// with <c>visibility="public"</c> — the DataMap chunk was bundled into the
/// same external-signer payment batch and stored on-network, and the address
/// is the shareable retrieval handle. Pre-0.6.1 daemons that don't emit this
/// field leave it as <c>""</c>.
/// </summary>
public sealed record FinalizeUploadResult(
    string Address,
    long ChunksStored,
    string DataMap = "",
    string DataMapAddress = "");

/// <summary>
/// Result of finalizing a merkle batch upload.
///
/// See <see cref="FinalizeUploadResult"/> for the meaning of <see cref="DataMap"/>
/// and <see cref="DataMapAddress"/>.
/// </summary>
public sealed record FinalizeMerkleUploadResult(
    string Address,
    long ChunksStored,
    string DataMap = "",
    string DataMapAddress = "");

/// <summary>
/// Result of preparing a single-chunk external-signer publish via
/// <c>POST /v1/chunks/prepare</c>.
///
/// When <see cref="AlreadyStored"/> is <c>true</c> the chunk is already on
/// the network — only <see cref="Address"/> and <see cref="AlreadyStored"/>
/// are meaningful, and no finalize call is needed. Otherwise the wave-batch
/// payment fields describe what the external signer must submit before
/// calling <c>FinalizeChunkUploadAsync</c>.
/// </summary>
public sealed record PrepareChunkResult(
    string Address,
    bool AlreadyStored = false,
    string UploadId = "",
    string PaymentType = "",
    List<PaymentInfo>? Payments = null,
    string TotalAmount = "",
    string PaymentVaultAddress = "",
    string PaymentTokenAddress = "",
    string RpcUrl = "");

/// <summary>
/// Pre-upload cost breakdown returned by <c>DataCostAsync</c> and <c>FileCostAsync</c>.
///
/// The server samples up to 5 chunk addresses and extrapolates the storage cost.
/// Gas is an advisory heuristic, not a live gas-oracle query.
/// </summary>
public sealed record UploadCostEstimate(
    string Cost,
    ulong FileSize,
    uint ChunkCount,
    string EstimatedGasCostWei,
    string PaymentMode);
