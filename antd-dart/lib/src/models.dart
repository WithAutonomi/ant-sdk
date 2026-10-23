import 'errors.dart';

/// Payment mode for upload operations.
///
/// Controls how on-chain payments for stored chunks are bundled. [auto] is
/// the recommended default — the daemon picks [merkle] for large uploads
/// and [single] for small ones based on chunk count. Library consumers
/// only need to override when they specifically want one transaction shape.
enum PaymentMode {
  /// Let the daemon pick — merkle batch for large uploads, single for small.
  auto('auto'),

  /// One on-chain transaction with a merkle proof covering all chunks.
  /// Requires ≥2 chunks.
  merkle('merkle'),

  /// N transactions, one per chunk. Works for any chunk count, including 1.
  single('single');

  /// The wire representation sent to the daemon (`auto`, `merkle`, `single`).
  final String wire;

  const PaymentMode(this.wire);
}

/// HealthStatus is the result of a health check.
///
/// The diagnostic fields ([version], [evmNetwork], [uptimeSeconds],
/// [buildCommit], [paymentTokenAddress], [paymentVaultAddress]) were added in
/// antd 0.4.0. They default to '' / 0 so the class stays usable when talking
/// to a pre-0.4.0 daemon that doesn't report them.
class HealthStatus {
  /// Whether the daemon is healthy.
  final bool ok;

  /// The network the daemon is connected to.
  final String network;

  /// antd crate version, e.g. "0.4.0". Empty when talking to a pre-0.4.0 daemon.
  final String version;

  /// EVM preset name: "arbitrum-one", "arbitrum-sepolia", "local", "custom".
  final String evmNetwork;

  /// Seconds since the daemon process started.
  final int uptimeSeconds;

  /// Short git SHA captured at build time, "" if unknown.
  final String buildCommit;

  /// Payment token contract address, "" if unconfigured.
  final String paymentTokenAddress;

  /// Payment vault contract address, "" if unconfigured.
  final String paymentVaultAddress;

  const HealthStatus({
    required this.ok,
    required this.network,
    this.version = '',
    this.evmNetwork = '',
    this.uptimeSeconds = 0,
    this.buildCommit = '',
    this.paymentTokenAddress = '',
    this.paymentVaultAddress = '',
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      ok: json['status'] == 'ok',
      network: json['network'] as String? ?? '',
      version: json['version'] as String? ?? '',
      evmNetwork: json['evm_network'] as String? ?? '',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      buildCommit: json['build_commit'] as String? ?? '',
      paymentTokenAddress: json['payment_token_address'] as String? ?? '',
      paymentVaultAddress: json['payment_vault_address'] as String? ?? '',
    );
  }

  @override
  String toString() => 'HealthStatus(ok: $ok, network: $network, '
      'version: $version, evmNetwork: $evmNetwork, '
      'uptimeSeconds: $uptimeSeconds, buildCommit: $buildCommit)';
}

/// Result of a single-chunk put ([AntdClient.chunkPut]).
class PutResult {
  /// Cost in atto tokens as a string.
  final String cost;

  /// The hex address of the stored chunk.
  final String address;

  const PutResult({required this.cost, required this.address});

  factory PutResult.fromJson(Map<String, dynamic> json) {
    return PutResult(
      cost: json['cost'] as String? ?? '',
      address: json['address'] as String? ?? '',
    );
  }

  @override
  String toString() => 'PutResult(cost: $cost, address: $address)';
}

/// Result of a private data put ([AntdClient.dataPut]).
///
/// The DataMap is returned to the caller; it is NOT stored on-network — the
/// caller keeps it as the only retrieval handle.
class DataPutResult {
  /// Hex-encoded DataMap. Hand this back to [AntdClient.dataGet] to retrieve.
  final String dataMap;

  /// Number of chunks stored on the network.
  final int chunksStored;

  /// Payment mode actually used by the daemon: `auto`, `merkle`, or `single`.
  final String paymentModeUsed;

  /// The plaintext's SHA-256, lowercase hex (64 characters). `null` on a
  /// daemon older than antd 0.17.0, which does not report it.
  final String? sha256;

  const DataPutResult({
    required this.dataMap,
    this.chunksStored = 0,
    this.paymentModeUsed = '',
    this.sha256,
  });

  factory DataPutResult.fromJson(Map<String, dynamic> json) {
    return DataPutResult(
      dataMap: json['data_map'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
      paymentModeUsed: json['payment_mode_used'] as String? ?? '',
      sha256: _optionalString(json['sha256']),
    );
  }

  @override
  String toString() =>
      'DataPutResult(dataMap: $dataMap, chunksStored: $chunksStored, paymentModeUsed: $paymentModeUsed, sha256: $sha256)';
}

/// Result of a public data put ([AntdClient.dataPutPublic]).
///
/// The DataMap is stored on-network as an additional chunk; [address] is the
/// shareable retrieval handle.
class DataPutPublicResult {
  /// Hex address of the on-network DataMap chunk. Shareable.
  final String address;

  /// Number of chunks stored on the network.
  final int chunksStored;

  /// Payment mode actually used by the daemon: `auto`, `merkle`, or `single`.
  final String paymentModeUsed;

  /// The plaintext's SHA-256, lowercase hex (64 characters). `null` on a
  /// daemon older than antd 0.17.0, which does not report it.
  final String? sha256;

  const DataPutPublicResult({
    required this.address,
    this.chunksStored = 0,
    this.paymentModeUsed = '',
    this.sha256,
  });

