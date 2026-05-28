defmodule Antd.V1.Cost do
  @moduledoc false

  use Protobuf, full_name: "antd.v1.Cost", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :atto_tokens, 1, type: :string, json_name: "attoTokens"
  field :file_size, 2, type: :uint64, json_name: "fileSize"
  field :chunk_count, 3, type: :uint32, json_name: "chunkCount"
  field :estimated_gas_cost_wei, 4, type: :string, json_name: "estimatedGasCostWei"
  field :payment_mode, 5, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.Address do
  @moduledoc false

  use Protobuf, full_name: "antd.v1.Address", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :hex, 1, type: :string
end

defmodule Antd.V1.PublicKeyProto do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PublicKeyProto",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :hex, 1, type: :string
end

defmodule Antd.V1.SecretKeyProto do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.SecretKeyProto",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :hex, 1, type: :string
end

defmodule Antd.V1.PaymentEntry do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PaymentEntry",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :quote_hash, 1, type: :string, json_name: "quoteHash"
  field :rewards_address, 2, type: :string, json_name: "rewardsAddress"
  field :amount, 3, type: :string
end
