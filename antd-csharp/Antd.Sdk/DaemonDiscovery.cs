using System.Runtime.InteropServices;

namespace Antd.Sdk;

/// <summary>
/// Reads the daemon.port file written by antd on startup to auto-discover
/// the REST and gRPC ports. The file contains up to three lines: REST port
/// on line 1, gRPC port on line 2, and daemon PID on line 3. If a PID is
/// present and the process is no longer alive, the file is considered stale
/// and discovery returns empty.
/// </summary>
public static class DaemonDiscovery
{
    private const string PortFileName = "daemon.port";
    private const string DataDirName = "ant";
    private const string SdkSubDirName = "sdk";

    /// <summary>
    /// Reads line 1 of the daemon.port file and returns the REST base URL
    /// (e.g. "http://127.0.0.1:8082"). Returns empty string on failure.
    /// </summary>
    public static string DiscoverDaemonUrl()
    {
        var (restPort, _) = ReadPortFile();
        return restPort > 0 ? $"http://127.0.0.1:{restPort}" : "";
    }

    /// <summary>
    /// Reads line 2 of the daemon.port file and returns the gRPC target
    /// (e.g. "http://127.0.0.1:50051"). Returns empty string on failure.
    /// </summary>
    public static string DiscoverGrpcTarget()
    {
        var (_, grpcPort) = ReadPortFile();
        return grpcPort > 0 ? $"http://127.0.0.1:{grpcPort}" : "";
    }

    private static (ushort restPort, ushort grpcPort) ReadPortFile()
    {
        var dir = DataDir();
        if (string.IsNullOrEmpty(dir))
            return (0, 0);

        var path = Path.Combine(dir, PortFileName);
        if (!File.Exists(path))
            return (0, 0);

        try
        {
            var text = File.ReadAllText(path).Trim();
            var lines = text.Split('\n');

            ushort rest = 0, grpc = 0;
            if (lines.Length >= 1)
                rest = ParsePort(lines[0]);
            if (lines.Length >= 2)
                grpc = ParsePort(lines[1]);

            // Line 3 is the daemon PID. If present and the process is
            // no longer running, the port file is stale.
            if (lines.Length >= 3
                && int.TryParse(lines[2].Trim(), out var pid)
                && pid > 0
                && !ProcessAlive(pid))
            {
                return (0, 0);
            }

            return (rest, grpc);
        }
        catch
        {
            return (0, 0);
        }
    }

    private static bool ProcessAlive(int pid)
    {
        try
        {
            System.Diagnostics.Process.GetProcessById(pid);
            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private static ushort ParsePort(string s)
    {
        return ushort.TryParse(s.Trim(), out var port) ? port : (ushort)0;
    }

    /// <summary>
    /// Returns the platform-specific data directory for the antd SDK daemon.
    ///   Windows: %APPDATA%\ant\sdk
    ///   macOS:   ~/Library/Application Support/ant/sdk
    ///   Linux:   $XDG_DATA_HOME/ant/sdk or ~/.local/share/ant/sdk
    ///
    /// The "sdk" subdirectory keeps antd's port file separate from the
    /// ant-node daemon, which writes to the same "ant" umbrella dir.
    /// </summary>
    private static string DataDir()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var appdata = Environment.GetEnvironmentVariable("APPDATA");
            return string.IsNullOrEmpty(appdata) ? "" : Path.Combine(appdata, DataDirName, SdkSubDirName);
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            var home = Environment.GetEnvironmentVariable("HOME");
            return string.IsNullOrEmpty(home) ? "" : Path.Combine(home, "Library", "Application Support", DataDirName, SdkSubDirName);
        }

        // Linux and others
        var xdg = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
        if (!string.IsNullOrEmpty(xdg))
            return Path.Combine(xdg, DataDirName, SdkSubDirName);

        var homeDir = Environment.GetEnvironmentVariable("HOME");
        return string.IsNullOrEmpty(homeDir) ? "" : Path.Combine(homeDir, ".local", "share", DataDirName, SdkSubDirName);
    }
}
