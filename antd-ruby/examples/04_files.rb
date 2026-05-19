#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 04: File upload and download, with round-trip assertions.

require "fileutils"
require "tmpdir"
require_relative "../lib/antd"

client = Antd::Client.new

Dir.mktmpdir("antd-ruby-04-files") do |tmp|
  file_content = "Hello from a file on Autonomi!"

  src_file = File.join(tmp, "hello.txt")
  File.write(src_file, file_content)

  cost = client.file_cost(src_file, true)
  puts "Estimated upload cost: #{cost} atto"

  result = client.file_upload_public(src_file)
  puts "File uploaded to #{result.address}"
  puts "  storage: #{result.storage_cost_atto} atto, gas: #{result.gas_cost_wei} wei"
  puts "  chunks: #{result.chunks_stored}, mode: #{result.payment_mode_used}"

  dst_file = File.join(tmp, "hello.txt.downloaded")
  client.file_download_public(result.address, dst_file)
  puts "File downloaded to #{dst_file}"

  unless File.read(dst_file) == file_content
    warn "round-trip mismatch on hello.txt"
    exit 1
  end

  puts "File upload/download OK!"
end
