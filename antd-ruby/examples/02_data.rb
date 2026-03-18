#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 02: Public data put/get with cost estimate

require_relative "../lib/antd"

client = Antd::Client.new

data = "Hello, Autonomi!"

# Estimate cost first
cost = client.data_cost(data)
puts "Estimated cost: #{cost} atto"

# Store data
result = client.data_put_public(data)
puts "Stored at #{result.address} (cost: #{result.cost} atto)"

# Retrieve data
retrieved = client.data_get_public(result.address)
puts "Retrieved: #{retrieved}"
