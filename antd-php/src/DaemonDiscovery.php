<?php

declare(strict_types=1);

namespace Autonomi\Antd;

/**
 * Discovers the antd daemon by reading the `daemon.port` file written on startup.
 *
 * The port file contains up to three lines: REST port (line 1), gRPC port (line 2),
 * and PID of the daemon process (line 3). If a PID is present and the process is
 * not alive, the file is considered stale and discovery returns empty.
 * File location is platform-specific:
 * - Windows: %APPDATA%\ant\daemon.port
 * - macOS:   ~/Library/Application Support/ant/daemon.port
 * - Linux:   $XDG_DATA_HOME/ant/daemon.port or ~/.local/share/ant/daemon.port
 */
class DaemonDiscovery
{
    private const PORT_FILE_NAME = 'daemon.port';
    private const DATA_DIR_NAME = 'ant';

    /**
     * Reads the daemon.port file and returns the REST base URL
     * (e.g. "http://127.0.0.1:8082"). Returns "" if unavailable.
     */
    public static function discoverDaemonUrl(): string
    {
        [$rest] = self::readPortFile();
        if ($rest === 0) {
            return '';
        }
        return "http://127.0.0.1:{$rest}";
    }

    /**
     * Reads the daemon.port file and returns the gRPC target
     * (e.g. "127.0.0.1:50051"). Returns "" if unavailable.
     */
    public static function discoverGrpcTarget(): string
    {
        [, $grpc] = self::readPortFile();
        if ($grpc === 0) {
            return '';
        }
        return "127.0.0.1:{$grpc}";
    }

    /**
     * Create an AntdClient using the discovered daemon URL.
     * Falls back to http://localhost:8082 if discovery fails.
     *
     * @param float $timeout Request timeout in seconds.
     * @param \GuzzleHttp\Client|null $httpClient Optional HTTP client.
     * @return array{0: AntdClient, 1: string} [$client, $url]
     */
    public static function autoDiscover(float $timeout = 300.0, ?\GuzzleHttp\Client $httpClient = null): array
    {
        $url = self::discoverDaemonUrl();
        if ($url === '') {
            $url = 'http://localhost:8082';
        }
        $client = new AntdClient($url, $timeout, $httpClient);
        return [$client, $url];
    }

    /**
     * @return array{0: int, 1: int} [restPort, grpcPort]
     */
    private static function readPortFile(): array
    {
        $dir = self::dataDir();
        if ($dir === '') {
            return [0, 0];
        }

        $path = $dir . DIRECTORY_SEPARATOR . self::PORT_FILE_NAME;
        $contents = @file_get_contents($path);
        if ($contents === false) {
            return [0, 0];
        }

        $lines = explode("\n", trim($contents));
        if (count($lines) < 1) {
            return [0, 0];
        }

        // Line 3: PID of the daemon process (optional stale-detection)
        if (count($lines) >= 3) {
            $pid = (int) trim($lines[2]);
            if ($pid > 0 && !self::isProcessAlive($pid)) {
                return [0, 0];
            }
        }

        $rest = self::parsePort($lines[0]);
        $grpc = count($lines) >= 2 ? self::parsePort($lines[1]) : 0;
        return [$rest, $grpc];
    }

    /**
     * Check if a process with the given PID is alive.
     * Uses posix_kill if available, falls back to /proc on Linux,
     * or tasklist on Windows.
     */
    private static function isProcessAlive(int $pid): bool
    {
        if ($pid <= 0) {
            return false;
        }

        if (PHP_OS_FAMILY === 'Windows') {
            // Use COM WMI query to avoid shell_exec injection risks.
            // Falls back to trusting the port file if COM is unavailable.
            if (class_exists('COM', false)) {
                try {
                    /** @phpstan-ignore-next-line */
                    $wmi = new \COM('WbemScripting.SWbemLocator');
                    /** @phpstan-ignore-next-line */
                    $service = $wmi->ConnectServer('.', 'root\\cimv2');
                    $query = $service->ExecQuery(
                        'SELECT ProcessId FROM Win32_Process WHERE ProcessId = ' . $pid
                    );
                    return $query->Count > 0;
                } catch (\Throwable) {
                    return true; // Cannot check; trust the port file.
                }
            }
            return true; // COM not available; trust the port file.
        }

        // Unix: prefer posix_kill, fall back to /proc
        if (function_exists('posix_kill')) {
            return posix_kill($pid, 0);
        }

        return file_exists("/proc/{$pid}");
    }

    private static function parsePort(string $s): int
    {
        $n = (int) trim($s);
        if ($n < 1 || $n > 65535) {
            return 0;
        }
        return $n;
    }

    private static function dataDir(): string
    {
        switch (PHP_OS_FAMILY) {
            case 'Windows':
                $appdata = getenv('APPDATA');
                if ($appdata === false || $appdata === '') {
                    return '';
                }
                return $appdata . DIRECTORY_SEPARATOR . self::DATA_DIR_NAME;

            case 'Darwin':
                $home = getenv('HOME');
                if ($home === false || $home === '') {
                    return '';
                }
                return $home . '/Library/Application Support/' . self::DATA_DIR_NAME;

            default: // Linux and others
                $xdg = getenv('XDG_DATA_HOME');
                if ($xdg !== false && $xdg !== '') {
                    return $xdg . '/' . self::DATA_DIR_NAME;
                }
                $home = getenv('HOME');
                if ($home === false || $home === '') {
                    return '';
                }
                return $home . '/.local/share/' . self::DATA_DIR_NAME;
        }
    }
}
