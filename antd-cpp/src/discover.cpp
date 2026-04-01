#include "antd/discover.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

#ifdef _WIN32
#include <windows.h>
#else
#include <cerrno>
#include <signal.h>
#include <sys/types.h>
#endif

namespace fs = std::filesystem;

namespace antd {
namespace {

constexpr const char* kPortFileName = "daemon.port";
constexpr const char* kDataDirName = "ant";

/// Check whether a process with the given PID is alive.
bool process_alive(unsigned long pid) {
#ifdef _WIN32
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                           static_cast<DWORD>(pid));
    if (h == NULL) return false;
    CloseHandle(h);
    return true;
#else
    // kill(pid, 0) checks existence without sending a signal.
    // EPERM means the process exists but we lack permission to signal it.
    return kill(static_cast<pid_t>(pid), 0) == 0 || errno == EPERM;
#endif
}

/// Parse a port number (1-65535) from a string. Returns 0 on failure.
uint16_t parse_port(const std::string& s) {
    try {
        unsigned long n = std::stoul(s);
        if (n == 0 || n > 65535) return 0;
        return static_cast<uint16_t>(n);
    } catch (...) {
        return 0;
    }
}

/// Return the platform-specific data directory for ant.
///   - Windows: %APPDATA%\ant
///   - macOS:   ~/Library/Application Support/ant
///   - Linux:   $XDG_DATA_HOME/ant or ~/.local/share/ant
fs::path data_dir() {
#ifdef _WIN32
    const char* appdata = std::getenv("APPDATA");
    if (!appdata || appdata[0] == '\0') return {};
    return fs::path(appdata) / kDataDirName;
#elif defined(__APPLE__)
    const char* home = std::getenv("HOME");
    if (!home || home[0] == '\0') return {};
    return fs::path(home) / "Library" / "Application Support" / kDataDirName;
#else
    const char* xdg = std::getenv("XDG_DATA_HOME");
    if (xdg && xdg[0] != '\0') {
        return fs::path(xdg) / kDataDirName;
    }
    const char* home = std::getenv("HOME");
    if (!home || home[0] == '\0') return {};
    return fs::path(home) / ".local" / "share" / kDataDirName;
#endif
}

/// Read the daemon.port file and return the REST and gRPC ports.
/// The file format is: REST port (line 1), gRPC port (line 2), PID (line 3).
/// If a PID is present and the process is not alive, the file is stale and
/// {0, 0} is returned.
std::pair<uint16_t, uint16_t> read_port_file() {
    auto dir = data_dir();
    if (dir.empty()) return {0, 0};

    auto path = dir / kPortFileName;
    std::ifstream ifs(path);
    if (!ifs.is_open()) return {0, 0};

    std::string line1, line2, line3;
    if (!std::getline(ifs, line1)) return {0, 0};
    std::getline(ifs, line2);  // optional second line (gRPC port)
    std::getline(ifs, line3);  // optional third line (PID)

    // Stale-file detection: if a PID is recorded, verify the process is alive.
    if (!line3.empty()) {
        try {
            unsigned long pid = std::stoul(line3);
            if (pid > 0 && !process_alive(pid)) return {0, 0};
        } catch (...) {
            // Malformed PID line — ignore and proceed without the check.
        }
    }

    return {parse_port(line1), parse_port(line2)};
}

}  // namespace

std::string discover_daemon_url() {
    auto [rest, grpc] = read_port_file();
    (void)grpc;
    if (rest == 0) return {};
    return "http://127.0.0.1:" + std::to_string(rest);
}

std::string discover_grpc_target() {
    auto [rest, grpc] = read_port_file();
    (void)rest;
    if (grpc == 0) return {};
    return "127.0.0.1:" + std::to_string(grpc);
}

}  // namespace antd
