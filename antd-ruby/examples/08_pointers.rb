#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 08: Pointers — a mutable reference to public data.
#
# A pointer's address is derived from its owner's key and never changes; the
# owner can point it at new data. The daemon holds the owner keys (started
# with `antd --pointer-keys <file-or-dir>`), so writes name the pointer by its
# address. Set ANTD_POINTER_OWNER to one of the addresses
# `client.pointer_keys` lists. ANTD_BASE_URL overrides the daemon URL
# (default http://localhost:8082).
#
# Every pointer write pays from the daemon wallet, about the price of one
# chunk, and every attempt pays again: the SDK never retries one, and neither
# should you.

require_relative "../lib/antd"

owner = ENV.fetch("ANTD_POINTER_OWNER", "").strip.downcase.delete_prefix("0x")
abort "Set ANTD_POINTER_OWNER to a pointer address the daemon holds a key for" if owner.empty?

client = Antd::Client.new(base_url: ENV.fetch("ANTD_BASE_URL", Antd::DEFAULT_BASE_URL))

unless client.pointer_keys.include?(owner)
  abort "The daemon holds no key for #{owner}; it can write: #{client.pointer_keys.join(', ')}"
end

# Two small pieces of public data to point at.
first = client.data_put_public("Pointer target, version 1").address
second = client.data_put_public("Pointer target, version 2").address
puts "Stored v1 at #{first}"
puts "Stored v2 at #{second}"

# Create the pointer at the first. A second run finds it already there.
begin
  w = client.pointer_create(owner, first)
  puts "Created pointer #{w.address} -> v1 (counter #{w.counter})"
rescue Antd::AlreadyExistsError
  puts "Pointer #{owner} already exists; updating it instead"
end

# Point it at the second.
w = client.pointer_update(owner, second)
puts "Updated pointer -> v2 (counter #{w.counter})"

# Read it back, and follow it to the data.
record = client.pointer_get(owner)
puts "Pointer #{record.address}: target #{record.target} (#{record.kind}), counter #{record.counter}, final #{record.final?}"
resolved = client.pointer_resolve(owner)
puts "Resolves to #{resolved.target}: #{client.data_get_public(resolved.target)}"

# Where the close group says it stands.
f = client.pointer_finality(owner)
counter = f.counter.nil? ? "" : ", counter #{f.counter}"
puts "Finality: #{f.status} (#{f.answered}/#{f.group} peers answered#{counter})"
