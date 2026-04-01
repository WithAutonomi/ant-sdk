package com.autonomi.antd;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

/**
 * Discovers the antd daemon by reading the {@code daemon.port} file
 * that the daemon writes on startup.
 *
 * <p>The file contains up to three lines: the REST port on line 1, the gRPC port
 * on line 2, and an optional PID on line 3. If a PID is present and the process
 * is no longer alive, the port file is considered stale and discovery returns empty.
 *
 * <p>Port file locations by platform:
 * <ul>
 *   <li>Windows: {@code %APPDATA%\ant\daemon.port}</li>
 *   <li>macOS:   {@code ~/Library/Application Support/ant/daemon.port}</li>
 *   <li>Linux:   {@code $XDG_DATA_HOME/ant/daemon.port} or {@code ~/.local/share/ant/daemon.port}</li>
 * </ul>
 */
public final class DaemonDiscovery {

    private static final String PORT_FILE_NAME = "daemon.port";
    private static final String DATA_DIR_NAME = "ant";

    private DaemonDiscovery() {}

    /**
     * Reads the daemon.port file and returns the REST base URL
     * (e.g. {@code "http://127.0.0.1:8082"}).
     *
     * @return the discovered URL, or an empty string if discovery fails
     */
    public static String discoverDaemonUrl() {
        int port = readPort(0);
        if (port == 0) {
            return "";
        }
        return "http://127.0.0.1:" + port;
    }

    /**
     * Reads the daemon.port file and returns the gRPC target
     * (e.g. {@code "127.0.0.1:50051"}).
     *
     * @return the discovered gRPC target, or an empty string if discovery fails
     */
    public static String discoverGrpcTarget() {
        int port = readPort(1);
        if (port == 0) {
            return "";
        }
        return "127.0.0.1:" + port;
    }

    /**
     * Reads the specified line from the port file and parses it as a port number.
     * If line 3 contains a PID and that process is no longer alive, the port file
     * is considered stale and 0 is returned.
     *
     * @param lineIndex 0 for REST port, 1 for gRPC port
     * @return the port number, or 0 on failure
     */
    private static int readPort(int lineIndex) {
        Path dir = dataDir();
        if (dir == null) {
            return 0;
        }

        Path portFile = dir.resolve(PORT_FILE_NAME);
        try {
            List<String> lines = Files.readAllLines(portFile);
            if (lines.size() <= lineIndex) {
                return 0;
            }

            // Check for stale port file via PID on line 3
            if (lines.size() >= 3) {
                String pidStr = lines.get(2).trim();
                if (!pidStr.isEmpty()) {
                    try {
                        long pid = Long.parseLong(pidStr);
                        if (!processAlive(pid)) {
                            return 0;
                        }
                    } catch (NumberFormatException e) {
                        // Malformed PID line — ignore and continue
                    }
                }
            }

            return parsePort(lines.get(lineIndex));
        } catch (IOException e) {
            return 0;
        }
    }

    /**
     * Returns true if a process with the given PID is currently alive.
     */
    private static boolean processAlive(long pid) {
        return ProcessHandle.of(pid).isPresent();
    }

    /**
     * Parses a port string into an integer in the valid port range (1-65535).
     *
     * @return the port number, or 0 if invalid
     */
    private static int parsePort(String s) {
        try {
            int n = Integer.parseInt(s.trim());
            if (n < 1 || n > 65535) {
                return 0;
            }
            return n;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /**
     * Returns the platform-specific data directory for ant.
     * <ul>
     *   <li>Windows: {@code %APPDATA%\ant}</li>
     *   <li>macOS:   {@code ~/Library/Application Support/ant}</li>
     *   <li>Linux:   {@code $XDG_DATA_HOME/ant} or {@code ~/.local/share/ant}</li>
     * </ul>
     *
     * @return the data directory path, or null if it cannot be determined
     */
    private static Path dataDir() {
        String os = System.getProperty("os.name", "").toLowerCase();

        if (os.contains("win")) {
            String appdata = System.getenv("APPDATA");
            if (appdata == null || appdata.isEmpty()) {
                return null;
            }
            return Paths.get(appdata, DATA_DIR_NAME);
        }

        if (os.contains("mac") || os.contains("darwin")) {
            String home = System.getProperty("user.home");
            if (home == null || home.isEmpty()) {
                return null;
            }
            return Paths.get(home, "Library", "Application Support", DATA_DIR_NAME);
        }

        // Linux and others
        String xdg = System.getenv("XDG_DATA_HOME");
        if (xdg != null && !xdg.isEmpty()) {
            return Paths.get(xdg, DATA_DIR_NAME);
        }
        String home = System.getProperty("user.home");
        if (home == null || home.isEmpty()) {
            return null;
        }
        return Paths.get(home, ".local", "share", DATA_DIR_NAME);
    }
}
