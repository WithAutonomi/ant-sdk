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
      HealthStatus.new(
        ok: resp.status == "ok",
        network: resp.network,
        version: resp.version,
        evm_network: resp.evm_network,
        uptime_seconds: resp.uptime_seconds,
        build_commit: resp.build_commit,
        payment_token_address: resp.payment_token_address,
        payment_vault_address: resp.payment_vault_address
      )
    end

    # --- Data ---

    # Store private encrypted data. Returns the caller-held DataMap (hex).
    # @param data [String] raw bytes
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [DataPutResult]
    def data_put(data, payment_mode: PaymentMode::AUTO)
      req = Antd::V1::PutDataRequest.new(data: data.b, payment_mode: payment_mode)
      resp = grpc_call { @data_stub.put(req) }
      DataPutResult.new(data_map: resp.data_map)
    end

    # Retrieve private data from a caller-held DataMap (hex).
    # @param data_map [String]
    # @return [String] raw bytes
    def data_get(data_map)
      req = Antd::V1::GetDataRequest.new(data_map: data_map)
      resp = grpc_call { @data_stub.get(req) }
      resp.data
    end

    # Store public data. Returns the on-network DataMap address.
    # @param data [String] raw bytes
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [DataPutPublicResult]
    def data_put_public(data, payment_mode: PaymentMode::AUTO)
      req = Antd::V1::PutPublicDataRequest.new(data: data.b, payment_mode: payment_mode)
      resp = grpc_call { @data_stub.put_public(req) }
      DataPutPublicResult.new(address: resp.address)
    end

    # Retrieve public data by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def data_get_public(address)
      req = Antd::V1::GetPublicDataRequest.new(address: address)
      resp = grpc_call { @data_stub.get_public(req) }
      resp.data
    end

    # Pre-upload cost breakdown for the given bytes.
    # @param data [String] raw bytes
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [UploadCostEstimate]
    def data_cost(data, payment_mode: PaymentMode::AUTO)
      req = Antd::V1::DataCostRequest.new(data: data.b, payment_mode: payment_mode)
      resp = grpc_call { @data_stub.cost(req) }
      UploadCostEstimate.new(
        cost: resp.atto_tokens,
        file_size: resp.file_size,
        chunk_count: resp.chunk_count,
        estimated_gas_cost_wei: resp.estimated_gas_cost_wei,
        payment_mode: resp.payment_mode
      )
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

    # Upload a file privately. Returns the caller-held DataMap (hex).
    # @param path [String] local file path
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [FilePutResult]
    def file_put(path, payment_mode: PaymentMode::AUTO)
      req = Antd::V1::PutFileRequest.new(path: path, payment_mode: payment_mode)
      resp = grpc_call { @file_stub.put(req) }
      FilePutResult.new(
        data_map: resp.data_map,
        storage_cost_atto: resp.storage_cost_atto,
        gas_cost_wei: resp.gas_cost_wei,
        chunks_stored: resp.chunks_stored,
        payment_mode_used: resp.payment_mode_used
      )
    end

    # Download a private file from a caller-held DataMap.
    # @param data_map [String]
    # @param dest_path [String]
    # @return [void]
    def file_get(data_map, dest_path)
      req = Antd::V1::GetFileRequest.new(data_map: data_map, dest_path: dest_path)
      grpc_call { @file_stub.get(req) }
      nil
    end

    # Upload a file publicly. Returns the on-network DataMap address.
    # @param path [String] local file path
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [FilePutPublicResult]
    def file_put_public(path, payment_mode: PaymentMode::AUTO)
      req = Antd::V1::PutFileRequest.new(path: path, payment_mode: payment_mode)
      resp = grpc_call { @file_stub.put_public(req) }
      FilePutPublicResult.new(
        address: resp.address,
        storage_cost_atto: resp.storage_cost_atto,
        gas_cost_wei: resp.gas_cost_wei,
        chunks_stored: resp.chunks_stored,
        payment_mode_used: resp.payment_mode_used
      )
    end

    # Download a public file from an on-network DataMap address.
    # @param address [String]
    # @param dest_path [String]
    # @return [void]
    def file_get_public(address, dest_path)
      req = Antd::V1::GetFilePublicRequest.new(address: address, dest_path: dest_path)
      grpc_call { @file_stub.get_public(req) }
      nil
    end

    # Pre-upload cost breakdown for the file at +path+.
    # @param path [String]
    # @param is_public [Boolean]
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [UploadCostEstimate]
    def file_cost(path, is_public, payment_mode: PaymentMode::AUTO)
      req = Antd::V1::FileCostRequest.new(
        path: path,
        is_public: is_public,
        payment_mode: payment_mode
      )
      resp = grpc_call { @file_stub.cost(req) }
      UploadCostEstimate.new(
        cost: resp.atto_tokens,
        file_size: resp.file_size,
        chunk_count: resp.chunk_count,
        estimated_gas_cost_wei: resp.estimated_gas_cost_wei,
        payment_mode: resp.payment_mode
      )
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
