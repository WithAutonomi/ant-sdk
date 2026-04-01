namespace Antd.Sdk;

/// <summary>Health check result from the antd daemon.</summary>
public sealed record HealthStatus(bool Ok, string Network);

/// <summary>Result of a put/create operation that stores data on the network.</summary>
public sealed record PutResult(string Cost, string Address);

/// <summary>Wallet address from the antd daemon.</summary>
public sealed record WalletAddress(string Address);

/// <summary>Wallet balance from the antd daemon.</summary>
public sealed record WalletBalance(string Balance, string GasBalance);

/// <summary>A single payment required for an upload.</summary>
public sealed record PaymentInfo(string QuoteHash, string RewardsAddress, string Amount);

/// <summary>Result of preparing an upload for external signing.</summary>
public sealed record PrepareUploadResult(
    string UploadId,
    List<PaymentInfo> Payments,
    string TotalAmount,
    string DataPaymentsAddress,
    string PaymentTokenAddress,
    string RpcUrl);

/// <summary>Result of finalizing an externally-signed upload.</summary>
public sealed record FinalizeUploadResult(string Address, long ChunksStored);