  factory DataPutPublicResult.fromJson(Map<String, dynamic> json) {
    return DataPutPublicResult(
      address: json['address'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
      paymentModeUsed: json['payment_mode_used'] as String? ?? '',
      sha256: _optionalString(json['sha256']),
    );
  }

  @override
  String toString() =>
      'DataPutPublicResult(address: $address, chunksStored: $chunksStored, paymentModeUsed: $paymentModeUsed, sha256: $sha256)';
}

/// Result of a private file upload ([AntdClient.filePut]).
///
/// The DataMap is returned to the caller; it is NOT stored on-network.
class FilePutResult {
  /// Hex-encoded msgpack-serialized DataMap.
  final String dataMap;

  /// Total storage cost in atto, "0" if all chunks already existed.
  final String storageCostAtto;

  /// Total gas cost in wei as a decimal string.
  final String gasCostWei;

  /// Number of chunks stored on the network.
  final int chunksStored;

  /// Which payment mode was actually used: `auto`, `merkle`, or `single`.
  final String paymentModeUsed;

  /// The plaintext's SHA-256, lowercase hex (64 characters). `null` on a
  /// daemon older than antd 0.17.0, which does not report it.
  final String? sha256;

  const FilePutResult({
    required this.dataMap,
    required this.storageCostAtto,
    required this.gasCostWei,
    required this.chunksStored,
    required this.paymentModeUsed,
    this.sha256,
  });

  factory FilePutResult.fromJson(Map<String, dynamic> json) {
    return FilePutResult(
      dataMap: json['data_map'] as String? ?? '',
      storageCostAtto: json['storage_cost_atto'] as String? ?? '',
      gasCostWei: json['gas_cost_wei'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
      paymentModeUsed: json['payment_mode_used'] as String? ?? '',
      sha256: _optionalString(json['sha256']),
    );
  }

  @override
  String toString() =>
      'FilePutResult(dataMap: $dataMap, storageCostAtto: $storageCostAtto, gasCostWei: $gasCostWei, chunksStored: $chunksStored, paymentModeUsed: $paymentModeUsed, sha256: $sha256)';
}

/// Result of a public file upload ([AntdClient.filePutPublic]).
///
/// The DataMap is stored on-network as an additional chunk; [address] is the
/// shareable retrieval handle.
class FilePutPublicResult {
  /// Hex network address of the stored DataMap.
  final String address;

  /// Total storage cost in atto, "0" if all chunks already existed.
  final String storageCostAtto;

  /// Total gas cost in wei as a decimal string.
  final String gasCostWei;

  /// Number of chunks stored on the network.
  final int chunksStored;

  /// Which payment mode was actually used: `auto`, `merkle`, or `single`.
  final String paymentModeUsed;

  /// The plaintext's SHA-256, lowercase hex (64 characters). `null` on a
  /// daemon older than antd 0.17.0, which does not report it.
  final String? sha256;

  const FilePutPublicResult({
    required this.address,
    required this.storageCostAtto,
    required this.gasCostWei,
    required this.chunksStored,
    required this.paymentModeUsed,
    this.sha256,
  });

  factory FilePutPublicResult.fromJson(Map<String, dynamic> json) {
    return FilePutPublicResult(
      address: json['address'] as String? ?? '',
      storageCostAtto: json['storage_cost_atto'] as String? ?? '',
      gasCostWei: json['gas_cost_wei'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
      paymentModeUsed: json['payment_mode_used'] as String? ?? '',
      sha256: _optionalString(json['sha256']),
    );
  }

  @override
  String toString() =>
      'FilePutPublicResult(address: $address, storageCostAtto: $storageCostAtto, gasCostWei: $gasCostWei, chunksStored: $chunksStored, paymentModeUsed: $paymentModeUsed, sha256: $sha256)';
}

/// WalletAddress is the wallet address response.
class WalletAddress {
  /// The 0x-prefixed hex address.
  final String address;

  const WalletAddress({required this.address});

  factory WalletAddress.fromJson(Map<String, dynamic> json) {
    return WalletAddress(
      address: json['address'] as String? ?? '',
    );
  }

  @override
  String toString() => 'WalletAddress(address: $address)';
}

/// WalletBalance is the wallet balance response.
class WalletBalance {
  /// Token balance in atto tokens as a string.
  final String balance;

  /// Gas balance in atto tokens as a string.
  final String gasBalance;

