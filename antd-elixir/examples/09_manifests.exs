Mix.install([
  {:antd, path: ".."}
])

# Example 09: Manifests — one `.ant` file or `ant://` link for a set of files.
#
# A manifest (ADR-0006) lists files, each with a path and either an embedded
# DataMap (the key to a private upload) or a public DataMap address. The
# daemon builds and decodes it. Building and decoding upload nothing and pay
# nothing; only the two uploads below pay.
#
# Prerequisite: antd with a wallet (the antd release after 0.15.0, the first
# with manifests).
#
#   ANTD_BASE_URL  the daemon's REST URL (default http://localhost:8082)

client = Antd.Client.new(System.get_env("ANTD_BASE_URL", "http://localhost:8082"))

# 1. Two small pieces of public data.
texts = %{
  "notes/one.txt" => "Hello from manifest file one",
  "notes/two.txt" => "Hello from manifest file two, a little longer"
}

entries =
  for {path, text} <- texts do
    address = Antd.Client.data_put_public!(client, text).address
    IO.puts("Stored #{path} at #{address}")
    # `struct!/2` rather than a `%Antd.ManifestEntryInput{}` literal: the
    # script is compiled before Mix.install has loaded the SDK.
    struct!(Antd.ManifestEntryInput, path: path, address: address)
  end

# 2. Build a manifest naming them. Nothing is uploaded or paid for.
built = Antd.Client.build_manifest!(client, entries, name: "example")
IO.puts("Manifest: #{byte_size(built.manifest)} bytes")
IO.puts("Link: #{built.link || "(too long for a link; share the .ant bytes)"}")

for e <- built.entries do
  IO.puts("  #{e.effective_name} -> #{e.content_address} (#{e.kind})")
end

# 3. Decode it with resolve: true, which fetches each entry's DataMap to
#    report its exact size (content chunks are not fetched).
decoded =
  if built.link,
    do: Antd.Client.decode_manifest_link!(client, built.link, resolve: true),
    else: Antd.Client.decode_manifest!(client, built.manifest, resolve: true)

IO.puts("Decoded #{decoded.source} #{inspect(decoded.name)}:")

for e <- decoded.entries do
  # A failure to resolve one entry comes back in its `error` rather than
  # failing the call; this example treats it as fatal.
  if e.error, do: raise("#{e.effective_name}: #{e.error}")
  IO.puts("  #{e.effective_name}: exact_size #{inspect(e.exact_size)}")

  unless e.exact_size == byte_size(texts[e.effective_name]),
    do: raise("#{e.effective_name}: unexpected size")
end

IO.puts("Manifest round-trip OK!")
