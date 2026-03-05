namespace Antd.Sdk;

/// <summary>Health check result from the antd daemon.</summary>
public sealed record HealthStatus(bool Ok, string Network);

/// <summary>Result of a put/create operation that stores data on the network.</summary>
public sealed record PutResult(string Cost, string Address);

/// <summary>Target of a pointer — identifies both the kind and address of the target.</summary>
public sealed record PointerTarget(string Kind, string Address);

/// <summary>A pointer record retrieved from the network.</summary>
public sealed record Pointer(string Address, string Owner, ulong Counter, PointerTarget Target);

/// <summary>A scratchpad record retrieved from the network.</summary>
public sealed record ScratchpadRecord(string Address, ulong DataEncoding, byte[] Data, ulong Counter);

/// <summary>A descendant entry in a graph node.</summary>
public sealed record GraphDescendant(string PublicKey, string Content);

/// <summary>A graph entry retrieved from the network.</summary>
public sealed record GraphEntry(string Owner, List<string> Parents, string Content, List<GraphDescendant> Descendants);

/// <summary>A register value retrieved from the network.</summary>
public sealed record Register(string Value);

/// <summary>A vault record retrieved from the network.</summary>
public sealed record Vault(byte[] Data, ulong ContentType);

/// <summary>A single entry in an archive manifest.</summary>
public sealed record ArchiveEntry(string Path, string Address, ulong Created, ulong Modified, ulong Size);

/// <summary>An archive manifest containing file entries.</summary>
public sealed record Archive(List<ArchiveEntry> Entries);
