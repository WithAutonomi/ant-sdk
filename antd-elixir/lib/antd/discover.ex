defmodule Antd.Discover do
  @moduledoc """
  Auto-discovers the antd daemon by reading the `daemon.port` file that antd
  writes on startup.

  The file contains up to three lines: REST port (line 1), gRPC port (line 2),
  and optionally the daemon PID (line 3).

  If a PID is present and the process is no longer alive, the port file is
  considered stale and discovery returns empty.

  Port file location is platform-specific:
    - Windows: `%APPDATA%\\ant\\sdk\\daemon.port`
    - macOS:   `~/Library/Application Support/ant/sdk/daemon.port`
    - Linux:   `$XDG_DATA_HOME/ant/sdk/daemon.port` or `~/.local/share/ant/sdk/daemon.port`

  The `sdk` subdirectory keeps antd's port file separate from the ant-node
  daemon, which writes to the same `ant` umbrella dir.
  """

  @port_file_name "daemon.port"
  @data_dir_name "ant"
  @sdk_subdir_name "sdk"

  @doc """
  Reads the daemon.port file and returns the REST base URL
  (e.g. `"http://127.0.0.1:8082"`).

  Returns `""` if the port file is not found or unreadable.
  """
  @spec discover_daemon_url() :: String.t()
  def discover_daemon_url do
    case read_port_file() do
      {rest, _grpc} when rest > 0 -> "http://127.0.0.1:#{rest}"
      _ -> ""
    end
  end

  @doc """
  Reads the daemon.port file and returns the gRPC target
  (e.g. `"127.0.0.1:50051"`).

  Returns `""` if the port file is not found or has no gRPC line.
  """
  @spec discover_grpc_target() :: String.t()
  def discover_grpc_target do
    case read_port_file() do
      {_rest, grpc} when grpc > 0 -> "127.0.0.1:#{grpc}"
      _ -> ""
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp read_port_file do
    case data_dir() do
      "" ->
        {0, 0}

      dir ->
        path = Path.join(dir, @port_file_name)

        case File.read(path) do
          {:ok, contents} ->
            lines =
              contents
              |> String.trim()
              |> String.split("\n", trim: true)

            rest_port = parse_port(Enum.at(lines, 0, ""))
            grpc_port = parse_port(Enum.at(lines, 1, ""))
            pid = parse_pid(Enum.at(lines, 2, ""))

            if pid > 0 and not process_alive?(pid) do
              {0, 0}
            else
              {rest_port, grpc_port}
            end

          {:error, _} ->
            {0, 0}
        end
    end
  end

  defp parse_port(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} when n > 0 and n <= 65535 -> n
      _ -> 0
    end
  end

  defp parse_pid(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} when n > 0 -> n
      _ -> 0
    end
  end

  defp process_alive?(pid) do
    case :os.type() do
      {:unix, _} ->
        case System.cmd("kill", ["-0", to_string(pid)], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end

      {:win32, _} ->
        # On Windows, trust the port file — no reliable zero-signal check.
        true
    end
  end

  defp data_dir do
    case :os.type() do
      {:win32, _} ->
        case System.get_env("APPDATA") do
          nil -> ""
          "" -> ""
          appdata -> Path.join([appdata, @data_dir_name, @sdk_subdir_name])
        end

      {:unix, :darwin} ->
        case System.get_env("HOME") do
          nil -> ""
          "" -> ""
          home -> Path.join([home, "Library", "Application Support", @data_dir_name, @sdk_subdir_name])
        end

      {:unix, _} ->
        case System.get_env("XDG_DATA_HOME") do
          xdg when is_binary(xdg) and xdg != "" ->
            Path.join([xdg, @data_dir_name, @sdk_subdir_name])

          _ ->
            case System.get_env("HOME") do
              nil -> ""
              "" -> ""
              home -> Path.join([home, ".local", "share", @data_dir_name, @sdk_subdir_name])
            end
        end
    end
  end
end
