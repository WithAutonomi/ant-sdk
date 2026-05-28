defmodule Antd.V1.GetWalletAddressRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetWalletAddressRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Antd.V1.GetWalletAddressResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetWalletAddressResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.GetWalletBalanceRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetWalletBalanceRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Antd.V1.GetWalletBalanceResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetWalletBalanceResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :balance, 1, type: :string
  field :gas_balance, 2, type: :string, json_name: "gasBalance"
end

defmodule Antd.V1.WalletApproveRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.WalletApproveRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Antd.V1.WalletApproveResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.WalletApproveResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :approved, 1, type: :bool
end

defmodule Antd.V1.WalletService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.WalletService", protoc_gen_elixir_version: "0.16.0"

  rpc :GetAddress, Antd.V1.GetWalletAddressRequest, Antd.V1.GetWalletAddressResponse

  rpc :GetBalance, Antd.V1.GetWalletBalanceRequest, Antd.V1.GetWalletBalanceResponse

  rpc :Approve, Antd.V1.WalletApproveRequest, Antd.V1.WalletApproveResponse
end

defmodule Antd.V1.WalletService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.WalletService.Service
end
