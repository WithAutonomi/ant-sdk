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

/// Result of a public file or directory upload.
class FileUploadResult {
  /// Hex network address of the uploaded file/directory.
  final String address;

  /// Storage cost in atto, "0" if all chunks already existed.
  final String storageCostAtto;

  /// Gas cost in wei as decimal string.
  final String gasCostWei;

  /// Number of chunks stored on the network (uint64).
  final int chunksStored;

  /// Which payment mode was actually used: "auto", "merkle", or "single".
  final String paymentModeUsed;

  const FileUploadResult({
    required this.address,
    required this.storageCostAtto,
    required this.gasCostWei,
    required this.chunksStored,
    required this.paymentModeUsed,
  });

  factory FileUploadResult.fromJson(Map<String, dynamic> json) {
    return FileUploadResult(
      address: json['address'] as String? ?? '',
      storageCostAtto: json['storage_cost_atto'] as String? ?? '',
      gasCostWei: json['gas_cost_wei'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
      paymentModeUsed: json['payment_mode_used'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'FileUploadResult(address: $address, storageCostAtto: $storageCostAtto, gasCostWei: $gasCostWei, chunksStored: $chunksStored, paymentModeUsed: $paymentModeUsed)';
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
    );
  }

  @override
  String toString() =>
      'PrepareUploadResult(uploadId: $uploadId, paymentType: $paymentType, totalAmount: $totalAmount)';
}

/// Result of finalizing an externally-signed upload.
class FinalizeUploadResult {
  final String address;
  final int chunksStored;

  const FinalizeUploadResult({
    required this.address,
    required this.chunksStored,
  });

  factory FinalizeUploadResult.fromJson(Map<String, dynamic> json) {
    return FinalizeUploadResult(
      address: json['address'] as String? ?? '',
      chunksStored: (json['chunks_stored'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'FinalizeUploadResult(address: $address, chunksStored: $chunksStored)';
}
