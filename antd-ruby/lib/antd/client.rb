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
      HealthStatus.new(ok: j["status"] == "ok", network: j["network"])
    end

    # --- Data ---

    # Store public immutable data on the network.
    # @param data [String] raw bytes
    # @return [PutResult]
    def data_put_public(data, payment_mode: nil)
      body = { data: b64_encode(data) }
      body[:payment_mode] = payment_mode if payment_mode
      j = do_json(:post, "/v1/data/public", body)
      PutResult.new(cost: j["cost"], address: j["address"])
    end

    # Retrieve public data by address.
    # @param address [String] hex address
    # @return [String] raw bytes
    def data_get_public(address)
      j = do_json(:get, "/v1/data/public/#{address}")
      b64_decode(j["data"])
    end

    # Store private encrypted data on the network.
    # @param data [String] raw bytes
    # @return [PutResult]
    def data_put_private(data, payment_mode: nil)
      body = { data: b64_encode(data) }
      body[:payment_mode] = payment_mode if payment_mode
      j = do_json(:post, "/v1/data/private", body)
      PutResult.new(cost: j["cost"], address: j["data_map"])
    end

    # Retrieve private data using a data map.
    # @param data_map [String]
    # @return [String] raw bytes
    def data_get_private(data_map)
      j = do_json(:get, "/v1/data/private?data_map=#{URI.encode_www_form_component(data_map)}")
      b64_decode(j["data"])
    end

    # Estimate the cost of storing data.
    # @param data [String] raw bytes
    # @return [String] cost in atto tokens
    def data_cost(data)
      j = do_json(:post, "/v1/data/cost", { data: b64_encode(data) })
      j["cost"]
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

    # --- Graph ---

    # Create a new graph entry (DAG node).
    # @param owner_secret_key [String]
    # @param parents [Array<String>]
    # @param content [String]
    # @param descendants [Array<GraphDescendant>]
    # @return [PutResult]
    def graph_entry_put(owner_secret_key, parents, content, descendants)
      descs = descendants.map { |d| { public_key: d.public_key, content: d.content } }
      j = do_json(:post, "/v1/graph", {
        owner_secret_key: owner_secret_key,
        parents: parents,
        content: content,
        descendants: descs
      })
      PutResult.new(cost: j["cost"], address: j["address"])
    end

    # Retrieve a graph entry by address.
    # @param address [String]
    # @return [GraphEntry]
    def graph_entry_get(address)
      j = do_json(:get, "/v1/graph/#{address}")
      descs = (j["descendants"] || []).map do |d|
        GraphDescendant.new(public_key: d["public_key"], content: d["content"])
      end
      GraphEntry.new(
        owner: j["owner"],
        parents: j["parents"] || [],
        content: j["content"],
        descendants: descs
      )
    end

    # Check if a graph entry exists at the given address.
    # @param address [String]
    # @return [Boolean]
    def graph_entry_exists(address)
      code = do_head("/v1/graph/#{address}")
      return false if code == 404
      raise Antd.error_for_status(code, "graph entry exists check failed") if code >= 300

      true
    end

    # Estimate the cost of creating a graph entry.
    # @param public_key [String]
    # @return [String] cost in atto tokens
    def graph_entry_cost(public_key)
      j = do_json(:post, "/v1/graph/cost", { public_key: public_key })
      j["cost"]
    end

    # --- Files ---

    # Upload a local file to the network.
    # @param path [String] local file path
    # @return [PutResult]
    def file_upload_public(path, payment_mode: nil)
      body = { path: path }
      body[:payment_mode] = payment_mode if payment_mode
      j = do_json(:post, "/v1/files/upload/public", body)
      PutResult.new(cost: j["cost"], address: j["address"])
    end

    # Download a file from the network to a local path.
    # @param address [String]
    # @param dest_path [String]
    # @return [void]
    def file_download_public(address, dest_path)
      do_json(:post, "/v1/files/download/public", { address: address, dest_path: dest_path })
      nil
    end

    # Upload a local directory to the network.
    # @param path [String] local directory path
    # @return [PutResult]
    def dir_upload_public(path, payment_mode: nil)
      body = { path: path }
      body[:payment_mode] = payment_mode if payment_mode
      j = do_json(:post, "/v1/dirs/upload/public", body)
      PutResult.new(cost: j["cost"], address: j["address"])
    end

    # Download a directory from the network to a local path.
    # @param address [String]
    # @param dest_path [String]
    # @return [void]
    def dir_download_public(address, dest_path)
      do_json(:post, "/v1/dirs/download/public", { address: address, dest_path: dest_path })
      nil
    end

    # Retrieve an archive manifest by address.
    # @param address [String]
    # @return [Archive]
    def archive_get_public(address)
      j = do_json(:get, "/v1/archives/public/#{address}")
      entries = (j["entries"] || []).map do |e|
        ArchiveEntry.new(
          path: e["path"],
          address: e["address"],
          created: e["created"].to_i,
          modified: e["modified"].to_i,
          size: e["size"].to_i
        )
      end
      Archive.new(entries: entries)
    end

    # Create an archive manifest on the network.
    # @param archive [Archive]
    # @return [PutResult]
    def archive_put_public(archive)
      entries = archive.entries.map do |e|
        { path: e.path, address: e.address, created: e.created, modified: e.modified, size: e.size }
      end
      j = do_json(:post, "/v1/archives/public", { entries: entries })
      PutResult.new(cost: j["cost"], address: j["address"])
    end

    # Estimate the cost of uploading a file.
    # @param path [String]
    # @param is_public [Boolean]
    # @param include_archive [Boolean]
    # @return [String] cost in atto tokens
    def file_cost(path, is_public, include_archive)
      j = do_json(:post, "/v1/cost/file", {
        path: path,
        is_public: is_public,
        include_archive: include_archive
      })
      j["cost"]
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
    # @param path [String] local file path
    # @return [PrepareUploadResult]
    def prepare_upload(path)
      j = do_json(:post, "/v1/upload/prepare", { path: path })
      payments = (j["payments"] || []).map do |p|
        PaymentInfo.new(
          quote_hash: p["quote_hash"],
          rewards_address: p["rewards_address"],
          amount: p["amount"]
        )
      end
      PrepareUploadResult.new(
        upload_id: j["upload_id"],
        payments: payments,
        total_amount: j["total_amount"],
        data_payments_address: j["data_payments_address"],
        payment_token_address: j["payment_token_address"],
        rpc_url: j["rpc_url"]
      )
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
      FinalizeUploadResult.new(address: j["address"], chunks_stored: j["chunks_stored"].to_i)
    end

    private

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
