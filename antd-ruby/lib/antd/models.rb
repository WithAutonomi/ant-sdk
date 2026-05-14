# frozen_string_literal: true

module Antd
  # Result of a health check.
  #
  # The diagnostic fields (:version, :evm_network, :uptime_seconds,
  # :build_commit, :payment_token_address, :payment_vault_address) were added
  # in antd 0.4.0. They default to "" / 0 so existing two-arg
  # `HealthStatus.new(ok:, network:)` calls keep working and pre-0.4.0 daemon
  # responses parse cleanly.
  HealthStatus = Struct.new(
    :ok, :network,
    :version, :evm_network, :uptime_seconds,
    :build_commit, :payment_token_address, :payment_vault_address,
    keyword_init: true
  ) do
    def initialize(ok:, network:, version: "", evm_network: "",
                   uptime_seconds: 0, build_commit: "",
                   payment_token_address: "", payment_vault_address: "")
      super
    end
  end

  # Result of a put/create operation.
  PutResult = Struct.new(:cost, :address, keyword_init: true)

  # Result of a public file or directory upload.
  FileUploadResult = Struct.new(
    :address,            # hex network address
    :storage_cost_atto,  # storage cost in atto, "0" if all chunks already existed
    :gas_cost_wei,       # gas cost in wei as decimal string
    :chunks_stored,      # number of chunks stored on the network (uint64)
    :payment_mode_used,  # "auto", "merkle", or "single"
    keyword_init: true
  )

  # Wallet address result.
  WalletAddress = Struct.new(:address, keyword_init: true)

  # Wallet balance result.
  WalletBalance = Struct.new(:balance, :gas_balance, keyword_init: true)

  # A single payment required for an upload.
  PaymentInfo = Struct.new(:quote_hash, :rewards_address, :amount, keyword_init: true)

  # A candidate node within a merkle payment pool.
  CandidateNodeEntry = Struct.new(:rewards_address, :amount, keyword_init: true)

  # A pool commitment containing candidate nodes for merkle batch payment.
  PoolCommitmentEntry = Struct.new(:pool_hash, :candidates, keyword_init: true)

  # Result of preparing an upload for external signing.
  PrepareUploadResult = Struct.new(
    :upload_id, :payments, :total_amount,
    :payment_vault_address, :payment_token_address, :rpc_url,
    :payment_type, :depth, :pool_commitments,
    :merkle_payment_timestamp,
    keyword_init: true
  )

  # Result of finalizing an externally-signed upload.
  #
  # +data_map+ is the hex-encoded msgpack DataMap (always returned by the
  # daemon — kept as a convenience even when the caller doesn't need it).
  # +data_map_address+ is populated only when prepare was called with
  # +visibility: "public"+ — the DataMap chunk was paid + stored in the same
  # external-signer batch, and this is the shareable retrieval handle.
  FinalizeUploadResult = Struct.new(
    :address, :chunks_stored, :data_map, :data_map_address,
    keyword_init: true
  ) do
    def initialize(address: "", chunks_stored: 0, data_map: "", data_map_address: "")
      super
    end
  end

  # Result of preparing a single-chunk external-signer publish via
  # +Client#prepare_chunk_upload+.
  #
  # When +already_stored+ is true the chunk is already on-network and no
  # payment or finalize step is needed — +upload_id+ and the payment fields
  # are empty. Otherwise the wave-batch payment fields describe what the
  # external signer must submit before calling +finalize_chunk_upload+.
  PrepareChunkResult = Struct.new(
    :address, :already_stored, :upload_id, :payment_type,
    :payments, :total_amount,
    :payment_vault_address, :payment_token_address, :rpc_url,
    keyword_init: true
  ) do
    def initialize(address: "", already_stored: false, upload_id: "",
                   payment_type: "", payments: [], total_amount: "",
                   payment_vault_address: "", payment_token_address: "",
                   rpc_url: "")
      super
    end
  end

  # Pre-upload cost breakdown returned by +data_cost+ and +file_cost+.
  # The server samples up to 5 chunk addresses and extrapolates the storage
  # cost. Gas is an advisory heuristic, not a live gas-oracle query.
  UploadCostEstimate = Struct.new(
    :cost,                    # storage cost in atto tokens
    :file_size,               # original file size in bytes
    :chunk_count,             # number of data chunks
    :estimated_gas_cost_wei,  # advisory gas heuristic in wei
    :payment_mode,            # "auto" | "merkle" | "single"
    keyword_init: true
  )
end
