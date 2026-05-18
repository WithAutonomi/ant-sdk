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
