defmodule Antd.PaymentMode do
  @moduledoc """
  Payment-batching strategy for uploads.

  * `:auto`   — server picks (merkle for 64+ chunks, single otherwise).
  * `:merkle` — force merkle-batch (saves gas, min 2 chunks).
  * `:single` — force per-chunk payments (works for any chunk count).

  The atom is serialized to the wire string at the request boundary; the
  empty wire value is treated as `"auto"` by the daemon so older clients
  that omit the field stay compatible.
  """

  @type t :: :auto | :merkle | :single

  @doc "Serialize a `t:t/0` atom to the wire string the daemon expects."
  @spec to_wire(t() | nil) :: String.t()
  def to_wire(:auto), do: "auto"
  def to_wire(:merkle), do: "merkle"
  def to_wire(:single), do: "single"
  def to_wire(nil), do: "auto"
end

defmodule Antd.HealthStatus do
  @moduledoc """
  Result of a health check.

  The diagnostic fields (`:version`, `:evm_network`, `:uptime_seconds`,
  `:build_commit`, `:payment_token_address`, `:payment_vault_address`) were
  added in antd 0.4.0. They default to `""` / `0` so existing struct
  constructions and pre-0.4.0 daemon responses both still work.
  """

  @enforce_keys [:ok, :network]
  defstruct ok: nil,
            network: nil,
            version: "",
            evm_network: "",
            uptime_seconds: 0,
            build_commit: "",
            payment_token_address: "",
            payment_vault_address: ""

  @type t :: %__MODULE__{
          ok: boolean(),
          network: String.t(),
          version: String.t(),
          evm_network: String.t(),
          uptime_seconds: non_neg_integer(),
          build_commit: String.t(),
          payment_token_address: String.t(),
          payment_vault_address: String.t()
        }
end

defmodule Antd.PutResult do
  @moduledoc """
  Result of a single-chunk put (used by `Antd.Client.chunk_put/2`).

  Data and file puts return richer types (`Antd.DataPutResult` /
  `Antd.DataPutPublicResult` / `Antd.FilePutResult` /
  `Antd.FilePutPublicResult`).
  """

  @enforce_keys [:cost, :address]
  defstruct [:cost, :address]

  @type t :: %__MODULE__{
          cost: String.t(),
          address: String.t()
        }
end

defmodule Antd.DataPutResult do
  @moduledoc """
  Result of a private data put.

  The DataMap is returned to the caller; it is NOT stored on-network. The
  REST transport populates `:chunks_stored` and `:payment_mode_used`; the
  gRPC transport currently leaves them empty because proto
  `PutDataResponse` only carries `data_map`.

  `:sha256` is the plaintext's SHA-256 (lowercase hex) on both transports, or
  `nil` on a daemon older than antd 0.17.0.
  """

  @enforce_keys [:data_map]
  defstruct data_map: "", chunks_stored: 0, payment_mode_used: "", sha256: nil

  @type t :: %__MODULE__{
          data_map: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t(),
          sha256: String.t() | nil
        }
end

defmodule Antd.DataPutPublicResult do
  @moduledoc """
  Result of a public data put.

  The DataMap is stored on-network as an additional chunk; `:address` is the
  shareable retrieval handle. REST populates `:chunks_stored` and
  `:payment_mode_used`; gRPC currently leaves them empty. `:sha256` is the
  plaintext's SHA-256 (lowercase hex), or `nil` on a daemon older than antd
  0.17.0.
  """

  @enforce_keys [:address]
  defstruct address: "", chunks_stored: 0, payment_mode_used: "", sha256: nil

  @type t :: %__MODULE__{
          address: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t(),
          sha256: String.t() | nil
        }
end

