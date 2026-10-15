# frozen_string_literal: true

require_relative "manifests"
require_relative "grpc_client"
require_relative "v1/manifests_services_pb"

# The manifest methods on +Antd::GrpcClient+, over ManifestService. The
# models and the entry check are in manifests.rb, shared with REST.
module Antd
  # Channel arguments for the manifest stub's own channel. grpc-ruby has no
  # per-call message limit, so ManifestService gets a channel of its own
  # with both limits raised to +MANIFEST_GRPC_MAX_MESSAGE+; the other
  # services keep gRPC's defaults.
  MANIFEST_GRPC_CHANNEL_ARGS = {
    "grpc.max_receive_message_length" => MANIFEST_GRPC_MAX_MESSAGE,
    "grpc.max_send_message_length" => MANIFEST_GRPC_MAX_MESSAGE
  }.freeze

  class GrpcClient
    # --- Manifests ---
    #
    # The same methods and models as the REST +Client+ (see there). The
    # `.ant` bytes travel raw over gRPC; REST's base64 never shows. Unset
    # optionals (proto3 +optional+ without a value, or an empty string) read
    # as nil, as REST's omitted fields do.

    # Mirrors +Client#build_manifest+. Nothing is paid for.
    #
    # Needs the antd release after 0.15.0.
    #
    # @return [BuiltManifest]
    # @raise [BadRequestError] an entry with both or neither of +data_map+ and
    #   +address+, or a bad +size+, before anything is sent
    # @raise [BadRequestError] an entry the daemon rejects (INVALID_ARGUMENT);
    #   the message names +entries[i]+
    def build_manifest(entries, name: nil, torrent_info_hashes: nil, embed_roots: true)
      inputs = Antd.manifest_entry_inputs(entries)
      req = Antd::V1::BuildManifestRequest.new(
        torrent_info_hashes: Array(torrent_info_hashes),
        # Always sent, so "unset means true" never depends on the daemon.
        embed_roots: embed_roots ? true : false,
        entries: inputs.map { |e| manifest_entry_input_pb(e) }
      )
      req.name = name unless name.nil? || name.empty?

      resp = grpc_call { manifest_stub.build(req) }
      BuiltManifest.new(
        manifest: resp.manifest,
        link: manifest_pb_string(resp.link),
        entries: resp.entries.map { |e| manifest_entry_info_from_pb(e) }
      )
    end

    # Mirrors +Client#decode_manifest+. The bytes are sent raw.
    #
    # Needs the antd release after 0.15.0.
    #
    # @return [DecodedManifest]
    def decode_manifest(manifest, resolve: false)
      raise BadRequestError, MANIFEST_DECODE_NEEDS_INPUT if manifest.nil? || manifest.empty?

      decode_manifest_pb(Antd::V1::DecodeManifestRequest.new(manifest: manifest.b, resolve: resolve ? true : false))
    end

    # Mirrors +Client#decode_manifest_link+.
    #
    # Needs the antd release after 0.15.0.
    #
    # @return [DecodedManifest]
    def decode_manifest_link(link, resolve: false)
      raise BadRequestError, MANIFEST_DECODE_NEEDS_INPUT if link.nil? || link.empty?

      decode_manifest_pb(Antd::V1::DecodeManifestRequest.new(link: link, resolve: resolve ? true : false))
    end

    private

    # ManifestService on its own channel, with +MANIFEST_GRPC_CHANNEL_ARGS+.
    # Made on first use, so +initialize+ stays as it is.
    def manifest_stub
      @manifest_stub ||= Antd::V1::ManifestService::Stub.new(
        @target, :this_channel_is_insecure, channel_args: MANIFEST_GRPC_CHANNEL_ARGS
      )
    end

    def decode_manifest_pb(req)
      resp = grpc_call { manifest_stub.decode(req) }
      DecodedManifest.new(
        source: resp.source,
        name: resp.has_name? ? manifest_pb_string(resp.name) : nil,
        torrent_info_hash_v1: manifest_pb_string(resp.torrent_info_hash_v1),
        torrent_info_hash_v2: manifest_pb_string(resp.torrent_info_hash_v2),
        entries: resp.entries.map { |e| manifest_entry_info_from_pb(e) }
      )
    end

    def manifest_entry_input_pb(e)
      attrs = {}
      attrs[:path] = e.path unless e.path.nil? || e.path.empty?
      attrs[:size] = e.size unless e.size.nil?
      if e.data_map.nil? || e.data_map.empty?
        attrs[:address] = e.address
      else
        attrs[:data_map] = e.data_map
      end
      Antd::V1::ManifestEntryInput.new(**attrs)
    end

    # proto3 +optional+ sizes are checked for presence: unset is nil, not 0.
    def manifest_entry_info_from_pb(e)
      ManifestEntryInfo.new(
        effective_name: e.effective_name,
        path: e.has_path? ? manifest_pb_string(e.path) : nil,
        size: e.has_size? ? e.size : nil,
        kind: e.kind,
        content_address: e.content_address,
        data_map: manifest_pb_string(e.data_map),
        exact_size: e.has_exact_size? ? e.exact_size : nil,
        error: manifest_pb_string(e.error)
      )
    end

    # A proto string, or nil when empty.
    def manifest_pb_string(value)
      value.nil? || value.empty? ? nil : value
    end
  end
end
