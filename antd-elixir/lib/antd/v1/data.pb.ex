defmodule Antd.V1.GetPublicDataRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :address, 1, type: :string
end

defmodule Antd.V1.GetPublicDataResponse do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutPublicDataRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.PutPublicDataResponse do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :cost, 1, type: Antd.V1.Cost
  field :address, 2, type: :string
end

defmodule Antd.V1.StreamPublicDataRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :address, 1, type: :string
end

defmodule Antd.V1.DataChunk do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
end

defmodule Antd.V1.GetDataRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data_map, 1, type: :string, json_name: "dataMap"
end

defmodule Antd.V1.GetDataResponse do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutDataRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.PutDataResponse do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :cost, 1, type: Antd.V1.Cost
  field :data_map, 2, type: :string, json_name: "dataMap"
end

defmodule Antd.V1.DataCostRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
  field :payment_mode, 2, type: :string, json_name: "paymentMode"
end

defmodule Antd.V1.DataService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.DataService", protoc_gen_elixir_version: "0.13.0"

  rpc :Put, Antd.V1.PutDataRequest, Antd.V1.PutDataResponse

  rpc :PutPublic, Antd.V1.PutPublicDataRequest, Antd.V1.PutPublicDataResponse

  rpc :Get, Antd.V1.GetDataRequest, Antd.V1.GetDataResponse

  rpc :GetPublic, Antd.V1.GetPublicDataRequest, Antd.V1.GetPublicDataResponse

  rpc :StreamPublic, Antd.V1.StreamPublicDataRequest, stream(Antd.V1.DataChunk)

  rpc :Cost, Antd.V1.DataCostRequest, Antd.V1.Cost
end

defmodule Antd.V1.DataService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.DataService.Service
end