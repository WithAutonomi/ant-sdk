#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 03: Chunk put/get

require_relative "../lib/antd"

client = Antd::Client.new

# Store a raw chunk
result = client.chunk_put("raw chunk data")
puts "Chunk stored at #{result.address} (cost: #{result.cost} atto)"

# Retrieve the chunk
data = client.chunk_get(result.address)
puts "Retrieved chunk: #{data}"
