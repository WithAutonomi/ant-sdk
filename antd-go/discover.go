package antd

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

const portFileName = "daemon.port"
const dataDirName = "ant"
const sdkSubDirName = "sdk"

// DiscoverDaemonURL reads the daemon.port file written by antd on startup
// and returns the REST base URL (e.g. "http://127.0.0.1:8082").
// Returns empty string if the port file is not found or unreadable.
func DiscoverDaemonURL() string {
	rest, _ := readPortFile()
	if rest == 0 {
		return ""
	}
	return fmt.Sprintf("http://127.0.0.1:%d", rest)
}

// DiscoverGrpcTarget reads the daemon.port file written by antd on startup
// and returns the gRPC target (e.g. "127.0.0.1:50051").
// Returns empty string if the port file is not found or has no gRPC line.
func DiscoverGrpcTarget() string {
	_, grpc := readPortFile()
	if grpc == 0 {
		return ""
	}
	return fmt.Sprintf("127.0.0.1:%d", grpc)
}

// readPortFile reads the daemon.port file and returns the REST and gRPC ports.
// The file format is: REST port (line 1), gRPC port (line 2), PID (line 3).
// A single-line file is valid (gRPC port will be 0).
// If a PID is present and the process is not running, the file is considered
// stale and both ports are returned as 0.
func readPortFile() (restPort, grpcPort uint16) {
	dir := dataDir()
	if dir == "" {
		return 0, 0
	}

	data, err := os.ReadFile(filepath.Join(dir, portFileName))
	if err != nil {
		return 0, 0
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) < 1 {
		return 0, 0
	}

	// Check PID on line 3 — if present and process is dead, file is stale
	if len(lines) >= 3 {
		if pid, err := strconv.Atoi(strings.TrimSpace(lines[2])); err == nil && pid > 0 {
			if !processAlive(pid) {
				return 0, 0
			}
		}
	}

	restPort = parsePort(lines[0])
	if len(lines) >= 2 {
		grpcPort = parsePort(lines[1])
	}
	return restPort, grpcPort
}

// processAlive is implemented per-platform in discover_unix.go and discover_windows.go.

func parsePort(s string) uint16 {
	n, err := strconv.ParseUint(strings.TrimSpace(s), 10, 16)
	if err != nil {
		return 0
	}
	return uint16(n)
}

// dataDir returns the platform-specific data directory for the antd SDK daemon.
//   - Windows: %APPDATA%\ant\sdk
//   - macOS:   ~/Library/Application Support/ant/sdk
//   - Linux:   $XDG_DATA_HOME/ant/sdk or ~/.local/share/ant/sdk
//
// The sdk subdirectory keeps antd's port file separate from the ant-node
// daemon, which writes to the same ant umbrella dir.
func dataDir() string {
	switch runtime.GOOS {
	case "windows":
		appdata := os.Getenv("APPDATA")
		if appdata == "" {
			return ""
		}
		return filepath.Join(appdata, dataDirName, sdkSubDirName)

	case "darwin":
		home := os.Getenv("HOME")
		if home == "" {
			return ""
		}
		return filepath.Join(home, "Library", "Application Support", dataDirName, sdkSubDirName)

	default: // linux and others
		if xdg := os.Getenv("XDG_DATA_HOME"); xdg != "" {
			return filepath.Join(xdg, dataDirName, sdkSubDirName)
		}
		home := os.Getenv("HOME")
		if home == "" {
			return ""
		}
		return filepath.Join(home, ".local", "share", dataDirName, sdkSubDirName)
	}
}