defmodule Antd.FilePutResult do
  @moduledoc """
  Result of a private file upload.

  The DataMap is returned to the caller; it is NOT stored on-network.
  `:sha256` is the plaintext's SHA-256 (lowercase hex), or `nil` on a daemon
  older than antd 0.17.0.
  """

  @enforce_keys [:data_map, :storage_cost_atto, :gas_cost_wei, :chunks_stored, :payment_mode_used]
  defstruct [
    :data_map,
    :storage_cost_atto,
    :gas_cost_wei,
    :chunks_stored,
    :payment_mode_used,
    sha256: nil
  ]

  @type t :: %__MODULE__{
          data_map: String.t(),
          storage_cost_atto: String.t(),
          gas_cost_wei: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t(),
          sha256: String.t() | nil
        }
end

defmodule Antd.FilePutPublicResult do
  @moduledoc """
  Result of a public file upload.

  The DataMap is stored on-network as an additional chunk; `:address` is the
  shareable retrieval handle. `:sha256` is the plaintext's SHA-256 (lowercase
  hex), or `nil` on a daemon older than antd 0.17.0.
  """

  @enforce_keys [:address, :storage_cost_atto, :gas_cost_wei, :chunks_stored, :payment_mode_used]
  defstruct [
    :address,
    :storage_cost_atto,
    :gas_cost_wei,
    :chunks_stored,
    :payment_mode_used,
    sha256: nil
  ]

  @type t :: %__MODULE__{
          address: String.t(),
          storage_cost_atto: String.t(),
          gas_cost_wei: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t(),
          sha256: String.t() | nil
        }
end

defmodule Antd.WalletAddress do
  @moduledoc "Wallet address result."

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: String.t()
        }
end

defmodule Antd.WalletBalance do
  @moduledoc "Wallet balance result."

  @enforce_keys [:balance, :gas_balance]
  defstruct [:balance, :gas_balance]

  @type t :: %__MODULE__{
          balance: String.t(),
          gas_balance: String.t()
        }
end

defmodule Antd.PaymentInfo do
  @moduledoc "A single payment required for an upload."

  @enforce_keys [:quote_hash, :rewards_address, :amount]
  defstruct [:quote_hash, :rewards_address, :amount]

  @type t :: %__MODULE__{
          quote_hash: String.t(),
          rewards_address: String.t(),
          amount: String.t()
        }
end

defmodule Antd.CandidateNodeEntry do
  @moduledoc "A candidate node within a merkle payment pool."

  @enforce_keys [:rewards_address, :amount]
  defstruct [:rewards_address, :amount]

  @type t :: %__MODULE__{
          rewards_address: String.t(),
          amount: String.t()
        }
end

defmodule Antd.PoolCommitmentEntry do
  @moduledoc "A pool commitment containing candidate nodes for merkle batch payment."

  @enforce_keys [:pool_hash, :candidates]
  defstruct [:pool_hash, :candidates]

  @type t :: %__MODULE__{
          pool_hash: String.t(),
          candidates: [Antd.CandidateNodeEntry.t()]
        }
end

defmodule Antd.PrepareUploadResult do
  @moduledoc "Result of preparing an upload for external signing."

  @enforce_keys [
    :upload_id,
    :payments,
    :total_amount,
    :payment_vault_address,
    :payment_token_address,
    :rpc_url
  ]
  defstruct [
    :upload_id,
    :payments,
    :total_amount,
    :payment_vault_address,
    :payment_token_address,
    :rpc_url,
    :payment_type,
    :depth,
    :pool_commitments,
    :merkle_payment_timestamp,
    :total_chunks,
    :already_stored_count
  ]

  @type t :: %__MODULE__{
          upload_id: String.t(),
          payments: [Antd.PaymentInfo.t()],
          total_amount: String.t(),
          payment_vault_address: String.t(),
          payment_token_address: String.t(),
          rpc_url: String.t(),
          payment_type: String.t() | nil,
          depth: integer() | nil,
          pool_commitments: [Antd.PoolCommitmentEntry.t()] | nil,
          merkle_payment_timestamp: integer() | nil,
          # Already-stored preflight (added in antd 0.10.0). 0 on older daemons.
          # The external signer pays for total_chunks - already_stored_count.
          total_chunks: integer(),
          already_stored_count: integer()
        }
end

