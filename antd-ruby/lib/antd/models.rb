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

  # Payment-batching strategy for uploads.
  #
  # +AUTO+    -- server picks (merkle for 64+ chunks, single otherwise).
  # +MERKLE+  -- force merkle-batch (saves gas, min 2 chunks).
  # +SINGLE+  -- force per-chunk payments.
  module PaymentMode
    AUTO   = "auto"
    MERKLE = "merkle"
    SINGLE = "single"
  end

  # Result of a single-chunk put (used by +chunk_put+). Data and file puts
  # return richer types (+DataPutResult+ / +DataPutPublicResult+ /
  # +FilePutResult+ / +FilePutPublicResult+).
  PutResult = Struct.new(:cost, :address, keyword_init: true)

  # Result of a private data put. The DataMap is returned to the caller;
  # it is NOT stored on-network.
  DataPutResult = Struct.new(:data_map, :chunks_stored, :payment_mode_used, keyword_init: true) do
    def initialize(data_map: "", chunks_stored: 0, payment_mode_used: "")
      super
    end
  end

  # Result of a public data put. The DataMap is stored on-network as an extra
  # chunk; +address+ is the shareable retrieval handle.
  DataPutPublicResult = Struct.new(:address, :chunks_stored, :payment_mode_used, keyword_init: true) do
    def initialize(address: "", chunks_stored: 0, payment_mode_used: "")
      super
    end
  end

  # Result of a private file upload. The DataMap is returned to the caller;
  # it is NOT stored on-network.
  FilePutResult = Struct.new(
    :data_map,           # hex-encoded msgpack DataMap
    :storage_cost_atto,  # "0" if all chunks already existed
    :gas_cost_wei,       # decimal string
    :chunks_stored,      # uint64
    :payment_mode_used,  # "auto", "merkle", or "single"
    keyword_init: true
  )

  # Result of a public file upload. The DataMap is stored on-network as an
  # extra chunk; +address+ is the shareable retrieval handle.
  FilePutPublicResult = Struct.new(
    :address,            # hex network address of the stored DataMap
    :storage_cost_atto,
    :gas_cost_wei,
    :chunks_stored,
    :payment_mode_used,
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
  # +total_chunks+ and +already_stored_count+ (added in antd 0.10.0) describe
  # the already-stored preflight: +total_chunks+ includes chunks already on the
  # network, +already_stored_count+ is how many were skipped (no payment/PUT).
  # Older daemons omit them and they default to 0.
  PrepareUploadResult = Struct.new(
    :upload_id, :payments, :total_amount,
    :payment_vault_address, :payment_token_address, :rpc_url,
    :payment_type, :depth, :pool_commitments,
    :merkle_payment_timestamp,
    :total_chunks, :already_stored_count,
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
