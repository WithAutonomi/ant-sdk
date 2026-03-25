import * as fs from "fs";
import * as path from "path";
import * as os from "os";

const PORT_FILE_NAME = "daemon.port";
const DATA_DIR_NAME = "ant";

/**
 * Reads the daemon.port file written by antd on startup and returns the
 * REST base URL (e.g. "http://127.0.0.1:8082").
 * Returns empty string if the port file is not found or unreadable.
 */
export function discoverDaemonUrl(): string {
  const ports = readPortFile();
  if (ports.rest === 0) {
    return "";
  }
  return `http://127.0.0.1:${ports.rest}`;
}

/**
 * Reads the daemon.port file and returns the parsed REST and gRPC ports.
 * The file format is two lines: REST port on line 1, gRPC port on line 2.
 * A single-line file is valid (gRPC port will be 0).
 */
function readPortFile(): { rest: number; grpc: number } {
  const dir = dataDir();
  if (dir === "") {
    return { rest: 0, grpc: 0 };
  }

  let data: string;
  try {
    data = fs.readFileSync(path.join(dir, PORT_FILE_NAME), "utf-8");
  } catch {
    return { rest: 0, grpc: 0 };
  }

  const lines = data.trim().split("\n");
  if (lines.length < 1) {
    return { rest: 0, grpc: 0 };
  }

  const rest = parsePort(lines[0]);
  const grpc = lines.length >= 2 ? parsePort(lines[1]) : 0;
  return { rest, grpc };
}

function parsePort(s: string): number {
  const n = parseInt(s.trim(), 10);
  if (isNaN(n) || n < 1 || n > 65535) {
    return 0;
  }
  return n;
}

/**
 * Returns the platform-specific data directory for ant.
 *   - Windows: %APPDATA%\ant
 *   - macOS:   ~/Library/Application Support/ant
 *   - Linux:   $XDG_DATA_HOME/ant or ~/.local/share/ant
 */
function dataDir(): string {
  switch (process.platform) {
    case "win32": {
      const appdata = process.env.APPDATA ?? "";
      if (appdata === "") return "";
      return path.join(appdata, DATA_DIR_NAME);
    }
    case "darwin": {
      const home = os.homedir();
      if (home === "") return "";
      return path.join(home, "Library", "Application Support", DATA_DIR_NAME);
    }
    default: {
      const xdg = process.env.XDG_DATA_HOME ?? "";
      if (xdg !== "") {
        return path.join(xdg, DATA_DIR_NAME);
      }
      const home = os.homedir();
      if (home === "") return "";
      return path.join(home, ".local", "share", DATA_DIR_NAME);
    }
  }
}
