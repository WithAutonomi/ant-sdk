defmodule Antd.V1.Cost do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :atto_tokens, 1, type: :string, json_name: "attoTokens"
  field :file_size, 2, type: :uint64, json_name: "fileSize"
  field :chunk_count, 3, type: :uint32, json_name: "chunkCount"
  field :estimated_gas_cost_wei, 4, type: :string, json_name: "estimatedGasCostWei"
  field :payment_mode, 5, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.Address do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :hex, 1, type: :string
end

defmodule Antd.V1.PublicKeyProto do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :hex, 1, type: :string
end

defmodule Antd.V1.SecretKeyProto do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :hex, 1, type: :string
end