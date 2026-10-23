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
  #
  # +sha256+ (antd 0.17.0 or later) is the plaintext's SHA-256 as lowercase
  # hex, or nil on an older daemon. The put results below carry it too.
  DataPutResult = Struct.new(:data_map, :chunks_stored, :payment_mode_used, :sha256, keyword_init: true) do
    def initialize(data_map: "", chunks_stored: 0, payment_mode_used: "", sha256: nil)
      super
    end
  end

  # Result of a public data put. The DataMap is stored on-network as an extra
  # chunk; +address+ is the shareable retrieval handle.
  DataPutPublicResult = Struct.new(:address, :chunks_stored, :payment_mode_used, :sha256, keyword_init: true) do
    def initialize(address: "", chunks_stored: 0, payment_mode_used: "", sha256: nil)
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
    :sha256,             # plaintext SHA-256 (hex), nil before antd 0.17.0
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
    :sha256,             # plaintext SHA-256 (hex), nil before antd 0.17.0
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
  # +sha256+ (antd 0.17.0 or later) is the plaintext's SHA-256 as lowercase
  # hex, or nil on an older daemon.
  FinalizeUploadResult = Struct.new(
    :address, :chunks_stored, :data_map, :data_map_address, :sha256,
    keyword_init: true
  ) do
    def initialize(address: "", chunks_stored: 0, data_map: "", data_map_address: "", sha256: nil)
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

  # A fetch-progress update emitted during a streaming download when progress
  # is requested. Counts are in *chunks*, not bytes — the byte denominator is
  # the download's total size (the +x-content-length+ header over gRPC, the
  # leading NDJSON +meta+ frame over REST). +total+ is 0 while still unknown
  # (mid DataMap-resolution).
  #
  # +phase+ is one of:
  # * +"resolving_map"+ -- walking the hierarchical DataMap to learn the count
  # * +"resolved"+      -- DataMap resolved; +total+ now holds the chunk count
  # * +"fetching"+      -- fetching data chunks; +fetched+/+total+ advance the bar
  DownloadProgress = Struct.new(:phase, :fetched, :total, keyword_init: true) do
    def initialize(phase: "", fetched: 0, total: 0)
      super
    end
  end

  # One frame of a progress-enabled streaming download: the total size
  # (+meta+), a plaintext data chunk (+data+), or a +DownloadProgress+ update
  # (+progress+). At most one of the three is set. Yielded by the
  # +*_with_progress+ streaming methods; the plain +data_stream+ /
  # +data_stream_public+ methods stay a pure byte stream for callers that don't
  # need progress.
  DownloadFrame = Struct.new(:data, :progress, :meta, keyword_init: true) do
    def initialize(data: nil, progress: nil, meta: nil)
      super
    end

    # True if this frame carries a progress update rather than data bytes.
    def progress?
      !progress.nil?
    end
    alias_method :is_progress, :progress?

    # True if this frame carries the total-size denominator (in bytes).
    #
    # Surfaced from the gRPC +x-content-length+ response metadata or the REST
    # NDJSON +meta+ frame. Emitted at most once, before any data.
    def meta?
      !meta.nil?
    end
    alias_method :is_meta, :meta?
  end

  # One +payments+ quote in full signed form, returned by +pointer_prepare+
  # when called with +include_signed_quotes: true+. +quote+ and
  # +commitment_sidecar+ are opaque base64 strings on both transports (the
  # gRPC client encodes the proto's bytes the same way); only antd parses
  # them. +commitment_sidecar+ is nil for baseline quotes.
  SignedQuoteEntry = Struct.new(:quote_hash, :quote, :commitment_sidecar, keyword_init: true)

  # --- Pointers (ADR-0016 / ADR-0018 in ant-node) ---
  #
  # A pointer is a small, owner-signed, mutable reference. Its address is
  # derived from the owner's key and never changes; what it points at (a
  # chunk, such as a public file's data map, or another pointer) can be
  # changed by the owner, and the owner can hand it over to another pointer
  # for good. antd signs with owner keys it loaded at startup
  # (+--pointer-keys+), so a write names the pointer by its address (+owner+),
  # never by a key.
  #
  # Every write pays, and every attempt pays again: never retry a create,
  # update, transfer or finalize automatically.

  # Counter of a pointer's final state, after a transfer or a freeze:
  # 2^64 - 1 (u64::MAX). Nothing can replace a state at this counter.
  POINTER_FINAL_COUNTER = 18_446_744_073_709_551_615

  # What a pointer's target is. Pass as +kind:+ to the pointer writes; the
  # daemon defaults to +CHUNK+ when it is omitted.
  module PointerKind
    # An immutable chunk, such as a public file's data map. The default.
    CHUNK = "chunk"
    # Another pointer: a forwarding the owner can still change. Use
    # +pointer_transfer+ to hand a pointer over for good.
    POINTER = "pointer"

    # The kind a raw +kind_tag+ names (0 chunk, 1 pointer), or nil for a tag
    # this SDK does not know.
    #
    # @param tag [Integer]
    # @return [String, nil]
    def self.from_tag(tag)
      case tag
      when 0 then CHUNK
      when 1 then POINTER
      end
    end
  end

  # The write +pointer_prepare+ signs for an external signer.
  module PointerOp
    # Create the pointer at +target+. Refused if it already exists.
    CREATE = "create"
    # Point the pointer at +target+, creating it if it does not exist.
    UPDATE = "update"
    # Hand the pointer over for good to the pointer at +recipient+, which must
    # already exist. Irreversible once stored.
    TRANSFER = "transfer"
  end

  # Where a pointer stands with respect to finality (+PointerFinality#status+).
  #
  # The status is the daemon's wire string. These are the values this SDK
  # knows; a newer daemon may send another, which is kept verbatim (the
  # "unknown" arm: +PointerFinality#status_known?+ is false). Give a +case+
  # over the status an +else+ branch.
  module PointerFinalityStatus
    # No peer that answered holds a final state: the owner can still move the
    # pointer. Rules a final state out only when every peer answered.
    OPEN = "open"
    # One final state, not yet held by a majority: a transfer still
    # spreading, or a write that fell short.
    SETTLING = "settling"
    # One final state held by a majority, but not every peer answered, so a
    # rival could still be unseen. Ask again.
    UNCONFIRMED = "unconfirmed"
    # One final state held by a majority, every peer answered, no rival. The
    # only status a recipient should rely on.
    FINAL = "final"
    # The owner signed two or more different final states.
    FORKED = "forked"

    # Every status this SDK knows.
    KNOWN = [OPEN, SETTLING, UNCONFIRMED, FINAL, FORKED].freeze

    # @param status [String]
    # @return [Boolean] whether this SDK knows +status+
    def self.known?(status)
      KNOWN.include?(status)
    end
  end

  # The state a pointer write stored (+pointer_create+ / +pointer_update+).
  # +counter+ is an Integer; a final state sits at +POINTER_FINAL_COUNTER+.
  PointerWriteResult = Struct.new(:address, :state_id, :counter, keyword_init: true)

  # A pointer's current state, as the network serves it (+pointer_get+).
  #
  # - +owner+: the owner's ML-DSA-65 public key (hex, 1,952 bytes). The
  #   address is derived from it, so it is the proof of who owns the pointer.
  # - +counter+: Integer, +POINTER_FINAL_COUNTER+ once final.
  # - +kind+: "chunk", "pointer", or "unknown" for a kind the daemon does not
  #   know; +kind_tag+ carries the raw value either way.
  # - +is_final+: the state is at the final counter, so nothing can replace it.
  # - +transferred_to+: the pointer this one was handed over to, or nil.
  PointerRecord = Struct.new(
    :address, :owner, :counter, :kind, :kind_tag, :target, :state_id,
    :is_final, :transferred_to,
    keyword_init: true
  ) do
    # @return [Boolean] true at the final counter: transferred or frozen
    def final?
      is_final == true
    end

    # @return [String, nil] the target's +PointerKind+, if this SDK knows its tag
    def target_kind
      PointerKind.from_tag(kind_tag)
    end
  end

  # Where a chain of pointers ends (+pointer_resolve+): the target's +kind+
  # ("chunk", or "unknown" for a kind the daemon does not know), its raw
  # +kind_tag+ and the +target+ address.
  PointerTarget = Struct.new(:kind, :kind_tag, :target, keyword_init: true) do
    # @return [String, nil] the target's +PointerKind+, if this SDK knows its tag
    def target_kind
      PointerKind.from_tag(kind_tag)
    end
  end

  # One final state, as a finality check reports it. +holders+ is how many
  # peers of the close group hold it; +transferred_to+ is nil unless the
  # state is a transfer.
  PointerFinalState = Struct.new(
    :state_id, :kind, :kind_tag, :target, :holders, :transferred_to,
    keyword_init: true
  )

  # Where a pointer stands, as its whole close group reports it
  # (+pointer_finality+). Check it before relying on a transfer: only
  # +final?+ means the transfer is beyond dispute.
  #
  # - +group+ / +answered+: peers in the close group, and peers that answered.
  # - +status+: a +PointerFinalityStatus+ string (see there for unknown ones).
  # - +counter+: +open+ only, the Integer counter a read would return, or nil
  #   when no state is corroborated.
  # - +state+: +settling+, +unconfirmed+ and +final+, the one final state seen
  #   (+PointerFinalState+), else nil.
  # - +states+ / +majority+: +forked+ only, every final state seen (most-held
  #   first) and the one a majority holds, which reads return. +states+ is
  #   empty and +majority+ nil otherwise.
  # - +transferred_to+: the pointer this one was handed over to, once that is
  #   beyond dispute (status +final+), else nil.
  PointerFinality = Struct.new(
    :address, :group, :answered, :status, :counter, :state, :states,
    :majority, :transferred_to,
    keyword_init: true
  ) do
    # @return [Boolean] one final state, held by a majority, every peer
    #   answering and no rival seen
    def final?
      status == PointerFinalityStatus::FINAL
    end

    # @return [Boolean] false for a status a newer daemon added
    def status_known?
      PointerFinalityStatus.known?(status)
    end
  end

  # Whose pointer decides what an address resolves to, after following every
  # transfer (+pointer_controller+). +transfers+ lists every pointer the
  # address was handed over to, in order; +frozen+ is true when +pointer+ is
  # final without being handed over, so nobody can move it.
  PointerController = Struct.new(:pointer, :transfers, :frozen, keyword_init: true)

  # What a transfer stored, and where the close group says it stands.
  # +finality+ (a +PointerFinality+) is nil when that check failed, and
  # +finality_error+ says why; the transfer itself is stored and final either
  # way. Ask again with +pointer_finality+.
  PointerTransferResult = Struct.new(:address, :state_id, :finality, :finality_error, keyword_init: true)

  # A pointer write signed by the daemon and quoted for an external signer
  # (+pointer_prepare+). Pay +payments+ with +payForQuotes()+, then call
  # +pointer_finalize+. +op+ is a +PointerOp+ string, +counter+ an Integer,
  # +payment_type+ always "wave_batch" (a pointer state is paid with one
  # quote). +signed_quotes+ (+SignedQuoteEntry+) is filled only when the
  # prepare asked for it, else empty.
  #
  # While it awaits payment, other writes to the pointer raise
  # +ConflictError+ until it is finalized or expires (one hour).
  PointerPrepareResult = Struct.new(
    :upload_id, :op, :address, :state_id, :counter, :payment_type,
    :payments, :total_amount, :payment_vault_address, :payment_token_address,
    :rpc_url, :signed_quotes,
    keyword_init: true
  )

  # The state a pointer finalize stored. +finality+ is set for a transfer
  # (where the close group says it stands), else nil.
  PointerFinalizeResult = Struct.new(:address, :state_id, :counter, :finality, keyword_init: true)

  # Parses a pointer counter. The daemon sends counters as decimal strings on
  # both transports, because a final state sits at 2^64 - 1, past what a JSON
  # number keeps exactly in many languages. Ruby integers are unbounded, so
  # the value is checked against the daemon's u64 range here.
  #
  # Strict: only a String of ASCII digits within u64 parses. +Integer()+ alone
  # would also take a sign, underscores or a radix prefix, and a malformed
  # counter must never read as 0.
  #
  # @param field [String] the field name, for the error message
  # @param value [Object] the wire value
  # @return [Integer]
  # @raise [InternalError] when +value+ is not a decimal u64
  def self.parse_pointer_counter(field, value)
    if value.is_a?(String) && value.match?(/\A[0-9]+\z/)
      n = Integer(value, 10)
      return n if n <= POINTER_FINAL_COUNTER
    end
    raise InternalError, "invalid pointer #{field} #{value.inspect}: expected a decimal u64"
  end
end
