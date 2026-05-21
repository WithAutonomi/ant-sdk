namespace Antd.Sdk;

/// <summary>
/// Payment-batching strategy for uploads.
///
/// - <see cref="Auto"/>   — server picks (merkle for 64+ chunks, single otherwise).
/// - <see cref="Merkle"/> — force merkle-batch (saves gas, min 2 chunks).
/// - <see cref="Single"/> — force per-chunk payments.
/// </summary>
public enum PaymentMode
{
    Auto,
    Merkle,
    Single,
}

public static class PaymentModeExtensions
{
    /// <summary>Serialize a <see cref="PaymentMode"/> to the wire string the daemon expects.</summary>
    public static string ToWire(this PaymentMode mode) => mode switch
    {
        PaymentMode.Auto => "auto",
        PaymentMode.Merkle => "merkle",
        PaymentMode.Single => "single",
        _ => "auto",
    };
}

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

/// <summary>Result of a single-chunk put (used by <c>ChunkPutAsync</c>).</summary>
public sealed record PutResult(string Cost, string Address);

/// <summary>
/// Result of a private data put. The DataMap is returned to the caller;
/// it is NOT stored on-network. REST populates ChunksStored and PaymentModeUsed;
/// the gRPC transport currently leaves them empty.
/// </summary>
public sealed record DataPutResult(
    string DataMap,
    ulong ChunksStored = 0,
    string PaymentModeUsed = "");

/// <summary>
/// Result of a public data put. The DataMap is stored on-network as an extra
/// chunk; Address is the shareable retrieval handle.
/// </summary>
public sealed record DataPutPublicResult(
    string Address,
    ulong ChunksStored = 0,
    string PaymentModeUsed = "");

/// <summary>
/// Result of a private file upload. The DataMap is returned to the caller;
/// it is NOT stored on-network.
/// </summary>
public sealed record FilePutResult(
    string DataMap,
    string StorageCostAtto,
    string GasCostWei,
    ulong ChunksStored,
    string PaymentModeUsed);

/// <summary>
/// Result of a public file upload. The DataMap is stored on-network as an
/// extra chunk; Address is the shareable retrieval handle.
/// </summary>
public sealed record FilePutPublicResult(
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

/// <summary>Result of finalizing an externally-signed wave-batch upload.</summary>
public sealed record FinalizeUploadResult(
    string Address,
    long ChunksStored,
    string DataMap = "",
    string DataMapAddress = "");

/// <summary>Result of finalizing a merkle batch upload.</summary>
public sealed record FinalizeMerkleUploadResult(
    string Address,
    long ChunksStored,
    string DataMap = "",
    string DataMapAddress = "");

/// <summary>Result of preparing a single-chunk external-signer publish.</summary>
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

/// <summary>Pre-upload cost breakdown returned by <c>DataCostAsync</c> and <c>FileCostAsync</c>.</summary>
public sealed record UploadCostEstimate(
    string Cost,
    ulong FileSize,
    uint ChunkCount,
    string EstimatedGasCostWei,
    string PaymentMode);
