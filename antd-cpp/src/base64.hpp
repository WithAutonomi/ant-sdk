#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace antd::detail {

/// Encode binary data to base64.
std::string base64_encode(const std::vector<uint8_t>& data);

/// Decode a base64 string to binary data.
std::vector<uint8_t> base64_decode(std::string_view encoded);

}  // namespace antd::detail
