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
  @moduledoc "Result of a put/create operation."

  @enforce_keys [:cost, :address]
  defstruct [:cost, :address]

  @type t :: %__MODULE__{
          cost: String.t(),
          address: String.t()
        }
end

defmodule Antd.FileUploadResult do
  @moduledoc """
  Result of a public file or directory upload.

  Returned by `Antd.Client.file_upload_public/2`,
  `Antd.Client.dir_upload_public/2`, and the equivalent gRPC client functions.
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

  @enforce_keys [:upload_id, :payments, :total_amount, :payment_vault_address, :payment_token_address, :rpc_url]
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
  @moduledoc "Result of finalizing an externally-signed upload."

  @enforce_keys [:address, :chunks_stored]
  defstruct [:address, :chunks_stored]

  @type t :: %__MODULE__{
          address: String.t(),
          chunks_stored: integer()
        }
end

defmodule Antd.UploadCostEstimate do
  @moduledoc """
  Pre-upload cost breakdown returned by `Antd.Client.data_cost/2` and
  `Antd.Client.file_cost/3`.

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
