namespace Antd.Sdk;

/// <summary>Health check result from the antd daemon.</summary>
public sealed record HealthStatus(bool Ok, string Network);

/// <summary>Result of a put/create operation that stores data on the network.</summary>
public sealed record PutResult(string Cost, string Address);

/// <summary>A descendant entry in a graph node.</summary>
public sealed record GraphDescendant(string PublicKey, string Content);

/// <summary>A graph entry retrieved from the network.</summary>
public sealed record GraphEntry(string Owner, List<string> Parents, string Content, List<GraphDescendant> Descendants);

/// <summary>A single entry in an archive manifest.</summary>
public sealed record ArchiveEntry(string Path, string Address, ulong Created, ulong Modified, ulong Size);

/// <summary>An archive manifest containing file entries.</summary>
public sealed record Archive(List<ArchiveEntry> Entries);

/// <summary>Wallet address from the antd daemon.</summary>
public sealed record WalletAddress(string Address);

/// <summary>Wallet balance from the antd daemon.</summary>
public sealed record WalletBalance(string Balance, string GasBalance);
