# frozen_string_literal: true

module Antd
  # Result of a health check.
  HealthStatus = Struct.new(:ok, :network, keyword_init: true)

  # Result of a put/create operation.
  PutResult = Struct.new(:cost, :address, keyword_init: true)

  # Wallet address result.
  WalletAddress = Struct.new(:address, keyword_init: true)

  # Wallet balance result.
  WalletBalance = Struct.new(:balance, :gas_balance, keyword_init: true)

  # A single payment required for an upload.
  PaymentInfo = Struct.new(:quote_hash, :rewards_address, :amount, keyword_init: true)

  # Result of preparing an upload for external signing.
  PrepareUploadResult = Struct.new(:upload_id, :payments, :total_amount, :data_payments_address, :payment_token_address, :rpc_url, keyword_init: true)

  # Result of finalizing an externally-signed upload.
  FinalizeUploadResult = Struct.new(:address, :chunks_stored, keyword_init: true)
end