  const WalletBalance({required this.balance, required this.gasBalance});

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    return WalletBalance(
      balance: json['balance'] as String? ?? '',
      gasBalance: json['gas_balance'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'WalletBalance(balance: $balance, gasBalance: $gasBalance)';
}

/// A single payment required for an upload.
class PaymentInfo {
  final String quoteHash;
  final String rewardsAddress;
  final String amount;

  const PaymentInfo({
    required this.quoteHash,
    required this.rewardsAddress,
    required this.amount,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      quoteHash: json['quote_hash'] as String? ?? '',
      rewardsAddress: json['rewards_address'] as String? ?? '',
      amount: json['amount'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'PaymentInfo(quoteHash: $quoteHash, rewardsAddress: $rewardsAddress, amount: $amount)';
}

/// A candidate node entry within a merkle pool commitment.
class CandidateNodeEntry {
  /// The 0x-prefixed hex rewards address.
  final String rewardsAddress;

  /// Node price as a decimal string (atto tokens).
  final String amount;

  const CandidateNodeEntry({
    required this.rewardsAddress,
    required this.amount,
  });

  factory CandidateNodeEntry.fromJson(Map<String, dynamic> json) {
    return CandidateNodeEntry(
      rewardsAddress: json['rewards_address'] as String? ?? '',
      amount: json['amount'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'CandidateNodeEntry(rewardsAddress: $rewardsAddress, amount: $amount)';
}

/// A pool commitment containing candidate nodes for merkle batch payments.
class PoolCommitmentEntry {
  /// The 0x-prefixed hex pool hash (32 bytes).
  final String poolHash;

  /// Candidate nodes in this pool (exactly 16).
  final List<CandidateNodeEntry> candidates;

  const PoolCommitmentEntry({
    required this.poolHash,
    required this.candidates,
  });

  factory PoolCommitmentEntry.fromJson(Map<String, dynamic> json) {
    return PoolCommitmentEntry(
      poolHash: json['pool_hash'] as String? ?? '',
      candidates: (json['candidates'] as List<dynamic>?)
              ?.map(
                  (e) => CandidateNodeEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  @override
  String toString() =>
      'PoolCommitmentEntry(poolHash: $poolHash, candidates: $candidates)';
}

/// Result of preparing an upload for external signing.
/// [paymentType] is "wave_batch" or "merkle" -- determines which fields are
/// populated and which contract call the external signer must make.
class PrepareUploadResult {
  final String uploadId;
  final List<PaymentInfo> payments;
  final String totalAmount;
  final String paymentVaultAddress;
  final String paymentTokenAddress;
  final String rpcUrl;

  /// "wave_batch" or "merkle".
  final String paymentType;

  /// Merkle tree depth (1-8). Present only when [paymentType] == "merkle".
  final int? depth;

  /// Pool commitments for payForMerkleTree(). Present only when [paymentType] == "merkle".
  final List<PoolCommitmentEntry>? poolCommitments;

  /// Unix-seconds timestamp for the merkle payment. Present only when [paymentType] == "merkle".
  final int? merklePaymentTimestamp;

  /// Total chunks in this upload, including any already on-network. Added in
  /// antd 0.10.0; 0 against older daemons. The external signer pays for
  /// ([totalChunks] - [alreadyStoredCount]) chunks.
  final int totalChunks;

  /// Chunks already stored on-network and excluded from payment + PUT (added in antd 0.10.0).
  final int alreadyStoredCount;

  const PrepareUploadResult({
    required this.uploadId,
    required this.payments,
    required this.totalAmount,
    required this.paymentVaultAddress,
    required this.paymentTokenAddress,
    required this.rpcUrl,
    this.paymentType = 'wave_batch',
    this.depth,
    this.poolCommitments,
    this.merklePaymentTimestamp,
    this.totalChunks = 0,
    this.alreadyStoredCount = 0,
  });

  factory PrepareUploadResult.fromJson(Map<String, dynamic> json) {
    return PrepareUploadResult(
      uploadId: json['upload_id'] as String? ?? '',
      payments: (json['payments'] as List<dynamic>?)
              ?.map((e) => PaymentInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: json['total_amount'] as String? ?? '',
      paymentVaultAddress: json['payment_vault_address'] as String? ?? '',
      paymentTokenAddress: json['payment_token_address'] as String? ?? '',
      rpcUrl: json['rpc_url'] as String? ?? '',
      paymentType: json['payment_type'] as String? ?? 'wave_batch',
      depth: (json['depth'] as num?)?.toInt(),
      poolCommitments: (json['pool_commitments'] as List<dynamic>?)
          ?.map(
              (e) => PoolCommitmentEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      merklePaymentTimestamp:
          (json['merkle_payment_timestamp'] as num?)?.toInt(),
      totalChunks: (json['total_chunks'] as num?)?.toInt() ?? 0,
      alreadyStoredCount: (json['already_stored_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'PrepareUploadResult(uploadId: $uploadId, paymentType: $paymentType, totalAmount: $totalAmount)';
}

/// Result of finalizing an externally-signed upload.
class FinalizeUploadResult {
  /// Legacy: hex address set when `store_data_map=true` was passed (paid by
  /// the daemon wallet). Empty when not requested.
  final String address;

  /// Number of chunks stored on the network.
  final int chunksStored;

  /// Hex-encoded msgpack DataMap (always returned by antd >= 0.6.1).
  final String dataMap;

  /// Hex network address of the DataMap chunk — populated when prepare was
  /// called with `visibility="public"` (the DataMap was bundled into the same
  /// external-signer payment batch). Empty for private uploads.
  final String dataMapAddress;

  /// The plaintext's SHA-256, lowercase hex (64 characters). `null` on a
  /// daemon older than antd 0.17.0, which does not report it.
  final String? sha256;

  const FinalizeUploadResult({
    required this.address,
    required this.chunksStored,
    this.dataMap = '',
    this.dataMapAddress = '',
    this.sha256,
  });

  factory FinalizeUploadResult.fromJson(Map<String, dynamic> json) {
    return FinalizeUploadResult(
      address: json['address'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
      dataMap: json['data_map'] as String? ?? '',
      dataMapAddress: json['data_map_address'] as String? ?? '',
      sha256: _optionalString(json['sha256']),
    );
  }

  @override
  String toString() =>
      'FinalizeUploadResult(address: $address, chunksStored: $chunksStored, dataMap: $dataMap, dataMapAddress: $dataMapAddress, sha256: $sha256)';
}

/// Result of preparing a single-chunk external-signer publish via
/// `POST /v1/chunks/prepare`.
///
/// When [alreadyStored] is true the chunk is already on-network — only
/// [address] is meaningful and no finalize call is needed. Otherwise the
/// wave-batch payment fields describe what the external signer must submit
/// before calling `finalizeChunkUpload`.
class PrepareChunkResult {
  /// Content-addressed BLAKE3 of the chunk bytes (hex, 64 chars). Always set.
  final String address;

  /// True if the chunk is already stored on the network and no payment is
  /// needed.
  final bool alreadyStored;

  /// Opaque identifier to pass back to `finalizeChunkUpload`. Empty when
  /// [alreadyStored] is true.
  final String uploadId;

  /// Always "wave_batch" for single-chunk publishes.
  final String paymentType;

  /// Per-quote payment entries for `payForQuotes()`. Empty when
  /// [alreadyStored] is true.
  final List<PaymentInfo> payments;

  /// Total amount to pay (atto tokens, decimal string).
  final String totalAmount;

  /// Payment vault contract address.
  final String paymentVaultAddress;

  /// Payment token contract address.
  final String paymentTokenAddress;

  /// EVM RPC URL for submitting transactions.
  final String rpcUrl;

  const PrepareChunkResult({
    required this.address,
    this.alreadyStored = false,
    this.uploadId = '',
    this.paymentType = '',
    this.payments = const [],
    this.totalAmount = '',
    this.paymentVaultAddress = '',
    this.paymentTokenAddress = '',
    this.rpcUrl = '',
  });

  factory PrepareChunkResult.fromJson(Map<String, dynamic> json) {
    return PrepareChunkResult(
      address: json['address'] as String? ?? '',
      alreadyStored: json['already_stored'] as bool? ?? false,
      uploadId: json['upload_id'] as String? ?? '',
      paymentType: json['payment_type'] as String? ?? '',
      payments: (json['payments'] as List<dynamic>?)
              ?.map((e) => PaymentInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      totalAmount: json['total_amount'] as String? ?? '',
      paymentVaultAddress: json['payment_vault_address'] as String? ?? '',
      paymentTokenAddress: json['payment_token_address'] as String? ?? '',
      rpcUrl: json['rpc_url'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'PrepareChunkResult(address: $address, alreadyStored: $alreadyStored, uploadId: $uploadId, paymentType: $paymentType, totalAmount: $totalAmount)';
}

/// Pre-upload cost breakdown returned by [AntdClient.dataCost] and
/// [AntdClient.fileCost].
///
/// The server samples up to 5 chunk addresses and extrapolates the storage
/// cost. Gas is an advisory heuristic, not a live gas-oracle query.
class UploadCostEstimate {
  /// Storage cost in atto tokens as a string.
  final String cost;

  /// Original file size in bytes.
  final int fileSize;

  /// Number of data chunks the file would split into.
  final int chunkCount;

  /// Advisory gas cost heuristic in wei as a string.
  final String estimatedGasCostWei;

  /// Payment mode: "auto", "merkle", or "single".
  final String paymentMode;

  const UploadCostEstimate({
    required this.cost,
    required this.fileSize,
    required this.chunkCount,
    required this.estimatedGasCostWei,
    required this.paymentMode,
  });

  factory UploadCostEstimate.fromJson(Map<String, dynamic> json) {
    return UploadCostEstimate(
      cost: json['cost'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      chunkCount: (json['chunk_count'] as num?)?.toInt() ?? 0,
      estimatedGasCostWei: json['estimated_gas_cost_wei'] as String? ?? '',
      paymentMode: json['payment_mode'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'UploadCostEstimate(cost: $cost, fileSize: $fileSize, chunkCount: $chunkCount, estimatedGasCostWei: $estimatedGasCostWei, paymentMode: $paymentMode)';
}

/// A fetch-progress update emitted during a streaming download when progress is
/// requested. Counts are in *chunks*, not bytes — the byte denominator is the
/// download's total size (the `x-content-length` header over gRPC, the leading
/// NDJSON `meta` frame over REST). [total] is 0 while still unknown (mid
/// DataMap-resolution).
///
/// [phase] is one of:
///   * `"resolving_map"` — walking the hierarchical DataMap to learn the count
///   * `"resolved"` — DataMap resolved, [total] now holds the real chunk count
///   * `"fetching"` — fetching data chunks; [fetched]/[total] advance the bar
class DownloadProgress {
  /// One of `"resolving_map"`, `"resolved"`, `"fetching"`.
  final String phase;

  /// Chunks fetched so far in the current phase.
  final int fetched;

  /// Total chunks for the current phase, or 0 if not yet known.
  final int total;

  const DownloadProgress({
    required this.phase,
    required this.fetched,
    required this.total,
  });

  @override
  String toString() =>
      'DownloadProgress(phase: $phase, fetched: $fetched, total: $total)';
}

/// One frame of a progress-enabled streaming download: the total size, a
/// plaintext data chunk, or a [DownloadProgress] update. At most one of [meta]
/// / [data] / [progress] is set. Yielded by the `*WithProgress` streaming
/// methods; the plain `dataStream` / `dataStreamPublic` methods stay a pure
/// byte stream for callers that don't need progress.
class DownloadFrame {
  /// Plaintext bytes for a data frame, `null` otherwise.
  final List<int>? data;

  /// The progress update for a progress frame, `null` otherwise.
  final DownloadProgress? progress;

  /// Total download size in *bytes* — the progress *denominator* — for a meta
  /// frame, `null` otherwise.
  ///
  /// Surfaced from the gRPC `x-content-length` response metadata or the REST
  /// NDJSON `meta` frame. Emitted at most once, before any data, when the
  /// daemon reports it. Pair it with the byte count of the [data] frames (or
  /// with [DownloadProgress] chunk counts) to render a byte-accurate progress
  /// bar.
  final int? totalBytes;

  /// Constructs a data frame carrying plaintext [bytes].
  const DownloadFrame.data(List<int> bytes)
      : data = bytes,
        progress = null,
        totalBytes = null;

  /// Constructs a progress frame carrying a [DownloadProgress] update.
  const DownloadFrame.progress(DownloadProgress this.progress)
      : data = null,
        totalBytes = null;

  /// Constructs a meta frame carrying the total download size in [bytes].
  const DownloadFrame.meta(int bytes)
      : totalBytes = bytes,
        data = null,
        progress = null;

  /// True if this frame carries a progress update rather than data bytes.
  bool get isProgress => progress != null;

  /// True if this frame carries the total-size denominator (in bytes).
  bool get isMeta => totalBytes != null;

  @override
  String toString() {
    if (isMeta) return 'DownloadFrame.meta($totalBytes bytes)';
    if (isProgress) return 'DownloadFrame.progress($progress)';
    return 'DownloadFrame.data(${data!.length} bytes)';
  }
}

// --- Pointers (ADR-0016 / ADR-0018 in ant-node) ---
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; its target (a chunk, such
// as a public file's data map, or another pointer) can be changed by the
// owner. antd signs with owner keys it loaded at startup (`--pointer-keys`),
// so a write names the pointer by its address (`owner`), never by a key.
//
// Every write pays, and every attempt pays again: do not retry a create,
// update or transfer automatically.

/// The counter of a pointer's final state, after a transfer or a freeze:
/// 2^64 - 1. Nothing can replace a state at this counter.
final BigInt pointerFinalCounter = (BigInt.one << 64) - BigInt.one;

final _decimalCounter = RegExp(r'^[0-9]+$');

/// Parses a pointer counter. The daemon sends counters as decimal strings on
/// both transports, because a final state sits at 2^64 - 1
/// ([pointerFinalCounter]): past a Dart `int`, which is signed 64-bit on the
/// VM and exact only to 2^53 on the web. Counters are therefore [BigInt]s.
///
/// Throws an [InternalError] naming [field] unless [value] is a string of
/// ASCII digits no greater than 2^64 - 1. A malformed counter is an error,
/// never a zero.
BigInt parsePointerCounter(String field, Object? value) {
  if (value is String && _decimalCounter.hasMatch(value)) {
    final counter = BigInt.parse(value);
    if (counter <= pointerFinalCounter) return counter;
  }
  throw InternalError(
      'invalid pointer $field "$value": expected a decimal u64');
}

/// An optional string the daemon leaves unset: `null` over REST, `""` over
/// gRPC. Both read as `null`.
String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// What a pointer's target is.
enum PointerKind {
  /// An immutable chunk, such as a public file's data map. The default.
  chunk('chunk', 0),

  /// Another pointer: a forwarding the owner can still change. Use
  /// `pointerTransfer` to hand a pointer over for good.
  pointer('pointer', 1);

  /// The wire string the daemon expects (`chunk`, `pointer`).
  final String wire;

  /// The raw target tag the network stores (`0` chunk, `1` pointer).
  final int tag;

  const PointerKind(this.wire, this.tag);

  /// The kind a raw target tag names, or `null` for a tag this SDK does not
  /// know.
  static PointerKind? fromTag(int tag) {
    for (final kind in values) {
      if (kind.tag == tag) return kind;
    }
    return null;
  }
}

/// The state a pointer write stored.
class PointerWriteResult {
  /// The pointer's address (hex).
  final String address;

  /// The stored state's id (hex): the identifier it was paid against.
  final String stateId;

  /// The state's counter. A final state (a transfer) sits at
  /// [pointerFinalCounter].
  final BigInt counter;

  const PointerWriteResult({
    required this.address,
    required this.stateId,
    required this.counter,
  });

  /// Throws an [InternalError] if `counter` is not a decimal u64.
  factory PointerWriteResult.fromJson(Map<String, dynamic> json) {
    return PointerWriteResult(
      address: json['address'] as String? ?? '',
      stateId: json['state_id'] as String? ?? '',
      counter: parsePointerCounter('counter', json['counter']),
    );
  }

  @override
  String toString() =>
      'PointerWriteResult(address: $address, stateId: $stateId, counter: $counter)';
}

/// A pointer's current state, as the network serves it.
class PointerRecord {
  /// The pointer's address (hex).
  final String address;

  /// The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
  /// derived from it, so it is the proof of who owns the pointer.
  final String owner;

  /// The state's counter; [pointerFinalCounter] once the pointer is final.
  final BigInt counter;

  /// `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not
  /// know; [kindTag] carries the raw value either way.
  final String kind;

  /// The raw target tag (`0` chunk, `1` pointer).
  final int kindTag;

  /// The address the pointer points at (hex).
  final String target;

  /// The state's id (hex).
  final String stateId;

  /// The state is at the final counter: the pointer was handed over or
  /// frozen, and nothing can replace it. `is_final` on the wire, since
  /// `final` is a Dart keyword.
  final bool isFinal;

  /// The pointer this one was handed over to, when its final state is a
  /// transfer; `null` otherwise.
  final String? transferredTo;

  const PointerRecord({
    required this.address,
    required this.owner,
    required this.counter,
    required this.kind,
    required this.kindTag,
    required this.target,
    required this.stateId,
    required this.isFinal,
    this.transferredTo,
  });

  /// Throws an [InternalError] if `counter` is not a decimal u64.
  factory PointerRecord.fromJson(Map<String, dynamic> json) {
    return PointerRecord(
      address: json['address'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      counter: parsePointerCounter('counter', json['counter']),
      kind: json['kind'] as String? ?? '',
      kindTag: (json['kind_tag'] as num?)?.toInt() ?? 0,
      target: json['target'] as String? ?? '',
      stateId: json['state_id'] as String? ?? '',
      isFinal: json['is_final'] as bool? ?? false,
      transferredTo: _optionalString(json['transferred_to']),
    );
  }

  /// The target's kind, or `null` if this SDK does not know its tag.
  PointerKind? get targetKind => PointerKind.fromTag(kindTag);

  @override
  String toString() => 'PointerRecord(address: $address, counter: $counter, '
      'kind: $kind, target: $target, stateId: $stateId, isFinal: $isFinal, '
      'transferredTo: $transferredTo)';
}

/// Where a chain of pointers ends (`pointerResolve`).
class PointerTarget {
  /// `"chunk"`, or `"unknown"` for a target kind the daemon does not know.
  final String kind;

  /// The raw target tag.
  final int kindTag;

  /// The address at the end of the chain (hex).
  final String target;

  const PointerTarget({
    required this.kind,
    required this.kindTag,
    required this.target,
  });

  factory PointerTarget.fromJson(Map<String, dynamic> json) {
    return PointerTarget(
      kind: json['kind'] as String? ?? '',
      kindTag: (json['kind_tag'] as num?)?.toInt() ?? 0,
      target: json['target'] as String? ?? '',
    );
  }

  /// The target's kind, or `null` if this SDK does not know its tag.
  PointerKind? get targetKind => PointerKind.fromTag(kindTag);

  @override
  String toString() =>
      'PointerTarget(kind: $kind, kindTag: $kindTag, target: $target)';
}

/// Where a pointer stands with respect to finality, as its whole close group
/// reports it.
///
/// A sealed type, so a `switch` over it is exhaustive: [PointerOpen],
/// [PointerSettling], [PointerUnconfirmed], [PointerFinal], [PointerForked],
/// and [PointerFinalityUnknown] for a status a newer daemon may add.
sealed class PointerFinalityStatus {
  const PointerFinalityStatus();

  /// Parses the daemon's wire string. One this SDK does not know is a
  /// [PointerFinalityUnknown] carrying it.
  factory PointerFinalityStatus.fromWire(String wire) {
    switch (wire) {
      case 'open':
        return const PointerOpen();
      case 'settling':
        return const PointerSettling();
      case 'unconfirmed':
        return const PointerUnconfirmed();
      case 'final':
        return const PointerFinal();
      case 'forked':
        return const PointerForked();
      default:
        return PointerFinalityUnknown(wire);
    }
  }

  /// The daemon's wire string for this status.
  String get wire;

  @override
  bool operator ==(Object other) =>
      other is PointerFinalityStatus &&
      other.runtimeType == runtimeType &&
      other.wire == wire;

  @override
  int get hashCode => Object.hash(runtimeType, wire);

  @override
  String toString() => wire;
}

/// No peer that answered holds a final state: the owner can still move the
/// pointer. Rules a final state out only when every peer answered.
final class PointerOpen extends PointerFinalityStatus {
  const PointerOpen();

  @override
  String get wire => 'open';
}

/// One final state, not yet held by a majority: a transfer still spreading,
/// or a write that fell short.
final class PointerSettling extends PointerFinalityStatus {
  const PointerSettling();

  @override
  String get wire => 'settling';
}

/// One final state held by a majority, but not every peer answered, so a
/// rival could still be unseen. Ask again.
final class PointerUnconfirmed extends PointerFinalityStatus {
  const PointerUnconfirmed();

  @override
  String get wire => 'unconfirmed';
}

/// One final state held by a majority, every peer answered, no rival. The
/// only status a recipient should rely on.
final class PointerFinal extends PointerFinalityStatus {
  const PointerFinal();

  @override
  String get wire => 'final';
}

/// The owner signed two or more different final states.
final class PointerForked extends PointerFinalityStatus {
  const PointerForked();

  @override
  String get wire => 'forked';
}

/// A status this SDK does not know (a newer daemon); [wire] carries it.
final class PointerFinalityUnknown extends PointerFinalityStatus {
  @override
  final String wire;

  const PointerFinalityUnknown(this.wire);
}

/// One final state, as a finality check reports it.
class PointerFinalState {
  /// The state's id (hex).
  final String stateId;

  /// `"chunk"`, `"pointer"` or `"unknown"`; [kindTag] is the raw value.
  final String kind;

  /// The raw target tag.
  final int kindTag;

  /// The address the state points at (hex).
  final String target;

  /// How many peers of the close group hold it.
  final int holders;

  /// The pointer the state hands this one over to, if it is a transfer.
  final String? transferredTo;

  const PointerFinalState({
    required this.stateId,
    required this.kind,
    required this.kindTag,
    required this.target,
    required this.holders,
    this.transferredTo,
  });

  factory PointerFinalState.fromJson(Map<String, dynamic> json) {
    return PointerFinalState(
      stateId: json['state_id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      kindTag: (json['kind_tag'] as num?)?.toInt() ?? 0,
      target: json['target'] as String? ?? '',
      holders: (json['holders'] as num?)?.toInt() ?? 0,
      transferredTo: _optionalString(json['transferred_to']),
    );
  }

  @override
  String toString() => 'PointerFinalState(stateId: $stateId, target: $target, '
      'holders: $holders, transferredTo: $transferredTo)';
}

/// The whole close group's answer to a pointer finality check. Check it
/// before relying on a transfer: only [isFinal] (status [PointerFinal]) means
/// the transfer is beyond dispute.
class PointerFinality {
  /// The pointer's address (hex).
  final String address;

  /// Peers in the close group.
  final int group;

  /// Peers that answered.
  final int answered;

  /// Where the pointer stands.
  final PointerFinalityStatus status;

  /// [PointerOpen] only: the counter a read would return, if any state is
  /// corroborated; `null` otherwise.
  final BigInt? counter;

  /// [PointerSettling], [PointerUnconfirmed] and [PointerFinal]: the one
  /// final state seen.
  final PointerFinalState? state;

  /// [PointerForked] only: every final state seen, most-held first.
  final List<PointerFinalState> states;

  /// [PointerForked] only: the state a majority holds, which reads return.
  final PointerFinalState? majority;

  /// The pointer this one was handed over to, once that is beyond dispute
  /// (status [PointerFinal]); `null` otherwise.
  final String? transferredTo;

  const PointerFinality({
    required this.address,
    required this.group,
    required this.answered,
    required this.status,
    this.counter,
    this.state,
    this.states = const [],
    this.majority,
    this.transferredTo,
  });

  /// Throws an [InternalError] if `counter` is set but not a decimal u64.
  factory PointerFinality.fromJson(Map<String, dynamic> json) {
    final counter = json['counter'];
    final state = json['state'];
    final majority = json['majority'];
    return PointerFinality(
      address: json['address'] as String? ?? '',
      group: (json['group'] as num?)?.toInt() ?? 0,
      answered: (json['answered'] as num?)?.toInt() ?? 0,
      status: PointerFinalityStatus.fromWire(json['status'] as String? ?? ''),
      counter: counter == null ? null : parsePointerCounter('counter', counter),
      state: state is Map<String, dynamic>
          ? PointerFinalState.fromJson(state)
          : null,
      states: (json['states'] as List<dynamic>?)
              ?.map(
                  (e) => PointerFinalState.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      majority: majority is Map<String, dynamic>
          ? PointerFinalState.fromJson(majority)
          : null,
      transferredTo: _optionalString(json['transferred_to']),
    );
  }

  /// One final state, held by a majority, with every peer answering and no
  /// rival seen.
  bool get isFinal => status is PointerFinal;

  @override
  String toString() => 'PointerFinality(address: $address, status: $status, '
      'answered: $answered/$group, counter: $counter, '
      'transferredTo: $transferredTo)';
}

/// Whose pointer decides what an address resolves to, after following every
/// transfer (`pointerController`).
class PointerController {
  /// The pointer whose owner now decides.
  final String pointer;

  /// Every pointer the address was handed over to, in order.
  final List<String> transfers;

  /// [pointer] is final without being handed over: nobody can move it.
  final bool frozen;

  const PointerController({
    required this.pointer,
    this.transfers = const [],
    this.frozen = false,
  });

  factory PointerController.fromJson(Map<String, dynamic> json) {
    return PointerController(
      pointer: json['pointer'] as String? ?? '',
      transfers: (json['transfers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      frozen: json['frozen'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'PointerController(pointer: $pointer, transfers: $transfers, frozen: $frozen)';
}

/// What a transfer stored, and where the close group says it stands.
class PointerTransferResult {
  /// The transferred pointer's address (hex).
  final String address;

  /// The final state's id (hex).
  final String stateId;

  /// The close group's view once the write landed. `null` when that check
  /// failed (see [finalityError]), which does not undo the transfer: it is
  /// stored and final. Ask again with `pointerFinality`.
  final PointerFinality? finality;

  /// Why the finality check failed, when [finality] is `null`.
  final String? finalityError;

  const PointerTransferResult({
    required this.address,
    required this.stateId,
    this.finality,
    this.finalityError,
  });

  /// Throws an [InternalError] if the finality's `counter` is set but not a
  /// decimal u64.
  factory PointerTransferResult.fromJson(Map<String, dynamic> json) {
    final finality = json['finality'];
    return PointerTransferResult(
      address: json['address'] as String? ?? '',
      stateId: json['state_id'] as String? ?? '',
      finality: finality is Map<String, dynamic>
          ? PointerFinality.fromJson(finality)
          : null,
      finalityError: _optionalString(json['finality_error']),
    );
  }

  @override
  String toString() => 'PointerTransferResult(address: $address, '
      'stateId: $stateId, finality: $finality, finalityError: $finalityError)';
}

/// The write a [PointerPrepareRequest] signs.
enum PointerOp {
  /// Create the pointer. Refused if it already exists.
  create('create'),

  /// Point the pointer at a new target, creating it if it does not exist.
  update('update'),

  /// Hand the pointer over for good to the recipient's pointer.
  transfer('transfer');

  /// The wire string the daemon expects.
  final String wire;

  const PointerOp(this.wire);
}

/// Asks antd to sign a pointer write with its loaded owner key and quote it
/// for an external signer (`pointerPrepare`).
class PointerPrepareRequest {
  /// Address of the pointer to write.
  final String owner;

  /// The write to sign.
  final PointerOp op;

  /// Create and update: the address to point at.
  final String? target;

  /// Create and update: what [target] is.
  final PointerKind? kind;

  /// Transfer: the recipient's pointer, which must already exist.
  final String? recipient;

  /// Ask the daemon for the full signed quotes
  /// ([PointerPrepareResult.signedQuotes]), for offline verification.
  final bool includeSignedQuotes;

  /// Create the pointer at [owner], pointing at [target].
  const PointerPrepareRequest.create({
    required this.owner,
    required String this.target,
    PointerKind this.kind = PointerKind.chunk,
    this.includeSignedQuotes = false,
  })  : op = PointerOp.create,
        recipient = null;

  /// Point the pointer at [owner] at [target], creating it if needed.
  const PointerPrepareRequest.update({
    required this.owner,
    required String this.target,
    PointerKind this.kind = PointerKind.chunk,
    this.includeSignedQuotes = false,
  })  : op = PointerOp.update,
        recipient = null;

  /// Hand the pointer at [owner] over to the pointer at [recipient], for
  /// good. Irreversible once stored.
  const PointerPrepareRequest.transfer({
    required this.owner,
    required String this.recipient,
    this.includeSignedQuotes = false,
  })  : op = PointerOp.transfer,
        target = null,
        kind = null;

  /// The REST request body. `include_signed_quotes` is sent only when set.
  Map<String, dynamic> toJson() => {
        'owner': owner,
        'op': op.wire,
        if (target != null) 'target': target,
        if (kind != null) 'kind': kind!.wire,
        if (recipient != null) 'recipient': recipient,
        if (includeSignedQuotes) 'include_signed_quotes': true,
      };

  @override
  String toString() => 'PointerPrepareRequest(owner: $owner, op: ${op.wire}, '
      'target: $target, kind: ${kind?.wire}, recipient: $recipient)';
}

/// One signed wave-batch quote from a prepare response, as opaque base64
/// blobs. The same on REST and gRPC, whose bytes are base64-encoded to match.
class SignedQuoteEntry {
  /// Quote hash (hex with 0x prefix); matches the [PaymentInfo] entry.
  final String quoteHash;

  /// base64(msgpack) signed `PaymentQuote`. Opaque.
  final String quote;

  /// base64(msgpack) `StorageCommitment` sidecar the quote's commitment pin
  /// resolves to; `null` for baseline quotes.
  final String? commitmentSidecar;

  const SignedQuoteEntry({
    required this.quoteHash,
    required this.quote,
    this.commitmentSidecar,
  });

  factory SignedQuoteEntry.fromJson(Map<String, dynamic> json) {
    return SignedQuoteEntry(
      quoteHash: json['quote_hash'] as String? ?? '',
      quote: json['quote'] as String? ?? '',
      commitmentSidecar: _optionalString(json['commitment_sidecar']),
    );
  }

  @override
  String toString() => 'SignedQuoteEntry(quoteHash: $quoteHash)';
}

/// A pointer write signed by the daemon and quoted for an external signer.
/// Pay [payments] with `payForQuotes()`, then call `pointerFinalize`.
///
/// While it awaits payment, other writes to the pointer throw a
/// [ConflictError] until it is finalized or expires (the daemon's one-hour
/// pending TTL).
class PointerPrepareResult {
  /// Pass back to `pointerFinalize`.
  final String uploadId;

  /// `"create"`, `"update"` or `"transfer"`.
  final String op;

  /// The pointer's address (hex).
  final String address;

  /// The signed state's id (hex).
  final String stateId;

  /// The signed state's counter.
  final BigInt counter;

  /// Always `"wave_batch"`: a pointer state is paid with one quote.
  final String paymentType;

  /// Per-quote payment entries for `payForQuotes()`.
  final List<PaymentInfo> payments;

  /// Total amount to pay (atto tokens, decimal string).
  final String totalAmount;

  /// Payment vault contract address.
  final String paymentVaultAddress;

  /// Payment token contract address.
  final String paymentTokenAddress;

  /// EVM RPC URL for submitting transactions.
  final String rpcUrl;

  /// The full signed quotes, when requested with
  /// [PointerPrepareRequest.includeSignedQuotes]; empty otherwise.
  final List<SignedQuoteEntry> signedQuotes;

  const PointerPrepareResult({
    required this.uploadId,
    required this.op,
    required this.address,
    required this.stateId,
    required this.counter,
    this.paymentType = 'wave_batch',
    this.payments = const [],
    this.totalAmount = '',
    this.paymentVaultAddress = '',
    this.paymentTokenAddress = '',
    this.rpcUrl = '',
    this.signedQuotes = const [],
  });

  /// Throws an [InternalError] if `counter` is not a decimal u64.
  factory PointerPrepareResult.fromJson(Map<String, dynamic> json) {
    return PointerPrepareResult(
      uploadId: json['upload_id'] as String? ?? '',
      op: json['op'] as String? ?? '',
      address: json['address'] as String? ?? '',
      stateId: json['state_id'] as String? ?? '',
      counter: parsePointerCounter('counter', json['counter']),
      paymentType: json['payment_type'] as String? ?? 'wave_batch',
      payments: (json['payments'] as List<dynamic>?)
              ?.map((e) => PaymentInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      totalAmount: json['total_amount'] as String? ?? '',
      paymentVaultAddress: json['payment_vault_address'] as String? ?? '',
      paymentTokenAddress: json['payment_token_address'] as String? ?? '',
      rpcUrl: json['rpc_url'] as String? ?? '',
      signedQuotes: (json['signed_quotes'] as List<dynamic>?)
              ?.map((e) => SignedQuoteEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  String toString() => 'PointerPrepareResult(uploadId: $uploadId, op: $op, '
      'address: $address, counter: $counter, totalAmount: $totalAmount)';
}

/// The state a pointer finalize stored.
class PointerFinalizeResult {
  /// The pointer's address (hex).
  final String address;

  /// The stored state's id (hex).
  final String stateId;

  /// The stored state's counter.
  final BigInt counter;

  /// Transfers only: where the close group says the transfer stands.
  final PointerFinality? finality;

  const PointerFinalizeResult({
    required this.address,
    required this.stateId,
    required this.counter,
    this.finality,
  });

  /// Throws an [InternalError] if a `counter` is not a decimal u64.
  factory PointerFinalizeResult.fromJson(Map<String, dynamic> json) {
    final finality = json['finality'];
    return PointerFinalizeResult(
      address: json['address'] as String? ?? '',
      stateId: json['state_id'] as String? ?? '',
      counter: parsePointerCounter('counter', json['counter']),
      finality: finality is Map<String, dynamic>
          ? PointerFinality.fromJson(finality)
          : null,
    );
  }

  @override
  String toString() => 'PointerFinalizeResult(address: $address, '
      'stateId: $stateId, counter: $counter, finality: $finality)';
}
