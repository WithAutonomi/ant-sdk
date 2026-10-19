"""Example 09: Pointers -- a mutable, owner-signed reference to data.

Stores two pieces of public data, creates a pointer at the first, updates it
to the second, then reads it back (get + resolve) and asks the close group
where it stands (finality).

Every pointer write pays (about the price of one chunk) and every attempt
pays again, so the SDK never retries a write and neither does this example.

Prerequisites: antd daemon (with the pointer API) on a local testnet, with a
wallet, started with ``--pointer-keys`` so it holds the owner key.

Environment:
    ANTD_POINTER_OWNER  address of a pointer the daemon holds the key for
                        (one of ``client.pointer_keys()``); required
    ANTD_BASE_URL       daemon REST URL (default http://localhost:8082)
"""

import os
import sys

from antd import AlreadyExistsError, AntdClient

owner = os.environ.get("ANTD_POINTER_OWNER")
if not owner:
    sys.exit("Set ANTD_POINTER_OWNER to a pointer address the daemon holds the key for")

base_url = os.environ.get("ANTD_BASE_URL", "http://localhost:8082")
client = AntdClient(base_url=base_url)

keys = client.pointer_keys()
print(f"Daemon holds keys for {len(keys)} pointer(s)")
if owner.lower().removeprefix("0x") not in keys:
    sys.exit(f"The daemon holds no key for {owner}")

# 1. Two small pieces of public data to point at.
first = client.data_put_public(b"Pointer target, version 1").address
second = client.data_put_public(b"Pointer target, version 2").address
print(f"Stored version 1 at {first}")
print(f"Stored version 2 at {second}")

# 2. Create the pointer at the first. A pointer that exists already (say,
#    from an earlier run) is refused before paying; point it there instead.
try:
    w = client.pointer_create(owner, first)
    print(f"Created pointer {w.address} -> version 1 (counter {w.counter})")
except AlreadyExistsError:
    w = client.pointer_update(owner, first)
    print(f"Pointer {w.address} already existed; pointed it at version 1 (counter {w.counter})")

# 3. Update it to the second. The address stays the same; the counter rises.
w = client.pointer_update(owner, second)
print(f"Updated pointer -> version 2 (counter {w.counter})")

# 4. Read it back: the record, then the chain followed to its target.
record = client.pointer_get(owner)
print(f"Get: counter {record.counter}, target {record.target}, kind {record.kind}, final {record.is_final}")
target = client.pointer_resolve(owner)
data = client.data_get_public(target.target)
print(f"Resolve: {target.target} -> {data.decode()!r}")
assert data == b"Pointer target, version 2", "pointer does not lead to version 2"

# 5. Where it stands, as the whole close group reports it.
finality = client.pointer_finality(owner)
print(
    f"Finality: {finality.status.value} ({finality.answered}/{finality.group} peers answered, "
    f"counter {finality.counter})"
)

client.close()
print("Pointer round-trip OK!")
