defmodule Antd.V1.ManifestEntryInput do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.ManifestEntryInput",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :source, 0

  field :path, 1, proto3_optional: true, type: :string
  field :size, 2, proto3_optional: true, type: :uint64
  field :sha256, 5, proto3_optional: true, type: :string
  field :data_map, 3, type: :string, json_name: "dataMap", oneof: 0
  field :address, 4, type: :string, oneof: 0
end

defmodule Antd.V1.BuildManifestRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.BuildManifestRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :name, 1, proto3_optional: true, type: :string
  field :torrent_info_hashes, 2, repeated: true, type: :string, json_name: "torrentInfoHashes"
  field :embed_roots, 3, proto3_optional: true, type: :bool, json_name: "embedRoots"
  field :entries, 4, repeated: true, type: Antd.V1.ManifestEntryInput
end

defmodule Antd.V1.ManifestEntryInfo do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.ManifestEntryInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :effective_name, 1, type: :string, json_name: "effectiveName"
  field :path, 2, proto3_optional: true, type: :string
  field :size, 3, proto3_optional: true, type: :uint64
  field :kind, 4, type: :string
  field :content_address, 5, type: :string, json_name: "contentAddress"
  field :data_map, 6, type: :string, json_name: "dataMap"
  field :exact_size, 7, proto3_optional: true, type: :uint64, json_name: "exactSize"
  field :error, 8, type: :string
  field :sha256, 9, type: :string
end

defmodule Antd.V1.BuildManifestResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.BuildManifestResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :manifest, 1, type: :bytes
  field :link, 2, type: :string
  field :entries, 3, repeated: true, type: Antd.V1.ManifestEntryInfo
end

defmodule Antd.V1.DecodeManifestRequest do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.DecodeManifestRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :input, 0

  field :manifest, 1, type: :bytes, oneof: 0
  field :link, 2, type: :string, oneof: 0
  field :resolve, 3, type: :bool
end

defmodule Antd.V1.DecodeManifestResponse do
  @moduledoc false

  use Protobuf,
    full_name: "antd.v1.DecodeManifestResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :source, 1, type: :string
  field :name, 2, proto3_optional: true, type: :string
  field :torrent_info_hash_v1, 3, type: :string, json_name: "torrentInfoHashV1"
  field :torrent_info_hash_v2, 4, type: :string, json_name: "torrentInfoHashV2"
  field :entries, 5, repeated: true, type: Antd.V1.ManifestEntryInfo
end

defmodule Antd.V1.ManifestService.Service do
  @moduledoc false

  use GRPC.Service, name: "antd.v1.ManifestService", protoc_gen_elixir_version: "0.16.0"

  rpc :Build, Antd.V1.BuildManifestRequest, Antd.V1.BuildManifestResponse

  rpc :Decode, Antd.V1.DecodeManifestRequest, Antd.V1.DecodeManifestResponse
end

defmodule Antd.V1.ManifestService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Antd.V1.ManifestService.Service
end