defmodule Antd.FinalizeUploadResult do
  @moduledoc """
  Result of finalizing an externally-signed upload.

  `:data_map` is the hex-encoded serialized DataMap (always returned by the
  daemon on success). `:data_map_address` is populated only when prepare was
  called with `visibility: "public"` — the DataMap chunk was bundled into the
  same external-signer payment batch and stored on-network, and this is the
  shareable retrieval handle. `:sha256` is the plaintext's SHA-256 (lowercase
  hex), or `nil` on a daemon older than antd 0.17.0.
  """

  @enforce_keys [:address, :chunks_stored]
  defstruct [:address, :chunks_stored, data_map: "", data_map_address: "", sha256: nil]

  @type t :: %__MODULE__{
          address: String.t(),
          chunks_stored: integer(),
          data_map: String.t(),
          data_map_address: String.t(),
          sha256: String.t() | nil
        }
end

defmodule Antd.PrepareChunkResult do
  @moduledoc """
  Result of preparing a single-chunk external-signer publish via
  `POST /v1/chunks/prepare`.

  When `:already_stored` is `true` the chunk is already on-network and no
  payment / finalize step is needed — `:upload_id` and the payment fields
  remain empty. Otherwise the wave-batch payment fields describe what the
  external signer must submit before calling `finalize_chunk_upload/3`.
  """

  @enforce_keys [:address, :already_stored]
  defstruct [
    :address,
    :already_stored,
    upload_id: "",
    payment_type: "",
    payments: [],
    total_amount: "",
    payment_vault_address: "",
    payment_token_address: "",
    rpc_url: ""
  ]

  @type t :: %__MODULE__{
          address: String.t(),
          already_stored: boolean(),
          upload_id: String.t(),
          payment_type: String.t(),
          payments: [Antd.PaymentInfo.t()],
          total_amount: String.t(),
          payment_vault_address: String.t(),
          payment_token_address: String.t(),
          rpc_url: String.t()
        }
end

defmodule Antd.UploadCostEstimate do
  @moduledoc """
  Pre-upload cost breakdown returned by `Antd.Client.data_cost/3` and
  `Antd.Client.file_cost/4`.

  The server samples up to 5 chunk addresses and extrapolates the storage
  cost. Gas is an advisory heuristic, not a live gas-oracle query.
  """

  @enforce_keys [:cost, :file_size, :chunk_count, :estimated_gas_cost_wei, :payment_mode]
  defstruct [:cost, :file_size, :chunk_count, :estimated_gas_cost_wei, :payment_mode]

  @type t :: %__MODULE__{
          cost: String.t(),
          file_size: non_neg_integer(),
          chunk_count: non_neg_integer(),
          estimated_gas_cost_wei: String.t(),
          payment_mode: String.t()
        }
end

defmodule Antd.DownloadProgress do
  @moduledoc """
  A fetch-progress update emitted during a streaming download when progress is
  requested. Counts are in *chunks*, not bytes — the byte denominator is the
  download's total size (the `x-content-length` header over gRPC, the leading
  NDJSON `meta` frame over REST). `total` is 0 while still unknown (mid
  DataMap-resolution).

  `phase` is one of:

    * `"resolving_map"` — walking the hierarchical DataMap to learn the count
    * `"resolved"` — DataMap resolved, `total` now holds the real chunk count
    * `"fetching"` — fetching data chunks; `fetched`/`total` advance the bar
  """

  defstruct phase: "", fetched: 0, total: 0

  @type t :: %__MODULE__{
          phase: String.t(),
          fetched: non_neg_integer(),
          total: non_neg_integer()
        }
end

