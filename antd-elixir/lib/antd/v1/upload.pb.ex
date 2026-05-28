defmodule Antd.V1.PrepareFileUploadRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PrepareFileUploadRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :path, 1, type: :string
  field :visibility, 2, type: :string
end

defmodule Antd.V1.PrepareDataUploadRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PrepareDataUploadRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data, 1, type: :bytes
  field :visibility, 2, type: :string
end

defmodule Antd.V1.PrepareUploadResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PrepareUploadResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :upload_id, 1, type: :string, json_name: "uploadId"
  field :payment_type, 2, type: :string, json_name: "paymentType"
  field :payments, 3, repeated: true, type: Antd.V1.PaymentEntry
  field :depth, 4, type: :uint32

  field :pool_commitments, 5,
    repeated: true,
    type: Antd.V1.PoolCommitmentEntry,
    json_name: "poolCommitments"

  field :merkle_payment_timestamp, 6, type: :uint64, json_name: "merklePaymentTimestamp"
  field :total_amount, 7, type: :string, json_name: "totalAmount"
  field :payment_vault_address, 8, type: :string, json_name: "paymentVaultAddress"
  field :payment_token_address, 9, type: :string, json_name: "paymentTokenAddress"
  field :rpc_url, 10, type: :string, json_name: "rpcUrl"
end

defmodule Antd.V1.PoolCommitmentEntry do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.PoolCommitmentEntry",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :pool_hash, 1, type: :string, json_name: "poolHash"
  field :candidates, 2, repeated: true, type: Antd.V1.CandidateNodeEntry
end

defmodule Antd.V1.CandidateNodeEntry do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.CandidateNodeEntry",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :rewards_address, 1, type: :string, json_name: "rewardsAddress"
  field :amount, 2, type: :string
end

defmodule Antd.V1.FinalizeUploadRequest.TxHashesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizeUploadRequest.TxHashesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Antd.V1.FinalizeUploadRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizeUploadRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :upload_id, 1, type: :string, json_name: "uploadId"

  field :tx_hashes, 2,
    repeated: true,
    type: Antd.V1.FinalizeUploadRequest.TxHashesEntry,
    json_name: "txHashes",
    map: true

  field :winner_pool_hash, 3, type: :string, json_name: "winnerPoolHash"
  field :store_data_map, 4, type: :bool, json_name: "storeDataMap"
end

defmodule Antd.V1.FinalizeUploadResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.FinalizeUploadResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :data_map, 1, type: :string, json_name: "dataMap"
  field :address, 2, type: :string
  field :data_map_address, 3, type: :string, json_name: "dataMapAddress"
  field :chunks_stored, 4, type: :uint64, json_name: "chunksStored"
end

defmodule Antd.V1.UploadService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.UploadService", protoc_gen_elixir_version: "0.16.0"

  rpc :PrepareFileUpload, Antd.V1.PrepareFileUploadRequest, Antd.V1.PrepareUploadResponse

  rpc :PrepareDataUpload, Antd.V1.PrepareDataUploadRequest, Antd.V1.PrepareUploadResponse

  rpc :FinalizeUpload, Antd.V1.FinalizeUploadRequest, Antd.V1.FinalizeUploadResponse
end

defmodule Antd.V1.UploadService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.UploadService.Service
end
