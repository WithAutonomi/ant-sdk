use std::fs;
use std::io::Write;
use std::path::PathBuf;

const PORT_FILE_NAME: &str = "daemon.port";
const DATA_DIR_NAME: &str = "ant";
const SDK_SUBDIR_NAME: &str = "sdk";

/// Returns the platform-specific data directory for the antd SDK daemon.
///
/// - Windows: `%APPDATA%\ant\sdk`
/// - macOS:   `~/Library/Application Support/ant/sdk`
/// - Linux:   `$XDG_DATA_HOME/ant/sdk` or `~/.local/share/ant/sdk`
///
/// The `sdk` subdirectory keeps antd's port file separate from the ant-node
/// daemon, which writes to the same `ant` umbrella dir.
fn data_dir() -> Option<PathBuf> {
    dirs::data_dir().map(|d| d.join(DATA_DIR_NAME).join(SDK_SUBDIR_NAME))
}

/// Returns the full path to the port file.
fn port_file_path() -> Option<PathBuf> {
    data_dir().map(|d| d.join(PORT_FILE_NAME))
}

/// Writes the port file atomically.
///
/// Format: two lines — REST port on line 1, gRPC port on line 2.
/// Writes to a temp file first then renames for atomicity.
/// On Windows, removes the target first since rename fails if it exists.
/// Also removes any stale port file from a previous crashed instance.
pub fn write(rest_port: u16, grpc_port: u16) -> Option<PathBuf> {
    let dir = data_dir()?;
    if let Err(e) = fs::create_dir_all(&dir) {
        tracing::warn!(path = %dir.display(), error = %e, "failed to create data directory");
        return None;
    }

    let target = dir.join(PORT_FILE_NAME);
    let tmp = dir.join(format!("{PORT_FILE_NAME}.tmp"));

    let pid = std::process::id();
    let contents = format!("{rest_port}\n{grpc_port}\n{pid}\n");

    let result = (|| -> std::io::Result<()> {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(contents.as_bytes())?;
        f.sync_all()?;
        // On Windows, rename fails if target exists — remove it first.
        // This is not atomic on Windows but is the best we can do.
        if cfg!(windows) {
            let _ = fs::remove_file(&target);
        }
        fs::rename(&tmp, &target)?;
        Ok(())
    })();

    match result {
        Ok(()) => Some(target),
        Err(e) => {
            tracing::warn!(path = %target.display(), error = %e, "failed to write port file");
            let _ = fs::remove_file(&tmp);
            None
        }
    }
}

/// Removes the port file. Best-effort; logs on failure.
pub fn remove() {
    if let Some(path) = port_file_path() {
        if path.exists() {
            if let Err(e) = fs::remove_file(&path) {
                tracing::warn!(path = %path.display(), error = %e, "failed to remove port file");
            }
        }
    }
}
