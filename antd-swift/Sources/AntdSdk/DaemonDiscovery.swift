import Foundation

/// Discovers the antd daemon by reading the `daemon.port` file written on startup.
///
/// The port file contains up to three lines: REST port (line 1), gRPC port (line 2),
/// and PID of the daemon process (line 3). If a PID is present and the process is
/// not alive, the file is considered stale and discovery returns empty.
/// File location is platform-specific:
/// - macOS: `~/Library/Application Support/ant/sdk/daemon.port`
/// - Linux: `$XDG_DATA_HOME/ant/sdk/daemon.port` or `~/.local/share/ant/sdk/daemon.port`
/// - Windows: `%APPDATA%\ant\sdk\daemon.port`
///
/// The `sdk` subdirectory keeps antd's port file separate from the ant-node
/// daemon, which writes to the same `ant` umbrella dir.
public enum DaemonDiscovery {

    private static let portFileName = "daemon.port"
    private static let dataDirName = "ant"
    private static let sdkSubDirName = "sdk"

    /// Reads the daemon.port file and returns the REST base URL
    /// (e.g. `"http://127.0.0.1:8082"`). Returns `""` if unavailable.
    public static func discoverDaemonUrl() -> String {
        guard let (rest, _) = readPortFile(), rest > 0 else { return "" }
        return "http://127.0.0.1:\(rest)"
    }

    /// Reads the daemon.port file and returns the gRPC target
    /// (e.g. `"127.0.0.1:50051"`). Returns `""` if unavailable.
    public static func discoverGrpcTarget() -> String {
        guard let (_, grpc) = readPortFile(), grpc > 0 else { return "" }
        return "127.0.0.1:\(grpc)"
    }

    /// Create an ``AntdRestClient`` using the discovered daemon URL.
    /// Falls back to `http://localhost:8082` if discovery fails.
    ///
    /// - Parameter timeout: Request timeout in seconds (default 300).
    /// - Returns: A tuple of the client and the URL it connected to.
    public static func autoDiscover(timeout: TimeInterval = 300) -> (client: AntdRestClient, url: String) {
        var url = discoverDaemonUrl()
        if url.isEmpty {
            url = "http://localhost:8082"
        }
        let client = AntdRestClient(baseURL: url, timeout: timeout)
        return (client, url)
    }

    /// Create an ``AntdGrpcClient`` using the discovered gRPC target.
    /// Falls back to `localhost:50051` if discovery fails.
    ///
    /// - Returns: A tuple of the client and the target it connected to.
    public static func autoDiscoverGrpc() -> (client: AntdGrpcClient, target: String) {
        var target = discoverGrpcTarget()
        if target.isEmpty {
            target = "localhost:50051"
        }
        let client = AntdGrpcClient(target: target)
        return (client, target)
    }

    // MARK: - Private

    private static func readPortFile() -> (rest: UInt16, grpc: UInt16)? {
        guard let dir = dataDir() else { return nil }
        let path = (dir as NSString).appendingPathComponent(portFileName)
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        let lines = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        // Line 3: PID of the daemon process (optional)
        if lines.count >= 3, let pid = Int32(lines[2].trimmingCharacters(in: .whitespaces)), pid > 0 {
            if !isProcessAlive(pid) {
                return nil
            }
        }

        let rest = parsePort(lines[0])
        let grpc = lines.count >= 2 ? parsePort(lines[1]) : 0
        return (rest, grpc)
    }

    /// Check if a process with the given PID is alive.
    /// Uses the C `kill` function with signal 0 — this doesn't send a signal but
    /// checks whether the process exists. Returns true if alive or if permission
    /// is denied (EPERM means it exists but we can't signal it).
    private static func isProcessAlive(_ pid: Int32) -> Bool {
        #if os(Windows)
        // On Windows, trust the port file — kill(pid, 0) is not available.
        return true
        #else
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
        #endif
    }

    private static func parsePort(_ s: String) -> UInt16 {
        UInt16(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func dataDir() -> String? {
        #if os(macOS)
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else { return nil }
        return (home as NSString).appendingPathComponent("Library/Application Support/\(dataDirName)/\(sdkSubDirName)")
        #elseif os(Linux)
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return (xdg as NSString).appendingPathComponent("\(dataDirName)/\(sdkSubDirName)")
        }
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else { return nil }
        return (home as NSString).appendingPathComponent(".local/share/\(dataDirName)/\(sdkSubDirName)")
        #elseif os(Windows)
        guard let appdata = ProcessInfo.processInfo.environment["APPDATA"], !appdata.isEmpty else { return nil }
        return (appdata as NSString).appendingPathComponent("\(dataDirName)/\(sdkSubDirName)")
        #else
        return nil
        #endif
    }
}
