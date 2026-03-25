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
// The file format is two lines: REST port on line 1, gRPC port on line 2.
// A single-line file is valid (gRPC port will be 0).
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

	restPort = parsePort(lines[0])
	if len(lines) >= 2 {
		grpcPort = parsePort(lines[1])
	}
	return restPort, grpcPort
}

func parsePort(s string) uint16 {
	n, err := strconv.ParseUint(strings.TrimSpace(s), 10, 16)
	if err != nil {
		return 0
	}
	return uint16(n)
}

// dataDir returns the platform-specific data directory for ant.
//   - Windows: %APPDATA%\ant
//   - macOS:   ~/Library/Application Support/ant
//   - Linux:   $XDG_DATA_HOME/ant or ~/.local/share/ant
func dataDir() string {
	switch runtime.GOOS {
	case "windows":
		appdata := os.Getenv("APPDATA")
		if appdata == "" {
			return ""
		}
		return filepath.Join(appdata, dataDirName)

	case "darwin":
		home := os.Getenv("HOME")
		if home == "" {
			return ""
		}
		return filepath.Join(home, "Library", "Application Support", dataDirName)

	default: // linux and others
		if xdg := os.Getenv("XDG_DATA_HOME"); xdg != "" {
			return filepath.Join(xdg, dataDirName)
		}
		home := os.Getenv("HOME")
		if home == "" {
			return ""
		}
		return filepath.Join(home, ".local", "share", dataDirName)
	}
}