defmodule Antd.DownloadFrame do
  @moduledoc """
  One frame of a progress-enabled streaming download: the total size, a
  plaintext data chunk, or a `Antd.DownloadProgress` update. At most one of
  `:meta`, `:data`, or `:progress` is set. Yielded by the `*_with_progress`
  streaming methods; the plain `data_stream` methods stay a pure binary stream
  for callers that don't need progress.

  `:meta` is the total download size in *bytes* — the progress denominator,
  surfaced from the gRPC `x-content-length` response header or the REST NDJSON
  `meta` frame. Emitted at most once, before any data.
  """

  defstruct data: nil, progress: nil, meta: nil

  @type t :: %__MODULE__{
          data: binary() | nil,
          progress: Antd.DownloadProgress.t() | nil,
          meta: non_neg_integer() | nil
        }

  @doc "True if this frame carries a progress update rather than data bytes."
  @spec progress?(t()) :: boolean()
  def progress?(%__MODULE__{progress: progress}), do: not is_nil(progress)

  @doc "True if this frame carries the total-size denominator (in bytes)."
  @spec meta?(t()) :: boolean()
  def meta?(%__MODULE__{meta: meta}), do: not is_nil(meta)
end

defmodule Antd.SignedQuoteEntry do
  @moduledoc """
  One `payments` quote in full signed form, returned by a prepare called with
  `include_signed_quotes: true`. `quote` and `commitment_sidecar` are opaque
  base64 blobs (the msgpack-serialized signed `PaymentQuote`, and the
  `StorageCommitment` it pins); only antd parses them. `commitment_sidecar`
  is `nil` for baseline quotes. Over gRPC the raw bytes are base64-encoded,
  so both transports give the same values.
  """

  @enforce_keys [:quote_hash, :quote]
  defstruct [:quote_hash, :quote, commitment_sidecar: nil]

  @type t :: %__MODULE__{
          quote_hash: String.t(),
          quote: String.t(),
          commitment_sidecar: String.t() | nil
        }
end

defmodule Antd.PointerKind do
  @moduledoc """
  What a pointer write points at: the `:kind` option of `pointer_create`,
  `pointer_update` and a `pointer_prepare` create or update.

    * `:chunk` — a chunk, such as the address `data_put_public` or
      `file_put_public` returns. The daemon's default when the option is
      left out.
    * `:pointer` — another pointer: a forwarding its owner can still change.
      Use `pointer_transfer` to hand a pointer over for good.

  Results carry the daemon's `kind` string (`"chunk"`, `"pointer"`, or
  `"unknown"` for a kind the daemon does not know) and the raw `kind_tag`.
  """

  @type t :: :chunk | :pointer

  @doc "Serialize a `t:t/0` atom to the wire string the daemon expects."
  @spec to_wire(t()) :: String.t()
  def to_wire(:chunk), do: "chunk"
  def to_wire(:pointer), do: "pointer"
end

defmodule Antd.PointerOp do
  @moduledoc """
  The write a `pointer_prepare` signs and quotes for an external signer:

    * `{:create, target}` / `{:create, target, kind}` — create the pointer.
    * `{:update, target}` / `{:update, target, kind}` — point it at a new
      target, creating it if it does not exist.
    * `{:transfer, recipient}` — hand it over for good to the recipient's
      pointer, which must already exist.

  `kind` is an `t:Antd.PointerKind.t/0`; the daemon defaults it to `:chunk`.
  """

  @type t ::
          {:create, String.t()}
          | {:create, String.t(), Antd.PointerKind.t()}
          | {:update, String.t()}
          | {:update, String.t(), Antd.PointerKind.t()}
          | {:transfer, String.t()}

  # The op's wire fields: `op` plus `target` and optionally `kind`, or
  # `recipient`. Shared by the REST and gRPC clients.
  @doc false
  @spec to_fields(t()) :: map()
  def to_fields({op, target}) when op in [:create, :update] and is_binary(target),
    do: %{op: Atom.to_string(op), target: target}

  def to_fields({op, target, kind}) when op in [:create, :update] and is_binary(target),
    do: %{op: Atom.to_string(op), target: target, kind: Antd.PointerKind.to_wire(kind)}

  def to_fields({:transfer, recipient}) when is_binary(recipient),
    do: %{op: "transfer", recipient: recipient}
end

defmodule Antd.PointerWriteResult do
  @moduledoc """
  The state a pointer write stored (`pointer_create` / `pointer_update`).
  `state_id` is the hex identifier the state was paid against; `counter` is
  its counter, an integer parsed from the daemon's decimal string.
  """

  @enforce_keys [:address, :state_id, :counter]
  defstruct [:address, :state_id, :counter]

  @type t :: %__MODULE__{
          address: String.t(),
          state_id: String.t(),
          counter: non_neg_integer()
        }
