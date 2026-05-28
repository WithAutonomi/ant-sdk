defmodule Antd.V1.GetChunkRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetChunkRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.GetChunkResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetChunkResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutChunkRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutChunkRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutChunkResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutChunkResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :cost, 1, type: Antd.V1.Cost
  field :address, 2, type: :string
end

defmodule Antd.V1.PrepareChunkRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PrepareChunkRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PrepareChunkResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PrepareChunkResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :already_stored, 2, type: :bool, json_name: "alreadyStored"
  field :upload_id, 3, type: :string, json_name: "uploadId"
  field :payment_type, 4, type: :string, json_name: "paymentType"
  field :payments, 5, repeated: true, type: Antd.V1.PaymentEntry
  field :total_amount, 6, type: :string, json_name: "totalAmount"
  field :payment_vault_address, 7, type: :string, json_name: "paymentVaultAddress"
  field :payment_token_address, 8, type: :string, json_name: "paymentTokenAddress"
  field :rpc_url, 9, type: :string, json_name: "rpcUrl"
end

defmodule Antd.V1.FinalizeChunkRequest.TxHashesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizeChunkRequest.TxHashesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Antd.V1.FinalizeChunkRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizeChunkRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :upload_id, 1, type: :string, json_name: "uploadId"

  field :tx_hashes, 2,
    repeated: true,
    type: Antd.V1.FinalizeChunkRequest.TxHashesEntry,
    json_name: "txHashes",
    map: true
end

defmodule Antd.V1.FinalizeChunkResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizeChunkResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.ChunkService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.ChunkService", protoc_gen_elixir_version: "0.16.0"

  rpc :Get, Antd.V1.GetChunkRequest, Antd.V1.GetChunkResponse

  rpc :Put, Antd.V1.PutChunkRequest, Antd.V1.PutChunkResponse

  rpc :PrepareChunk, Antd.V1.PrepareChunkRequest, Antd.V1.PrepareChunkResponse

  rpc :FinalizeChunk, Antd.V1.FinalizeChunkRequest, Antd.V1.FinalizeChunkResponse
end

defmodule Antd.V1.ChunkService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.ChunkService.Service
end
