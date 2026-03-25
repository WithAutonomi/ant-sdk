//! Port discovery for the antd daemon.
//!
//! The antd daemon writes a `daemon.port` file on startup containing the REST
//! port on line 1 and the gRPC port on line 2.  These helpers read that file
//! to auto-discover the daemon without hard-coding a port.

use std::env;
use std::fs;
use std::path::PathBuf;

const PORT_FILE_NAME: &str = "daemon.port";
const DATA_DIR_NAME: &str = "ant";

/// Reads the daemon port file and returns the REST base URL
/// (e.g. `"http://127.0.0.1:8082"`), or `None` if the file is missing or
/// unreadable.
pub fn discover_daemon_url() -> Option<String> {
    let (rest, _) = read_port_file()?;
    Some(format!("http://127.0.0.1:{rest}"))
}

/// Reads the daemon port file and returns the gRPC target URL
/// (e.g. `"http://127.0.0.1:50051"`), or `None` if the file is missing or
/// has no gRPC line.
pub fn discover_grpc_target() -> Option<String> {
    let (_, grpc) = read_port_file()?;
    let grpc = grpc?;
    Some(format!("http://127.0.0.1:{grpc}"))
}

/// Reads the `daemon.port` file and returns `(rest_port, Option<grpc_port>)`.
fn read_port_file() -> Option<(u16, Option<u16>)> {
    let dir = data_dir()?;
    let path = dir.join(PORT_FILE_NAME);
    let contents = fs::read_to_string(path).ok()?;

    let mut lines = contents.trim().lines();

    let rest: u16 = lines.next()?.trim().parse().ok()?;
    let grpc: Option<u16> = lines.next().and_then(|l| l.trim().parse().ok());

    Some((rest, grpc))
}

/// Returns the platform-specific data directory for ant.
///
/// - Windows: `%APPDATA%\ant`
/// - macOS:   `~/Library/Application Support/ant`
/// - Linux:   `$XDG_DATA_HOME/ant` or `~/.local/share/ant`
fn data_dir() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        let appdata = env::var("APPDATA").ok()?;
        Some(PathBuf::from(appdata).join(DATA_DIR_NAME))
    }

    #[cfg(target_os = "macos")]
    {
        let home = env::var("HOME").ok()?;
        Some(PathBuf::from(home).join("Library").join("Application Support").join(DATA_DIR_NAME))
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        if let Ok(xdg) = env::var("XDG_DATA_HOME") {
            return Some(PathBuf::from(xdg).join(DATA_DIR_NAME));
        }
        let home = env::var("HOME").ok()?;
        Some(PathBuf::from(home).join(".local").join("share").join(DATA_DIR_NAME))
    }
}

#[cfg(test)]
mod tests {
    /// Simulate the same parsing logic used in `read_port_file`.
    fn parse_port_contents(contents: &str) -> Option<(u16, Option<u16>)> {
        let mut lines = contents.trim().lines();
        let rest: u16 = lines.next()?.trim().parse().ok()?;
        let grpc: Option<u16> = lines.next().and_then(|l| l.trim().parse().ok());
        Some((rest, grpc))
    }

    #[test]
    fn parse_two_line_port_file() {
        let result = parse_port_contents("8082\n50051\n");
        assert_eq!(result, Some((8082, Some(50051))));
    }

    #[test]
    fn parse_single_line_port_file() {
        let result = parse_port_contents("8082\n");
        assert_eq!(result, Some((8082, None)));
    }

    #[test]
    fn parse_empty_returns_none() {
        let result = parse_port_contents("");
        assert_eq!(result, None);
    }

    #[test]
    fn parse_invalid_port_returns_none() {
        let result = parse_port_contents("notanumber\n");
        assert_eq!(result, None);
    }

    #[test]
    fn parse_with_whitespace() {
        let result = parse_port_contents("  8082 \n  50051 \n");
        assert_eq!(result, Some((8082, Some(50051))));
    }
}