end

defmodule Antd.PointerRecord do
  @moduledoc """
  A pointer's current state, as the network serves it (`pointer_get`).

    * `owner` — the owner's ML-DSA-65 public key (hex, 1,952 bytes). The
      address is derived from it, so it is the proof of who owns the pointer.
    * `counter` — an integer, the daemon's `u64` sent as a decimal string. A
      final state (after a transfer or a freeze) sits at `final_counter/0`,
      2^64 - 1, and `is_final` is `true`: nothing can replace it.
    * `kind` — `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon
      does not know; `kind_tag` is the raw value either way.
    * `transferred_to` — the pointer this one was handed over to, or `nil`.
  """

  @final_counter 18_446_744_073_709_551_615

  @enforce_keys [:address, :owner, :counter, :kind, :kind_tag, :target, :state_id]
  defstruct [
    :address,
    :owner,
    :counter,
    :kind,
    :kind_tag,
    :target,
    :state_id,
    is_final: false,
    transferred_to: nil
  ]

  @type t :: %__MODULE__{
          address: String.t(),
          owner: String.t(),
          counter: non_neg_integer(),
          kind: String.t(),
          kind_tag: non_neg_integer(),
          target: String.t(),
          state_id: String.t(),
          is_final: boolean(),
          transferred_to: String.t() | nil
        }

  @doc "The counter of a pointer's final state, 2^64 - 1."
  @spec final_counter() :: non_neg_integer()
  def final_counter, do: @final_counter
end

defmodule Antd.PointerTarget do
  @moduledoc """
  Where a chain of pointers ends (`pointer_resolve`): the `target` address,
  its `kind` string and the raw `kind_tag`.
  """

  @enforce_keys [:kind, :kind_tag, :target]
  defstruct [:kind, :kind_tag, :target]

  @type t :: %__MODULE__{
          kind: String.t(),
          kind_tag: non_neg_integer(),
          target: String.t()
        }
end

defmodule Antd.PointerFinalState do
  @moduledoc """
  One final state, as a finality check reports it. `holders` is how many
  peers of the close group hold it; `transferred_to` is the pointer the state
  hands over to, or `nil`.
  """

  @enforce_keys [:state_id, :kind, :kind_tag, :target, :holders]
  defstruct [:state_id, :kind, :kind_tag, :target, :holders, transferred_to: nil]

  @type t :: %__MODULE__{
          state_id: String.t(),
          kind: String.t(),
          kind_tag: non_neg_integer(),
          target: String.t(),
          holders: non_neg_integer(),
          transferred_to: String.t() | nil
        }
end

defmodule Antd.PointerFinality do
  @moduledoc """
  The whole close group's view of where a pointer stands
  (`pointer_finality`). Check it before relying on a transfer: only
  `status: :final` means it is beyond dispute.

  `status` is one of:

    * `:open` — no peer that answered holds a final state. `counter` is the
      counter a read would return, or `nil` if no state is corroborated.
    * `:settling` — one final state (`state`), not yet held by a majority.
    * `:unconfirmed` — one final state held by a majority, but not every peer
      of the group answered, so a rival could still exist.
    * `:final` — one final state, held by a majority, every peer answered,
      no rival seen. `transferred_to` is set when it is a transfer.
    * `:forked` — the owner signed two or more different final states.
      `states` lists them, most-held first; `majority` is the one a majority
      holds, which reads return, or `nil`.
    * `{:unknown, status}` — a status this SDK does not know yet, as the
      daemon sent it.

  Unset values are `nil` on both transports: REST sends `null`, gRPC an
  empty string or an absent message.
  """

  @enforce_keys [:address, :group, :answered, :status]
  defstruct [
    :address,
    :group,
    :answered,
    :status,
    counter: nil,
    state: nil,
    states: [],
    majority: nil,
    transferred_to: nil
  ]

  @type status :: :open | :settling | :unconfirmed | :final | :forked | {:unknown, String.t()}

  @type t :: %__MODULE__{
          address: String.t(),
          group: non_neg_integer(),
          answered: non_neg_integer(),
          status: status(),
          counter: non_neg_integer() | nil,
          state: Antd.PointerFinalState.t() | nil,
          states: [Antd.PointerFinalState.t()],
          majority: Antd.PointerFinalState.t() | nil,
          transferred_to: String.t() | nil
        }

  @doc "True only for `status: :final`: the transfer is beyond dispute."
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{status: status}), do: status == :final

  @doc """
  Parses the daemon's status string. A status this SDK does not know yet
  comes back as `{:unknown, status}`.
  """
  @spec parse_status(String.t()) :: status()
  def parse_status("open"), do: :open
  def parse_status("settling"), do: :settling
  def parse_status("unconfirmed"), do: :unconfirmed
  def parse_status("final"), do: :final
  def parse_status("forked"), do: :forked
  def parse_status(other) when is_binary(other), do: {:unknown, other}
