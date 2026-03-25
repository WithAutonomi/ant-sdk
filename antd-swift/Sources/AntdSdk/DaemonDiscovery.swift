import Foundation

/// Discovers the antd daemon by reading the `daemon.port` file written on startup.
///
/// The port file contains two lines: REST port on line 1, gRPC port on line 2.
/// File location is platform-specific:
/// - macOS: `~/Library/Application Support/ant/daemon.port`
/// - Linux: `$XDG_DATA_HOME/ant/daemon.port` or `~/.local/share/ant/daemon.port`
/// - Windows: `%APPDATA%\ant\daemon.port`
public enum DaemonDiscovery {

    private static let portFileName = "daemon.port"
    private static let dataDirName = "ant"

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

        let rest = parsePort(lines[0])
        let grpc = lines.count >= 2 ? parsePort(lines[1]) : 0
        return (rest, grpc)
    }

    private static func parsePort(_ s: String) -> UInt16 {
        UInt16(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func dataDir() -> String? {
        #if os(macOS)
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else { return nil }
        return (home as NSString).appendingPathComponent("Library/Application Support/\(dataDirName)")
        #elseif os(Linux)
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return (xdg as NSString).appendingPathComponent(dataDirName)
        }
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else { return nil }
        return (home as NSString).appendingPathComponent(".local/share/\(dataDirName)")
        #elseif os(Windows)
        guard let appdata = ProcessInfo.processInfo.environment["APPDATA"], !appdata.isEmpty else { return nil }
        return (appdata as NSString).appendingPathComponent(dataDirName)
        #else
        return nil
        #endif
    }
}
