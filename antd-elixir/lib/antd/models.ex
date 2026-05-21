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
  """

  @enforce_keys [:data_map]
  defstruct data_map: "", chunks_stored: 0, payment_mode_used: ""

  @type t :: %__MODULE__{
          data_map: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t()
        }
end

defmodule Antd.DataPutPublicResult do
  @moduledoc """
  Result of a public data put.

  The DataMap is stored on-network as an additional chunk; `:address` is the
  shareable retrieval handle. REST populates `:chunks_stored` and
  `:payment_mode_used`; gRPC currently leaves them empty.
  """

  @enforce_keys [:address]
  defstruct address: "", chunks_stored: 0, payment_mode_used: ""

  @type t :: %__MODULE__{
          address: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t()
        }
end

defmodule Antd.FilePutResult do
  @moduledoc """
  Result of a private file upload.

  The DataMap is returned to the caller; it is NOT stored on-network.
  """

  @enforce_keys [:data_map, :storage_cost_atto, :gas_cost_wei, :chunks_stored, :payment_mode_used]
  defstruct [:data_map, :storage_cost_atto, :gas_cost_wei, :chunks_stored, :payment_mode_used]

  @type t :: %__MODULE__{
          data_map: String.t(),
          storage_cost_atto: String.t(),
          gas_cost_wei: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t()
        }
end

defmodule Antd.FilePutPublicResult do
  @moduledoc """
  Result of a public file upload.

  The DataMap is stored on-network as an additional chunk; `:address` is the
  shareable retrieval handle.
  """

  @enforce_keys [:address, :storage_cost_atto, :gas_cost_wei, :chunks_stored, :payment_mode_used]
  defstruct [:address, :storage_cost_atto, :gas_cost_wei, :chunks_stored, :payment_mode_used]

  @type t :: %__MODULE__{
          address: String.t(),
          storage_cost_atto: String.t(),
          gas_cost_wei: String.t(),
          chunks_stored: non_neg_integer(),
          payment_mode_used: String.t()
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
    :merkle_payment_timestamp
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
          merkle_payment_timestamp: integer() | nil
        }
end

defmodule Antd.FinalizeUploadResult do
  @moduledoc """
  Result of finalizing an externally-signed upload.

  `:data_map` is the hex-encoded serialized DataMap (always returned by the
  daemon on success). `:data_map_address` is populated only when prepare was
  called with `visibility: "public"` — the DataMap chunk was bundled into the
  same external-signer payment batch and stored on-network, and this is the
  shareable retrieval handle.
  """

  @enforce_keys [:address, :chunks_stored]
  defstruct [:address, :chunks_stored, data_map: "", data_map_address: ""]

  @type t :: %__MODULE__{
          address: String.t(),
          chunks_stored: integer(),
          data_map: String.t(),
          data_map_address: String.t()
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
