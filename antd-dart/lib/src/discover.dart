import 'dart:io';

const _portFileName = 'daemon.port';
const _dataDirName = 'ant';

/// Reads the daemon.port file written by antd on startup and returns the
/// REST base URL (e.g. "http://127.0.0.1:8082").
/// Returns empty string if the port file is not found or unreadable.
String discoverDaemonUrl() {
  final ports = _readPortFile();
  if (ports.$1 == 0) {
    return '';
  }
  return 'http://127.0.0.1:${ports.$1}';
}

/// Reads the daemon.port file written by antd on startup and returns the
/// gRPC target (e.g. "127.0.0.1:50051").
/// Returns empty string if the port file is not found or has no gRPC line.
String discoverGrpcTarget() {
  final ports = _readPortFile();
  if (ports.$2 == 0) {
    return '';
  }
  return '127.0.0.1:${ports.$2}';
}

/// Reads the daemon.port file and returns (restPort, grpcPort).
/// The file format is up to three lines:
///   line 1: REST port
///   line 2: gRPC port
///   line 3: PID of the antd process
/// A single-line file is valid (gRPC port will be 0, no PID check).
/// If a PID is present and the process is not alive, the port file is
/// considered stale and (0, 0) is returned.
(int, int) _readPortFile() {
  final dir = _dataDir();
  if (dir.isEmpty) {
    return (0, 0);
  }

  final file = File('$dir${Platform.pathSeparator}$_portFileName');
  String data;
  try {
    data = file.readAsStringSync();
  } catch (_) {
    return (0, 0);
  }

  final lines = data.trim().split('\n');
  if (lines.isEmpty) {
    return (0, 0);
  }

  // If a PID is recorded on line 3, verify the process is still alive.
  if (lines.length >= 3) {
    final pid = int.tryParse(lines[2].trim());
    if (pid != null && pid > 0 && !_isProcessAlive(pid)) {
      return (0, 0);
    }
  }

  final rest = _parsePort(lines[0]);
  final grpc = lines.length >= 2 ? _parsePort(lines[1]) : 0;
  return (rest, grpc);
}

/// Returns true if a process with the given [pid] is currently running.
///
/// On non-Windows platforms, uses `kill -0 <pid>` which sends no signal but
/// returns exit code 0 if the process exists.
/// On Windows, Dart lacks a clean way to probe a PID without side effects,
/// so we optimistically return true (trust the port file).
bool _isProcessAlive(int pid) {
  if (Platform.isWindows) {
    // No reliable non-destructive PID probe in Dart on Windows.
    return true;
  }
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    // If we can't run the check, assume alive to avoid false negatives.
    return true;
  }
}

int _parsePort(String s) {
  final n = int.tryParse(s.trim());
  if (n == null || n < 1 || n > 65535) {
    return 0;
  }
  return n;
}

/// Returns the platform-specific data directory for ant.
///   - Windows: %APPDATA%\ant
///   - macOS:   ~/Library/Application Support/ant
///   - Linux:   $XDG_DATA_HOME/ant or ~/.local/share/ant
String _dataDir() {
  if (Platform.isWindows) {
    final appdata = Platform.environment['APPDATA'] ?? '';
    if (appdata.isEmpty) return '';
    return '$appdata${Platform.pathSeparator}$_dataDirName';
  }

  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return '';
    return '$home/Library/Application Support/$_dataDirName';
  }

  // Linux and others
  final xdg = Platform.environment['XDG_DATA_HOME'] ?? '';
  if (xdg.isNotEmpty) {
    return '$xdg/$_dataDirName';
  }
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return '';
  return '$home/.local/share/$_dataDirName';
}
