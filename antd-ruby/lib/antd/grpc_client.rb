# frozen_string_literal: true

# Proto-generated Ruby stubs — produced by `grpc_tools_ruby_protoc`.
# Run:
#   grpc_tools_ruby_protoc \
#     -I../../antd/proto \
#     --ruby_out=lib --grpc_out=lib \
#     antd/v1/common.proto antd/v1/health.proto antd/v1/data.proto \
#     antd/v1/chunks.proto antd/v1/files.proto antd/v1/upload.proto
#
# The generated files are expected under lib/antd/v1/.

require "grpc"
require_relative "v1/health_services_pb"
require_relative "v1/data_services_pb"
require_relative "v1/chunks_services_pb"
require_relative "v1/files_services_pb"
require_relative "v1/upload_services_pb"
require_relative "v1/wallet_services_pb"

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
      @upload_stub = Antd::V1::UploadService::Stub.new(target, :this_channel_is_insecure)
      @wallet_stub = Antd::V1::WalletService::Stub.new(target, :this_channel_is_insecure)
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
      DataPutResult.new(data_map: resp.data_map, chunks_stored: resp.chunks_stored, payment_mode_used: resp.payment_mode_used)
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
      DataPutPublicResult.new(address: resp.address, chunks_stored: resp.chunks_stored, payment_mode_used: resp.payment_mode_used)
    end

    # Retrieve public data by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def data_get_public(address)
      req = Antd::V1::GetPublicDataRequest.new(address: address)
      resp = grpc_call { @data_stub.get_public(req) }
      resp.data
    end

    # Stream private data from a caller-held DataMap (hex), one decrypt batch at
    # a time, instead of buffering the whole object. The gRPC counterpart to
    # +data_get+ and mirror of the REST client's +data_stream+.
    #
    # When a block is given, each raw byte chunk is yielded as it arrives and the
    # method returns +nil+. When no block is given, an +Enumerator+ over the
    # chunks is returned.
    #
    # @param data_map [String] hex-encoded DataMap
    # @yieldparam chunk [String] a raw byte chunk of the decrypted payload
    # @return [nil, Enumerator]
    def data_stream(data_map, &block)
      return enum_for(:data_stream, data_map) unless block_given?

      req = Antd::V1::StreamDataRequest.new(data_map: data_map)
      grpc_call { @data_stub.stream(req).each { |chunk| block.call(chunk.data) } }
      nil
    end

    # Stream public data by address — the gRPC counterpart to +data_get_public+.
    # Same block/Enumerator contract as +data_stream+.
    #
    # @param address [String] hex address
    # @yieldparam chunk [String] a raw byte chunk of the decrypted payload
    # @return [nil, Enumerator]
    def data_stream_public(address, &block)
      return enum_for(:data_stream_public, address) unless block_given?

      req = Antd::V1::StreamPublicDataRequest.new(address: address)
      grpc_call { @data_stub.stream_public(req).each { |chunk| block.call(chunk.data) } }
      nil
    end

    # Like +data_stream+ but requests interleaved fetch-progress frames so the
    # caller can drive a *determinate* progress bar. Sets the request's
    # +include_progress+ flag and yields +DownloadFrame+s — each either a
    # plaintext byte chunk (+frame.data+) or a +DownloadProgress+ update
    # (+frame.progress+). The byte denominator is surfaced as a leading
    # +DownloadFrame+ (+frame.meta+), read from the response's
    # +x-content-length+ initial metadata before any chunk.
    #
    # When a block is given each frame is yielded and the method returns +nil+;
    # otherwise an +Enumerator+ over the frames is returned.
    #
    # @param data_map [String] hex-encoded DataMap
    # @yieldparam frame [DownloadFrame]
    # @return [nil, Enumerator]
    def data_stream_with_progress(data_map, &block)
      return enum_for(:data_stream_with_progress, data_map) unless block_given?

      req = Antd::V1::StreamDataRequest.new(data_map: data_map, include_progress: true)
      grpc_call { stream_with_progress(@data_stub.stream(req, return_op: true), &block) }
      nil
    end

    # Like +data_stream_public+ but requests interleaved fetch-progress frames.
    # See +data_stream_with_progress+ for the contract.
    #
    # @param address [String] hex address
    # @yieldparam frame [DownloadFrame]
    # @return [nil, Enumerator]
    def data_stream_public_with_progress(address, &block)
      return enum_for(:data_stream_public_with_progress, address) unless block_given?

      req = Antd::V1::StreamPublicDataRequest.new(address: address, include_progress: true)
      grpc_call { stream_with_progress(@data_stub.stream_public(req, return_op: true), &block) }
      nil
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

    # --- External Signer (chunks) ---

    # Prepare a single chunk for external-signer publish.
    #
    # When the chunk is already on-network the result has
    # +already_stored: true+ and the caller can skip +finalize_chunk_upload+
    # entirely.
    #
    # @param data [String] raw chunk bytes
    # @return [PrepareChunkResult]
    def prepare_chunk_upload(data)
      req = Antd::V1::PrepareChunkRequest.new(data: data.b)
      resp = grpc_call { @chunk_stub.prepare_chunk(req) }
      PrepareChunkResult.new(
        address: resp.address,
        already_stored: resp.already_stored,
        upload_id: resp.upload_id,
        payment_type: resp.payment_type,
        payments: resp.payments.map { |p|
          PaymentInfo.new(
            quote_hash: p.quote_hash,
            rewards_address: p.rewards_address,
            amount: p.amount
          )
        },
        total_amount: resp.total_amount,
        payment_vault_address: resp.payment_vault_address,
        payment_token_address: resp.payment_token_address,
        rpc_url: resp.rpc_url
      )
    end

    # Submit a prepared chunk after external payment. Returns the chunk address.
    #
    # @param upload_id [String]
    # @param tx_hashes [Hash<String, String>]
    # @return [String] hex chunk address
    def finalize_chunk_upload(upload_id, tx_hashes)
      req = Antd::V1::FinalizeChunkRequest.new(
        upload_id: upload_id,
        tx_hashes: tx_hashes
      )
      resp = grpc_call { @chunk_stub.finalize_chunk(req) }
      resp.address
    end

    # --- External Signer (uploads) ---

    # Prepare a file upload for external signing.
    #
    # @param path [String] local file path on the daemon host
    # @param visibility [String, nil] +"private"+ (default when nil) or
    #   +"public"+ to bundle the DataMap chunk into the same external-signer
    #   payment batch
    # @return [PrepareUploadResult]
    def prepare_upload(path, visibility: nil)
      req = Antd::V1::PrepareFileUploadRequest.new(
        path: path,
        visibility: visibility.to_s
      )
      resp = grpc_call { @upload_stub.prepare_file_upload(req) }
      build_prepare_upload_result(resp)
    end

    # Convenience wrapper for +prepare_upload(path, visibility: "public")+.
    #
    # @param path [String]
    # @return [PrepareUploadResult]
    def prepare_upload_public(path)
      prepare_upload(path, visibility: "public")
    end

    # Prepare an in-memory data upload for external signing.
    #
    # @param data [String] raw bytes
    # @param visibility [String, nil] same semantics as +prepare_upload+
    # @return [PrepareUploadResult]
    def prepare_data_upload(data, visibility: nil)
      req = Antd::V1::PrepareDataUploadRequest.new(
        data: data.b,
        visibility: visibility.to_s
      )
      resp = grpc_call { @upload_stub.prepare_data_upload(req) }
      build_prepare_upload_result(resp)
    end

    # Finalize a wave-batch upload after external payment.
    #
    # @param upload_id [String]
    # @param tx_hashes [Hash<String, String>]
    # @return [FinalizeUploadResult]
    def finalize_upload(upload_id, tx_hashes)
      req = Antd::V1::FinalizeUploadRequest.new(
        upload_id: upload_id,
        tx_hashes: tx_hashes
      )
      resp = grpc_call { @upload_stub.finalize_upload(req) }
      FinalizeUploadResult.new(
        address: resp.address,
        chunks_stored: resp.chunks_stored.to_i,
        data_map: resp.data_map,
        data_map_address: resp.data_map_address
      )
    end

    # Finalize a merkle-batch upload after the winning pool has been
    # determined.
    #
    # @param upload_id [String]
    # @param winner_pool_hash [String]
    # @param store_data_map [Boolean]
    # @return [FinalizeUploadResult]
    def finalize_merkle_upload(upload_id, winner_pool_hash, store_data_map: false)
      req = Antd::V1::FinalizeUploadRequest.new(
        upload_id: upload_id,
        winner_pool_hash: winner_pool_hash,
        store_data_map: store_data_map
      )
      resp = grpc_call { @upload_stub.finalize_upload(req) }
      FinalizeUploadResult.new(
        address: resp.address,
        chunks_stored: resp.chunks_stored.to_i,
        data_map: resp.data_map,
        data_map_address: resp.data_map_address
      )
    end

    # --- Wallet ---

    # V2-286: parity with REST Antd::Client. A missing daemon wallet emits
    # GRPC::FailedPrecondition which grpc_call surfaces as PaymentError
    # (established FailedPrecondition->Payment convention across all SDKs).

    # @return [WalletAddress]
    def wallet_address
      resp = grpc_call { @wallet_stub.get_address(Antd::V1::GetWalletAddressRequest.new) }
      WalletAddress.new(address: resp.address)
    end

    # @return [WalletBalance]
    def wallet_balance
      resp = grpc_call { @wallet_stub.get_balance(Antd::V1::GetWalletBalanceRequest.new) }
      WalletBalance.new(balance: resp.balance, gas_balance: resp.gas_balance)
    end

    # @return [Boolean]
    def wallet_approve
      resp = grpc_call { @wallet_stub.approve(Antd::V1::WalletApproveRequest.new) }
      resp.approved
    end

    private

    # Drives a +return_op: true+ server-streaming call, yielding +DownloadFrame+s.
    # The byte denominator is surfaced first as a leading +DownloadFrame+ (its
    # +meta+ set), read from the response's +x-content-length+ initial metadata;
    # then each wire +DataChunk+ is mapped to a data/progress frame.
    #
    # +op+ is a +GRPC::ActiveCall::Operation+ (from calling the stub method with
    # +return_op: true+). +op.execute+ returns the response enumerator and starts
    # the call; +op.metadata+ then holds the server's initial metadata. An
    # absent or unparseable +x-content-length+ (older daemons) yields no Meta
    # frame.
    def stream_with_progress(op)
      responses = op.execute
      meta = meta_frame_from_op(op)
      yield meta unless meta.nil?
      responses.each { |chunk| yield frame_from_chunk(chunk) }
    end

    # Builds a leading byte-total +DownloadFrame+ from a server-stream
    # operation's +x-content-length+ initial metadata, or +nil+ when the header
    # is absent or unparseable.
    def meta_frame_from_op(op)
      md = op.metadata
      return nil if md.nil?

      value = md["x-content-length"]
      return nil if value.nil?

      value = value.first if value.is_a?(Array)
      total = Integer(value, 10) rescue nil
      return nil if total.nil?

      DownloadFrame.new(meta: total)
    end

    # Maps a wire +DataChunk+ (oneof kind {data | progress}) onto a public
    # +DownloadFrame+. A chunk with no arm set (shouldn't occur) is treated as
    # an empty data frame, matching the antd-rust reference consumer.
    def frame_from_chunk(chunk)
      if chunk.kind == :progress
        p = chunk.progress
        DownloadFrame.new(progress: DownloadProgress.new(phase: p.phase, fetched: p.fetched, total: p.total))
      else
        DownloadFrame.new(data: chunk.data)
      end
    end

    # Maps a PrepareUploadResponse proto into a +PrepareUploadResult+ struct,
    # populating the merkle-only fields (+depth+, +pool_commitments+,
    # +merkle_payment_timestamp+) only when +payment_type+ is +"merkle"+.
    def build_prepare_upload_result(resp)
      is_merkle = resp.payment_type == "merkle"
      pool_commitments = if is_merkle
        resp.pool_commitments.map { |pc|
          PoolCommitmentEntry.new(
            pool_hash: pc.pool_hash,
            candidates: pc.candidates.map { |c|
              CandidateNodeEntry.new(
                rewards_address: c.rewards_address,
                amount: c.amount
              )
            }
          )
        }
      end
      PrepareUploadResult.new(
        upload_id: resp.upload_id,
        payments: resp.payments.map { |p|
          PaymentInfo.new(
            quote_hash: p.quote_hash,
            rewards_address: p.rewards_address,
            amount: p.amount
          )
        },
        total_amount: resp.total_amount,
        payment_vault_address: resp.payment_vault_address,
        payment_token_address: resp.payment_token_address,
        rpc_url: resp.rpc_url,
        payment_type: resp.payment_type,
        depth: is_merkle ? resp.depth : nil,
        pool_commitments: pool_commitments,
        merkle_payment_timestamp: is_merkle ? resp.merkle_payment_timestamp.to_i : nil
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
      raise AntdError.new(e.message, status_code: e.code)
    end
  end
end
