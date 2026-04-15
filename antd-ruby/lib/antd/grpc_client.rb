# frozen_string_literal: true

# Proto-generated Ruby stubs — produced by `grpc_tools_ruby_protoc`.
# Run:
#   grpc_tools_ruby_protoc \
#     -I../../antd/proto \
#     --ruby_out=lib --grpc_out=lib \
#     antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
#     antd/v1/chunks.proto antd/v1/files.proto
#
# The generated files are expected under lib/antd/v1/.

require "grpc"
require_relative "v1/health_services_pb"
require_relative "v1/data_services_pb"
require_relative "v1/chunks_services_pb"
require_relative "v1/files_services_pb"

module Antd
  DEFAULT_GRPC_TARGET = "localhost:50051"

  # gRPC client for the antd daemon.
  #
  # Provides the same methods as the REST +Client+, but communicates over
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

    # --- Files ---

    # Upload a local file to the network.
    # @param path [String] local file path
    # @return [FileUploadResult]
    def file_upload_public(path)
      req = Antd::V1::UploadFileRequest.new(path: path)
      resp = grpc_call { @file_stub.upload_public(req) }
      file_upload_result_from_proto(resp)
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
    # @return [FileUploadResult]
    def dir_upload_public(path)
      req = Antd::V1::UploadFileRequest.new(path: path)
      resp = grpc_call { @file_stub.dir_upload_public(req) }
      file_upload_result_from_proto(resp)
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

    # Estimate the cost of uploading a file.
    # @param path [String]
    # @param is_public [Boolean]
    # @return [String] cost in atto tokens
    def file_cost(path, is_public)
      req = Antd::V1::FileCostRequest.new(
        path: path,
        is_public: is_public
      )
      resp = grpc_call { @file_stub.get_file_cost(req) }
      resp.atto_tokens
    end

    private

    # Build a FileUploadResult from an UploadPublicResponse proto.
    def file_upload_result_from_proto(resp)
      FileUploadResult.new(
        address: resp.address,
        storage_cost_atto: resp.storage_cost_atto,
        gas_cost_wei: resp.gas_cost_wei,
        chunks_stored: resp.chunks_stored,
        payment_mode_used: resp.payment_mode_used
      )
    end

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
