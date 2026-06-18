defmodule Antd.V1.GetPublicDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetPublicDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.GetPublicDataResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetPublicDataResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutPublicDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutPublicDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.PutPublicDataResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutPublicDataResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :cost, 1, type: Antd.V1.Cost
  field :address, 2, type: :string
  field :chunks_stored, 3, type: :uint64, json_name: "chunksStored"
  field :payment_mode_used, 4, type: :string, json_name: "paymentModeUsed"
end

defmodule Antd.V1.StreamPublicDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.StreamPublicDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :include_progress, 2, type: :bool, json_name: "includeProgress"
end

defmodule Antd.V1.DataChunk do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.DataChunk",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :kind, 0

  field :data, 1, type: :bytes, oneof: 0
  field :progress, 2, type: Antd.V1.DownloadProgress, oneof: 0
end

defmodule Antd.V1.DownloadProgress do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.DownloadProgress",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :phase, 1, type: :string
  field :fetched, 2, type: :uint64
  field :total, 3, type: :uint64
end

defmodule Antd.V1.GetDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data_map, 1, type: :string, json_name: "dataMap"
end

defmodule Antd.V1.StreamDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.StreamDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data_map, 1, type: :string, json_name: "dataMap"
  field :include_progress, 2, type: :bool, json_name: "includeProgress"
end

defmodule Antd.V1.GetDataResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetDataResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.PutDataResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PutDataResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :cost, 1, type: Antd.V1.Cost
  field :data_map, 2, type: :string, json_name: "dataMap"
  field :chunks_stored, 3, type: :uint64, json_name: "chunksStored"
  field :payment_mode_used, 4, type: :string, json_name: "paymentModeUsed"
end

defmodule Antd.V1.DataCostRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.DataCostRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.DataService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.DataService", protoc_gen_elixir_version: "0.16.0"

  rpc :Put, Antd.V1.PutDataRequest, Antd.V1.PutDataResponse

  rpc :PutPublic, Antd.V1.PutPublicDataRequest, Antd.V1.PutPublicDataResponse

  rpc :Get, Antd.V1.GetDataRequest, Antd.V1.GetDataResponse

  rpc :GetPublic, Antd.V1.GetPublicDataRequest, Antd.V1.GetPublicDataResponse

  rpc :Stream, Antd.V1.StreamDataRequest, stream(Antd.V1.DataChunk)

  rpc :StreamPublic, Antd.V1.StreamPublicDataRequest, stream(Antd.V1.DataChunk)

  rpc :Cost, Antd.V1.DataCostRequest, Antd.V1.Cost
end

defmodule Antd.V1.DataService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.DataService.Service
end
