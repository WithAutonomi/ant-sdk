--- Example: Upload and download files and directories, with round-trip assertions.

local antd = require("antd")

local client = antd.new_client()

local function write_file(path, content)
    local f = assert(io.open(path, "wb"))
    f:write(content)
    f:close()
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local content = f:read("*a")
    f:close()
    return content
end

local function run_cmd(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local tmp = "/tmp/antd-lua-04-files"
run_cmd("rm -rf " .. tmp)
assert(run_cmd("mkdir -p " .. tmp))

local file_content = "Hello from a file on Autonomi!"
local dir_file_content = "File inside an uploaded directory."

local src_file = tmp .. "/hello.txt"
write_file(src_file, file_content)

local src_dir = tmp .. "/mydir"
assert(run_cmd("mkdir -p " .. src_dir))
write_file(src_dir .. "/file_in_dir.txt", dir_file_content)

local cost, err5 = client:file_cost(src_file, true, false)
if err5 then
    print("Cost error: " .. err5.message)
    os.exit(1)
end
print(string.format("Estimated upload cost: %s atto (%d chunks)", cost.cost, cost.chunk_count))

local result, err = client:file_upload_public(src_file)
if err then
    print("Upload error: " .. err.message)
    os.exit(1)
end

print("File uploaded at: " .. result.address)
print("Storage cost: " .. result.storage_cost_atto .. " atto, gas: " .. result.gas_cost_wei .. " wei")
print("Chunks stored: " .. result.chunks_stored .. ", payment mode: " .. result.payment_mode_used)

local dst_file = tmp .. "/hello.txt.downloaded"
local _, err2 = client:file_download_public(result.address, dst_file)
if err2 then
    print("Download error: " .. err2.message)
    os.exit(1)
end

print("File downloaded to " .. dst_file)

if read_file(dst_file) ~= file_content then
    run_cmd("rm -rf " .. tmp)
    print("Round-trip mismatch on hello.txt")
    os.exit(1)
end

local dir_result, err3 = client:dir_upload_public(src_dir)
if err3 then
    print("Dir upload error: " .. err3.message)
    os.exit(1)
end

print("Directory uploaded at: " .. dir_result.address)

local dst_dir = tmp .. "/mydir_copy"
local _, err4 = client:dir_download_public(dir_result.address, dst_dir)
if err4 then
    print("Dir download error: " .. err4.message)
    os.exit(1)
end

print("Directory downloaded to " .. dst_dir)

if read_file(dst_dir .. "/file_in_dir.txt") ~= dir_file_content then
    run_cmd("rm -rf " .. tmp)
    print("Directory round-trip mismatch on file_in_dir.txt")
    os.exit(1)
end

run_cmd("rm -rf " .. tmp)
print("File and directory upload/download OK!")
