#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace antd {

/// Result of a health check.
struct HealthStatus {
    bool ok{false};
    std::string network;
};

/// Result of a put/create operation.
struct PutResult {
    std::string cost;     // atto tokens as string
    std::string address;  // hex
};

/// A descendant entry in a graph node.
struct GraphDescendant {
    std::string public_key;  // hex
    std::string content;     // hex, 32 bytes
};

/// A DAG node from the network.
struct GraphEntry {
    std::string owner;
    std::vector<std::string> parents;
    std::string content;
    std::vector<GraphDescendant> descendants;
};

/// A single entry in a file archive.
struct ArchiveEntry {
    std::string path;
    std::string address;
    int64_t created{0};
    int64_t modified{0};
    int64_t size{0};
};

/// A collection of archive entries.
struct Archive {
    std::vector<ArchiveEntry> entries;
};

}  // namespace antd
