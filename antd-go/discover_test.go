package antd

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// withTempPortFile creates a temp directory, writes a daemon.port file with the
// given content, and sets the environment so dataDir() returns that directory.
// It returns a cleanup function that restores the original env.
func withTempPortFile(t *testing.T, content string) (cleanup func()) {
	t.Helper()
	dir := t.TempDir()
	sdkDir := filepath.Join(dir, dataDirName, sdkSubDirName)
	if err := os.MkdirAll(sdkDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if content != "" {
		if err := os.WriteFile(filepath.Join(sdkDir, portFileName), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	// Override env so dataDir() finds our temp directory
	switch runtime.GOOS {
	case "windows":
		old := os.Getenv("APPDATA")
		os.Setenv("APPDATA", dir)
		return func() { os.Setenv("APPDATA", old) }
	case "darwin":
		old := os.Getenv("HOME")
		os.Setenv("HOME", dir)
		// On macOS dataDir uses ~/Library/Application Support/ant/sdk, so adjust
		macDir := filepath.Join(dir, "Library", "Application Support", dataDirName, sdkSubDirName)
		os.MkdirAll(macDir, 0o755)
		if content != "" {
			os.WriteFile(filepath.Join(macDir, portFileName), []byte(content), 0o644)
		}
		return func() { os.Setenv("HOME", old) }
	default:
		old := os.Getenv("XDG_DATA_HOME")
		os.Setenv("XDG_DATA_HOME", dir)
		return func() {
			if old == "" {
				os.Unsetenv("XDG_DATA_HOME")
			} else {
				os.Setenv("XDG_DATA_HOME", old)
			}
		}
	}
}

func TestDiscoverDaemonURL_ValidFile(t *testing.T) {
	cleanup := withTempPortFile(t, "8082\n50051\n")
	defer cleanup()

	url := DiscoverDaemonURL()
	if url != "http://127.0.0.1:8082" {
		t.Fatalf("expected http://127.0.0.1:8082, got %s", url)
	}
}

func TestDiscoverGrpcTarget_ValidFile(t *testing.T) {
	cleanup := withTempPortFile(t, "8082\n50051\n")
	defer cleanup()

	target := DiscoverGrpcTarget()
	if target != "127.0.0.1:50051" {
		t.Fatalf("expected 127.0.0.1:50051, got %s", target)
	}
}

func TestDiscoverDaemonURL_SingleLine(t *testing.T) {
	cleanup := withTempPortFile(t, "9000\n")
	defer cleanup()

	url := DiscoverDaemonURL()
	if url != "http://127.0.0.1:9000" {
		t.Fatalf("expected http://127.0.0.1:9000, got %s", url)
	}

	// gRPC should be empty with single line
	target := DiscoverGrpcTarget()
	if target != "" {
		t.Fatalf("expected empty gRPC target, got %s", target)
	}
}

func TestDiscoverDaemonURL_MissingFile(t *testing.T) {
	cleanup := withTempPortFile(t, "")
	defer cleanup()

	url := DiscoverDaemonURL()
	if url != "" {
		t.Fatalf("expected empty string, got %s", url)
	}
}

func TestDiscoverDaemonURL_InvalidContent(t *testing.T) {
	cleanup := withTempPortFile(t, "not-a-number\n")
	defer cleanup()

	url := DiscoverDaemonURL()
	if url != "" {
		t.Fatalf("expected empty string, got %s", url)
	}
}

func TestDiscoverDaemonURL_WhitespaceHandling(t *testing.T) {
	cleanup := withTempPortFile(t, "  8082  \n  50051  \n")
	defer cleanup()

	url := DiscoverDaemonURL()
	if url != "http://127.0.0.1:8082" {
		t.Fatalf("expected http://127.0.0.1:8082, got %s", url)
	}

	target := DiscoverGrpcTarget()
	if target != "127.0.0.1:50051" {
		t.Fatalf("expected 127.0.0.1:50051, got %s", target)
	}
}

func TestNewClientAutoDiscover_WithPortFile(t *testing.T) {
	cleanup := withTempPortFile(t, "9999\n")
	defer cleanup()

	c, url := NewClientAutoDiscover()
	if url != "http://127.0.0.1:9999" {
		t.Fatalf("expected http://127.0.0.1:9999, got %s", url)
	}
	if c.baseURL != "http://127.0.0.1:9999" {
		t.Fatalf("client baseURL mismatch: %s", c.baseURL)
	}
}

func TestNewClientAutoDiscover_Fallback(t *testing.T) {
	cleanup := withTempPortFile(t, "")
	defer cleanup()

	c, url := NewClientAutoDiscover()
	if url != DefaultBaseURL {
		t.Fatalf("expected %s, got %s", DefaultBaseURL, url)
	}
	if c.baseURL != DefaultBaseURL {
		t.Fatalf("client baseURL mismatch: %s", c.baseURL)
	}
}