end

defmodule Antd.PointerController do
  @moduledoc """
  Whose pointer decides what an address resolves to, after following every
  transfer (`pointer_controller`). `transfers` lists every pointer the
  address was handed over to, in order. `frozen` is `true` when `pointer` is
  final without being handed over: nobody can move it.
  """

  @enforce_keys [:pointer]
  defstruct [:pointer, transfers: [], frozen: false]

  @type t :: %__MODULE__{
          pointer: String.t(),
          transfers: [String.t()],
          frozen: boolean()
        }
end

defmodule Antd.PointerTransferResult do
  @moduledoc """
  What a transfer stored, and where the close group says it stands
  (`pointer_transfer`). `finality` is `nil` when that check failed, and
  `finality_error` says why; the transfer itself is stored and final either
  way. Ask again with `pointer_finality`.
  """

  @enforce_keys [:address, :state_id]
  defstruct [:address, :state_id, finality: nil, finality_error: nil]

  @type t :: %__MODULE__{
          address: String.t(),
          state_id: String.t(),
          finality: Antd.PointerFinality.t() | nil,
          finality_error: String.t() | nil
        }
end

defmodule Antd.PointerPrepareResult do
  @moduledoc """
  A pointer write signed with the daemon's loaded owner key, and the
  wave-batch payment for it (`pointer_prepare`). Pay `payments` with
  `payForQuotes()`, then call `pointer_finalize` with `upload_id`.

  `op` is the daemon's `"create"`, `"update"` or `"transfer"`; `counter` is
  the counter the write will store. `payment_type` is always `"wave_batch"`
  and `total_amount` is in atto tokens. `signed_quotes` is filled only when
  the prepare asked for it (`include_signed_quotes: true`).
  """

  @enforce_keys [:upload_id, :op, :address, :state_id, :counter]
  defstruct [
    :upload_id,
    :op,
    :address,
    :state_id,
    :counter,
    payment_type: "wave_batch",
    payments: [],
    total_amount: "",
    payment_vault_address: "",
    payment_token_address: "",
    rpc_url: "",
    signed_quotes: []
  ]

  @type t :: %__MODULE__{
          upload_id: String.t(),
          op: String.t(),
          address: String.t(),
          state_id: String.t(),
          counter: non_neg_integer(),
          payment_type: String.t(),
          payments: [Antd.PaymentInfo.t()],
          total_amount: String.t(),
          payment_vault_address: String.t(),
          payment_token_address: String.t(),
          rpc_url: String.t(),
          signed_quotes: [Antd.SignedQuoteEntry.t()]
        }
end

defmodule Antd.PointerFinalizeResult do
  @moduledoc """
  The state a `pointer_finalize` stored. `finality` is set for a transfer.
  """

  @enforce_keys [:address, :state_id, :counter]
  defstruct [:address, :state_id, :counter, finality: nil]

  @type t :: %__MODULE__{
          address: String.t(),
          state_id: String.t(),
          counter: non_neg_integer(),
          finality: Antd.PointerFinality.t() | nil
        }
end
