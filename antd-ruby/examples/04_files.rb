#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 04: File upload and download

require_relative "../lib/antd"

client = Antd::Client.new

# Estimate upload cost
cost = client.file_cost("/tmp/example.txt", true, false)
puts "Estimated upload cost: #{cost} atto"

# Upload a file
result = client.file_upload_public("/tmp/example.txt")
puts "File uploaded to #{result.address}"
puts "  storage: #{result.storage_cost_atto} atto, gas: #{result.gas_cost_wei} wei"
puts "  chunks: #{result.chunks_stored}, mode: #{result.payment_mode_used}"

# Download the file
client.file_download_public(result.address, "/tmp/downloaded.txt")
puts "File downloaded to /tmp/downloaded.txt"

# Upload a directory
dir_result = client.dir_upload_public("/tmp/mydir")
puts "Directory uploaded to #{dir_result.address}"
puts "  storage: #{dir_result.storage_cost_atto} atto, gas: #{dir_result.gas_cost_wei} wei"
puts "  chunks: #{dir_result.chunks_stored}, mode: #{dir_result.payment_mode_used}"

# Download the directory
client.dir_download_public(dir_result.address, "/tmp/mydir_copy")
puts "Directory downloaded to /tmp/mydir_copy"
