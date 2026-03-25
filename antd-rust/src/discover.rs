//! Port discovery for the antd daemon.
//!
//! The antd daemon writes a `daemon.port` file on startup containing the REST
//! port on line 1, the gRPC port on line 2, and its PID on line 3.  These
//! helpers read that file to auto-discover the daemon without hard-coding a
//! port.  If a PID is present and the process is no longer alive, the port
//! file is considered stale and discovery returns `None`.

use std::env;
use std::fs;
use std::path::PathBuf;

const PORT_FILE_NAME: &str = "daemon.port";
const DATA_DIR_NAME: &str = "ant";

/// Reads the daemon port file and returns the REST base URL
/// (e.g. `"http://127.0.0.1:8082"`), or `None` if the file is missing,
/// unreadable, or stale (PID no longer alive).
pub fn discover_daemon_url() -> Option<String> {
    let (rest, _) = read_port_file()?;
    Some(format!("http://127.0.0.1:{rest}"))
}

/// Reads the daemon port file and returns the gRPC target URL
/// (e.g. `"http://127.0.0.1:50051"`), or `None` if the file is missing,
/// has no gRPC line, or is stale (PID no longer alive).
pub fn discover_grpc_target() -> Option<String> {
    let (_, grpc) = read_port_file()?;
    let grpc = grpc?;
    Some(format!("http://127.0.0.1:{grpc}"))
}

/// Reads the `daemon.port` file and returns `(rest_port, Option<grpc_port>)`.
///
/// If the file contains a PID on line 3 and that process is not alive, the
/// port file is stale and this returns `None`.
fn read_port_file() -> Option<(u16, Option<u16>)> {
    let dir = data_dir()?;
    let path = dir.join(PORT_FILE_NAME);
    let contents = fs::read_to_string(path).ok()?;

    parse_port_contents_checked(&contents, process_alive)
}

/// Parses port file contents and validates the PID using the supplied checker.
///
/// The `pid_checker` callback allows tests to substitute their own liveness
/// logic without spawning real processes.
fn parse_port_contents_checked(
    contents: &str,
    pid_checker: fn(u32) -> bool,
) -> Option<(u16, Option<u16>)> {
    let mut lines = contents.trim().lines();

    let rest: u16 = lines.next()?.trim().parse().ok()?;
    let grpc: Option<u16> = lines.next().and_then(|l| l.trim().parse().ok());

    // Line 3: optional PID — if present and the process is dead, file is stale.
    if let Some(pid_line) = lines.next() {
        if let Ok(pid) = pid_line.trim().parse::<u32>() {
            if !pid_checker(pid) {
                return None;
            }
        }
    }

    Some((rest, grpc))
}

/// Checks whether a process with the given PID is currently alive.
#[cfg(unix)]
fn process_alive(pid: u32) -> bool {
    // `kill -0` checks process existence without sending a signal.
    std::process::Command::new("kill")
        .args(["-0", &pid.to_string()])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(true) // if we can't check, trust the file
}

/// Checks whether a process with the given PID is currently alive.
#[cfg(windows)]
fn process_alive(pid: u32) -> bool {
    std::process::Command::new("tasklist")
        .args(["/FI", &format!("PID eq {}", pid), "/NH"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains(&pid.to_string()))
        .unwrap_or(true) // if we can't check, trust the file
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
    use super::parse_port_contents_checked;

    /// Stub: process is always alive.
    fn alive(_pid: u32) -> bool {
        true
    }

    /// Stub: process is always dead.
    fn dead(_pid: u32) -> bool {
        false
    }

    fn parse(contents: &str) -> Option<(u16, Option<u16>)> {
        parse_port_contents_checked(contents, alive)
    }

    #[test]
    fn parse_two_line_port_file() {
        let result = parse("8082\n50051\n");
        assert_eq!(result, Some((8082, Some(50051))));
    }

    #[test]
    fn parse_single_line_port_file() {
        let result = parse("8082\n");
        assert_eq!(result, Some((8082, None)));
    }

    #[test]
    fn parse_empty_returns_none() {
        let result = parse("");
        assert_eq!(result, None);
    }

    #[test]
    fn parse_invalid_port_returns_none() {
        let result = parse("notanumber\n");
        assert_eq!(result, None);
    }

    #[test]
    fn parse_with_whitespace() {
        let result = parse("  8082 \n  50051 \n");
        assert_eq!(result, Some((8082, Some(50051))));
    }

    #[test]
    fn parse_three_line_with_pid_alive() {
        let result = parse_port_contents_checked("8082\n50051\n12345\n", alive);
        assert_eq!(result, Some((8082, Some(50051))));
    }

    #[test]
    fn parse_three_line_with_pid_dead_returns_none() {
        let result = parse_port_contents_checked("8082\n50051\n12345\n", dead);
        assert_eq!(result, None);
    }

    #[test]
    fn parse_pid_only_rest_port_alive() {
        // Two lines: rest port + PID (no gRPC). The PID occupies line 2 but
        // it won't parse as a valid port (PIDs are typically > 65535 or the
        // daemon uses a known range).  However if the PID *does* parse as a
        // u16, it would be treated as the gRPC port and line 3 would be
        // absent.  This test verifies the three-line format specifically.
        let result = parse_port_contents_checked("8082\n50051\n99999\n", alive);
        assert_eq!(result, Some((8082, Some(50051))));
    }

    #[test]
    fn stale_file_no_grpc_port() {
        // rest port, no gRPC, PID dead — but PID is on line 3 so we need
        // something on line 2.  If line 2 is not a valid port, grpc is None
        // and line 2's value is consumed.  Line 3 is the PID.
        let result = parse_port_contents_checked("8082\n\n12345\n", dead);
        assert_eq!(result, None);
    }

    #[test]
    fn no_pid_line_always_succeeds() {
        // Legacy two-line format — no PID check performed.
        let result = parse_port_contents_checked("8082\n50051\n", dead);
        // `dead` is never called because there is no third line.
        assert_eq!(result, Some((8082, Some(50051))));
    }
}
