--- Pure Lua base64 encode/decode with mime module fallback.
-- @module antd.base64

local M = {}

-- Try to use luasocket's mime module first (faster C implementation)
local ok, mime = pcall(require, "mime")
if ok and mime.b64 and mime.unb64 then
    function M.encode(data)
        if data == nil or data == "" then return "" end
        return (mime.b64(data))
    end

    function M.decode(data)
        if data == nil or data == "" then return "" end
        return (mime.unb64(data))
    end

    return M
end

-- Pure Lua fallback implementation
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local b64lookup = {}
for i = 1, #b64chars do
    b64lookup[b64chars:sub(i, i)] = i - 1
end

--- Encode a string to base64.
-- @param data string to encode
-- @return base64 encoded string
function M.encode(data)
    if data == nil or data == "" then return "" end

    local result = {}
    local pad = #data % 3
    -- Process 3 bytes at a time
    for i = 1, #data - pad, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        local n = b1 * 65536 + b2 * 256 + b3
        result[#result + 1] = b64chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        result[#result + 1] = b64chars:sub(n % 64 + 1, n % 64 + 1)
    end

    if pad == 1 then
        local b1 = data:byte(#data)
        local n = b1 * 65536
        result[#result + 1] = b64chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        result[#result + 1] = "=="
    elseif pad == 2 then
        local b1, b2 = data:byte(#data - 1, #data)
        local n = b1 * 65536 + b2 * 256
        result[#result + 1] = b64chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        result[#result + 1] = "="
    end

    return table.concat(result)
end

--- Decode a base64 string.
-- @param data base64 encoded string
-- @return decoded string
function M.decode(data)
    if data == nil or data == "" then return "" end

    -- Remove whitespace and padding
    data = data:gsub("%s+", "")
    local pad = data:sub(-2) == "==" and 2 or (data:sub(-1) == "=" and 1 or 0)
    data = data:gsub("=", "")

    local result = {}
    for i = 1, #data, 4 do
        local c1 = b64lookup[data:sub(i, i)] or 0
        local c2 = b64lookup[data:sub(i + 1, i + 1)] or 0
        local c3 = b64lookup[data:sub(i + 2, i + 2)] or 0
        local c4 = b64lookup[data:sub(i + 3, i + 3)] or 0

        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4

        result[#result + 1] = string.char(math.floor(n / 65536) % 256)
        if i + 1 < #data or pad < 2 then
            result[#result + 1] = string.char(math.floor(n / 256) % 256)
        end
        if i + 2 < #data or pad < 1 then
            result[#result + 1] = string.char(n % 256)
        end
    end

    return table.concat(result)
end

return M
