defmodule Antd.HealthStatus do
  @moduledoc "Result of a health check."

  @enforce_keys [:ok, :network]
  defstruct [:ok, :network]

  @type t :: %__MODULE__{
          ok: boolean(),
          network: String.t()
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

defmodule Antd.GraphDescendant do
  @moduledoc "A descendant entry in a graph node."

  @enforce_keys [:public_key, :content]
  defstruct [:public_key, :content]

  @type t :: %__MODULE__{
          public_key: String.t(),
          content: String.t()
        }
end

defmodule Antd.GraphEntry do
  @moduledoc "A DAG node from the network."

  @enforce_keys [:owner, :parents, :content, :descendants]
  defstruct [:owner, :parents, :content, :descendants]

  @type t :: %__MODULE__{
          owner: String.t(),
          parents: [String.t()],
          content: String.t(),
          descendants: [Antd.GraphDescendant.t()]
        }
end

defmodule Antd.ArchiveEntry do
  @moduledoc "A single entry in a file archive."

  @enforce_keys [:path, :address, :created, :modified, :size]
  defstruct [:path, :address, :created, :modified, :size]

  @type t :: %__MODULE__{
          path: String.t(),
          address: String.t(),
          created: integer(),
          modified: integer(),
          size: integer()
        }
end

defmodule Antd.Archive do
  @moduledoc "A collection of archive entries."

  @enforce_keys [:entries]
  defstruct [:entries]

  @type t :: %__MODULE__{
          entries: [Antd.ArchiveEntry.t()]
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

defmodule Antd.PrepareUploadResult do
  @moduledoc "Result of preparing an upload for external signing."

  @enforce_keys [:upload_id, :payments, :total_amount, :data_payments_address, :payment_token_address, :rpc_url]
  defstruct [:upload_id, :payments, :total_amount, :data_payments_address, :payment_token_address, :rpc_url]

  @type t :: %__MODULE__{
          upload_id: String.t(),
          payments: [Antd.PaymentInfo.t()],
          total_amount: String.t(),
          data_payments_address: String.t(),
          payment_token_address: String.t(),
          rpc_url: String.t()
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
