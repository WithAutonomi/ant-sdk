defmodule Antd.Discover do
  @moduledoc """
  Auto-discovers the antd daemon by reading the `daemon.port` file that antd
  writes on startup.

  The file contains two lines: REST port on line 1, gRPC port on line 2.

  Port file location is platform-specific:
    - Windows: `%APPDATA%\\ant\\daemon.port`
    - macOS:   `~/Library/Application Support/ant/daemon.port`
    - Linux:   `$XDG_DATA_HOME/ant/daemon.port` or `~/.local/share/ant/daemon.port`
  """

  @port_file_name "daemon.port"
  @data_dir_name "ant"

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
            {rest_port, grpc_port}

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

  defp data_dir do
    case :os.type() do
      {:win32, _} ->
        case System.get_env("APPDATA") do
          nil -> ""
          "" -> ""
          appdata -> Path.join(appdata, @data_dir_name)
        end

      {:unix, :darwin} ->
        case System.get_env("HOME") do
          nil -> ""
          "" -> ""
          home -> Path.join([home, "Library", "Application Support", @data_dir_name])
        end

      {:unix, _} ->
        case System.get_env("XDG_DATA_HOME") do
          xdg when is_binary(xdg) and xdg != "" ->
            Path.join(xdg, @data_dir_name)

          _ ->
            case System.get_env("HOME") do
              nil -> ""
              "" -> ""
              home -> Path.join([home, ".local", "share", @data_dir_name])
            end
        end
    end
  end
end
