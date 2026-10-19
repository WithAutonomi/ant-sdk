defmodule Antd.V1.ListPointerKeysRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.ListPointerKeysRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Antd.V1.ListPointerKeysResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.ListPointerKeysResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :keys, 1, repeated: true, type: Antd.V1.PointerKey
end

defmodule Antd.V1.PointerKey do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerKey",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.PointerWriteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerWriteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :owner, 1, type: :string
  field :target, 2, type: :string
  field :kind, 3, type: :string
end

defmodule Antd.V1.PointerWriteResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerWriteResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :state_id, 2, type: :string, json_name: "stateId"
  field :counter, 3, type: :string
end

defmodule Antd.V1.PointerTransferRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerTransferRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :owner, 1, type: :string
  field :recipient, 2, type: :string
end

defmodule Antd.V1.PointerTransferResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerTransferResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :state_id, 2, type: :string, json_name: "stateId"
  field :finality, 3, type: Antd.V1.PointerFinality
  field :finality_error, 4, type: :string, json_name: "finalityError"
end

defmodule Antd.V1.GetPointerRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.GetPointerRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.PointerRecord do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerRecord",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :owner, 2, type: :string
  field :counter, 3, type: :string
  field :kind, 4, type: :string
  field :kind_tag, 5, type: :uint32, json_name: "kindTag"
  field :target, 6, type: :string
  field :state_id, 7, type: :string, json_name: "stateId"
  field :is_final, 8, type: :bool, json_name: "isFinal"
  field :transferred_to, 9, type: :string, json_name: "transferredTo"
end

defmodule Antd.V1.ResolvePointerRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.ResolvePointerRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.PointerResolved do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerResolved",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :kind, 1, type: :string
  field :kind_tag, 2, type: :uint32, json_name: "kindTag"
  field :target, 3, type: :string
end

defmodule Antd.V1.PointerFinalityRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerFinalityRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.PointerFinalState do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerFinalState",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :state_id, 1, type: :string, json_name: "stateId"
  field :kind, 2, type: :string
  field :kind_tag, 3, type: :uint32, json_name: "kindTag"
  field :target, 4, type: :string
  field :holders, 5, type: :uint32
  field :transferred_to, 6, type: :string, json_name: "transferredTo"
end

defmodule Antd.V1.PointerFinality do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerFinality",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :group, 2, type: :uint32
  field :answered, 3, type: :uint32
  field :status, 4, type: :string
  field :counter, 5, type: :string
  field :state, 6, type: Antd.V1.PointerFinalState
  field :states, 7, repeated: true, type: Antd.V1.PointerFinalState
  field :majority, 8, type: Antd.V1.PointerFinalState
  field :transferred_to, 9, type: :string, json_name: "transferredTo"
end

defmodule Antd.V1.PointerControllerRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerControllerRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
end

defmodule Antd.V1.PointerController do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PointerController",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :pointer, 1, type: :string
  field :transfers, 2, repeated: true, type: :string
  field :frozen, 3, type: :bool
end

defmodule Antd.V1.PreparePointerRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PreparePointerRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :owner, 1, type: :string
  field :op, 2, type: :string
  field :target, 3, type: :string
  field :kind, 4, type: :string
  field :recipient, 5, type: :string
  field :include_signed_quotes, 6, type: :bool, json_name: "includeSignedQuotes"
end

defmodule Antd.V1.PreparePointerResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PreparePointerResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :upload_id, 1, type: :string, json_name: "uploadId"
  field :op, 2, type: :string
  field :address, 3, type: :string
  field :state_id, 4, type: :string, json_name: "stateId"
  field :counter, 5, type: :string
  field :payment_type, 6, type: :string, json_name: "paymentType"
  field :payments, 7, repeated: true, type: Antd.V1.PaymentEntry
  field :total_amount, 8, type: :string, json_name: "totalAmount"
  field :payment_vault_address, 9, type: :string, json_name: "paymentVaultAddress"
  field :payment_token_address, 10, type: :string, json_name: "paymentTokenAddress"
  field :rpc_url, 11, type: :string, json_name: "rpcUrl"

  field :signed_quotes, 12,
    repeated: true,
    type: Antd.V1.SignedQuoteEntry,
    json_name: "signedQuotes"
end

defmodule Antd.V1.FinalizePointerRequest.TxHashesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizePointerRequest.TxHashesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Antd.V1.FinalizePointerRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizePointerRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :upload_id, 1, type: :string, json_name: "uploadId"

  field :tx_hashes, 2,
    repeated: true,
    type: Antd.V1.FinalizePointerRequest.TxHashesEntry,
    json_name: "txHashes",
    map: true
end

defmodule Antd.V1.FinalizePointerResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizePointerResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :address, 1, type: :string
  field :state_id, 2, type: :string, json_name: "stateId"
  field :counter, 3, type: :string
  field :finality, 4, type: Antd.V1.PointerFinality
end

defmodule Antd.V1.PointerService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.PointerService", protoc_gen_elixir_version: "0.16.0"

  rpc :ListKeys, Antd.V1.ListPointerKeysRequest, Antd.V1.ListPointerKeysResponse

  rpc :Create, Antd.V1.PointerWriteRequest, Antd.V1.PointerWriteResponse

  rpc :Update, Antd.V1.PointerWriteRequest, Antd.V1.PointerWriteResponse

  rpc :Transfer, Antd.V1.PointerTransferRequest, Antd.V1.PointerTransferResponse

  rpc :Get, Antd.V1.GetPointerRequest, Antd.V1.PointerRecord

  rpc :Resolve, Antd.V1.ResolvePointerRequest, Antd.V1.PointerResolved

  rpc :Finality, Antd.V1.PointerFinalityRequest, Antd.V1.PointerFinality

  rpc :Controller, Antd.V1.PointerControllerRequest, Antd.V1.PointerController

  rpc :Prepare, Antd.V1.PreparePointerRequest, Antd.V1.PreparePointerResponse

  rpc :Finalize, Antd.V1.FinalizePointerRequest, Antd.V1.FinalizePointerResponse
end

defmodule Antd.V1.PointerService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.PointerService.Service
end
