#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 09: Manifests — one `.ant` file or `ant://` link for a set of files.
#
# A manifest lists files by path, each with a public DataMap address or an
# embedded DataMap. Building and decoding one uploads nothing and pays
# nothing; only the two uploads below pay. ANTD_BASE_URL overrides the
# daemon URL (default http://localhost:8082).

require_relative "../lib/antd"

client = Antd::Client.new(base_url: ENV.fetch("ANTD_BASE_URL", Antd::DEFAULT_BASE_URL))

# Two small pieces of public data to list.
one = client.data_put_public("Manifest example, file one").address
two = client.data_put_public("Manifest example, file two, a little longer").address
puts "Stored notes/one.txt at #{one}"
puts "Stored notes/two.txt at #{two}"

built = client.build_manifest(
  [
    { path: "notes/one.txt", address: one },
    { path: "notes/two.txt", address: two }
  ],
  name: "example"
)
puts "Manifest: #{built.manifest.bytesize} bytes"
puts "Link: #{built.link || '(too long for a link; share the .ant bytes)'}"
built.entries.each do |e|
  puts "  #{e.effective_name} -> #{e.content_address}"
end

# Anyone with the link can list the files. resolve fetches each DataMap to
# report its exact size.
decoded = if built.link
            client.decode_manifest_link(built.link, resolve: true)
          else
            client.decode_manifest(built.manifest, resolve: true)
          end
puts "Decoded #{decoded.source} #{decoded.name.inspect}:"
decoded.entries.each do |e|
  size = e.error ? "unresolved (#{e.error})" : "#{e.exact_size} bytes"
  puts "  #{e.effective_name}: #{size}"
end
