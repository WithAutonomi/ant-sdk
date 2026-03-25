#pragma once

#include <string>

namespace antd {

/// Read the daemon.port file written by antd on startup and return the REST
/// base URL (e.g. "http://127.0.0.1:8082").
/// Returns an empty string if the port file is not found or unreadable.
std::string discover_daemon_url();

/// Read the daemon.port file written by antd on startup and return the gRPC
/// target (e.g. "127.0.0.1:50051").
/// Returns an empty string if the port file has no gRPC line or is unreadable.
std::string discover_grpc_target();

}  // namespace antd
