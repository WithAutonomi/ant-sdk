#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 04: File upload and download, with round-trip assertions.

require "fileutils"
require "tmpdir"
require_relative "../lib/antd"

client = Antd::Client.new

Dir.mktmpdir("antd-ruby-04-files") do |tmp|
  file_content = "Hello from a file on Autonomi!"
  dir_file_content = "File inside an uploaded directory."

  src_file = File.join(tmp, "hello.txt")
  File.write(src_file, file_content)

  src_dir = File.join(tmp, "mydir")
  Dir.mkdir(src_dir)
  File.write(File.join(src_dir, "file_in_dir.txt"), dir_file_content)

  cost = client.file_cost(src_file, true, false)
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

  dir_result = client.dir_upload_public(src_dir)
  puts "Directory uploaded to #{dir_result.address}"
  puts "  storage: #{dir_result.storage_cost_atto} atto, gas: #{dir_result.gas_cost_wei} wei"
  puts "  chunks: #{dir_result.chunks_stored}, mode: #{dir_result.payment_mode_used}"

  dst_dir = File.join(tmp, "mydir_copy")
  client.dir_download_public(dir_result.address, dst_dir)
  puts "Directory downloaded to #{dst_dir}"

  unless File.read(File.join(dst_dir, "file_in_dir.txt")) == dir_file_content
    warn "directory round-trip mismatch on file_in_dir.txt"
    exit 1
  end

  puts "File and directory upload/download OK!"
end
