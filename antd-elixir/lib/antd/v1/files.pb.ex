defmodule Antd.V1.PutFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :path, 1, type: :string
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.PutFilePublicResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutFilePublicResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 2, type: :string
  field :storage_cost_atto, 3, type: :string, json_name: "storageCostAtto"
  field :gas_cost_wei, 4, type: :string, json_name: "gasCostWei"
  field :chunks_stored, 5, type: :uint64, json_name: "chunksStored"
  field :payment_mode_used, 6, type: :string, json_name: "paymentModeUsed"
end

defmodule Antd.V1.PutFileResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutFileResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data_map, 1, type: :string, json_name: "dataMap"
  field :storage_cost_atto, 2, type: :string, json_name: "storageCostAtto"
  field :gas_cost_wei, 3, type: :string, json_name: "gasCostWei"
  field :chunks_stored, 4, type: :uint64, json_name: "chunksStored"
  field :payment_mode_used, 5, type: :string, json_name: "paymentModeUsed"
end

defmodule Antd.V1.GetFilePublicRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetFilePublicRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :dest_path, 2, type: :string, json_name: "destPath"
end

defmodule Antd.V1.GetFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data_map, 1, type: :string, json_name: "dataMap"
  field :dest_path, 2, type: :string, json_name: "destPath"
end

defmodule Antd.V1.GetFileResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetFileResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Antd.V1.FileCostRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FileCostRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :path, 1, type: :string
  field :is_public, 2, type: :bool, json_name: "isPublic"
  field :payment_mode, 3, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.FileService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.FileService", protoc_gen_elixir_version: "0.16.0"

  rpc :Put, Antd.V1.PutFileRequest, Antd.V1.PutFileResponse

  rpc :PutPublic, Antd.V1.PutFileRequest, Antd.V1.PutFilePublicResponse

  rpc :Get, Antd.V1.GetFileRequest, Antd.V1.GetFileResponse

  rpc :GetPublic, Antd.V1.GetFilePublicRequest, Antd.V1.GetFileResponse

  rpc :Cost, Antd.V1.FileCostRequest, Antd.V1.Cost
end

defmodule Antd.V1.FileService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.FileService.Service
end
