#include "manifests_grpc.hpp"

#include <optional>
#include <string>

#include "antd/models.hpp"

namespace antd::detail {

namespace v1 = antd::v1;

// proto3 `optional` fields (`path`, `size`, `exact_size`, `name`) are read by
// presence (has_*), never by value, so an unset size is std::nullopt, not 0.

namespace {

std::vector<ManifestEntryInfo> manifest_entries_from_pb(
    const google::protobuf::RepeatedPtrField<v1::ManifestEntryInfo>& entries) {
    std::vector<ManifestEntryInfo> out;
    out.reserve(static_cast<std::size_t>(entries.size()));
    for (const auto& e : entries) {
        ManifestEntryInfo info;
        info.effective_name = e.effective_name();
        if (e.has_path()) info.path = e.path();
        if (e.has_size()) info.size = e.size();
        info.kind = e.kind();
        info.content_address = e.content_address();
        info.data_map = e.data_map();
        if (e.has_exact_size()) info.exact_size = e.exact_size();
        info.error = e.error();
        info.sha256 = none_if_empty(e.sha256());
        out.push_back(std::move(info));
    }
    return out;
}

}  // namespace

grpc::ChannelArguments manifest_channel_arguments() {
    grpc::ChannelArguments args;
    args.SetMaxReceiveMessageSize(kMaxManifestGrpcMessageBytes);
    args.SetMaxSendMessageSize(kMaxManifestGrpcMessageBytes);
    return args;
}

v1::BuildManifestRequest manifest_build_request(const std::vector<ManifestEntryInput>& entries,
                                                const BuildManifestOptions& options) {
    check_manifest_entries(entries);
    v1::BuildManifestRequest req;
    if (!options.name.empty()) req.set_name(options.name);
    for (const auto& h : options.torrent_info_hashes) {
        req.add_torrent_info_hashes(h);
    }
    // Always set, so the default (embed) never depends on the daemon's.
    req.set_embed_roots(!options.keep_shrunk_data_maps);
    for (const auto& e : entries) {
        auto* in = req.add_entries();
        if (!e.path.empty()) in->set_path(e.path);
        if (e.size) in->set_size(*e.size);
        if (e.sha256 && !e.sha256->empty()) in->set_sha256(*e.sha256);
        if (!e.data_map.empty()) {
            in->set_data_map(e.data_map);
        } else {
            in->set_address(e.address);
        }
    }
    return req;
}

v1::DecodeManifestRequest manifest_decode_bytes_request(const std::vector<uint8_t>& manifest,
                                                        bool resolve) {
    check_manifest_input(manifest.empty());
    v1::DecodeManifestRequest req;
    req.set_manifest(manifest.data(), manifest.size());
    req.set_resolve(resolve);
    return req;
}

v1::DecodeManifestRequest manifest_decode_link_request(std::string_view link, bool resolve) {
    check_manifest_input(link.empty());
    v1::DecodeManifestRequest req;
    req.set_link(std::string(link));
    req.set_resolve(resolve);
    return req;
}

BuiltManifest built_manifest_from_pb(const v1::BuildManifestResponse& resp) {
    const auto& bytes = resp.manifest();
    return BuiltManifest{
        .manifest = std::vector<uint8_t>(bytes.begin(), bytes.end()),
        .link = resp.link(),
        .entries = manifest_entries_from_pb(resp.entries()),
    };
}

DecodedManifest decoded_manifest_from_pb(const v1::DecodeManifestResponse& resp) {
    DecodedManifest out;
    out.source = resp.source();
    if (resp.has_name()) out.name = resp.name();
    out.torrent_info_hash_v1 = resp.torrent_info_hash_v1();
    out.torrent_info_hash_v2 = resp.torrent_info_hash_v2();
    out.entries = manifest_entries_from_pb(resp.entries());
    return out;
}

}  // namespace antd::detail
