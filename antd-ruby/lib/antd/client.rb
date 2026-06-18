# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "uri"

module Antd
  DEFAULT_BASE_URL = "http://localhost:8082"
  DEFAULT_TIMEOUT  = 300 # seconds

  # REST client for the antd daemon.
  class Client
    # Creates a client using port discovery.
    #
    # Reads the daemon.port file to find the REST port. Falls back to the
    # default base URL if the port file is not found.
    #
    # @param kwargs [Hash] options passed to +initialize+ (e.g. +:timeout+)
    # @return [Array(Client, String)] the client and the resolved URL
    def self.auto_discover(**kwargs)
      url = Antd::Discover.daemon_url
      url = DEFAULT_BASE_URL if url.empty?
      [new(base_url: url, **kwargs), url]
    end

    # @param base_url [String] Base URL of the antd daemon
    # @param timeout  [Integer] HTTP request timeout in seconds
    def initialize(base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT)
      @base_url = base_url.chomp("/")
      @timeout  = timeout
    end

    # --- Health ---

    # Check daemon status.
    # @return [HealthStatus]
    def health
      j = do_json(:get, "/health")
      HealthStatus.new(
        ok: j["status"] == "ok",
        network: j["network"],
        version: j.fetch("version", ""),
        evm_network: j.fetch("evm_network", ""),
        uptime_seconds: j.fetch("uptime_seconds", 0),
        build_commit: j.fetch("build_commit", ""),
        payment_token_address: j.fetch("payment_token_address", ""),
        payment_vault_address: j.fetch("payment_vault_address", "")
      )
    end

    # --- Data ---

    # Store private encrypted data on the network. Returns the caller-held
    # DataMap (hex). The DataMap is NOT stored on-network.
    # @param data [String] raw bytes
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [DataPutResult]
    def data_put(data, payment_mode: PaymentMode::AUTO)
      j = do_json(:post, "/v1/data", { data: b64_encode(data), payment_mode: payment_mode })
      DataPutResult.new(
        data_map: j["data_map"] || "",
        chunks_stored: (j["chunks_stored"] || 0).to_i,
        payment_mode_used: j["payment_mode_used"] || ""
      )
    end

    # Retrieve private data from a caller-held DataMap (hex).
    # @param data_map [String]
    # @return [String] raw bytes
    def data_get(data_map)
      j = do_json(:post, "/v1/data/get", { data_map: data_map })
      b64_decode(j["data"])
    end

    # Stream private data from a caller-held DataMap (hex) — the streaming
    # counterpart to +data_get+. Decrypted bytes arrive in chunks, keeping
    # memory usage constant regardless of payload size.
    #
    # When a block is given, each raw byte chunk is yielded as it arrives and
    # the method returns +nil+ once the body is fully consumed. When no block
    # is given, an +Enumerator+ over the chunks is returned (lazy — the HTTP
    # request runs when the enumerator is iterated).
    #
    # @param data_map [String]
    # @yieldparam chunk [String] a raw byte chunk of the decrypted payload
    # @return [nil, Enumerator]
    def data_stream(data_map, &block)
      return enum_for(:data_stream, data_map) unless block_given?

      do_stream(:post, "/v1/data/stream", { data_map: data_map }, &block)
    end

    # Store public data. The DataMap is stored on-network as an extra chunk;
    # the returned address is the shareable retrieval handle.
    # @param data [String] raw bytes
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [DataPutPublicResult]
    def data_put_public(data, payment_mode: PaymentMode::AUTO)
      j = do_json(:post, "/v1/data/public", { data: b64_encode(data), payment_mode: payment_mode })
      DataPutPublicResult.new(
        address: j["address"] || "",
        chunks_stored: (j["chunks_stored"] || 0).to_i,
        payment_mode_used: j["payment_mode_used"] || ""
      )
    end

    # Retrieve public data by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def data_get_public(address)
      j = do_json(:get, "/v1/data/public/#{address}")
      b64_decode(j["data"])
    end

    # Stream public data by address — the streaming counterpart to
    # +data_get_public+. Decrypted bytes arrive in chunks, keeping memory
    # usage constant regardless of payload size.
    #
    # When a block is given, each raw byte chunk is yielded as it arrives and
    # the method returns +nil+ once the body is fully consumed. When no block
    # is given, an +Enumerator+ over the chunks is returned (lazy — the HTTP
    # request runs when the enumerator is iterated).
    #
    # @param address [String] hex address
    # @yieldparam chunk [String] a raw byte chunk of the payload
    # @return [nil, Enumerator]
    def data_stream_public(address, &block)
      return enum_for(:data_stream_public, address) unless block_given?

      do_stream(:get, "/v1/data/public/#{address}/stream", nil, &block)
    end

    # Pre-upload cost breakdown for the given bytes.
    # @param data [String] raw bytes
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [UploadCostEstimate]
    def data_cost(data, payment_mode: PaymentMode::AUTO)
      j = do_json(:post, "/v1/data/cost", { data: b64_encode(data), payment_mode: payment_mode })
      UploadCostEstimate.new(
        cost: j["cost"] || "",
        file_size: j["file_size"] || 0,
        chunk_count: j["chunk_count"] || 0,
        estimated_gas_cost_wei: j["estimated_gas_cost_wei"] || "",
        payment_mode: j["payment_mode"] || ""
      )
    end

    # --- Chunks ---

    # Store a raw chunk on the network.
    # @param data [String] raw bytes
    # @return [PutResult]
    def chunk_put(data)
      j = do_json(:post, "/v1/chunks", { data: b64_encode(data) })
      PutResult.new(cost: j["cost"], address: j["address"])
    end

    # Retrieve a chunk by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def chunk_get(address)
      j = do_json(:get, "/v1/chunks/#{address}")
      b64_decode(j["data"])
    end

    # Prepare a single chunk for external-signer publish.
    #
    # Returns either +already_stored: true+ (no payment needed) or a wave-batch
    # payment intent. After the external signer pays, call
    # +finalize_chunk_upload+ with the resulting tx hashes.
    #
    # Unlike +chunk_put+, this method does NOT require the daemon to have a
    # wallet — all funds flow through the external signer.
    #
    # @param data [String] raw chunk bytes
    # @return [PrepareChunkResult]
    def prepare_chunk_upload(data)
      j = do_json(:post, "/v1/chunks/prepare", { data: b64_encode(data) })
      parse_prepare_chunk_response(j)
    end

    # Submit a prepared chunk to the network after external payment.
    #
    # @param upload_id [String] the upload ID from +prepare_chunk_upload+
    # @param tx_hashes [Hash<String, String>] map of quote_hash to tx_hash
    # @return [String] network address of the stored chunk
    #   (matches +PrepareChunkResult#address+)
    def finalize_chunk_upload(upload_id, tx_hashes)
      j = do_json(:post, "/v1/chunks/finalize", {
        upload_id: upload_id,
        tx_hashes: tx_hashes
      })
      j["address"] || ""
    end

    # --- Files ---

    # Upload a file privately. Returns the caller-held DataMap (hex).
    # @param path [String] local file path
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [FilePutResult]
    def file_put(path, payment_mode: PaymentMode::AUTO)
      j = do_json(:post, "/v1/files", { path: path, payment_mode: payment_mode })
      FilePutResult.new(
        data_map: j["data_map"] || "",
        storage_cost_atto: j["storage_cost_atto"] || "",
        gas_cost_wei: j["gas_cost_wei"] || "",
        chunks_stored: (j["chunks_stored"] || 0).to_i,
        payment_mode_used: j["payment_mode_used"] || ""
      )
    end

    # Download a private file from a caller-held DataMap into +dest_path+.
    # @param data_map [String]
    # @param dest_path [String]
    # @return [void]
    def file_get(data_map, dest_path)
      do_json(:post, "/v1/files/get", { data_map: data_map, dest_path: dest_path })
      nil
    end

    # Upload a file publicly. The DataMap is stored on-network as an extra
    # chunk; the returned address is the shareable retrieval handle.
    # @param path [String] local file path
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [FilePutPublicResult]
    def file_put_public(path, payment_mode: PaymentMode::AUTO)
      j = do_json(:post, "/v1/files/public", { path: path, payment_mode: payment_mode })
      FilePutPublicResult.new(
        address: j["address"] || "",
        storage_cost_atto: j["storage_cost_atto"] || "",
        gas_cost_wei: j["gas_cost_wei"] || "",
        chunks_stored: (j["chunks_stored"] || 0).to_i,
        payment_mode_used: j["payment_mode_used"] || ""
      )
    end

    # Download a public file from an on-network DataMap address.
    # @param address [String]
    # @param dest_path [String]
    # @return [void]
    def file_get_public(address, dest_path)
      do_json(:post, "/v1/files/public/get", { address: address, dest_path: dest_path })
      nil
    end

    # Pre-upload cost breakdown for the file at +path+.
    # @param path [String]
    # @param is_public [Boolean]
    # @param payment_mode [String] PaymentMode::AUTO | MERKLE | SINGLE
    # @return [UploadCostEstimate]
    def file_cost(path, is_public, payment_mode: PaymentMode::AUTO)
      j = do_json(:post, "/v1/files/cost", {
        path: path,
        is_public: is_public,
        payment_mode: payment_mode
      })
      UploadCostEstimate.new(
        cost: j["cost"] || "",
        file_size: j["file_size"] || 0,
        chunk_count: j["chunk_count"] || 0,
        estimated_gas_cost_wei: j["estimated_gas_cost_wei"] || "",
        payment_mode: j["payment_mode"] || ""
      )
    end

    # --- Wallet ---

    # Get the wallet address configured on the daemon.
    # @return [WalletAddress]
    def wallet_address
      j = do_json(:get, "/v1/wallet/address")
      WalletAddress.new(address: j["address"])
    end

    # Get the wallet balance and gas balance.
    # @return [WalletBalance]
    def wallet_balance
      j = do_json(:get, "/v1/wallet/balance")
      WalletBalance.new(balance: j["balance"], gas_balance: j["gas_balance"])
    end

    # Approve the wallet to spend tokens on payment contracts (one-time operation).
    # @return [Boolean]
    def wallet_approve
      j = do_json(:post, "/v1/wallet/approve", {})
      j["approved"] == true
    end

    # --- External Signer (Two-Phase Upload) ---

    # Prepare a file upload for external signing.
    #
    # @param path [String] local file path
    # @param visibility [String, nil] +"public"+ to bundle the DataMap chunk
    #   into the same external-signer payment batch (the resulting
    #   +data_map_address+ on finalize is the shareable retrieval handle).
    #   +"private"+ or +nil+ keeps the existing private-only behaviour. When
    #   +nil+, the +visibility+ JSON field is omitted entirely to preserve
    #   the pre-public daemon wire shape.
    # @return [PrepareUploadResult]
    def prepare_upload(path, visibility: nil)
      body = { path: path }
      body[:visibility] = visibility unless visibility.nil?
      j = do_json(:post, "/v1/upload/prepare", body)
      parse_prepare_response(j)
    end

    # Convenience wrapper: prepare a *public* file upload for external signing.
    #
    # Equivalent to +prepare_upload(path, visibility: "public")+. In addition
    # to the data chunks, the daemon bundles the serialized DataMap chunk into
    # the same payment batch — the external signer signs ONE EVM transaction
    # covering chunks + DataMap. After +finalize_upload+, the result's
    # +data_map_address+ is the shareable retrieval handle.
    #
    # @param path [String] local file path
    # @return [PrepareUploadResult]
    def prepare_upload_public(path)
      prepare_upload(path, visibility: "public")
    end

    # Prepare a data upload for external signing.
    # Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    # @param data [String] raw bytes to upload
    # @return [PrepareUploadResult]
    def prepare_data_upload(data)
      j = do_json(:post, "/v1/data/prepare", { data: b64_encode(data) })
      parse_prepare_response(j)
    end

    # Finalize an upload after an external signer has submitted payment transactions.
    # @param upload_id [String] the upload ID from prepare_upload
    # @param tx_hashes [Hash<String, String>] map of quote_hash to tx_hash
    # @return [FinalizeUploadResult]
    def finalize_upload(upload_id, tx_hashes)
      j = do_json(:post, "/v1/upload/finalize", {
        upload_id: upload_id,
        tx_hashes: tx_hashes
      })
      parse_finalize_response(j)
    end

    # Finalize a merkle-batch upload after selecting a winning pool.
    # @param upload_id [String] the upload ID from prepare_upload
    # @param winner_pool_hash [String] hash of the winning pool commitment
    # @param store_data_map [Boolean] whether to store the data map on-network
    # @return [FinalizeUploadResult]
    def finalize_merkle_upload(upload_id, winner_pool_hash, store_data_map: false)
      j = do_json(:post, "/v1/upload/finalize", {
        upload_id: upload_id,
        winner_pool_hash: winner_pool_hash,
        store_data_map: store_data_map
      })
      parse_finalize_response(j)
    end

    private

    # Parse a /v1/upload/finalize JSON response into a FinalizeUploadResult.
    #
    # +data_map_address+ is populated only when prepare was called with
    # visibility="public" — the DataMap chunk was paid + stored in the same
    # external-signer batch.
    def parse_finalize_response(j)
      FinalizeUploadResult.new(
        address: j["address"] || "",
        chunks_stored: (j["chunks_stored"] || 0).to_i,
        data_map: j["data_map"] || "",
        data_map_address: j["data_map_address"] || ""
      )
    end

    # Parse a /v1/chunks/prepare JSON response into a PrepareChunkResult.
    def parse_prepare_chunk_response(j)
      payments = (j["payments"] || []).map do |p|
        PaymentInfo.new(
          quote_hash: p["quote_hash"],
          rewards_address: p["rewards_address"],
          amount: p["amount"]
        )
      end

      PrepareChunkResult.new(
        address: j["address"] || "",
        already_stored: j["already_stored"] == true,
        upload_id: j["upload_id"] || "",
        payment_type: j["payment_type"] || "",
        payments: payments,
        total_amount: j["total_amount"] || "",
        payment_vault_address: j["payment_vault_address"] || "",
        payment_token_address: j["payment_token_address"] || "",
        rpc_url: j["rpc_url"] || ""
      )
    end

    # Parse a prepare-upload JSON response into a PrepareUploadResult.
    def parse_prepare_response(j)
      payment_type = j["payment_type"] || "wave_batch"

      payments = (j["payments"] || []).map do |p|
        PaymentInfo.new(
          quote_hash: p["quote_hash"],
          rewards_address: p["rewards_address"],
          amount: p["amount"]
        )
      end

      pool_commitments = []
      if payment_type == "merkle_batch"
        (j["pool_commitments"] || []).each do |pc|
          candidates = (pc["candidates"] || []).map do |c|
            CandidateNodeEntry.new(
              rewards_address: c["rewards_address"] || "",
              amount: c["amount"] || ""
            )
          end
          pool_commitments << PoolCommitmentEntry.new(
            pool_hash: pc["pool_hash"] || "",
            candidates: candidates
          )
        end
      end

      PrepareUploadResult.new(
        upload_id: j["upload_id"] || "",
        payments: payments,
        total_amount: j["total_amount"] || "",
        payment_vault_address: j["payment_vault_address"] || "",
        payment_token_address: j["payment_token_address"] || "",
        rpc_url: j["rpc_url"] || "",
        payment_type: payment_type,
        depth: j["depth"] || 0,
        pool_commitments: pool_commitments,
        merkle_payment_timestamp: j["merkle_payment_timestamp"] || 0,
        total_chunks: j["total_chunks"] || 0,
        already_stored_count: j["already_stored_count"] || 0
      )
    end

    def b64_encode(data)
      Base64.strict_encode64(data)
    end

    def b64_decode(str)
      Base64.strict_decode64(str)
    end

    def build_uri(path)
      URI("#{@base_url}#{path}")
    end

    # Perform a JSON HTTP request and return the parsed response body.
    def do_json(method, path, body = nil)
      uri = build_uri(path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      request = case method
                when :get  then Net::HTTP::Get.new(uri)
                when :post then Net::HTTP::Post.new(uri)
                when :put  then Net::HTTP::Put.new(uri)
                end

      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      response = http.request(request)
      code = response.code.to_i

      unless (200...300).cover?(code)
        msg = response.body.to_s
        begin
          parsed = JSON.parse(msg)
          msg = parsed["error"] if parsed["error"]
        rescue JSON::ParserError
          # use raw body as message
        end
        raise Antd.error_for_status(code, msg)
      end

      return {} if response.body.nil? || response.body.empty?

      JSON.parse(response.body)
    end

    # Perform a streaming HTTP request, yielding raw body chunks to +block+ as
    # they arrive. Reuses the same base-URL / timeout / error-mapping plumbing
    # as +do_json+, but never buffers the success body in memory.
    #
    # On a non-2xx response the (short) body is read fully, parsed for an
    # +{"error":...}+ field, and raised via +Antd.error_for_status+ — mirroring
    # +do_json+. On 2xx, chunks are streamed straight to the block.
    def do_stream(method, path, body = nil)
      uri = build_uri(path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      request = case method
                when :get  then Net::HTTP::Get.new(uri)
                when :post then Net::HTTP::Post.new(uri)
                when :put  then Net::HTTP::Put.new(uri)
                end

      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      http.start do
        http.request(request) do |response|
          code = response.code.to_i

          unless (200...300).cover?(code)
            msg = response.body.to_s
            begin
              parsed = JSON.parse(msg)
              msg = parsed["error"] if parsed["error"]
            rescue JSON::ParserError
              # use raw body as message
            end
            raise Antd.error_for_status(code, msg)
          end

          response.read_body do |chunk|
            yield chunk unless chunk.empty?
          end
        end
      end

      nil
    end

    # Perform an HTTP HEAD request and return the status code.
    def do_head(path)
      uri = build_uri(path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      request = Net::HTTP::Head.new(uri)
      response = http.request(request)
      response.code.to_i
    end
  end
end
