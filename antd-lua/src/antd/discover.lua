--- Port discovery for the antd daemon.
-- Reads the `daemon.port` file written by antd on startup.
-- @module antd.discover

local Discover = {}

local PORT_FILE_NAME = "daemon.port"
local DATA_DIR_NAME = "ant"

--- Returns true if running on Windows.
local function is_windows()
    return package.config:sub(1, 1) == "\\"
end

--- Returns the platform-specific data directory for ant.
-- @return string|nil directory path, or nil if not determinable
local function data_dir()
    if is_windows() then
        local appdata = os.getenv("APPDATA")
        if not appdata or appdata == "" then return nil end
        return appdata .. "\\" .. DATA_DIR_NAME
    end

    -- Check for macOS by looking for ~/Library
    local home = os.getenv("HOME")
    if home and home ~= "" then
        local lib = home .. "/Library"
        local f = io.open(lib, "r")
        if f then
            f:close()
            -- macOS
            return home .. "/Library/Application Support/" .. DATA_DIR_NAME
        end
    end

    -- Linux / other Unix
    local xdg = os.getenv("XDG_DATA_HOME")
    if xdg and xdg ~= "" then
        return xdg .. "/" .. DATA_DIR_NAME
    end
    if home and home ~= "" then
        return home .. "/.local/share/" .. DATA_DIR_NAME
    end

    return nil
end

--- Read the daemon.port file and return the two port numbers.
-- @return number|nil REST port
-- @return number|nil gRPC port
local function read_port_file()
    local dir = data_dir()
    if not dir then return nil, nil end

    local sep = is_windows() and "\\" or "/"
    local path = dir .. sep .. PORT_FILE_NAME

    local f = io.open(path, "r")
    if not f then return nil, nil end

    local contents = f:read("*a")
    f:close()
    if not contents or contents == "" then return nil, nil end

    local lines = {}
    for line in contents:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end

    if #lines < 1 then return nil, nil end

    local rest_port = tonumber(lines[1])
    local grpc_port = #lines >= 2 and tonumber(lines[2]) or nil

    return rest_port, grpc_port
end

--- Discover the antd daemon REST URL.
-- Returns the URL (e.g. "http://127.0.0.1:8082") or "" if unavailable.
-- @return string
function Discover.daemon_url()
    local rest = read_port_file()
    if not rest or rest == 0 then return "" end
    return string.format("http://127.0.0.1:%d", rest)
end

--- Discover the antd daemon gRPC target.
-- Returns the target (e.g. "127.0.0.1:50051") or "" if unavailable.
-- @return string
function Discover.grpc_target()
    local _, grpc = read_port_file()
    if not grpc or grpc == 0 then return "" end
    return string.format("127.0.0.1:%d", grpc)
end

return Discover
