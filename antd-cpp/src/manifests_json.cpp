#include "manifests_json.hpp"

#include <exception>
#include <optional>
#include <string>

#include "antd/errors.hpp"
#include "base64.hpp"

namespace antd::detail {

using json = nlohmann::json;

// The daemon omits unset fields (`path`, `size`, `exact_size`, `data_map`,
// `error`, `name`, the torrent hashes, a `link` that does not fit). Each field
// is read by type, so an absent, `null` or mistyped value never escapes as a
// nlohmann::json exception: an optional reads as std::nullopt (a size is
// never read as 0) and a string as "".

namespace {

std::string manifest_str(const json& j, const char* key) {
    const auto it = j.find(key);
    return it != j.end() && it->is_string() ? it->get<std::string>() : std::string{};
}

std::optional<std::string> manifest_opt_str(const json& j, const char* key) {
    const auto it = j.find(key);
    if (it == j.end() || !it->is_string()) return std::nullopt;
    return it->get<std::string>();
}

/// A non-negative JSON integer, or std::nullopt when absent, `null` or of any
/// other type.
std::optional<std::uint64_t> manifest_opt_u64(const json& j, const char* key) {
    const auto it = j.find(key);
    if (it == j.end() || !it->is_number_unsigned()) return std::nullopt;
    return it->get<std::uint64_t>();
}

std::vector<ManifestEntryInfo> parse_manifest_entries(const json& j) {
    std::vector<ManifestEntryInfo> out;
    const auto arr = j.find("entries");
    if (arr == j.end() || !arr->is_array()) return out;
    for (const auto& e : *arr) {
        if (!e.is_object()) continue;
        out.push_back(ManifestEntryInfo{
            .effective_name = manifest_str(e, "effective_name"),
            .path = manifest_opt_str(e, "path"),
            .size = manifest_opt_u64(e, "size"),
            .kind = manifest_str(e, "kind"),
            .content_address = manifest_str(e, "content_address"),
            .data_map = manifest_str(e, "data_map"),
            .exact_size = manifest_opt_u64(e, "exact_size"),
            .error = manifest_str(e, "error"),
        });
    }
    return out;
}

}  // namespace

json manifest_build_body(const std::vector<ManifestEntryInput>& entries,
                         const BuildManifestOptions& options) {
    check_manifest_entries(entries);
    json wire = json::array();
    for (const auto& e : entries) {
        json m = json::object();
        if (!e.path.empty()) m["path"] = e.path;
        if (e.size) m["size"] = *e.size;
        if (!e.data_map.empty()) {
            m["data_map"] = e.data_map;
        } else {
            m["address"] = e.address;
        }
        wire.push_back(std::move(m));
    }
    // `embed_roots` is always sent, so the default (embed) never depends on
    // the daemon's own default.
    json body = {
        {"entries", std::move(wire)},
        {"embed_roots", !options.keep_shrunk_data_maps},
    };
    if (!options.name.empty()) body["name"] = options.name;
    if (!options.torrent_info_hashes.empty()) {
        body["torrent_info_hashes"] = options.torrent_info_hashes;
    }
    return body;
}

json manifest_decode_bytes_body(const std::vector<uint8_t>& manifest, bool resolve) {
    check_manifest_input(manifest.empty());
    return json{{"manifest", base64_encode(manifest)}, {"resolve", resolve}};
}

json manifest_decode_link_body(std::string_view link, bool resolve) {
    check_manifest_input(link.empty());
    return json{{"link", std::string(link)}, {"resolve", resolve}};
}

BuiltManifest parse_built_manifest(const json& j) {
    BuiltManifest out;
    try {
        out.manifest = base64_decode(manifest_str(j, "manifest"));
    } catch (const std::exception& e) {
        throw InternalError(std::string("manifest is not valid base64: ") + e.what());
    }
    out.link = manifest_str(j, "link");
    out.entries = parse_manifest_entries(j);
    return out;
}

DecodedManifest parse_decoded_manifest(const json& j) {
    return DecodedManifest{
        .source = manifest_str(j, "source"),
        .name = manifest_opt_str(j, "name"),
        .torrent_info_hash_v1 = manifest_str(j, "torrent_info_hash_v1"),
        .torrent_info_hash_v2 = manifest_str(j, "torrent_info_hash_v2"),
        .entries = parse_manifest_entries(j),
    };
}

}  // namespace antd::detail
