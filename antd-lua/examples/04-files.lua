--- Example: Upload and download files and directories.

local antd = require("antd")

local client = antd.new_client()

-- Upload a file
local result, err = client:file_upload_public("/path/to/myfile.txt")
if err then
    print("Upload error: " .. err.message)
    os.exit(1)
end

print("File uploaded at: " .. result.address)
print("Storage cost: " .. result.storage_cost_atto .. " atto, gas: " .. result.gas_cost_wei .. " wei")
print("Chunks stored: " .. result.chunks_stored .. ", payment mode: " .. result.payment_mode_used)

-- Download the file
local _, err2 = client:file_download_public(result.address, "/tmp/downloaded.txt")
if err2 then
    print("Download error: " .. err2.message)
    os.exit(1)
end

print("File downloaded successfully")

-- Upload a directory
local dir_result, err3 = client:dir_upload_public("/path/to/mydir")
if err3 then
    print("Dir upload error: " .. err3.message)
    os.exit(1)
end

print("Directory uploaded at: " .. dir_result.address)

-- Estimate file upload cost
local cost, err5 = client:file_cost("/path/to/myfile.txt", true, false)
if err5 then
    print("Cost error: " .. err5.message)
    os.exit(1)
end

print("Estimated upload cost: " .. cost .. " atto")
