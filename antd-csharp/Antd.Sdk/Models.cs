namespace Antd.Sdk;

/// <summary>Health check result from the antd daemon.</summary>
public sealed record HealthStatus(bool Ok, string Network);

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

/// <summary>Result of finalizing an externally-signed upload.</summary>
public sealed record FinalizeUploadResult(string Address, long ChunksStored);

/// <summary>Result of finalizing a merkle batch upload.</summary>
public sealed record FinalizeMerkleUploadResult(string Address, long ChunksStored);
