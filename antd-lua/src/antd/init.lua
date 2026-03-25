--- antd — Lua SDK for the antd daemon.
-- @module antd

local Client = require("antd.client")
local models = require("antd.models")
local errors = require("antd.errors")
local discover = require("antd.discover")

local M = {}

--- Module version.
M._VERSION = "0.1.0"

--- Default base URL for the antd daemon.
M.DEFAULT_BASE_URL = Client.DEFAULT_BASE_URL

--- Discover the daemon REST URL from the port file.
-- @return string URL or "" if unavailable
M.discover_daemon_url = discover.daemon_url

--- Discover the daemon gRPC target from the port file.
-- @return string target or "" if unavailable
M.discover_grpc_target = discover.grpc_target

--- Create a client using daemon port discovery.
-- Falls back to the default base URL if discovery fails.
-- @param opts table optional settings: { timeout = number }
-- @return Client client, string url
M.auto_discover = Client.auto_discover

--- Default timeout in seconds.
M.DEFAULT_TIMEOUT = Client.DEFAULT_TIMEOUT

--- Create a new antd client.
-- @param base_url string base URL (default "http://localhost:8082")
-- @param opts table optional settings: { timeout = number }
-- @return Client
function M.new_client(base_url, opts)
    return Client:new(base_url, opts)
end

-- Re-export models
M.new_health_status = models.new_health_status
M.new_put_result = models.new_put_result
M.new_graph_descendant = models.new_graph_descendant
M.new_graph_entry = models.new_graph_entry
M.new_archive_entry = models.new_archive_entry
M.new_archive = models.new_archive

-- Re-export errors
M.errors = errors
M.error_for_status = errors.error_for_status
M.is_antd_error = errors.is_antd_error

-- Re-export Client class
M.Client = Client

return M
