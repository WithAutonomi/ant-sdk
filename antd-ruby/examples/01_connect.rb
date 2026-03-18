#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 01: Connect and check daemon health

require_relative "../lib/antd"

client = Antd::Client.new

health = client.health
puts "OK: #{health.ok}, Network: #{health.network}"
