defmodule Antd.V1.HealthCheckRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.HealthCheckRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Antd.V1.HealthCheckResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.HealthCheckResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :status, 1, type: :string
  field :network, 2, type: :string
  field :version, 3, type: :string
  field :evm_network, 4, type: :string, json_name: "evmNetwork"
  field :uptime_seconds, 5, type: :uint64, json_name: "uptimeSeconds"
  field :build_commit, 6, type: :string, json_name: "buildCommit"
  field :payment_token_address, 7, type: :string, json_name: "paymentTokenAddress"
  field :payment_vault_address, 8, type: :string, json_name: "paymentVaultAddress"
end

defmodule Antd.V1.HealthService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.HealthService", protoc_gen_elixir_version: "0.16.0"

  rpc :Check, Antd.V1.HealthCheckRequest, Antd.V1.HealthCheckResponse
end

defmodule Antd.V1.HealthService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.HealthService.Service
end
