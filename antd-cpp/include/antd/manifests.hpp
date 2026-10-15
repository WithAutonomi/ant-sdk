#pragma once

/// @file manifests.hpp
/// Manifest types (ADR-0006): `.ant` files and `ant://` links.

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "errors.hpp"

namespace antd {

// ---------------------------------------------------------------------------
// Manifests (ADR-0006)
//
// A manifest is a `.ant` file, or an `ant://manifest/` link, that describes a
// set of files: each with an optional path and size, and either an embedded
// DataMap or a public DataMap address. The daemon builds and decodes them
// through ant-core, so callers never re-implement the format. Nothing is
// uploaded or paid for; the network is read only to resolve DataMaps (the
// embedding policy on build, `resolve` on decode), so a call can time out and
// is free to retry.
//
// The `.ant` bytes are raw bytes in this API on both transports (REST carries
// them as base64 in JSON; the client encodes and decodes). Sizes are
// std::optional<std::uint64_t>: unset is std::nullopt, never 0.
// ---------------------------------------------------------------------------

/// One file for build_manifest. Set exactly one of `data_map` or `address`;
/// build_manifest throws BadRequestError before sending anything otherwise.
struct ManifestEntryInput {
    /// The relative path the entry extracts under, subject to the portable
    /// path rules. Empty: it extracts under its content address.
    std::string path{};
    /// The plaintext size to record, as given (the creator's claim). Unset:
    /// none is recorded; readers take the exact size from an embedded root
    /// DataMap.
    std::optional<std::uint64_t> size{};
    /// A hex DataMap, as the upload methods return it. The entry embeds it:
    /// the manifest is the key to the file.
    std::string data_map{};
    /// A public file's DataMap address (hex, 32 bytes).
    std::string address{};
};

/// The optional parts of a build_manifest call. A default-constructed value
/// builds with no name and no torrent hashes, and embeds roots.
struct BuildManifestOptions {
    /// A suggested root directory name (one portable path component). Empty:
    /// none.
    std::string name{};
    /// BitTorrent info hashes of the same files: hex, 40 characters for v1
    /// and/or 64 for v2.
    std::vector<std::string> torrent_info_hashes{};
    /// Embed shrunk DataMaps exactly as given. By default (false) the daemon
    /// resolves each one's root (fetching its wrapper records) and embeds the
    /// root when it is at most 64 KiB, so recipients skip that fetch
    /// (ADR-0006's policy). Sent as `embed_roots = !keep_shrunk_data_maps`.
    bool keep_shrunk_data_maps{false};
};

/// What a manifest says about one entry.
struct ManifestEntryInfo {
    /// `path`, or the content address in hex when there is none.
    std::string effective_name;
    std::optional<std::string> path;
    /// The size recorded in the manifest: the creator's claim.
    std::optional<std::uint64_t> size;
    /// "embedded" or "public".
    std::string kind;
    /// Hex. The file's public DataMap address, whether or not it was ever
    /// made public; the same for private and public uploads of one file.
    std::string content_address;
    /// The embedded DataMap in the hex form the download methods accept.
    /// Decode only; empty for public entries.
    std::string data_map;
    /// The exact plaintext size: from an embedded root DataMap, or after a
    /// resolving decode.
    std::optional<std::uint64_t> exact_size;
    /// Why a resolving decode failed for this entry. Empty when it didn't:
    /// one entry's failure is reported here, not as a failed call.
    std::string error;
};

/// The result of build_manifest.
struct BuiltManifest {
    /// The `.ant` bytes.
    std::vector<uint8_t> manifest;
    /// The `ant://manifest/` link, set only when it fits the recommended
    /// 1,500 bytes. Empty otherwise.
    std::string link;
    /// In encoded order (sorted by effective name).
    std::vector<ManifestEntryInfo> entries;
};

/// The result of decode_manifest and decode_manifest_link.
struct DecodedManifest {
    /// "manifest", or "file_link" for a file link or bare address (reported
    /// as one public entry with no path).
    std::string source;
    std::optional<std::string> name;
    /// Hex; empty when absent.
    std::string torrent_info_hash_v1;
    /// Hex; empty when absent.
    std::string torrent_info_hash_v2;
    std::vector<ManifestEntryInfo> entries;
};

namespace detail {

/// Refuse, before anything is sent, an entry with both or neither of
/// `data_map` and `address`. Throws BadRequestError naming `entries[i]`, as
/// the daemon names the entries it rejects.
inline void check_manifest_entries(const std::vector<ManifestEntryInput>& entries) {
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (entries[i].data_map.empty() == entries[i].address.empty()) {
            throw BadRequestError("entries[" + std::to_string(i) +
                                  "]: set exactly one of data_map or address");
        }
    }
}

/// Refuse empty `.ant` bytes or an empty link before sending, as antd-go
/// does; the daemon would refuse them too.
inline void check_manifest_input(bool empty, const char* what) {
    if (empty) {
        throw BadRequestError(std::string(what) + " is empty");
    }
}

}  // namespace detail

}  // namespace antd
