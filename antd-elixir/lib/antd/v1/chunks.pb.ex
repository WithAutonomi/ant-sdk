defmodule Antd.V1.GetChunkRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :address, 1, type: :string
end

defmodule Antd.V1.GetChunkResponse do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutChunkRequest do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :data, 1, type: :bytes
end

defmodule Antd.V1.PutChunkResponse do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.13.0"

  field :cost, 1, type: Antd.V1.Cost
  field :address, 2, type: :string
end

defmodule Antd.V1.ChunkService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.ChunkService", protoc_gen_elixir_version: "0.13.0"

  rpc :Get, Antd.V1.GetChunkRequest, Antd.V1.GetChunkResponse

  rpc :Put, Antd.V1.PutChunkRequest, Antd.V1.PutChunkResponse
end

defmodule Antd.V1.ChunkService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.ChunkService.Service
end