"""Example 10: Manifests -- describe a set of files as one `.ant` file or link.

Stores two small pieces of public data, builds a manifest that names them
``notes/one.txt`` and ``notes/two.txt`` under the root ``example``, prints its
``ant://manifest/`` link and entries, then decodes the link with ``resolve`` to
read each entry's exact size back from the network.

Only the two uploads pay. Building and decoding a manifest uploads nothing and
pays nothing: the daemon only reads the network (``resolve`` fetches each
entry's DataMap, not its content).

Prerequisites: antd daemon (with the manifest API) on a local testnet, with a
wallet for the two uploads.

Environment:
    ANTD_BASE_URL       daemon REST URL (default http://localhost:8082)
"""

import os

from antd import AntdClient, ManifestEntryInput

base_url = os.environ.get("ANTD_BASE_URL", "http://localhost:8082")
client = AntdClient(base_url=base_url)

# 1. Two small pieces of public data (each upload pays).
one = b"Manifest example, note one"
two = b"Manifest example, note two, a little longer"
first = client.data_put_public(one).address
second = client.data_put_public(two).address
print(f"Stored notes/one.txt at {first}")
print(f"Stored notes/two.txt at {second}")

# 2. Build the manifest from the two public addresses (free).
built = client.build_manifest(
    [
        ManifestEntryInput(address=first, path="notes/one.txt"),
        ManifestEntryInput(address=second, path="notes/two.txt"),
    ],
    name="example",
)
print(f"Manifest: {len(built.manifest)} bytes")
print(f"Link: {built.link}")
for entry in built.entries:
    print(f"  {entry.effective_name} -> {entry.content_address} ({entry.kind})")
assert built.link, "a two-entry manifest should fit in a link"

# 3. Decode the link, resolving each entry's DataMap for its exact size (free).
decoded = client.decode_manifest_link(built.link, resolve=True)
print(f"Decoded {decoded.source} {decoded.name!r} with {len(decoded.entries)} entries")
for entry in decoded.entries:
    detail = f"error: {entry.error}" if entry.error else f"exact_size {entry.exact_size}"
    print(f"  {entry.effective_name}: {detail}")

sizes = {e.effective_name: e.exact_size for e in decoded.entries}
assert sizes == {"notes/one.txt": len(one), "notes/two.txt": len(two)}, sizes

client.close()
print("Manifest round-trip OK!")
