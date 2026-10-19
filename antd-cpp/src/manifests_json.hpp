#pragma once

/// @file manifests_json.hpp
/// REST wire mapping for the manifest API (internal; used by client.cpp).

#include <cstdint>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

#include "antd/manifests.hpp"

namespace antd::detail {

/// The POST /v1/manifests/build body. Checks the entries first (throws
/// BadRequestError naming `entries[i]`).
nlohmann::json manifest_build_body(const std::vector<ManifestEntryInput>& entries,
                                   const BuildManifestOptions& options);

/// The POST /v1/manifests/decode body for `.ant` bytes (sent as base64).
nlohmann::json manifest_decode_bytes_body(const std::vector<uint8_t>& manifest, bool resolve);

/// The POST /v1/manifests/decode body for a link or bare address.
nlohmann::json manifest_decode_link_body(std::string_view link, bool resolve);

/// Parse a build response; the base64 `manifest` becomes raw bytes.
BuiltManifest parse_built_manifest(const nlohmann::json& j);

/// Parse a decode response.
DecodedManifest parse_decoded_manifest(const nlohmann::json& j);

}  // namespace antd::detail
