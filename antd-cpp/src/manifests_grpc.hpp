#pragma once

/// @file manifests_grpc.hpp
/// gRPC wire mapping for the manifest API (internal; used by grpc_client.cpp).

#include <cstdint>
#include <string_view>
#include <vector>

#include <grpcpp/grpcpp.h>

#include "antd/manifests.hpp"
#include "antd/v1/manifests.pb.h"

namespace antd::detail {

/// The max receive and send message size of the ManifestService channel: a
/// manifest can be 64 MiB, a decode response carries its DataMaps in hex, and
/// the daemon accepts requests up to 100 MiB. Matches antd-go's
/// maxManifestGrpcMessage.
inline constexpr int kMaxManifestGrpcMessageBytes = 256 * 1024 * 1024;

/// The arguments of the channel ManifestService calls use: gRPC's 4 MiB
/// default receive limit raised, and the send limit set, to
/// kMaxManifestGrpcMessageBytes. C++ gRPC has no per-call message limit, so
/// the manifest calls get their own channel instead of raising the limits for
/// every service.
grpc::ChannelArguments manifest_channel_arguments();

/// The Build request. Checks the entries first (throws BadRequestError
/// naming `entries[i]`).
antd::v1::BuildManifestRequest manifest_build_request(
    const std::vector<ManifestEntryInput>& entries, const BuildManifestOptions& options);

/// The Decode request for raw `.ant` bytes.
antd::v1::DecodeManifestRequest manifest_decode_bytes_request(
    const std::vector<uint8_t>& manifest, bool resolve);

/// The Decode request for a link or bare address.
antd::v1::DecodeManifestRequest manifest_decode_link_request(std::string_view link,
                                                             bool resolve);

BuiltManifest built_manifest_from_pb(const antd::v1::BuildManifestResponse& resp);

DecodedManifest decoded_manifest_from_pb(const antd::v1::DecodeManifestResponse& resp);

}  // namespace antd::detail
