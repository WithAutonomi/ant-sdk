#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 06: Private data put/get

require_relative "../lib/antd"

client = Antd::Client.new

# Store private (encrypted) data
result = client.data_put_private("sensitive information")
puts "Private data stored (cost: #{result.cost} atto)"
puts "Data map: #{result.address}"

# Retrieve private data using the data map
data = client.data_get_private(result.address)
puts "Retrieved: #{data}"
