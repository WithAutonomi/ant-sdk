#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 05: Graph entry CRUD

require_relative "../lib/antd"

client = Antd::Client.new

# Estimate cost
cost = client.graph_entry_cost("a]b1c2d3...")
puts "Graph entry cost: #{cost} atto"

# Create a graph entry
result = client.graph_entry_put(
  "owner_secret_key_hex",
  [],                       # no parents
  "content_hash_hex",       # 32-byte content
  []                        # no descendants
)
puts "Graph entry created at #{result.address} (cost: #{result.cost} atto)"

# Check existence
exists = client.graph_entry_exists(result.address)
puts "Entry exists: #{exists}"

# Retrieve the entry
entry = client.graph_entry_get(result.address)
puts "Owner: #{entry.owner}"
puts "Content: #{entry.content}"
puts "Parents: #{entry.parents}"
puts "Descendants: #{entry.descendants.length}"
