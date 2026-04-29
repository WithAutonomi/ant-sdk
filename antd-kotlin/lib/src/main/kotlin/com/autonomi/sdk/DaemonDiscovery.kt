package com.autonomi.sdk

import java.io.File
import java.nio.file.Path
import java.nio.file.Paths

/**
 * Reads the `daemon.port` file written by antd on startup to auto-discover
 * the REST and gRPC ports.
 *
 * The file contains up to three lines: REST port on line 1, gRPC port on line 2,
 * and an optional PID on line 3. If a PID is present and the process is no longer
 * alive, the port file is considered stale and discovery returns empty.
 */
object DaemonDiscovery {

    private const val PORT_FILE_NAME = "daemon.port"
    private const val DATA_DIR_NAME = "ant"
    private const val SDK_SUBDIR_NAME = "sdk"

    /**
     * Returns the REST base URL (e.g. `"http://127.0.0.1:8082"`) discovered
     * from the daemon.port file, or an empty string if not found.
     */
    fun discoverDaemonUrl(): String {
        val (rest, _) = readPortFile()
        return if (rest == 0) "" else "http://127.0.0.1:$rest"
    }

    /**
     * Returns the gRPC target (e.g. `"127.0.0.1:50051"`) discovered from
     * the daemon.port file, or an empty string if not found.
     */
    fun discoverGrpcTarget(): String {
        val (_, grpc) = readPortFile()
        return if (grpc == 0) "" else "127.0.0.1:$grpc"
    }

    private fun readPortFile(): Pair<Int, Int> {
        val dir = dataDir() ?: return 0 to 0
        val file = dir.resolve(PORT_FILE_NAME).toFile()
        if (!file.exists()) return 0 to 0

        return try {
            val lines = file.readLines().map { it.trim() }

            // Check for stale port file via PID on line 3
            val pidStr = lines.getOrNull(2)
            if (!pidStr.isNullOrEmpty()) {
                val pid = pidStr.toLongOrNull()
                if (pid != null && !processAlive(pid)) {
                    return 0 to 0
                }
            }

            val rest = lines.getOrNull(0)?.toIntOrNull()?.takeIf { it in 1..65535 } ?: 0
            val grpc = lines.getOrNull(1)?.toIntOrNull()?.takeIf { it in 1..65535 } ?: 0
            rest to grpc
        } catch (_: Exception) {
            0 to 0
        }
    }

    /**
     * Returns true if a process with the given PID is currently alive.
     */
    private fun processAlive(pid: Long): Boolean =
        ProcessHandle.of(pid).isPresent

    private fun dataDir(): Path? {
        // The `sdk` subdirectory keeps antd's port file separate from the
        // ant-node daemon, which writes to the same `ant` umbrella dir.
        val os = System.getProperty("os.name", "").lowercase()
        return when {
            os.contains("win") -> {
                val appdata = System.getenv("APPDATA") ?: return null
                Paths.get(appdata, DATA_DIR_NAME, SDK_SUBDIR_NAME)
            }
            os.contains("mac") || os.contains("darwin") -> {
                val home = System.getProperty("user.home") ?: return null
                Paths.get(home, "Library", "Application Support", DATA_DIR_NAME, SDK_SUBDIR_NAME)
            }
            else -> {
                val xdg = System.getenv("XDG_DATA_HOME")
                if (!xdg.isNullOrEmpty()) {
                    Paths.get(xdg, DATA_DIR_NAME, SDK_SUBDIR_NAME)
                } else {
                    val home = System.getProperty("user.home") ?: return null
                    Paths.get(home, ".local", "share", DATA_DIR_NAME, SDK_SUBDIR_NAME)
                }
            }
        }
    }
}
