# frozen_string_literal: true

require "base64"
require_relative "models"
require_relative "errors"
require_relative "client"

# Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
# of files, each with an optional path and size and either an embedded
# DataMap or a public DataMap address. The daemon builds and decodes them
# through ant-core, so callers never re-implement the format. Nothing is
# uploaded or paid for.
#
# This file holds the models and the REST methods on +Antd::Client+;
# grpc_manifests.rb adds the same methods to +Antd::GrpcClient+.
module Antd
  # +ManifestEntryInfo#kind+ values.
  module ManifestEntryKind
    # The manifest carries the entry's DataMap: it is the key to the file.
    EMBEDDED = "embedded"
    # The manifest carries a public file's DataMap address.
    PUBLIC   = "public"
  end

  # +DecodedManifest#source+ values.
  module ManifestSource
    # `.ant` bytes or an `ant://manifest/` link.
    MANIFEST  = "manifest"
    # A file link or bare address, reported as one public entry with no path.
    FILE_LINK = "file_link"
  end

  # One file for +build_manifest+. Set exactly one of +data_map+ or
  # +address+; a Hash with the same keys works too.
  #
  # - +path+: the relative path the entry extracts under, subject to the
  #   portable path rules. nil: it extracts under its content address.
  # - +size+: the plaintext size to record, as given (the creator's claim).
  #   nil: none is recorded; readers take the exact size from an embedded
  #   root DataMap.
  # - +data_map+: a hex DataMap, as the upload methods return it. The entry
  #   embeds it.
  # - +address+: a public file's DataMap address (hex, 32 bytes).
  ManifestEntryInput = Struct.new(:path, :size, :data_map, :address, keyword_init: true) do
    def initialize(path: nil, size: nil, data_map: nil, address: nil)
      super
    end
  end

  # What a manifest says about one entry. Unset fields are nil on both
  # transports (REST omits them; gRPC sends no value or an empty string),
  # so a +size+ or +exact_size+ the manifest lacks is nil, never 0.
  #
  # - +effective_name+: +path+, or the content address in hex when there is
  #   none.
  # - +path+: the entry's path, or nil.
  # - +size+: the size recorded in the manifest (the creator's claim), or nil.
  # - +kind+: a +ManifestEntryKind+ string.
  # - +content_address+: hex. The file's public DataMap address, whether or
  #   not it was ever made public; the same for private and public uploads
  #   of one file.
  # - +data_map+: the embedded DataMap in the hex form the download methods
  #   accept. Decode only; nil for public entries.
  # - +exact_size+: the exact plaintext size, from an embedded root DataMap
  #   or after a resolving decode; nil when unknown.
  # - +error+: why a resolving decode failed for this entry, or nil. A
  #   failed entry does not fail the call.
  ManifestEntryInfo = Struct.new(
    :effective_name, :path, :size, :kind, :content_address, :data_map, :exact_size, :error,
    keyword_init: true
  ) do
    def initialize(effective_name: "", path: nil, size: nil, kind: "", content_address: "",
                   data_map: nil, exact_size: nil, error: nil)
      super
    end
  end

  # Result of +build_manifest+.
  #
  # - +manifest+: the `.ant` bytes (a binary String).
  # - +link+: the `ant://manifest/` link, or nil when it would not fit the
  #   recommended 1,500 bytes.
  # - +entries+: +ManifestEntryInfo+s in encoded order (sorted by effective
  #   name).
  BuiltManifest = Struct.new(:manifest, :link, :entries, keyword_init: true)

  # Result of +decode_manifest+ and +decode_manifest_link+.
  #
  # - +source+: a +ManifestSource+ string.
  # - +name+: the suggested root directory name, or nil.
  # - +torrent_info_hash_v1+, +torrent_info_hash_v2+: hex, or nil when absent.
  # - +entries+: +ManifestEntryInfo+s.
  DecodedManifest = Struct.new(
    :source, :name, :torrent_info_hash_v1, :torrent_info_hash_v2, :entries,
    keyword_init: true
  )

  # The gRPC message ceiling for manifest calls, both ways: a manifest can be
  # 64 MiB, and a decode response carries its DataMaps in hex. gRPC's default
  # receive limit is 4 MiB.
  MANIFEST_GRPC_MAX_MESSAGE = 256 * 1024 * 1024

  # Normalises +build_manifest+ entries to +ManifestEntryInput+s, rejecting
  # an entry with both or neither of +data_map+ and +address+ (nil and ""
  # count as unset) or a +size+ that is not a non-negative Integer, before
  # anything is sent.
  #
  # @api private
  # @param entries [Array<ManifestEntryInput, Hash>]
  # @return [Array<ManifestEntryInput>]
  # @raise [ArgumentError]
  def self.manifest_entry_inputs(entries)
    raise ArgumentError, "antd: manifest entries must be an Array" unless entries.is_a?(Array)

    entries.each_with_index.map do |e, i|
      e = ManifestEntryInput.new(**e.transform_keys(&:to_sym)) if e.is_a?(Hash)
      unless e.is_a?(ManifestEntryInput)
        raise ArgumentError, "antd: manifest entry #{i}: expected a ManifestEntryInput or Hash"
      end

      has_data_map = !(e.data_map.nil? || e.data_map.empty?)
      has_address = !(e.address.nil? || e.address.empty?)
      if has_data_map == has_address
        raise ArgumentError, "antd: manifest entry #{i}: set exactly one of data_map or address"
      end
      unless e.size.nil? || (e.size.is_a?(Integer) && e.size >= 0)
        raise ArgumentError, "antd: manifest entry #{i}: size must be a non-negative Integer or nil"
      end

      e
    end
  end

  class Client
    # --- Manifests ---

    # Build a `.ant` manifest from DataMaps and public addresses already in
    # hand (POST /v1/manifests/build). Nothing is uploaded or paid for.
    #
    # By default the daemon resolves each shrunk DataMap's root (fetching its
    # wrapper records) and embeds it when it is at most 64 KiB, so recipients
    # skip that fetch (ADR-0006's policy). That reads from the network, so the
    # call can time out; it is safe to retry.
    #
    # Needs the antd release after 0.15.0.
    #
    # @param entries [Array<ManifestEntryInput, Hash>] each with exactly one
    #   of +data_map+ or +address+; checked before anything is sent
    # @param name [String, nil] suggested root directory name (one portable
    #   path component)
    # @param torrent_info_hashes [Array<String>, nil] BitTorrent info hashes
    #   of the same files: hex, 40 characters for v1 and/or 64 for v2
    # @param embed_roots [Boolean] false embeds shrunk DataMaps exactly as
    #   given (the wire's +embed_roots+; default true)
    # @return [BuiltManifest]
    # @raise [ArgumentError] an entry with both or neither of +data_map+ and
    #   +address+, or a bad +size+
    # @raise [BadRequestError] an entry the daemon rejects; the message names
    #   +entries[i]+
    def build_manifest(entries, name: nil, torrent_info_hashes: nil, embed_roots: true)
      inputs = Antd.manifest_entry_inputs(entries)
      wire = inputs.map do |e|
        m = {}
        m[:path] = e.path unless e.path.nil? || e.path.empty?
        m[:size] = e.size unless e.size.nil?
        if e.data_map.nil? || e.data_map.empty?
          m[:address] = e.address
        else
          m[:data_map] = e.data_map
        end
        m
      end
      body = { entries: wire, embed_roots: embed_roots ? true : false }
      body[:name] = name unless name.nil? || name.empty?
      hashes = Array(torrent_info_hashes)
      body[:torrent_info_hashes] = hashes unless hashes.empty?

      j = do_json(:post, "/v1/manifests/build", body)
      BuiltManifest.new(
        manifest: manifest_bytes_from_b64(j["manifest"]),
        link: manifest_string(j["link"]),
        entries: manifest_entry_infos(j["entries"])
      )
    end

    # Decode `.ant` bytes (POST /v1/manifests/decode). With +resolve+, the
    # daemon fetches each entry's DataMap (and wrapper records) to report
    # +exact_size+ and confirm the DataMap is on the network; content chunks
    # are not fetched, and one entry's failure is reported in its +error+,
    # not as a failed call. Nothing is paid for; safe to retry.
    #
    # Needs the antd release after 0.15.0.
    #
    # @param manifest [String] the `.ant` bytes
    # @param resolve [Boolean]
    # @return [DecodedManifest]
    # @raise [ArgumentError] an empty +manifest+
    # @raise [BadRequestError] bytes that are not a manifest
    def decode_manifest(manifest, resolve: false)
      raise ArgumentError, "antd: decode_manifest: manifest is empty" if manifest.nil? || manifest.empty?

      post_manifest_decode({ manifest: b64_encode(manifest), resolve: resolve ? true : false })
    end

    # Decode an `ant://` manifest link, file link or bare 64-hex address
    # (POST /v1/manifests/decode). See +decode_manifest+ for +resolve+.
    #
    # Needs the antd release after 0.15.0.
    #
    # @param link [String]
    # @param resolve [Boolean]
    # @return [DecodedManifest]
    # @raise [ArgumentError] an empty +link+
    # @raise [BadRequestError] a link the daemon cannot read
    def decode_manifest_link(link, resolve: false)
      raise ArgumentError, "antd: decode_manifest_link: link is empty" if link.nil? || link.empty?

      post_manifest_decode({ link: link, resolve: resolve ? true : false })
    end

    private

    def post_manifest_decode(body)
      j = do_json(:post, "/v1/manifests/decode", body)
      DecodedManifest.new(
        source: j["source"] || "",
        name: manifest_string(j["name"]),
        torrent_info_hash_v1: manifest_string(j["torrent_info_hash_v1"]),
        torrent_info_hash_v2: manifest_string(j["torrent_info_hash_v2"]),
        entries: manifest_entry_infos(j["entries"])
      )
    end

    # The build response's base64 `.ant` bytes, raw.
    def manifest_bytes_from_b64(value)
      b64_decode(value.to_s)
    rescue ArgumentError => e
      raise InternalError, "build_manifest: manifest is not valid base64: #{e.message}"
    end

    def manifest_entry_infos(raw)
      return [] unless raw.is_a?(Array)

      raw.filter_map do |e|
        next unless e.is_a?(Hash)

        ManifestEntryInfo.new(
          effective_name: e["effective_name"] || "",
          path: manifest_string(e["path"]),
          size: manifest_size(e["size"]),
          kind: e["kind"] || "",
          content_address: e["content_address"] || "",
          data_map: manifest_string(e["data_map"]),
          exact_size: manifest_size(e["exact_size"]),
          error: manifest_string(e["error"])
        )
      end
    end

    # An optional size: a JSON integer, or nil when absent (never 0).
    def manifest_size(value)
      value.is_a?(Integer) && value >= 0 ? value : nil
    end

    # An optional string: nil when absent or empty.
    def manifest_string(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end
  end
end
