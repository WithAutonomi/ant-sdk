#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 02: Public data put/get with cost estimate

require_relative "../lib/antd"

client = Antd::Client.new

data = "Hello, Autonomi!"

# Estimate cost first
est = client.data_cost(data)
puts "Estimated cost: #{est.cost} atto (#{est.chunk_count} chunks)"

# Store data
result = client.data_put_public(data)
puts "Stored at #{result.address} (chunks: #{result.chunks_stored}, mode: #{result.payment_mode_used})"

# Retrieve data
retrieved = client.data_get_public(result.address)
puts "Retrieved: #{retrieved}"
