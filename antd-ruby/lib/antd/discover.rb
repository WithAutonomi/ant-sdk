# frozen_string_literal: true

require "rbconfig"

module Antd
  # Auto-discovers the antd daemon by reading the +daemon.port+ file that antd
  # writes on startup.
  #
  # The file contains up to three lines: REST port (line 1), gRPC port (line 2),
  # and optionally the daemon PID (line 3).
  #
  # If a PID is present and the process is no longer alive, the port file is
  # considered stale and discovery returns empty.
  #
  # Port file location is platform-specific:
  #   - Windows: %APPDATA%\ant\daemon.port
  #   - macOS:   ~/Library/Application Support/ant/daemon.port
  #   - Linux:   $XDG_DATA_HOME/ant/daemon.port or ~/.local/share/ant/daemon.port
  module Discover
    PORT_FILE_NAME = "daemon.port"
    DATA_DIR_NAME  = "ant"

    # Reads the daemon.port file and returns the REST base URL
    # (e.g. "http://127.0.0.1:8082").
    #
    # @return [String] the URL, or "" if the port file is not found
    def self.daemon_url
      rest, _ = read_port_file
      return "" if rest == 0

      "http://127.0.0.1:#{rest}"
    end

    # Reads the daemon.port file and returns the gRPC target
    # (e.g. "127.0.0.1:50051").
    #
    # @return [String] the target, or "" if the port file is not found
    def self.grpc_target
      _, grpc = read_port_file
      return "" if grpc == 0

      "127.0.0.1:#{grpc}"
    end

    # @api private
    def self.read_port_file
      dir = data_dir
      return [0, 0] if dir.empty?

      path = File.join(dir, PORT_FILE_NAME)
      return [0, 0] unless File.exist?(path)

      lines = File.read(path).strip.split("\n")
      rest_port = parse_port(lines[0])
      grpc_port = parse_port(lines[1])
      pid = parse_pid(lines[2])

      return [0, 0] if pid > 0 && !process_alive?(pid)

      [rest_port, grpc_port]
    rescue StandardError
      [0, 0]
    end

    # @api private
    def self.parse_port(str)
      return 0 if str.nil?

      s = str.strip
      return 0 unless s.match?(/\A\d+\z/)

      n = s.to_i
      (n > 0 && n <= 65535) ? n : 0
    end

    # @api private
    def self.data_dir
      host_os = RbConfig::CONFIG["host_os"]

      case host_os
      when /mswin|mingw|cygwin/
        appdata = ENV["APPDATA"]
        return "" if appdata.nil? || appdata.empty?

        File.join(appdata, DATA_DIR_NAME)
      when /darwin/
        home = ENV["HOME"]
        return "" if home.nil? || home.empty?

        File.join(home, "Library", "Application Support", DATA_DIR_NAME)
      else
        xdg = ENV["XDG_DATA_HOME"]
        if xdg && !xdg.empty?
          File.join(xdg, DATA_DIR_NAME)
        else
          home = ENV["HOME"]
          return "" if home.nil? || home.empty?

          File.join(home, ".local", "share", DATA_DIR_NAME)
        end
      end
    end

    # @api private
    def self.parse_pid(str)
      return 0 if str.nil?

      s = str.strip
      return 0 unless s.match?(/\A\d+\z/)

      n = s.to_i
      n > 0 ? n : 0
    end

    # @api private
    def self.process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      # Process exists but we lack permission to signal it — still alive.
      true
    end

    private_class_method :read_port_file, :parse_port, :parse_pid, :process_alive?, :data_dir
  end
end
