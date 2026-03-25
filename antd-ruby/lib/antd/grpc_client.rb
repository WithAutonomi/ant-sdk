# frozen_string_literal: true

# Proto-generated Ruby stubs — produced by `grpc_tools_ruby_protoc`.
# Run:
#   grpc_tools_ruby_protoc \
#     -I../../antd/proto \
#     --ruby_out=lib --grpc_out=lib \
#     antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
#     antd/v1/chunks.proto antd/v1/graph.proto antd/v1/files.proto
#
# The generated files are expected under lib/antd/v1/.

require "grpc"
require_relative "v1/health_services_pb"
require_relative "v1/data_services_pb"
require_relative "v1/chunks_services_pb"
require_relative "v1/graph_services_pb"
require_relative "v1/files_services_pb"

module Antd
  DEFAULT_GRPC_TARGET = "localhost:50051"

  # gRPC client for the antd daemon.
  #
  # Provides the same 19 methods as the REST +Client+, but communicates over
  # gRPC using the proto-generated stubs from +antd/v1/*.proto+.
  class GrpcClient
    # Creates a gRPC client using port discovery.
    #
    # Reads the daemon.port file to find the gRPC port. Falls back to the
    # default target if the port file is not found.
    #
    # @return [Array(GrpcClient, String)] the client and the resolved target
    def self.auto_discover
      target = Antd::Discover.grpc_target
      target = DEFAULT_GRPC_TARGET if target.empty?
      [new(target: target), target]
    end

    # @param target [String] gRPC target address (default: "localhost:50051")
    def initialize(target: DEFAULT_GRPC_TARGET)
      @target = target
      @health_stub = Antd::V1::HealthService::Stub.new(target, :this_channel_is_insecure)
      @data_stub   = Antd::V1::DataService::Stub.new(target, :this_channel_is_insecure)
      @chunk_stub  = Antd::V1::ChunkService::Stub.new(target, :this_channel_is_insecure)
      @graph_stub  = Antd::V1::GraphService::Stub.new(target, :this_channel_is_insecure)
      @file_stub   = Antd::V1::FileService::Stub.new(target, :this_channel_is_insecure)
    end

    # --- Health ---

    # Check daemon status.
    # @return [HealthStatus]
    def health
      resp = grpc_call { @health_stub.check(Antd::V1::HealthCheckRequest.new) }
      HealthStatus.new(ok: resp.status == "ok", network: resp.network)
    end

    # --- Data ---

    # Store public immutable data on the network.
    # @param data [String] raw bytes
    # @return [PutResult]
    def data_put_public(data)
      req = Antd::V1::PutPublicDataRequest.new(data: data.b)
      resp = grpc_call { @data_stub.put_public(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.address)
    end

    # Retrieve public data by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def data_get_public(address)
      req = Antd::V1::GetPublicDataRequest.new(address: address)
      resp = grpc_call { @data_stub.get_public(req) }
      resp.data
    end

    # Store private encrypted data on the network.
    # @param data [String] raw bytes
    # @return [PutResult]
    def data_put_private(data)
      req = Antd::V1::PutPrivateDataRequest.new(data: data.b)
      resp = grpc_call { @data_stub.put_private(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.data_map)
    end

    # Retrieve private data using a data map.
    # @param data_map [String]
    # @return [String] raw bytes
    def data_get_private(data_map)
      req = Antd::V1::GetPrivateDataRequest.new(data_map: data_map)
      resp = grpc_call { @data_stub.get_private(req) }
      resp.data
    end

    # Estimate the cost of storing data.
    # @param data [String] raw bytes
    # @return [String] cost in atto tokens
    def data_cost(data)
      req = Antd::V1::DataCostRequest.new(data: data.b)
      resp = grpc_call { @data_stub.get_cost(req) }
      resp.atto_tokens
    end

    # --- Chunks ---

    # Store a raw chunk on the network.
    # @param data [String] raw bytes
    # @return [PutResult]
    def chunk_put(data)
      req = Antd::V1::PutChunkRequest.new(data: data.b)
      resp = grpc_call { @chunk_stub.put(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.address)
    end

    # Retrieve a chunk by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def chunk_get(address)
      req = Antd::V1::GetChunkRequest.new(address: address)
      resp = grpc_call { @chunk_stub.get(req) }
      resp.data
    end

    # --- Graph ---

    # Create a new graph entry (DAG node).
    # @param owner_secret_key [String]
    # @param parents [Array<String>]
    # @param content [String]
    # @param descendants [Array<GraphDescendant>]
    # @return [PutResult]
    def graph_entry_put(owner_secret_key, parents, content, descendants)
      descs = descendants.map do |d|
        Antd::V1::GraphDescendant.new(public_key: d.public_key, content: d.content)
      end
      req = Antd::V1::PutGraphEntryRequest.new(
        owner_secret_key: owner_secret_key,
        parents: parents,
        content: content,
        descendants: descs
      )
      resp = grpc_call { @graph_stub.put(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.address)
    end

    # Retrieve a graph entry by address.
    # @param address [String]
    # @return [GraphEntry]
    def graph_entry_get(address)
      req = Antd::V1::GetGraphEntryRequest.new(address: address)
      resp = grpc_call { @graph_stub.get(req) }
      descs = resp.descendants.map do |d|
        GraphDescendant.new(public_key: d.public_key, content: d.content)
      end
      GraphEntry.new(
        owner: resp.owner,
        parents: resp.parents.to_a,
        content: resp.content,
        descendants: descs
      )
    end

    # Check if a graph entry exists at the given address.
    # @param address [String]
    # @return [Boolean]
    def graph_entry_exists(address)
      req = Antd::V1::CheckGraphEntryRequest.new(address: address)
      resp = grpc_call { @graph_stub.check_existence(req) }
      resp.exists
    end

    # Estimate the cost of creating a graph entry.
    # @param public_key [String]
    # @return [String] cost in atto tokens
    def graph_entry_cost(public_key)
      req = Antd::V1::GraphEntryCostRequest.new(public_key: public_key)
      resp = grpc_call { @graph_stub.get_cost(req) }
      resp.atto_tokens
    end

    # --- Files ---

    # Upload a local file to the network.
    # @param path [String] local file path
    # @return [PutResult]
    def file_upload_public(path)
      req = Antd::V1::UploadFileRequest.new(path: path)
      resp = grpc_call { @file_stub.upload_public(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.address)
    end

    # Download a file from the network to a local path.
    # @param address [String]
    # @param dest_path [String]
    # @return [void]
    def file_download_public(address, dest_path)
      req = Antd::V1::DownloadPublicRequest.new(address: address, dest_path: dest_path)
      grpc_call { @file_stub.download_public(req) }
      nil
    end

    # Upload a local directory to the network.
    # @param path [String] local directory path
    # @return [PutResult]
    def dir_upload_public(path)
      req = Antd::V1::UploadFileRequest.new(path: path)
      resp = grpc_call { @file_stub.dir_upload_public(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.address)
    end

    # Download a directory from the network to a local path.
    # @param address [String]
    # @param dest_path [String]
    # @return [void]
    def dir_download_public(address, dest_path)
      req = Antd::V1::DownloadPublicRequest.new(address: address, dest_path: dest_path)
      grpc_call { @file_stub.dir_download_public(req) }
      nil
    end

    # Retrieve an archive manifest by address.
    # @param address [String]
    # @return [Archive]
    def archive_get_public(address)
      req = Antd::V1::ArchiveGetRequest.new(address: address)
      resp = grpc_call { @file_stub.archive_get_public(req) }
      entries = resp.entries.map do |e|
        ArchiveEntry.new(
          path: e.path,
          address: e.address,
          created: e.created,
          modified: e.modified,
          size: e.size
        )
      end
      Archive.new(entries: entries)
    end

    # Create an archive manifest on the network.
    # @param archive [Archive]
    # @return [PutResult]
    def archive_put_public(archive)
      entries = archive.entries.map do |e|
        Antd::V1::ArchiveEntry.new(
          path: e.path,
          address: e.address,
          created: e.created,
          modified: e.modified,
          size: e.size
        )
      end
      req = Antd::V1::ArchivePutRequest.new(entries: entries)
      resp = grpc_call { @file_stub.archive_put_public(req) }
      PutResult.new(cost: resp.cost.atto_tokens, address: resp.address)
    end

    # Estimate the cost of uploading a file.
    # @param path [String]
    # @param is_public [Boolean]
    # @param include_archive [Boolean]
    # @return [String] cost in atto tokens
    def file_cost(path, is_public, include_archive)
      req = Antd::V1::FileCostRequest.new(
        path: path,
        is_public: is_public,
        include_archive: include_archive
      )
      resp = grpc_call { @file_stub.get_file_cost(req) }
      resp.atto_tokens
    end

    private

    # Executes a gRPC call and translates errors to Antd error types.
    def grpc_call
      yield
    rescue GRPC::InvalidArgument => e
      raise BadRequestError, e.message
    rescue GRPC::NotFound => e
      raise NotFoundError, e.message
    rescue GRPC::AlreadyExists => e
      raise AlreadyExistsError, e.message
    rescue GRPC::ResourceExhausted => e
      raise TooLargeError, e.message
    rescue GRPC::Internal => e
      raise InternalError, e.message
    rescue GRPC::Unavailable => e
      raise NetworkError, e.message
    rescue GRPC::FailedPrecondition => e
      raise PaymentError, e.message
    rescue GRPC::BadStatus => e
      raise AntdError.new(e.code, e.message)
    end
  end
end
