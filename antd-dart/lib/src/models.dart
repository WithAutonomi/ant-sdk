/// HealthStatus is the result of a health check.
class HealthStatus {
  /// Whether the daemon is healthy.
  final bool ok;

  /// The network the daemon is connected to.
  final String network;

  const HealthStatus({required this.ok, required this.network});

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      ok: json['status'] == 'ok',
      network: json['network'] as String? ?? '',
    );
  }

  @override
  String toString() => 'HealthStatus(ok: $ok, network: $network)';
}

/// PutResult is the result of a put/create operation.
class PutResult {
  /// Cost in atto tokens as a string.
  final String cost;

  /// The hex address of the stored data.
  final String address;

  const PutResult({required this.cost, required this.address});

  factory PutResult.fromJson(Map<String, dynamic> json,
      {String addressKey = 'address'}) {
    return PutResult(
      cost: json['cost'] as String? ?? '',
      address: json[addressKey] as String? ?? '',
    );
  }

  @override
  String toString() => 'PutResult(cost: $cost, address: $address)';
}

/// GraphDescendant is a descendant entry in a graph node.
class GraphDescendant {
  /// The public key in hex.
  final String publicKey;

  /// The content in hex (32 bytes).
  final String content;

  const GraphDescendant({required this.publicKey, required this.content});

  factory GraphDescendant.fromJson(Map<String, dynamic> json) {
    return GraphDescendant(
      publicKey: json['public_key'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'public_key': publicKey,
        'content': content,
      };

  @override
  String toString() =>
      'GraphDescendant(publicKey: $publicKey, content: $content)';
}

/// GraphEntry is a DAG node from the network.
class GraphEntry {
  /// The owner public key.
  final String owner;

  /// Parent addresses.
  final List<String> parents;

  /// The content hash.
  final String content;

  /// Descendant entries.
  final List<GraphDescendant> descendants;

  const GraphEntry({
    required this.owner,
    required this.parents,
    required this.content,
    required this.descendants,
  });

  factory GraphEntry.fromJson(Map<String, dynamic> json) {
    return GraphEntry(
      owner: json['owner'] as String? ?? '',
      parents: (json['parents'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      content: json['content'] as String? ?? '',
      descendants: (json['descendants'] as List<dynamic>?)
              ?.map((e) =>
                  GraphDescendant.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  @override
  String toString() =>
      'GraphEntry(owner: $owner, parents: $parents, content: $content, descendants: $descendants)';
}

/// ArchiveEntry is a single entry in a file archive.
class ArchiveEntry {
  /// The file path within the archive.
  final String path;

  /// The hex address of the file data.
  final String address;

  /// Creation timestamp (Unix epoch).
  final int created;

  /// Modification timestamp (Unix epoch).
  final int modified;

  /// File size in bytes.
  final int size;

  const ArchiveEntry({
    required this.path,
    required this.address,
    required this.created,
    required this.modified,
    required this.size,
  });

  factory ArchiveEntry.fromJson(Map<String, dynamic> json) {
    return ArchiveEntry(
      path: json['path'] as String? ?? '',
      address: json['address'] as String? ?? '',
      created: (json['created'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'address': address,
        'created': created,
        'modified': modified,
        'size': size,
      };

  @override
  String toString() =>
      'ArchiveEntry(path: $path, address: $address, created: $created, modified: $modified, size: $size)';
}

/// Archive is a collection of archive entries.
class Archive {
  /// The entries in this archive.
  final List<ArchiveEntry> entries;

  const Archive({required this.entries});

  factory Archive.fromJson(Map<String, dynamic> json) {
    return Archive(
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => ArchiveEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  @override
  String toString() => 'Archive(entries: $entries)';
}
