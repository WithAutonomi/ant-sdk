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

/// Result of preparing an upload for external signing.
class PrepareUploadResult {
  final String uploadId;
  final List<PaymentInfo> payments;
  final String totalAmount;
  final String dataPaymentsAddress;
  final String paymentTokenAddress;
  final String rpcUrl;

  const PrepareUploadResult({
    required this.uploadId,
    required this.payments,
    required this.totalAmount,
    required this.dataPaymentsAddress,
    required this.paymentTokenAddress,
    required this.rpcUrl,
  });

  factory PrepareUploadResult.fromJson(Map<String, dynamic> json) {
    return PrepareUploadResult(
      uploadId: json['upload_id'] as String? ?? '',
      payments: (json['payments'] as List<dynamic>?)
              ?.map((e) => PaymentInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: json['total_amount'] as String? ?? '',
      dataPaymentsAddress: json['data_payments_address'] as String? ?? '',
      paymentTokenAddress: json['payment_token_address'] as String? ?? '',
      rpcUrl: json['rpc_url'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'PrepareUploadResult(uploadId: $uploadId, payments: $payments, totalAmount: $totalAmount)';
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
