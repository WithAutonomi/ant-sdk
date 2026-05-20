#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 06: Private data put/get

require_relative "../lib/antd"

client = Antd::Client.new

# Store private (encrypted) data
result = client.data_put("sensitive information")
puts "Private data stored (chunks: #{result.chunks_stored}, mode: #{result.payment_mode_used})"
puts "Data map: #{result.data_map}"

# Retrieve private data using the data map
data = client.data_get(result.data_map)
puts "Retrieved: #{data}"
